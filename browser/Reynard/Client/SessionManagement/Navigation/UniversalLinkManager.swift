//
//  UniversalLinkManager.swift
//  Reynard
//
//  Created by Minh Ton on 12/8/26.
//

import Foundation
import GeckoView
import UIKit

final class UniversalLinkManager {
    private struct HandoffKey: Hashable {
        let session: ObjectIdentifier
        let uri: String
    }
    
    private nonisolated final class OpenGate: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Bool, Never>?
        private var result: Bool?
        
        func wait() async -> Bool {
            return await withCheckedContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(returning: result)
                    return
                }
                self.continuation = continuation
                lock.unlock()
            }
        }
        
        func finish(with result: Bool) {
            lock.lock()
            guard self.result == nil else {
                lock.unlock()
                return
            }
            self.result = result
            let continuation = continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: result)
        }
    }
    
    private enum ExternalOpenOutcome: Sendable {
        case declined
        case opened
        case failed
    }
    
    private var handoffTasks: [HandoffKey: Task<Bool, Never>] = [:]
    private var failedHandoffs = Set<HandoffKey>()
    private var externalOpenTasks: [HandoffKey: Task<ExternalOpenOutcome, Never>] = [:]
    private var declinedExternalOpens = Set<HandoffKey>()
    
    func decideHandoff(
        for request: LoadRequest,
        in session: GeckoSession
    ) async -> AllowOrDeny {
        guard
            Prefs.BrowsingSettings.openLinksInExternalApps,
            let url = URL(string: request.uri)
        else {
            return .allow
        }
        
        guard URLUtils.isWebURL(url) else {
            return await decideExternalOpen(of: url, uri: request.uri, in: session)
        }
        
        guard
            !session.isPrivateMode,
            request.isUserInitiatedNavigation
        else {
            return .allow
        }
        
        if let triggerUri = request.triggerUri,
           let triggerURL = URL(string: triggerUri),
           let triggerHost = triggerURL.host,
           let destinationHost = url.host,
           triggerHost.caseInsensitiveCompare(destinationHost) == .orderedSame {
            return .allow
        }
        
        let key = HandoffKey(session: ObjectIdentifier(session), uri: request.uri)
        if failedHandoffs.contains(key) {
            return .allow
        }
        if let task = handoffTasks[key] {
            return await task.value ? .deny : .allow
        }
        
        let task = Task { @MainActor in
            return await open(url, universalLinksOnly: true)
        }
        handoffTasks[key] = task
        defer { handoffTasks.removeValue(forKey: key) }
        
        let didOpen = await task.value
        if didOpen {
            failedHandoffs.remove(key)
        } else {
            failedHandoffs.insert(key)
        }
        return didOpen ? .deny : .allow
    }
    
    func didCommitNavigation(in session: GeckoSession) {
        let sessionID = ObjectIdentifier(session)
        failedHandoffs = Set(failedHandoffs.filter { $0.session != sessionID })
        declinedExternalOpens = Set(declinedExternalOpens.filter { $0.session != sessionID })
    }
    
    // One confirmation per app link: the load and pre-navigation callbacks for
    // the same link share it, and a page that keeps redirecting to a link the
    // user declined is not asked about again until its next navigation.
    // [reynard-browser-zh]
    private func decideExternalOpen(
        of url: URL,
        uri: String,
        in session: GeckoSession
    ) async -> AllowOrDeny {
        let key = HandoffKey(session: ObjectIdentifier(session), uri: uri)
        if declinedExternalOpens.contains(key) {
            return .deny
        }
        
        let task: Task<ExternalOpenOutcome, Never>
        if let pendingTask = externalOpenTasks[key] {
            task = pendingTask
        } else {
            task = Task { @MainActor in
                guard await confirmOpen() else {
                    return .declined
                }
                return await open(url, universalLinksOnly: false) ? .opened : .failed
            }
            externalOpenTasks[key] = task
        }
        
        let outcome = await task.value
        if externalOpenTasks[key] == task {
            externalOpenTasks.removeValue(forKey: key)
        }
        switch outcome {
        case .declined:
            declinedExternalOpens.insert(key)
            return .deny
        case .opened:
            return .deny
        case .failed:
            return .allow
        }
    }
    
    func didCreateNewSession(from session: GeckoSession, for uri: String) {
        failedHandoffs.remove(
            HandoffKey(session: ObjectIdentifier(session), uri: uri)
        )
    }
    
    @MainActor
    private func confirmOpen() async -> Bool {
        return await withCheckedContinuation { continuation in
            AlertPresenter.show(
                title: NSLocalizedString("Open this page in another app?", comment: ""),
                message: nil,
                buttons: [
                    AlertPresenter.Button(title: NSLocalizedString("Cancel", comment: ""), style: .cancel) {
                        continuation.resume(returning: false)
                    },
                    AlertPresenter.Button(title: NSLocalizedString("Open", comment: "")) {
                        continuation.resume(returning: true)
                    },
                ]
            )
        }
    }
    
    @MainActor
    private func open(_ url: URL, universalLinksOnly: Bool) async -> Bool {
        let gate = OpenGate()
        let timeoutTask = Task { @MainActor in
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                gate.finish(with: false)
            } catch {}
        }
        defer { timeoutTask.cancel() }
        
        return await withTaskCancellationHandler(operation: {
            guard !Task.isCancelled else {
                return false
            }
            UIApplication.shared.open(
                url,
                options: [.universalLinksOnly: universalLinksOnly],
                completionHandler: { success in
                    gate.finish(with: success)
                }
            )
            return await gate.wait()
        }, onCancel: {
            gate.finish(with: false)
        })
    }
}
