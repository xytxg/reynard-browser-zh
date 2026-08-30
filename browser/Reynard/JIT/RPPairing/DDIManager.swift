//
//  DDIManager.swift
//  Reynard
//
//  Created by Minh Ton on 23/3/26.
//

import CryptoKit
import Foundation

final class DDIManager: NSObject {
    enum DDIError: LocalizedError {
        case alreadyInProgress
        case cancelled
        case appSupportDirUnavail
        case invalidRemoteURL
        case invalidDownload
        
        var errorDescription: String? {
            switch self {
            case .alreadyInProgress:
                return NSLocalizedString("A Developer Disk Image download is already in progress.", comment: "")
            case .cancelled:
                return NSLocalizedString("Developer Disk Image download was cancelled.", comment: "")
            case .appSupportDirUnavail:
                return NSLocalizedString("Unable to access the app Application Support directory.", comment: "")
            case .invalidRemoteURL:
                return NSLocalizedString("Developer Disk Image source URL is invalid.", comment: "")
            case .invalidDownload:
                return NSLocalizedString("Developer Disk Image verification failed.", comment: "")
            }
        }
    }
    
    static let shared = DDIManager()
    
    private struct DownloadItem {
        let remoteURL: URL
        let destinationURL: URL
        let expectedByteCount: Int64
        let expectedSHA256: String
    }
    
    private struct DownloadPlan {
        let rootDirectoryURL: URL
        let items: [DownloadItem]
    }
    
    private struct ActiveDownload {
        var plan: DownloadPlan
        var currentIndex: Int
        var currentTask: URLSessionDownloadTask?
        let progressHandler: (Double) -> Void
        let completion: (Result<Void, Error>) -> Void
    }
    
    private let fileManager: FileManager
    private let stateQueue = DispatchQueue(label: "com.minh-ton.Reynard.DDIManager.Queue", qos: .userInitiated)
    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 10 * 60
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()
    
    private var activeDownload: ActiveDownload?
    
    override init() {
        self.fileManager = .default
        super.init()
    }
    
    func hasRequiredDDIFiles() -> Bool {
        guard let plan = try? makeDownloadPlan() else {
            return false
        }
        
        return plan.items.allSatisfy(isValidDownloadedItem)
    }
    
    func ensureRequiredDDIFiles(
        progress: @escaping (Double) -> Void,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        if hasRequiredDDIFiles() {
            DispatchQueue.main.async {
                progress(1)
                completion(.success(()))
            }
            return
        }
        
        stateQueue.async {
            if self.activeDownload != nil {
                self.dispatchCompletion(.failure(DDIError.alreadyInProgress), completion)
                return
            }
            
            do {
                let plan = try self.makeDownloadPlan()
                try self.ensureDDIRootDirectoryExists(at: plan.rootDirectoryURL)
                
                self.activeDownload = ActiveDownload(
                    plan: plan,
                    currentIndex: 0,
                    currentTask: nil,
                    progressHandler: progress,
                    completion: completion
                )
                
                self.dispatchProgress(0, handler: progress)
                self.startNextDownloadLocked()
            } catch {
                self.dispatchCompletion(.failure(error), completion)
            }
        }
    }
    
    func cancelActiveDownload() {
        stateQueue.async {
            guard let active = self.activeDownload else {
                _ = try? self.removeDDIRootDirectory()
                return
            }
            
            active.currentTask?.cancel()
            self.finishActiveDownloadLocked(result: .failure(DDIError.cancelled), shouldCleanup: true)
        }
    }
    
    private func startNextDownloadLocked() {
        guard var active = activeDownload else {
            return
        }
        
        guard active.currentIndex < active.plan.items.count else {
            finishActiveDownloadLocked(result: .success(()), shouldCleanup: false)
            return
        }
        
        let item = active.plan.items[active.currentIndex]
        
        do {
            try fileManager.createDirectory(
                at: item.destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            if fileManager.fileExists(atPath: item.destinationURL.path) {
                try fileManager.removeItem(at: item.destinationURL)
            }
        } catch {
            finishActiveDownloadLocked(result: .failure(error), shouldCleanup: true)
            return
        }
        
        let task = session.downloadTask(with: item.remoteURL)
        active.currentTask = task
        activeDownload = active
        task.resume()
    }
    
    private func completeCurrentFileDownload(location: URL, taskIdentifier: Int) {
        guard var active = activeDownload,
              let task = active.currentTask,
              task.taskIdentifier == taskIdentifier else {
            return
        }
        
        let item = active.plan.items[active.currentIndex]
        
        do {
            guard let response = task.response as? HTTPURLResponse,
                  response.statusCode == 200,
                  response.url == item.remoteURL,
                  isValidFile(at: location, for: item) else {
                throw DDIError.invalidDownload
            }

            try fileManager.createDirectory(
                at: item.destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            
            if fileManager.fileExists(atPath: item.destinationURL.path) {
                try fileManager.removeItem(at: item.destinationURL)
            }
            
            try fileManager.moveItem(at: location, to: item.destinationURL)
        } catch {
            finishActiveDownloadLocked(result: .failure(error), shouldCleanup: true)
            return
        }
        
        active.currentTask = nil
        active.currentIndex += 1
        activeDownload = active
        
        let completedRatio = Double(active.currentIndex) / Double(active.plan.items.count)
        dispatchProgress(completedRatio, handler: active.progressHandler)
        startNextDownloadLocked()
    }
    
    private func handleDownloadProgress(
        taskIdentifier: Int,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let active = activeDownload,
              let task = active.currentTask,
              task.taskIdentifier == taskIdentifier else {
            return
        }

        let item = active.plan.items[active.currentIndex]
        guard totalBytesWritten <= item.expectedByteCount else {
            task.cancel()
            finishActiveDownloadLocked(
                result: .failure(DDIError.invalidDownload),
                shouldCleanup: true
            )
            return
        }

        let fileProgress: Double
        if totalBytesExpectedToWrite > 0 {
            fileProgress = min(max(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite), 0), 1)
        } else {
            fileProgress = 0
        }
        
        let overallProgress = (Double(active.currentIndex) + fileProgress) / Double(active.plan.items.count)
        dispatchProgress(min(max(overallProgress, 0), 0.999), handler: active.progressHandler)
    }
    
    private func handleTaskFailure(taskIdentifier: Int, error: Error) {
        guard let active = activeDownload,
              let task = active.currentTask,
              task.taskIdentifier == taskIdentifier else {
            return
        }
        
        if let urlError = error as? URLError, urlError.code == .cancelled {
            finishActiveDownloadLocked(result: .failure(DDIError.cancelled), shouldCleanup: true)
            return
        }
        
        finishActiveDownloadLocked(result: .failure(error), shouldCleanup: false)
    }
    
    private func finishActiveDownloadLocked(result: Result<Void, Error>, shouldCleanup: Bool) {
        guard let active = activeDownload else {
            return
        }
        
        active.currentTask?.cancel()
        activeDownload = nil
        
        if shouldCleanup {
            _ = try? removeDDIRootDirectory()
        }
        
        if case .success = result {
            dispatchProgress(1, handler: active.progressHandler)
        }
        
        dispatchCompletion(result, active.completion)
    }
    
    private func dispatchProgress(_ value: Double, handler: @escaping (Double) -> Void) {
        let clamped = min(max(value, 0), 1)
        DispatchQueue.main.async {
            handler(clamped)
        }
    }
    
    private func dispatchCompletion(
        _ result: Result<Void, Error>,
        _ completion: @escaping (Result<Void, Error>) -> Void
    ) {
        DispatchQueue.main.async {
            completion(result)
        }
    }
    
    private func ensureDDIRootDirectoryExists(at rootDirectoryURL: URL) throws {
        guard !fileManager.fileExists(atPath: rootDirectoryURL.path) else {
            return
        }
        
        try fileManager.createDirectory(at: rootDirectoryURL, withIntermediateDirectories: true)
    }
    
    private func removeDDIRootDirectory() throws {
        let rootDirectoryURL = try ddiRootDirectoryURL()
        guard fileManager.fileExists(atPath: rootDirectoryURL.path) else {
            return
        }
        
        try fileManager.removeItem(at: rootDirectoryURL)
    }
    
    private func makeDownloadPlan() throws -> DownloadPlan {
        let rootDirectoryURL = try ddiRootDirectoryURL()
        let pinnedRevision = "5423e4e955fbb3a9eef3e1212acfbfc6e7a26236"
        let baseURLString = "https://raw.githubusercontent.com/doronz88/DeveloperDiskImage/\(pinnedRevision)/PersonalizedImages/Xcode_iOS_DDI_Personalized"
        guard let baseURL = URL(string: baseURLString),
              baseURL.scheme == "https",
              baseURL.host == "raw.githubusercontent.com" else {
            throw DDIError.invalidRemoteURL
        }
        
        let files: [(name: String, byteCount: Int64, sha256: String)] = [
            (
                "BuildManifest.plist",
                801_505,
                "8edd4a2f4f4ef1fbd7bfe49785d8badc673d1395d1d94d85b132ca8ab5ecaf54"
            ),
            (
                "Image.dmg",
                15_733_248,
                "05fd807da5e19f030fa4941f24800c965c6c77982ab572dd5d1ef778fb69f9ca"
            ),
            (
                "Image.dmg.trustcache",
                1_895,
                "36af60889ff5a737874a26daeb8e1a0139ebfebec6ec2e4d8f6a3c1bf1dce35c"
            ),
        ]
        let items = files.map { file in
            DownloadItem(
                remoteURL: baseURL.appendingPathComponent(file.name),
                destinationURL: rootDirectoryURL.appendingPathComponent(file.name, isDirectory: false),
                expectedByteCount: file.byteCount,
                expectedSHA256: file.sha256
            )
        }
        
        return DownloadPlan(rootDirectoryURL: rootDirectoryURL, items: items)
    }
    
    private func ddiRootDirectoryURL() throws -> URL {
        guard let applicationSupportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw DDIError.appSupportDirUnavail
        }
        
        return applicationSupportDirectory.appendingPathComponent("DDI", isDirectory: true)
    }

    private func isValidDownloadedItem(_ item: DownloadItem) -> Bool {
        return isValidFile(at: item.destinationURL, for: item)
    }

    private func isValidFile(at fileURL: URL, for item: DownloadItem) -> Bool {
        guard let values = try? fileURL.resourceValues(
            forKeys: [.isRegularFileKey, .fileSizeKey]
        ),
        values.isRegularFile == true,
        values.fileSize == Int(item.expectedByteCount),
        let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            return false
        }
        defer { fileHandle.closeFile() }

        var hasher = SHA256()
        while true {
            let data = fileHandle.readData(ofLength: 1024 * 1024)
            guard !data.isEmpty else {
                break
            }
            hasher.update(data: data)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return digest == item.expectedSHA256
    }
}

extension DDIManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        stateQueue.async {
            self.handleDownloadProgress(
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
            self.completeCurrentFileDownload(location: location, taskIdentifier: downloadTask.taskIdentifier)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else {
            return
        }
        
        stateQueue.async {
            self.handleTaskFailure(taskIdentifier: task.taskIdentifier, error: error)
        }
    }
}
