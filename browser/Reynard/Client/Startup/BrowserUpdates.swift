//
//  BrowserUpdates.swift
//  Reynard
//
//  Created by Minh Ton on 21/4/26.
//

import Foundation

struct BrowserUpdateAsset {
    let name: String
    let downloadURL: URL
    let size: Int64
    let checksumURL: URL?
}

struct BrowserUpdateRelease {
    let version: String
    let build: Int?
    let tagName: String
    let releaseNotes: String
    let publishedAt: Date
    let releasePageURL: URL
    let package: BrowserUpdateAsset
    let trollStorePackage: BrowserUpdateAsset?
}

enum BrowserUpdateCheckResult {
    case updateAvailable(BrowserUpdateRelease)
    case upToDate
    case failure(Error)
}

private enum BrowserUpdateError: LocalizedError {
    case invalidRequest
    case invalidResponse
    case serverStatus(Int)
    case responseTooLarge
    case invalidReleaseData
    case noCompatiblePackage

    var errorDescription: String? {
        switch self {
        case .invalidRequest:
            return NSLocalizedString("The update request could not be created.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("GitHub returned an invalid update response.", comment: "")
        case .serverStatus(let status):
            return String(
                format: NSLocalizedString("GitHub returned HTTP %d while checking for updates.", comment: ""),
                status
            )
        case .responseTooLarge:
            return NSLocalizedString("The update response was unexpectedly large.", comment: "")
        case .invalidReleaseData:
            return NSLocalizedString("The update information from GitHub could not be read.", comment: "")
        case .noCompatiblePackage:
            return NSLocalizedString("No compatible Reynard IPA was found in recent releases.", comment: "")
        }
    }
}

final class BrowserUpdates {
    static let shared = BrowserUpdates()

    private enum Limits {
        static let maximumResponseSize = 2 * 1024 * 1024
        static let maximumPackageSize: Int64 = 2 * 1024 * 1024 * 1024
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let name: String?
        let draft: Bool
        let prerelease: Bool
        let createdAt: String
        let publishedAt: String?
        let body: String?
        let pageURL: URL
        let assets: [GitHubAsset]

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case name
            case draft
            case prerelease
            case createdAt = "created_at"
            case publishedAt = "published_at"
            case body
            case pageURL = "html_url"
            case assets
        }
    }

    private struct GitHubAsset: Decodable {
        let name: String
        let size: Int64
        let state: String
        let downloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name
            case size
            case state
            case downloadURL = "browser_download_url"
        }
    }

    private(set) var hasUpdate = false
    private(set) var latestRelease: BrowserUpdateRelease?
    private(set) var isChecking = false
    var latestVersion: String { return latestRelease?.version ?? "" }
    var cachedReleaseNotes: NSAttributedString?

    private static let releasesURLString =
    "https://api.github.com/repos/xytxg/reynard-browser-zh/releases?per_page=20"
    private var activeTask: BoundedURLDataLoader?
    private var completions: [(BrowserUpdateCheckResult) -> Void] = []

    private init() {
        checkForUpdates()
    }

    func checkForUpdates(completion: ((BrowserUpdateCheckResult) -> Void)? = nil) {
        DispatchQueue.main.async {
            if let completion {
                self.completions.append(completion)
            }
            guard self.activeTask == nil else {
                return
            }
            self.startUpdateCheck()
        }
    }

    private func startUpdateCheck() {
        guard let url = URL(string: Self.releasesURLString),
              url.scheme == "https",
              url.host == "api.github.com" else {
            complete(.failure(BrowserUpdateError.invalidRequest))
            return
        }

        isChecking = true
        NotificationCenter.default.post(name: .appUpdateStateDidChange, object: nil)
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Reynard-iOS-UpdateChecker", forHTTPHeaderField: "User-Agent")

        let task = BoundedURLDataLoader(
            maximumByteCount: Limits.maximumResponseSize,
            timeoutIntervalForRequest: 20,
            timeoutIntervalForResource: 30,
            responseValidator: { response in
                return response.statusCode == 200 &&
                response.url?.scheme?.lowercased() == "https" &&
                response.url?.host?.lowercased() == "api.github.com"
            },
            completion: { [weak self] loaderResult in
                DispatchQueue.main.async {
                    guard let self else {
                        return
                    }
                    let result: BrowserUpdateCheckResult
                    switch loaderResult {
                    case .success(let loadedResponse):
                        result = self.processResponseData(loadedResponse.data)
                    case .failure(let error):
                        if let loaderError = error as? BoundedURLDataLoader.LoaderError {
                            result = .failure(
                                loaderError == .responseTooLarge ?
                                BrowserUpdateError.responseTooLarge :
                                BrowserUpdateError.invalidResponse
                            )
                        } else {
                            result = .failure(error)
                        }
                    }
                    self.complete(result)
                }
            }
        )
        activeTask = task
        task.start(with: request)
    }

    private func processResponseData(_ data: Data) -> BrowserUpdateCheckResult {
        guard data.count <= Limits.maximumResponseSize else {
            return .failure(BrowserUpdateError.responseTooLarge)
        }

        do {
            let releases = try JSONDecoder().decode([GitHubRelease].self, from: data)
            let candidates = releases.compactMap(makeRelease)
            guard !candidates.isEmpty else {
                return .failure(BrowserUpdateError.noCompatiblePackage)
            }

            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            let currentBuild = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String).flatMap(Int.init)
            let eligible = candidates.filter { release in
                BrowserUpdatePolicy.isUpdate(
                    remoteVersion: release.version,
                    remoteBuild: release.build,
                    currentVersion: currentVersion,
                    currentBuild: currentBuild
                )
            }
            guard let preferred = eligible.max(by: isOrderedBefore) else {
                return .upToDate
            }
            return .updateAvailable(preferred)
        } catch {
            return .failure(BrowserUpdateError.invalidReleaseData)
        }
    }

    private func makeRelease(_ release: GitHubRelease) -> BrowserUpdateRelease? {
        guard !release.draft,
              let packageSource = preferredStandardPackage(in: release.assets),
              let package = makeAsset(packageSource, allAssets: release.assets),
              let version = BrowserUpdatePolicy.version(
                in: [release.tagName, release.name ?? "", package.name]
              ),
              release.pageURL.scheme == "https",
              release.pageURL.host?.lowercased() == "github.com" else {
            return nil
        }

        let releaseNotes = release.body ?? ""
        let build = BrowserUpdatePolicy.buildNumber(
            tagName: release.tagName,
            releaseNotes: releaseNotes,
            packageName: package.name
        )
        let trollStorePackage = preferredTrollStorePackage(in: release.assets).flatMap {
            makeAsset($0, allAssets: release.assets)
        }
        let publishedAt = Self.parseDate(release.publishedAt ?? release.createdAt) ?? .distantPast
        return BrowserUpdateRelease(
            version: version,
            build: build,
            tagName: release.tagName,
            releaseNotes: releaseNotes,
            publishedAt: publishedAt,
            releasePageURL: release.pageURL,
            package: package,
            trollStorePackage: trollStorePackage
        )
    }

    private func preferredStandardPackage(in assets: [GitHubAsset]) -> GitHubAsset? {
        let packages = assets.filter { asset in
            let lowered = asset.name.lowercased()
            return asset.state == "uploaded" &&
            lowered.hasSuffix(".ipa") &&
            !lowered.contains("trollstore") &&
            !lowered.contains("jailbroken") &&
            BrowserUpdatePolicy.isAllowedPackageName(asset.name) &&
            BrowserUpdatePolicy.isAllowedReleaseDownloadURL(asset.downloadURL) &&
            asset.size > 0 && asset.size <= Limits.maximumPackageSize
        }
        return packages.first(where: { $0.name.lowercased().contains("unsigned") }) ??
        packages.sorted { $0.name < $1.name }.first
    }

    private func preferredTrollStorePackage(in assets: [GitHubAsset]) -> GitHubAsset? {
        return assets
            .filter { asset in
                let lowered = asset.name.lowercased()
                return asset.state == "uploaded" &&
                (lowered.hasSuffix(".tipa") || lowered.contains("trollstore")) &&
                BrowserUpdatePolicy.isAllowedPackageName(asset.name) &&
                BrowserUpdatePolicy.isAllowedReleaseDownloadURL(asset.downloadURL) &&
                asset.size > 0 && asset.size <= Limits.maximumPackageSize
            }
            .sorted { $0.name < $1.name }
            .first
    }

    private func makeAsset(_ asset: GitHubAsset, allAssets: [GitHubAsset]) -> BrowserUpdateAsset? {
        guard BrowserUpdatePolicy.isAllowedPackageName(asset.name),
              BrowserUpdatePolicy.isAllowedReleaseDownloadURL(asset.downloadURL) else {
            return nil
        }
        let checksumURL = allAssets.first { checksumAsset in
            checksumAsset.state == "uploaded" &&
            checksumAsset.name == asset.name + ".sha256" &&
            checksumAsset.size > 0 &&
            checksumAsset.size <= 4096 &&
            BrowserUpdatePolicy.isAllowedReleaseDownloadURL(checksumAsset.downloadURL)
        }?.downloadURL
        return BrowserUpdateAsset(
            name: asset.name,
            downloadURL: asset.downloadURL,
            size: asset.size,
            checksumURL: checksumURL
        )
    }

    private func isOrderedBefore(_ lhs: BrowserUpdateRelease, _ rhs: BrowserUpdateRelease) -> Bool {
        let versionComparison = BrowserUpdatePolicy.compareVersions(lhs.version, rhs.version)
        if versionComparison != 0 {
            return versionComparison < 0
        }
        let lhsBuild = lhs.build ?? 0
        let rhsBuild = rhs.build ?? 0
        if lhsBuild != rhsBuild {
            return lhsBuild < rhsBuild
        }
        return lhs.publishedAt < rhs.publishedAt
    }

    private func complete(_ result: BrowserUpdateCheckResult) {
        activeTask = nil
        isChecking = false

        switch result {
        case .updateAvailable(let release):
            if latestRelease?.tagName != release.tagName {
                cachedReleaseNotes = nil
            }
            latestRelease = release
            hasUpdate = true
        case .upToDate:
            latestRelease = nil
            cachedReleaseNotes = nil
            hasUpdate = false
        case .failure:
            break
        }

        NotificationCenter.default.post(name: .appUpdateStateDidChange, object: nil)
        let callbacks = completions
        completions.removeAll()
        callbacks.forEach { $0(result) }
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) {
            return date
        }
        return ISO8601DateFormatter().date(from: value)
    }
}
