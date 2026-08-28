//
//  DownloadStore.swift
//  Reynard
//
//  Created by Minh Ton on 2/4/26.
//

import Foundation
import GeckoView
import UniformTypeIdentifiers
import MobileCoreServices

struct DownloadStoreSummary {
    let totalCount: Int
    let activeCount: Int
    let aggregateProgress: Float
    let hasUnviewedCompletedDownloads: Bool

    var showsToolbarButton: Bool {
        return activeCount > 0 || (hasUnviewedCompletedDownloads && totalCount > 0)
    }
}

struct DownloadStoreSnapshot {
    let summary: DownloadStoreSummary
    let items: [DownloadItemSnapshot]
}

struct DownloadItemSnapshot {
    enum State: Equatable {
        case downloading
        case paused
        case cancelled
        case failed
        case completed
    }

    let id: UUID
    let fileName: String
    let fileURL: URL?
    let sourceURL: URL
    let originalURL: URL?
    let mimeType: String?
    let state: State
    let canPause: Bool
    let fileExists: Bool
    let totalBytes: Int64?
    let downloadedBytes: Int64
    let bytesPerSecond: Int64
    let addedAt: Date
    let failureDescription: String?
    let canRetry: Bool
}

final class DownloadStore: NSObject {
    static let shared = DownloadStore()

    struct WebExtensionDownloadItem {
        let id: Int
        let fileName: String
        let localFilePath: String
        let mimeType: String?
        let addedAt: Date
    }

    struct PendingDownload {
        let fileName: String
        let sourceHost: String
        let expectedBytes: Int64?
        let mimeType: String?
        fileprivate let startHandler: () -> WebExtensionDownloadItem?
    }

    private struct StorageURLs {
        let downloadsDirectoryURL: URL
        let appDataDirectoryURL: URL
        let manifestFileURL: URL
        let manifestBackupFileURL: URL
    }

    private enum PersistedDownloadState: String, Codable {
        case inProgress = "active"
        case cancelled
        case completed
        case failed
    }

    private struct PersistedDownloadEntry: Codable {
        let id: UUID
        let fileName: String
        let relativePath: String
        let sourceURLString: String
        let originalURLString: String?
        let mimeType: String?
        let fileSize: Int64
        let addedAt: Date
        var state: PersistedDownloadState?
        var failureDescription: String?
        let canRetry: Bool?

        var effectiveState: PersistedDownloadState {
            return state ?? .completed
        }
    }

    private struct ProgressSample {
        let bytesWritten: Int64
        let timestamp: TimeInterval
    }

    private final class ActiveDownload {
        let id: UUID
        let sourceURL: URL
        let originalURL: URL?
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        let task: URLSessionDownloadTask
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        var isPaused: Bool

        init(
            id: UUID,
            sourceURL: URL,
            originalURL: URL?,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            task: URLSessionDownloadTask
        ) {
            self.id = id
            self.sourceURL = sourceURL
            self.originalURL = originalURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.task = task
            self.expectedBytes = nil
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
            self.isPaused = false
        }
    }

    private struct CapturedDownloadControls {
        let cancel: () -> Void
        let pause: () -> Void
        let resume: () -> Void
    }

    private final class CapturedDownload {
        let id: UUID
        let localFilePath: String
        let sourceURL: URL
        let fileName: String
        let destinationURL: URL
        let mimeType: String?
        let addedAt: Date
        let controls: CapturedDownloadControls?
        weak var originatingSession: GeckoSession?
        var expectedBytes: Int64?
        var downloadedBytes: Int64
        var bytesPerSecond: Int64
        var lastProgressSample: ProgressSample?
        var isPaused: Bool

        init(
            id: UUID,
            localFilePath: String,
            sourceURL: URL,
            fileName: String,
            destinationURL: URL,
            mimeType: String?,
            addedAt: Date,
            expectedBytes: Int64?,
            controls: CapturedDownloadControls? = nil,
            originatingSession: GeckoSession? = nil
        ) {
            self.id = id
            self.localFilePath = localFilePath
            self.sourceURL = sourceURL
            self.fileName = fileName
            self.destinationURL = destinationURL
            self.mimeType = mimeType
            self.addedAt = addedAt
            self.controls = controls
            self.originatingSession = originatingSession
            self.expectedBytes = expectedBytes
            self.downloadedBytes = 0
            self.bytesPerSecond = 0
            self.isPaused = false
        }
    }

    private let fileManager: FileManager
    private let storage: StorageURLs
    private let storageIsAvailable: Bool
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.DownloadStore.Queue", qos: .userInitiated)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var activeDownloads: [Int: ActiveDownload] = [:]
    private var capturedDownloads: [String: CapturedDownload] = [:]
    private var persistedDownloads: [PersistedDownloadEntry] = []
    private let progressNotificationInterval: TimeInterval = 0.35
    private var lastProgressNotificationTime: TimeInterval = 0
    private var pendingProgressNotification: DispatchWorkItem?
    private var progressNotificationGeneration = 0
    private var hasUnviewedCompletedDownloads = false
    private var nextWebExtensionDownloadID = 1

    // MARK: - Lifecycle

    override init() {
        self.fileManager = .default

        let documentsDirectoryURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
        let applicationSupportDirectoryURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        self.storageIsAvailable = documentsDirectoryURL != nil && applicationSupportDirectoryURL != nil
        let fallbackDirectoryURL = fileManager.temporaryDirectory.appendingPathComponent("ReynardUnavailableStorage", isDirectory: true)

        let downloadsDirectoryURL = (documentsDirectoryURL ?? fallbackDirectoryURL).appendingPathComponent("Downloads", isDirectory: true)
        let appDataDirectoryURL = (applicationSupportDirectoryURL ?? fallbackDirectoryURL).appendingPathComponent("AppData", isDirectory: true)
        let manifestFileURL = appDataDirectoryURL.appendingPathComponent("DownloadStore", isDirectory: false)
        self.storage = StorageURLs(
            downloadsDirectoryURL: downloadsDirectoryURL,
            appDataDirectoryURL: appDataDirectoryURL,
            manifestFileURL: manifestFileURL,
            manifestBackupFileURL: appDataDirectoryURL.appendingPathComponent("DownloadStore.backup", isDirectory: false)
        )

        super.init()

        stateQueue.sync {
            self.prepareStorageLocked()
            self.loadPersistedDownloadsLocked()
        }
    }

    // MARK: - Downloads

    func currentSnapshot() -> DownloadStoreSnapshot {
        stateQueue.sync {
            makeSnapshotLocked()
        }
    }

    // MARK: - Pending Downloads

    func pendingDownload(from response: ExternalResponseInfo, session: GeckoSession) -> PendingDownload? {
        guard storageIsAvailable,
              let sourceURL = URL(string: response.url),
              DownloadFileSafety.capturedTemporaryFileURL(forPath: response.localFilePath) != nil else {
            return nil
        }

        let fileName = resolvedFileName(
            suggestedFileName: response.filename,
            sourceURL: sourceURL,
            mimeType: response.mimeType
        )
        let controls = CapturedDownloadControls(
            cancel: response.cancel,
            pause: response.pause,
            resume: response.resume
        )

        return PendingDownload(
            fileName: fileName,
            sourceHost: sourceURL.host ?? sourceURL.absoluteString,
            expectedBytes: response.contentLength.flatMap { $0 > 0 ? $0 : nil },
            mimeType: response.mimeType,
            startHandler: { [weak self] in
                self?.beginCapturedDownload(
                    localFilePath: response.localFilePath,
                    sourceURL: sourceURL,
                    fileName: fileName,
                    mimeType: response.mimeType,
                    expectedBytes: response.contentLength,
                    controls: controls,
                    originatingSession: session
                )
                return nil
            }
        )
    }

    func pendingDownload(from request: SavePdfInfo) -> PendingDownload? {
        guard storageIsAvailable else {
            return nil
        }
        let candidateURLs = [request.url, request.originalUrl].compactMap { $0 }.compactMap(URL.init(string:))
        guard let sourceURL = candidateURLs.first(where: { URLUtils.isWebURL($0) }) else {
            return nil
        }

        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: request.filename,
                sourceURL: sourceURL,
                mimeType: "application/pdf"
            ),
            sourceHost: sourceURL.host ?? sourceURL.absoluteString,
            expectedBytes: nil,
            mimeType: "application/pdf",
            startHandler: { [weak self] in
                self?.enqueueDownload(
                    sourceURL: sourceURL,
                    originalURL: URL(string: request.originalUrl ?? ""),
                    suggestedFileName: request.filename,
                    mimeType: "application/pdf"
                )
                return nil
            }
        )
    }

    func pendingDownload(from options: [String: Any?]) -> PendingDownload? {
        guard storageIsAvailable,
              let urlString = options["url"] as? String,
              let sourceURL = URL(string: urlString) else {
            return nil
        }

        let suggestedFileName = options["filename"] as? String
        let mimeType = options["mimeType"] as? String

        return PendingDownload(
            fileName: resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            ),
            sourceHost: sourceURL.host ?? sourceURL.absoluteString,
            expectedBytes: nil,
            mimeType: mimeType,
            startHandler: { [weak self] in
                self?.beginWebExtensionDownload(
                    sourceURL: sourceURL,
                    suggestedFileName: suggestedFileName,
                    mimeType: mimeType
                )
            }
        )
    }

    @discardableResult
    func startDownload(_ pendingDownload: PendingDownload) -> WebExtensionDownloadItem? {
        return pendingDownload.startHandler()
    }

    // MARK: - Captured Download Events

    func updateCapturedDownload(localFilePath: String, bytesReceived: Int64) -> Bool {
        return stateQueue.sync {
            guard let active = capturedDownloads[localFilePath] else {
                return false
            }

            updateCapturedProgress(active, bytesReceived: bytesReceived)
            return true
        }
    }

    func completeCapturedDownload(localFilePath: String, succeeded: Bool) {
        stateQueue.sync {
            self.completeCapturedDownloadLocked(
                localFilePath: localFilePath,
                succeeded: succeeded
            )
        }
    }

    func failCapturedDownloads(for session: GeckoSession) {
        stateQueue.sync {
            let terminatedDownloads = capturedDownloads.values.filter {
                $0.originatingSession === session
            }
            for download in terminatedDownloads {
                capturedDownloads.removeValue(forKey: download.localFilePath)
                if let temporaryURL = DownloadFileSafety.capturedTemporaryFileURL(forPath: download.localFilePath) {
                    try? fileManager.removeItem(at: temporaryURL)
                }
                storePersistedEntryLocked(
                    makePersistedEntry(for: download, state: .failed,
                        failureDescription: NSLocalizedString("Download failed in the browser engine.", comment: "Download failure"))
                )
            }
            if !terminatedDownloads.isEmpty {
                postDidChange()
            }
        }
    }

    // MARK: - Download Management

    func cancel(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                self.activeDownloads.removeValue(forKey: active.task.taskIdentifier)
                self.storePersistedEntryLocked(
                    self.makePersistedEntry(for: active, state: .cancelled)
                )
                active.task.cancel()
                self.postDidChange()
                return
            }

            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }) else {
                return
            }

            self.capturedDownloads.removeValue(forKey: captured.localFilePath)
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: captured, state: .cancelled)
            )
            captured.controls?.cancel()
            if let temporaryURL = DownloadFileSafety.capturedTemporaryFileURL(forPath: captured.localFilePath) {
                try? self.fileManager.removeItem(at: temporaryURL)
            }
            self.postDidChange()
        }
    }

    func pause(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                guard !active.isPaused else {
                    return
                }

                active.task.suspend()
                active.isPaused = true
                active.bytesPerSecond = 0
                active.lastProgressSample = nil
                self.postDidChange()
                return
            }

            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }),
                  let controls = captured.controls,
                  !captured.isPaused else {
                return
            }

            controls.pause()
            captured.isPaused = true
            captured.bytesPerSecond = 0
            captured.lastProgressSample = nil
            self.postDidChange()
        }
    }

    func resume(id: UUID) {
        stateQueue.async {
            if let active = self.activeDownloads.values.first(where: { $0.id == id }) {
                guard active.isPaused else {
                    return
                }

                active.task.resume()
                active.isPaused = false
                active.bytesPerSecond = 0
                active.lastProgressSample = nil
                self.postDidChange()
                return
            }

            guard let captured = self.capturedDownloads.values.first(where: { $0.id == id }),
                  let controls = captured.controls,
                  captured.isPaused else {
                return
            }

            controls.resume()
            captured.isPaused = false
            captured.bytesPerSecond = 0
            captured.lastProgressSample = nil
            self.postDidChange()
        }
    }

    func retry(id: UUID) {
        stateQueue.async {
            guard let index = self.persistedDownloads.firstIndex(where: { $0.id == id }),
                  self.persistedDownloads[index].canRetry == true,
                  [.failed, .cancelled].contains(self.persistedDownloads[index].effectiveState),
                  let sourceURL = URL(string: self.persistedDownloads[index].sourceURLString),
                  URLUtils.isWebURL(sourceURL), self.storageIsAvailable else {
                return
            }
            let entry = self.persistedDownloads.remove(at: index)
            self.savePersistedDownloadsLocked()
            self.enqueueDownload(
                sourceURL: sourceURL,
                originalURL: entry.originalURLString.flatMap(URL.init(string:)),
                suggestedFileName: entry.fileName,
                mimeType: entry.mimeType
            )
            self.postDidChange()
        }
    }

    func removeDownload(id: UUID) {
        stateQueue.async {
            guard let index = self.persistedDownloads.firstIndex(where: { $0.id == id }),
                  self.persistedDownloads[index].effectiveState != .inProgress else { return }
            let entry = self.persistedDownloads.remove(at: index)
            // Failed/cancelled records do not own a file; a later download may reuse that name.
            if entry.effectiveState == .completed,
               let fileURL = DownloadFileSafety.containedFileURL(
                   forRelativePath: entry.relativePath, in: self.storage.downloadsDirectoryURL
               ) {
                try? self.fileManager.removeItem(at: fileURL)
            }
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }

    func clearCompletedDownloadFiles(since startDate: Date? = nil) {
        stateQueue.async {
            let partition = DownloadCleanupPolicy.partition(
                self.persistedDownloads,
                since: startDate,
                addedAt: { $0.addedAt },
                isActive: { $0.effectiveState == .inProgress }
            )
            self.persistedDownloads = partition.retained
            for entry in partition.removed where entry.effectiveState == .completed {
                if let fileURL = DownloadFileSafety.containedFileURL(
                    forRelativePath: entry.relativePath, in: self.storage.downloadsDirectoryURL
                ) {
                    try? self.fileManager.removeItem(at: fileURL)
                }
            }
            self.savePersistedDownloadsLocked()
            self.postDidChange()
        }
    }

    func markCompletedAsViewed() {
        stateQueue.async {
            guard self.hasUnviewedCompletedDownloads else {
                return
            }

            self.hasUnviewedCompletedDownloads = false
            self.postDidChange()
        }
    }

    // MARK: - Captured Downloads

    private func beginCapturedDownload(
        localFilePath: String,
        sourceURL: URL,
        fileName: String,
        mimeType: String?,
        expectedBytes: Int64?,
        controls: CapturedDownloadControls,
        originatingSession: GeckoSession
    ) {
        stateQueue.sync {
            guard self.storageIsAvailable,
                  DownloadFileSafety.capturedTemporaryFileURL(forPath: localFilePath) != nil,
                  self.capturedDownloads[localFilePath] == nil else {
                controls.cancel()
                return
            }
            self.prepareStorageLocked()

            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            let active = CapturedDownload(
                id: UUID(),
                localFilePath: localFilePath,
                sourceURL: sourceURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                expectedBytes: expectedBytes.flatMap { $0 > 0 ? $0 : nil },
                controls: controls,
                originatingSession: originatingSession
            )
            self.capturedDownloads[localFilePath] = active
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: active, state: .inProgress)
            )
            self.postDidStartDownload()
            self.postDidChange()
        }
    }

    private func beginWebExtensionDownload(
        sourceURL: URL,
        suggestedFileName: String?,
        mimeType: String?
    ) -> WebExtensionDownloadItem? {
        return stateQueue.sync {
            guard self.storageIsAvailable else {
                return nil
            }
            self.prepareStorageLocked()

            let fileName = self.resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)
            let localFilePath = self.fileManager.temporaryDirectory
                .appendingPathComponent(
                    "reynard-download-webextension-\(UUID().uuidString)",
                    isDirectory: false
                )
                .path
            let downloadID = self.nextWebExtensionDownloadID
            self.nextWebExtensionDownloadID += 1
            let addedAt = Date()

            let active = CapturedDownload(
                id: UUID(),
                localFilePath: localFilePath,
                sourceURL: sourceURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: addedAt,
                expectedBytes: nil
            )
            self.capturedDownloads[localFilePath] = active
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: active, state: .inProgress)
            )
            self.postDidStartDownload()
            self.postDidChange()

            return WebExtensionDownloadItem(
                id: downloadID,
                fileName: destinationURL.lastPathComponent,
                localFilePath: localFilePath,
                mimeType: mimeType,
                addedAt: addedAt
            )
        }
    }

    // MARK: - URL Session Downloads

    private func enqueueDownload(
        sourceURL: URL,
        originalURL: URL?,
        suggestedFileName: String?,
        mimeType: String?
    ) {
        stateQueue.async {
            guard self.storageIsAvailable, URLUtils.isWebURL(sourceURL) else {
                return
            }
            self.prepareStorageLocked()

            let fileName = self.resolvedFileName(
                suggestedFileName: suggestedFileName,
                sourceURL: sourceURL,
                mimeType: mimeType
            )
            let destinationURL = self.makeUniqueDestinationURLLocked(for: fileName)

            let task = self.session.downloadTask(with: sourceURL)
            let active = ActiveDownload(
                id: UUID(),
                sourceURL: sourceURL,
                originalURL: originalURL,
                fileName: destinationURL.lastPathComponent,
                destinationURL: destinationURL,
                mimeType: mimeType,
                addedAt: Date(),
                task: task
            )

            self.activeDownloads[task.taskIdentifier] = active
            self.storePersistedEntryLocked(
                self.makePersistedEntry(for: active, state: .inProgress)
            )
            task.resume()
            self.postDidStartDownload()
            self.postDidChange()
        }
    }

    // MARK: - Snapshots

    private func makeSnapshotLocked() -> DownloadStoreSnapshot {
        let sessionItems = activeDownloads.values
            .map { active in
                DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: active.originalURL,
                    mimeType: active.mimeType,
                    state: active.isPaused ? .paused : .downloading,
                    canPause: true,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt,
                    failureDescription: nil,
                    canRetry: false
                )
            }
            .sorted { $0.addedAt > $1.addedAt }

        let capturedItems = capturedDownloads.values
            .map { active in
                let canPause = active.controls != nil
                return DownloadItemSnapshot(
                    id: active.id,
                    fileName: active.fileName,
                    fileURL: nil,
                    sourceURL: active.sourceURL,
                    originalURL: nil,
                    mimeType: active.mimeType,
                    state: active.isPaused && canPause ? .paused : .downloading,
                    canPause: canPause,
                    fileExists: true,
                    totalBytes: active.expectedBytes,
                    downloadedBytes: active.downloadedBytes,
                    bytesPerSecond: active.bytesPerSecond,
                    addedAt: active.addedAt,
                    failureDescription: nil,
                    canRetry: false
                )
            }

        let activeItems = (sessionItems + capturedItems)
            .sorted { $0.addedAt > $1.addedAt }

        let terminalItems = persistedDownloads
            .compactMap { entry -> DownloadItemSnapshot? in
                guard entry.effectiveState != .inProgress else {
                    return nil
                }

                let fileURL = DownloadFileSafety.containedFileURL(forRelativePath: entry.relativePath, in: storage.downloadsDirectoryURL)
                let isCompleted = entry.effectiveState == .completed
                let itemState: DownloadItemSnapshot.State
                if entry.effectiveState == .cancelled {
                    itemState = .cancelled
                } else if isCompleted {
                    itemState = .completed
                } else {
                    itemState = .failed
                }
                return DownloadItemSnapshot(
                    id: entry.id,
                    fileName: entry.fileName,
                    fileURL: isCompleted ? fileURL : nil,
                    sourceURL: URL(string: entry.sourceURLString) ?? storage.downloadsDirectoryURL,
                    originalURL: entry.originalURLString.flatMap(URL.init(string:)),
                    mimeType: entry.mimeType,
                    state: itemState,
                    canPause: false,
                    fileExists: isCompleted && (fileURL.map { fileManager.fileExists(atPath: $0.path) } ?? false),
                    totalBytes: isCompleted ? entry.fileSize : nil,
                    downloadedBytes: isCompleted ? entry.fileSize : 0,
                    bytesPerSecond: 0,
                    addedAt: entry.addedAt,
                    failureDescription: entry.failureDescription,
                    canRetry: !isCompleted && entry.canRetry == true
                )
            }

        return DownloadStoreSnapshot(summary: makeSummaryLocked(), items: activeItems + terminalItems)
    }

    private func makeSummaryLocked() -> DownloadStoreSummary {
        let activeProgress = activeDownloads.values.map { ($0.expectedBytes, $0.downloadedBytes) }
        + capturedDownloads.values.map { ($0.expectedBytes, $0.downloadedBytes) }
        let hasUnknownExpectedBytes = activeProgress.contains { $0.0 == nil }
        let totalExpectedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + max(item.0 ?? 0, 0)
        }
        let totalDownloadedBytes = activeProgress.reduce(Int64(0)) { partialResult, item in
            partialResult + min(item.1, item.0 ?? item.1)
        }
        let aggregateProgress: Float
        if totalExpectedBytes > 0 && !hasUnknownExpectedBytes {
            aggregateProgress = Float(totalDownloadedBytes) / Float(totalExpectedBytes)
        } else {
            aggregateProgress = 0
        }

        let terminalCount = persistedDownloads.lazy.filter { $0.effectiveState != .inProgress }.count
        return DownloadStoreSummary(
            totalCount: terminalCount + activeProgress.count,
            activeCount: activeProgress.count,
            aggregateProgress: min(max(aggregateProgress, 0), 1),
            hasUnviewedCompletedDownloads: hasUnviewedCompletedDownloads
        )
    }

    // MARK: - Persistence

    private func prepareStorageLocked() {
        guard storageIsAvailable else { return }
        try? fileManager.createDirectory(at: storage.downloadsDirectoryURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: storage.appDataDirectoryURL, withIntermediateDirectories: true)
        // Do not create an empty primary manifest before attempting backup recovery.
    }

    private func loadPersistedDownloadsLocked() {
        guard storageIsAvailable else { return }
        let recovery = DownloadManifestRecovery.recover(
            primaryData: try? Data(contentsOf: storage.manifestFileURL),
            backupData: try? Data(contentsOf: storage.manifestBackupFileURL),
            decode: decodedAndValidatedEntries(from:)
        )
        var entries = recovery.entries
        var interrupted = false
        for index in entries.indices where entries[index].effectiveState == .inProgress {
            entries[index].state = .failed
            entries[index].failureDescription = NSLocalizedString("The download was interrupted when the app closed.", comment: "Download recovery")
            interrupted = true
        }
        persistedDownloads = entries.sorted { $0.addedAt > $1.addedAt }
        if recovery.source != .primary || interrupted {
            writeManifestLocked(createBackup: recovery.source == .primary)
        }
    }

    private func savePersistedDownloadsLocked() {
        writeManifestLocked(createBackup: true)
    }

    private func writeManifestLocked(createBackup: Bool) {
        guard storageIsAvailable else {
            return
        }
        guard let data = try? JSONEncoder().encode(persistedDownloads.sorted { $0.addedAt > $1.addedAt }) else {
            return
        }

        if createBackup,
           let currentData = try? Data(contentsOf: storage.manifestFileURL),
           decodedAndValidatedEntries(from: currentData) != nil {
            try? currentData.write(to: storage.manifestBackupFileURL, options: .atomic)
        }
        try? data.write(to: storage.manifestFileURL, options: .atomic)
    }

    private func decodedAndValidatedEntries(from data: Data) -> [PersistedDownloadEntry]? {
        guard let decoded = try? JSONDecoder().decode([PersistedDownloadEntry].self, from: data) else {
            return nil
        }
        return decoded.filter {
            DownloadFileSafety.containedFileURL(
                forRelativePath: $0.relativePath,
                in: storage.downloadsDirectoryURL
            ) != nil
        }
    }

    private func makePersistedEntry(
        for download: ActiveDownload,
        state: PersistedDownloadState,
        fileSize: Int64 = 0,
        failureDescription: String? = nil
    ) -> PersistedDownloadEntry {
        return PersistedDownloadEntry(
            id: download.id,
            fileName: download.fileName,
            relativePath: download.destinationURL.lastPathComponent,
            sourceURLString: download.sourceURL.absoluteString,
            originalURLString: download.originalURL?.absoluteString,
            mimeType: download.mimeType,
            fileSize: fileSize,
            addedAt: download.addedAt,
            state: state,
            failureDescription: failureDescription,
            canRetry: true
        )
    }

    private func makePersistedEntry(
        for download: CapturedDownload,
        state: PersistedDownloadState,
        fileSize: Int64 = 0,
        failureDescription: String? = nil
    ) -> PersistedDownloadEntry {
        return PersistedDownloadEntry(
            id: download.id,
            fileName: download.fileName,
            relativePath: download.destinationURL.lastPathComponent,
            sourceURLString: download.sourceURL.absoluteString,
            originalURLString: nil,
            mimeType: download.mimeType,
            fileSize: fileSize,
            addedAt: download.addedAt,
            state: state,
            failureDescription: failureDescription,
            canRetry: false
        )
    }

    private func storePersistedEntryLocked(_ entry: PersistedDownloadEntry) {
        if let index = persistedDownloads.firstIndex(where: { $0.id == entry.id }) {
            persistedDownloads[index] = entry
        } else {
            persistedDownloads.insert(entry, at: 0)
        }
        savePersistedDownloadsLocked()
    }

    // MARK: - Files

    private func resolvedFileName(suggestedFileName: String?, sourceURL: URL, mimeType: String?) -> String {
        let fallbackName = sourceURL.lastPathComponent.isEmpty ? NSLocalizedString("Download", comment: "") : sourceURL.lastPathComponent
        let initialName = DownloadFileSafety.sanitizedFileName(
            suggestedFileName ?? fallbackName,
            fallback: NSLocalizedString("Download", comment: "")
        )

        guard URL(fileURLWithPath: initialName).pathExtension.isEmpty,
              let mimeType,
              let contentType = UTTypeCreatePreferredIdentifierForTag(
                kUTTagClassMIMEType,
                mimeType as CFString,
                nil
              )?.takeRetainedValue(),
              let preferredExtension = UTTypeCopyPreferredTagWithClass(
                contentType,
                kUTTagClassFilenameExtension
              )?.takeRetainedValue() as String? else {
            return initialName
        }

        return DownloadFileSafety.sanitizedFileName(
            "\(initialName).\(preferredExtension)",
            fallback: NSLocalizedString("Download", comment: "")
        )
    }

    private func makeUniqueDestinationURLLocked(for fileName: String) -> URL {
        let activeNames = Set(
            activeDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() }
            + capturedDownloads.values.map { $0.destinationURL.lastPathComponent.lowercased() }
        )
        return DownloadFileSafety.uniqueDestinationURL(
            for: fileName,
            in: storage.downloadsDirectoryURL,
            reservedFileNames: activeNames,
            fileExists: { self.fileManager.fileExists(atPath: $0.path) }
        )
    }

    private func importFileLocked(from sourceURL: URL, to destinationURL: URL) -> Bool {
        guard fileManager.fileExists(atPath: sourceURL.path),
              DownloadFileSafety.containedFileURL(
                  forRelativePath: destinationURL.lastPathComponent,
                  in: storage.downloadsDirectoryURL
              ) == destinationURL.standardizedFileURL,
              !fileManager.fileExists(atPath: destinationURL.path) else {
            return false
        }

        do {
            do {
                try fileManager.moveItem(at: sourceURL, to: destinationURL)
            } catch {
                try fileManager.copyItem(at: sourceURL, to: destinationURL)
                try? fileManager.removeItem(at: sourceURL)
            }

            return true
        } catch {
            return false
        }
    }

    // MARK: - Transfer Lifecycle

    private func completeCapturedDownloadLocked(localFilePath: String, succeeded: Bool) {
        guard let active = capturedDownloads.removeValue(forKey: localFilePath) else {
            // Ignore stale/unknown engine events instead of deleting arbitrary paths.
            return
        }

        guard let sourceFileURL = DownloadFileSafety.capturedTemporaryFileURL(forPath: localFilePath) else {
            storePersistedEntryLocked(makePersistedEntry(for: active, state: .failed,
                failureDescription: NSLocalizedString("Couldn’t save the downloaded file.", comment: "Download failure")))
            postDidChange()
            return
        }

        guard succeeded else {
            try? fileManager.removeItem(at: sourceFileURL)
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .failed,
                    failureDescription: NSLocalizedString("Download failed in the browser engine.", comment: "Download failure"))
            )
            postDidChange()
            return
        }

        prepareStorageLocked()

        guard importFileLocked(from: sourceFileURL, to: active.destinationURL) else {
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .failed,
                    failureDescription: NSLocalizedString("Couldn’t save the downloaded file.", comment: "Download failure"))
            )
            postDidChange()
            return
        }

        let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes
        storePersistedEntryLocked(
            makePersistedEntry(for: active, state: .completed, fileSize: fileSize)
        )
        hasUnviewedCompletedDownloads = true
        postDidChange()
    }

    private func updateCapturedProgress(_ active: CapturedDownload, bytesReceived: Int64) {
        active.downloadedBytes = max(bytesReceived, 0)
        guard !active.isPaused else {
            postProgressDidChangeLocked()
            return
        }

        updateTransferRate(
            totalBytesWritten: bytesReceived,
            bytesPerSecond: &active.bytesPerSecond,
            lastProgressSample: &active.lastProgressSample
        )
        postProgressDidChangeLocked()
    }

    private func updateTransferRate(
        totalBytesWritten: Int64,
        bytesPerSecond: inout Int64,
        lastProgressSample: inout ProgressSample?
    ) {
        let now = ProcessInfo.processInfo.systemUptime
        if let previousSample = lastProgressSample {
            let deltaTime = max(now - previousSample.timestamp, 0.001)
            let deltaBytes = max(totalBytesWritten - previousSample.bytesWritten, 0)
            let instantaneousSpeed = Int64(Double(deltaBytes) / deltaTime)
            if bytesPerSecond == 0 {
                bytesPerSecond = instantaneousSpeed
            } else {
                let smoothedSpeed = (Double(bytesPerSecond) * 0.65) + (Double(instantaneousSpeed) * 0.35)
                bytesPerSecond = Int64(smoothedSpeed)
            }
        }
        lastProgressSample = ProgressSample(bytesWritten: totalBytesWritten, timestamp: now)
    }

    private func completeDownload(taskIdentifier: Int, temporaryLocation: URL) {
        guard let active = activeDownloads.removeValue(forKey: taskIdentifier) else {
            return
        }

        prepareStorageLocked()

        do {
            guard DownloadFileSafety.containedFileURL(
                forRelativePath: active.destinationURL.lastPathComponent,
                in: storage.downloadsDirectoryURL
            ) == active.destinationURL.standardizedFileURL else {
                throw CocoaError(.fileWriteInvalidFileName)
            }
            // moveItem refuses to overwrite a file created after this download began.
            try fileManager.moveItem(at: temporaryLocation, to: active.destinationURL)
            let fileSize = resolvedFileSize(at: active.destinationURL) ?? active.downloadedBytes

            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .completed, fileSize: fileSize)
            )
            hasUnviewedCompletedDownloads = true
        } catch {
            try? fileManager.removeItem(at: temporaryLocation)
            storePersistedEntryLocked(
                makePersistedEntry(for: active, state: .failed,
                    failureDescription: failureDescription(for: error))
            )
        }

        postDidChange()
    }

    private func resolvedFileSize(at url: URL) -> Int64? {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else {
            return nil
        }

        return size.int64Value
    }

    private func updateProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let active = activeDownloads[taskIdentifier] else {
            return
        }

        active.downloadedBytes = max(totalBytesWritten, 0)
        if totalBytesExpectedToWrite > 0 {
            active.expectedBytes = totalBytesExpectedToWrite
        }

        guard !active.isPaused else {
            postProgressDidChangeLocked()
            return
        }

        updateTransferRate(
            totalBytesWritten: totalBytesWritten,
            bytesPerSecond: &active.bytesPerSecond,
            lastProgressSample: &active.lastProgressSample
        )

        postProgressDidChangeLocked()
    }

    private func failDownload(taskIdentifier: Int, error: Error) {
        guard let active = activeDownloads.removeValue(forKey: taskIdentifier) else {
            return
        }

        storePersistedEntryLocked(
            makePersistedEntry(for: active, state: .failed,
                failureDescription: failureDescription(for: error))
        )
        postDidChange()
    }

    private func failureDescription(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            switch nsError.code {
            case NSFileWriteOutOfSpaceError:
                return NSLocalizedString("Not enough storage space.", comment: "Download failure")
            case NSFileWriteNoPermissionError, NSFileReadNoPermissionError:
                return NSLocalizedString("Reynard doesn’t have permission to save this file.", comment: "Download failure")
            default:
                return NSLocalizedString("Couldn’t save the downloaded file.", comment: "Download failure")
            }
        }

        if nsError.domain == NSURLErrorDomain {
            if nsError.code == NSURLErrorBadServerResponse {
                return NSLocalizedString("The server returned an error instead of a file.", comment: "Download failure")
            }
            return NSLocalizedString("A network error interrupted the download.", comment: "Download failure")
        }
        return NSLocalizedString("The download could not be completed.", comment: "Download failure")
    }

    // MARK: - Notifications

    private func postDidChange() {
        progressNotificationGeneration += 1
        pendingProgressNotification?.cancel()
        pendingProgressNotification = nil
        lastProgressNotificationTime = ProcessInfo.processInfo.systemUptime
        dispatchDidChangeNotification()
    }

    private func postProgressDidChangeLocked() {
        guard pendingProgressNotification == nil else {
            return
        }

        let elapsed = ProcessInfo.processInfo.systemUptime - lastProgressNotificationTime
        if elapsed >= progressNotificationInterval {
            lastProgressNotificationTime = ProcessInfo.processInfo.systemUptime
            dispatchDidChangeNotification()
            return
        }

        let generation = progressNotificationGeneration
        let workItem = DispatchWorkItem { [weak self] in
            guard let self, self.progressNotificationGeneration == generation else {
                return
            }
            self.pendingProgressNotification = nil
            self.lastProgressNotificationTime = ProcessInfo.processInfo.systemUptime
            self.dispatchDidChangeNotification()
        }
        pendingProgressNotification = workItem
        stateQueue.asyncAfter(
            deadline: .now() + max(progressNotificationInterval - elapsed, 0),
            execute: workItem
        )
    }

    private func dispatchDidChangeNotification() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStoreDidChange, object: self)
        }
    }

    private func postDidStartDownload() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .downloadStoreDidStartDownload, object: self)
        }
    }
}

extension DownloadStore: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        stateQueue.async {
            self.updateProgress(
                taskIdentifier: downloadTask.taskIdentifier,
                totalBytesWritten: totalBytesWritten,
                totalBytesExpectedToWrite: totalBytesExpectedToWrite
            )
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        stateQueue.sync {
            if let response = downloadTask.response as? HTTPURLResponse,
               !(200..<300).contains(response.statusCode) {
                self.failDownload(taskIdentifier: downloadTask.taskIdentifier, error: URLError(.badServerResponse))
                return
            }
            self.completeDownload(taskIdentifier: downloadTask.taskIdentifier, temporaryLocation: location)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            return
        }

        stateQueue.async {
            self.failDownload(taskIdentifier: task.taskIdentifier, error: error)
        }
    }
}
