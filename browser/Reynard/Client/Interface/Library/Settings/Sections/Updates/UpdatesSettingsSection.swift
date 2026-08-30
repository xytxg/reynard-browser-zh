//
//  UpdatesSettingsSection.swift
//  Reynard
//
//  Created by Minh Ton on 18/6/26.
//

import UIKit

private enum UpdateDownloadError: LocalizedError {
    case missingChecksum
    case invalidChecksum
    case invalidResponse
    case serverStatus(Int)
    case unavailableStorage

    var errorDescription: String? {
        switch self {
        case .missingChecksum:
            return NSLocalizedString("This release does not include a SHA-256 checksum for its IPA.", comment: "")
        case .invalidChecksum:
            return NSLocalizedString("The update checksum from GitHub is invalid.", comment: "")
        case .invalidResponse:
            return NSLocalizedString("GitHub returned an invalid package download response.", comment: "")
        case .serverStatus(let status):
            return String(
                format: NSLocalizedString("GitHub returned HTTP %d while downloading the update.", comment: ""),
                status
            )
        case .unavailableStorage:
            return NSLocalizedString("The update could not be saved in the app's Documents folder.", comment: "")
        }
    }
}

final class UpdatesSettingsSection {
    private enum UX {
        static let releaseNotesHeightRatio: CGFloat = 0.55
        static let maximumReleaseNotesHeight: CGFloat = 320
        static let maximumChecksumResponseSize = 4096
    }

    enum Row {
        case releaseNotes
        case updateNow
        case checkNow
    }

    private let updateSession: URLSession
    private var activeChecksumTask: BoundedURLDataLoader?
    private var activeUpdateTask: URLSessionDownloadTask?
    private var updateProgressObservation: NSKeyValueObservation?
    private var activeOperationID: UUID?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpMaximumConnectionsPerHost = 1
        updateSession = URLSession(configuration: configuration)
    }

    deinit {
        activeChecksumTask?.cancel()
        activeUpdateTask?.cancel()
        updateProgressObservation?.invalidate()
        updateSession.invalidateAndCancel()
    }

    func rowCount(allowUpdate: Bool) -> Int {
        return displayedRows(allowUpdate: allowUpdate).count
    }

    var installedThroughTrollStore: Bool {
        let trollStoreMarkerPath = Bundle.main.bundlePath + "/../_TrollStore"
        return access(trollStoreMarkerPath, F_OK) == 0
    }

    func rowHeight(at index: Int, allowUpdate: Bool, in tableView: UITableView) -> CGFloat {
        let rows = displayedRows(allowUpdate: allowUpdate)
        guard rows.indices.contains(index) else {
            return UITableView.automaticDimension
        }

        switch rows[index] {
        case .releaseNotes:
            return min(
                tableView.bounds.height * UX.releaseNotesHeightRatio,
                UX.maximumReleaseNotesHeight
            )
        case .updateNow, .checkNow:
            return UITableView.automaticDimension
        }
    }

    func cell(at index: Int, allowUpdate: Bool, tintColor: UIColor?) -> UITableViewCell {
        let rows = displayedRows(allowUpdate: allowUpdate)
        guard rows.indices.contains(index) else {
            return UITableViewCell()
        }

        switch rows[index] {
        case .releaseNotes:
            return UpdateReleaseNotesCell()
        case .updateNow:
            let cell = SettingsViewUtils.actionCell(
                title: NSLocalizedString("Download Update", comment: ""),
                tintColor: tintColor
            )
            cell.textLabel?.textAlignment = .center
            return cell
        case .checkNow:
            let checking = BrowserUpdates.shared.isChecking
            let cell = SettingsViewUtils.actionCell(
                title: checking ?
                NSLocalizedString("Checking for Updates…", comment: "") :
                NSLocalizedString("Check for Updates", comment: ""),
                tintColor: checking ? .secondaryLabel : tintColor
            )
            cell.textLabel?.textAlignment = .center
            cell.isUserInteractionEnabled = !checking
            return cell
        }
    }

    func footerView(allowUpdate: Bool) -> UIView {
        if !allowUpdate {
            return makeFooterView(
                text: NSLocalizedString(
                    "This build does not support in-app updates. Visit the project's Releases page to download the latest version of the app.",
                    comment: ""
                )
            )
        }
        if installedThroughTrollStore {
            let text: String
            if BrowserUpdates.shared.latestRelease?.trollStorePackage != nil {
                text = NSLocalizedString("Make sure TrollStore's URL Scheme is enabled.", comment: "")
            } else {
                text = NSLocalizedString(
                    "No TrollStore package is attached to this release. The verified unsigned IPA can still be downloaded and shared.",
                    comment: ""
                )
            }
            return makeFooterView(text: text)
        }
        return makeFooterView(
            text: NSLocalizedString(
                "The downloaded IPA is unsigned. Choose AltStore, SideStore, or another compatible signing app in the share sheet to install it.",
                comment: ""
            )
        )
    }

    func selectRow(
        at index: Int,
        allowUpdate: Bool,
        from viewController: UIViewController,
        stateDidChange: @escaping () -> Void
    ) {
        let rows = displayedRows(allowUpdate: allowUpdate)
        guard rows.indices.contains(index) else {
            return
        }

        switch rows[index] {
        case .releaseNotes:
            return
        case .updateNow:
            beginUpdate(from: viewController)
        case .checkNow:
            checkForUpdates(stateDidChange: stateDidChange)
        }
    }

    private func displayedRows(allowUpdate: Bool) -> [Row] {
        guard BrowserUpdates.shared.hasUpdate else {
            return [.checkNow]
        }

        var rows: [Row] = [.releaseNotes]
        if allowUpdate {
            rows.append(.updateNow)
        }
        rows.append(.checkNow)
        return rows
    }

    private func checkForUpdates(stateDidChange: @escaping () -> Void) {
        BrowserUpdates.shared.checkForUpdates { result in
            stateDidChange()
            switch result {
            case .updateAvailable(let release):
                AlertPresenter.show(
                    title: NSLocalizedString("Update Available", comment: ""),
                    message: String(
                        format: NSLocalizedString("Reynard %@ is available to download.", comment: ""),
                        release.version
                    )
                )
            case .upToDate:
                let info = Bundle.main.infoDictionary
                let version = info?["CFBundleShortVersionString"] as? String ?? "—"
                let build = info?["CFBundleVersion"] as? String ?? "—"
                AlertPresenter.show(
                    title: NSLocalizedString("Reynard Is Up to Date", comment: ""),
                    message: String(
                        format: NSLocalizedString("Version %@ (%@) is the latest available build.", comment: ""),
                        version,
                        build
                    )
                )
            case .failure(let error):
                AlertPresenter.show(
                    title: NSLocalizedString("Couldn’t Check for Updates", comment: ""),
                    message: error.localizedDescription
                )
            }
        }
    }

    private func beginUpdate(from viewController: UIViewController) {
        guard let release = BrowserUpdates.shared.latestRelease else {
            AlertPresenter.show(
                title: NSLocalizedString("Update Unavailable", comment: ""),
                message: NSLocalizedString("Could not retrieve the download URL.", comment: "")
            )
            return
        }

        if installedThroughTrollStore,
           let trollStorePackage = release.trollStorePackage,
           openInTrollStore(trollStorePackage) {
            return
        }

        downloadVerifiedUpdate(release.package, from: viewController)
    }

    private func openInTrollStore(_ package: BrowserUpdateAsset) -> Bool {
        guard BrowserUpdatePolicy.isAllowedReleaseDownloadURL(package.downloadURL) else {
            return false
        }
        var components = URLComponents()
        components.scheme = "apple-magnifier"
        components.host = "install"
        components.queryItems = [URLQueryItem(name: "url", value: package.downloadURL.absoluteString)]
        guard let schemeURL = components.url,
              UIApplication.shared.canOpenURL(schemeURL) else {
            return false
        }
        UIApplication.shared.open(schemeURL)
        return true
    }

    private func downloadVerifiedUpdate(
        _ package: BrowserUpdateAsset,
        from viewController: UIViewController
    ) {
        guard BrowserUpdatePolicy.isAllowedPackageName(package.name),
              BrowserUpdatePolicy.isAllowedReleaseDownloadURL(package.downloadURL),
              let checksumURL = package.checksumURL,
              BrowserUpdatePolicy.isAllowedReleaseDownloadURL(checksumURL) else {
            AlertPresenter.show(
                title: NSLocalizedString("Update Verification Unavailable", comment: ""),
                message: UpdateDownloadError.missingChecksum.localizedDescription
            )
            return
        }

        let message = NSLocalizedString(
            "The IPA will be verified with its SHA-256 checksum. When the download finishes, choose the app that you use to sign Reynard in the share sheet.",
            comment: ""
        )
        let alert = UIAlertController(
            title: NSLocalizedString("Downloading Update", comment: ""),
            message: message,
            preferredStyle: .alert
        )
        let operationID = UUID()
        guard activeOperationID == nil else {
            return
        }
        activeOperationID = operationID
        let progressView = UIProgressView(progressViewStyle: .default)
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressView.progress = 0

        alert.addAction(UIAlertAction(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) { [weak self] _ in
            self?.cancelActiveUpdate(operationID: operationID)
        })
        viewController.present(alert, animated: true) { [weak self, weak viewController] in
            guard let self,
                  let viewController else {
                return
            }
            SettingsViewUtils.addProgressView(progressView, to: alert)
            self.fetchChecksum(
                checksumURL,
                packageName: package.name,
                package: package,
                progressView: progressView,
                alert: alert,
                viewController: viewController,
                operationID: operationID
            )
        }
    }

    private func fetchChecksum(
        _ checksumURL: URL,
        packageName: String,
        package: BrowserUpdateAsset,
        progressView: UIProgressView,
        alert: UIAlertController,
        viewController: UIViewController,
        operationID: UUID
    ) {
        var request = URLRequest(url: checksumURL)
        request.setValue("Reynard-iOS-UpdateDownloader", forHTTPHeaderField: "User-Agent")
        let task = BoundedURLDataLoader(
            maximumByteCount: UX.maximumChecksumResponseSize,
            responseValidator: { response in
                guard response.statusCode == 200,
                      let responseURL = response.url else {
                    return false
                }
                return BrowserUpdatePolicy.isAllowedDownloadResponseURL(responseURL)
            },
            completion: {
                [weak self, weak alert, weak viewController, weak progressView] result in
                guard let self,
                      let alert,
                      let viewController,
                      let progressView else {
                    return
                }

                let data: Data
                switch result {
                case .success(let loadedResponse):
                    data = loadedResponse.data
                case .failure(let error):
                    let displayedError: Error = error is BoundedURLDataLoader.LoaderError ?
                    UpdateDownloadError.invalidResponse : error
                    self.finishUpdate(
                        .failure(displayedError),
                        alert: alert,
                        viewController: viewController,
                        operationID: operationID
                    )
                    return
                }

                guard data.count <= UX.maximumChecksumResponseSize,
                      let sidecar = String(data: data, encoding: .utf8),
                      let expectedChecksum = BrowserUpdatePolicy.checksum(
                        from: sidecar,
                        packageName: packageName
                      ) else {
                    self.finishUpdate(
                        .failure(UpdateDownloadError.invalidChecksum),
                        alert: alert,
                        viewController: viewController,
                        operationID: operationID
                    )
                    return
                }

                DispatchQueue.main.async {
                    guard self.activeOperationID == operationID else {
                        return
                    }
                    self.activeChecksumTask = nil
                    self.startPackageDownload(
                        package,
                        expectedChecksum: expectedChecksum,
                        progressView: progressView,
                        alert: alert,
                        viewController: viewController,
                        operationID: operationID
                    )
                }
            }
        )
        activeChecksumTask = task
        task.start(with: request)
    }

    private func startPackageDownload(
        _ package: BrowserUpdateAsset,
        expectedChecksum: String,
        progressView: UIProgressView,
        alert: UIAlertController,
        viewController: UIViewController,
        operationID: UUID
    ) {
        guard activeOperationID == operationID else {
            return
        }
        var request = URLRequest(url: package.downloadURL)
        request.setValue("Reynard-iOS-UpdateDownloader", forHTTPHeaderField: "User-Agent")
        let task = updateSession.downloadTask(with: request) {
            [weak self, weak alert, weak viewController] location, response, error in
            guard let self,
                  let alert,
                  let viewController else {
                return
            }

            if let error {
                self.finishUpdate(
                    .failure(error),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
                return
            }
            guard let httpResponse = response as? HTTPURLResponse,
                  let responseURL = httpResponse.url,
                  BrowserUpdatePolicy.isAllowedDownloadResponseURL(responseURL) else {
                self.finishUpdate(
                    .failure(UpdateDownloadError.invalidResponse),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
                return
            }
            guard httpResponse.statusCode == 200 else {
                self.finishUpdate(
                    .failure(UpdateDownloadError.serverStatus(httpResponse.statusCode)),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
                return
            }
            guard let location else {
                self.finishUpdate(
                    .failure(UpdateDownloadError.invalidResponse),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
                return
            }

            do {
                try UpdatePackageVerifier.verify(
                    fileURL: location,
                    expectedSize: package.size,
                    expectedSHA256: expectedChecksum
                )
                let destinationURL = try self.saveDownloadedPackage(
                    from: location,
                    fileName: package.name
                )
                self.finishUpdate(
                    .success(destinationURL),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
            } catch {
                self.finishUpdate(
                    .failure(error),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
            }
        }
        activeUpdateTask = task
        updateProgressObservation = task.progress.observe(
            \.fractionCompleted,
            options: [.new]
        ) { [weak self, weak task, weak progressView, weak alert, weak viewController] progress, _ in
            guard let self,
                  let task,
                  let alert,
                  let viewController else {
                return
            }
            if progress.completedUnitCount > package.size {
                task.cancel()
                self.finishUpdate(
                    .failure(UpdatePackageVerificationError.invalidSize),
                    alert: alert,
                    viewController: viewController,
                    operationID: operationID
                )
                return
            }
            DispatchQueue.main.async {
                progressView?.setProgress(Float(progress.fractionCompleted), animated: true)
            }
        }
        task.resume()
    }

    private func saveDownloadedPackage(from temporaryURL: URL, fileName: String) throws -> URL {
        guard BrowserUpdatePolicy.isAllowedPackageName(fileName),
              let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
              ).first else {
            throw UpdateDownloadError.unavailableStorage
        }

        let updatesDirectory = documentsURL.appendingPathComponent("Updates", isDirectory: true)
        try FileManager.default.createDirectory(
            at: updatesDirectory,
            withIntermediateDirectories: true
        )
        let destinationURL = updatesDirectory.appendingPathComponent(fileName, isDirectory: false)
        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destinationURL)
        var excludedURL = destinationURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? excludedURL.setResourceValues(resourceValues)
        return destinationURL
    }

    private func finishUpdate(
        _ result: Result<URL, Error>,
        alert: UIAlertController,
        viewController: UIViewController,
        operationID: UUID
    ) {
        DispatchQueue.main.async {
            guard self.activeOperationID == operationID else {
                return
            }
            self.activeOperationID = nil
            self.activeChecksumTask = nil
            self.activeUpdateTask = nil
            self.updateProgressObservation?.invalidate()
            self.updateProgressObservation = nil

            if case .failure(let error) = result {
                let nsError = error as NSError
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
            }

            SettingsViewUtils.dismissPresentedAlert(alert, from: viewController) {
                switch result {
                case .success(let packageURL):
                    self.shareDownloadedUpdate(at: packageURL, from: viewController)
                case .failure(let error):
                    AlertPresenter.show(
                        title: NSLocalizedString("Update Download Failed", comment: ""),
                        message: error.localizedDescription
                    )
                }
            }
        }
    }

    private func cancelActiveUpdate(operationID: UUID) {
        guard activeOperationID == operationID else {
            return
        }
        activeOperationID = nil
        activeChecksumTask?.cancel()
        activeUpdateTask?.cancel()
        activeChecksumTask = nil
        activeUpdateTask = nil
        updateProgressObservation?.invalidate()
        updateProgressObservation = nil
    }

    private func makeFooterView(text: String) -> UIView {
        let footerView = UITableViewHeaderFooterView(reuseIdentifier: nil)
        footerView.contentView.preservesSuperviewLayoutMargins = true

        let footerLabel = UILabel()
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.numberOfLines = 0
        footerLabel.font = UIFont.preferredFont(forTextStyle: .footnote)
        footerLabel.adjustsFontForContentSizeCategory = true
        footerLabel.textColor = .secondaryLabel
        footerLabel.text = text

        footerView.contentView.addSubview(footerLabel)
        NSLayoutConstraint.activate([
            footerLabel.leadingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.trailingAnchor),
            footerLabel.topAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.topAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: footerView.contentView.layoutMarginsGuide.bottomAnchor),
        ])
        return footerView
    }

    private func shareDownloadedUpdate(at updateFileURL: URL, from viewController: UIViewController) {
        let activityController = UIActivityViewController(
            activityItems: [updateFileURL],
            applicationActivities: nil
        )
        if let popover = activityController.popoverPresentationController {
            popover.sourceView = viewController.view
            popover.sourceRect = CGRect(
                x: viewController.view.bounds.midX,
                y: viewController.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        viewController.present(activityController, animated: true)
    }
}
