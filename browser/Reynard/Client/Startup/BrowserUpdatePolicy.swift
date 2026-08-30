//
//  BrowserUpdatePolicy.swift
//  Reynard
//
//  Created by OpenAI Codex on 30/8/26.
//

import Foundation

enum BrowserUpdatePolicy {
    private static let repositoryReleasePath = "/xytxg/reynard-browser-zh/releases/download/"
    private static let maximumPackageNameLength = 180
    private static let versionExpression = try? NSRegularExpression(
        pattern: #"(?<![0-9])(\d+)\.(\d+)(?:\.(\d+))?"#
    )
    private static let packageNameExpression = try? NSRegularExpression(
        pattern: #"^Reynard-[A-Za-z0-9._-]+\.(?:ipa|tipa)$"#,
        options: [.caseInsensitive]
    )

    static func version(in values: [String]) -> String? {
        for value in values {
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let versionExpression,
                  let match = versionExpression.firstMatch(in: value, range: range) else {
                continue
            }

            let components = (1...3).map { index -> Int in
                guard match.range(at: index).location != NSNotFound,
                      let componentRange = Range(match.range(at: index), in: value) else {
                    return 0
                }
                return Int(value[componentRange]) ?? 0
            }
            return components.map(String.init).joined(separator: ".")
        }
        return nil
    }

    static func buildNumber(tagName: String, releaseNotes: String, packageName: String) -> Int? {
        let candidates = [
            (#"^build-(\d+)$"#, tagName),
            (#"reynard-update-build:\s*(\d+)"#, releaseNotes),
            (#"actions/runs/\d+[^\n]*\[#(\d+)\]"#, releaseNotes),
            (#"-build-(\d+)-"#, packageName),
        ]

        for (pattern, value) in candidates {
            guard let expression = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
                continue
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            guard let match = expression.firstMatch(in: value, range: range),
                  match.range(at: 1).location != NSNotFound,
                  let valueRange = Range(match.range(at: 1), in: value),
                  let build = Int(value[valueRange]) else {
                continue
            }
            return build
        }
        return nil
    }

    static func isUpdate(
        remoteVersion: String,
        remoteBuild: Int?,
        currentVersion: String,
        currentBuild: Int?
    ) -> Bool {
        let comparison = compareVersions(remoteVersion, currentVersion)
        if comparison != 0 {
            return comparison > 0
        }

        guard let remoteBuild else {
            return false
        }
        return remoteBuild > (currentBuild ?? 0)
    }

    static func compareVersions(_ lhs: String, _ rhs: String) -> Int {
        let lhsParts = numericVersionParts(lhs)
        let rhsParts = numericVersionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let lhsValue = index < lhsParts.count ? lhsParts[index] : 0
            let rhsValue = index < rhsParts.count ? rhsParts[index] : 0
            if lhsValue != rhsValue {
                return lhsValue < rhsValue ? -1 : 1
            }
        }
        return 0
    }

    static func isAllowedPackageName(_ name: String) -> Bool {
        guard !name.isEmpty,
              name.count <= maximumPackageNameLength,
              !name.contains("/"),
              !name.contains("\\"),
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return false
        }

        let range = NSRange(name.startIndex..<name.endIndex, in: name)
        return packageNameExpression?.firstMatch(in: name, range: range) != nil
    }

    static func isAllowedReleaseDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "github.com" else {
            return false
        }
        return url.path.hasPrefix(repositoryReleasePath)
    }

    static func isAllowedDownloadResponseURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        return host == "github.com" || host.hasSuffix(".githubusercontent.com")
    }

    static func checksum(from sidecar: String, packageName: String) -> String? {
        var unnamedChecksum: String?
        for rawLine in sidecar.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else {
                continue
            }

            let fields = line.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let checksum = fields.first.map(String.init),
                  checksum.range(of: #"^[A-Fa-f0-9]{64}$"#, options: .regularExpression) != nil else {
                continue
            }

            guard fields.count > 1 else {
                unnamedChecksum = checksum.lowercased()
                continue
            }
            let reportedPath = String(fields[1]).trimmingCharacters(in: CharacterSet(charactersIn: "* \t"))
            if URL(fileURLWithPath: reportedPath).lastPathComponent == packageName {
                return checksum.lowercased()
            }
        }
        return unnamedChecksum
    }

    private static func numericVersionParts(_ value: String) -> [Int] {
        guard let normalized = version(in: [value]) else {
            return []
        }
        return normalized.split(separator: ".").map { Int($0) ?? 0 }
    }
}
