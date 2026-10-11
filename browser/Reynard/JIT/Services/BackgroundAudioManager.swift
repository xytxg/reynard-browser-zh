//
//  BackgroundAudioManager.swift
//  Reynard
//
//  Created by Minh Ton on 26/7/26.
//

// https://github.com/StephenDev0/StikDebug/blob/03b7c109ac2767d7558e88c621924fbf9b18ad74/StikDebug/Services/BackgroundAudioManager.swift

import AVFoundation

final class BackgroundAudioManager {
    static let shared = BackgroundAudioManager()
    
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var healthCheckTimer: Timer?
    private var isRunning = false
    // A failed restart (for example while a call or another app holds the audio
    // session) must not stop keep-alive for the rest of the process. Failures
    // are retried by the health check with exponential backoff instead.
    private var consecutiveFailures = 0
    private var nextRecoveryAttempt: Date?
    private static let maximumRecoveryDelay: TimeInterval = 60
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption(_:)),
            name: AVAudioSession.interruptionNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMediaServicesReset),
            name: AVAudioSession.mediaServicesWereResetNotification,
            object: nil
        )
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    func start() {
        guard !isRunning else {
            recoverIfNeeded()
            return
        }
        
        isRunning = true
        resetRecoveryBackoff()
        if !startEngine() {
            recordRecoveryFailure()
        }
        startHealthCheck()
    }
    
    func stop() {
        guard isRunning else {
            return
        }
        
        isRunning = false
        resetRecoveryBackoff()
        healthCheckTimer?.invalidate()
        healthCheckTimer = nil
        player.stop()
        engine.stop()
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }
    
    @discardableResult
    private func startEngine() -> Bool {
        do {
            engine.stop()
            player.stop()
            engine = AVAudioEngine()
            player = AVAudioPlayerNode()
            
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, options: .mixWithOthers)
            try session.setActive(true)
            
            engine.attach(player)
            let format = engine.mainMixerNode.outputFormat(forBus: 0)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            scheduleSilence()
            try engine.start()
            player.play()
            return true
        } catch {
            NSLog("BackgroundAudioManager: %@", error.localizedDescription)
            player.stop()
            engine.stop()
            try? AVAudioSession.sharedInstance().setActive(
                false,
                options: .notifyOthersOnDeactivation
            )
            return false
        }
    }
    
    private func scheduleSilence() {
        let format = engine.mainMixerNode.outputFormat(forBus: 0)
        let frameCount = AVAudioFrameCount(format.sampleRate)
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: frameCount
        ) else {
            return
        }
        
        buffer.frameLength = frameCount
        player.scheduleBuffer(buffer, at: nil, options: .loops)
    }
    
    private func startHealthCheck() {
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            self?.recoverIfNeeded()
        }
        RunLoop.main.add(timer, forMode: .common)
        healthCheckTimer = timer
    }
    
    private func recoverIfNeeded() {
        guard isRunning,
              !engine.isRunning || !player.isPlaying else {
            return
        }
        if let nextRecoveryAttempt,
           Date() < nextRecoveryAttempt {
            return
        }
        
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
            player.play()
            resetRecoveryBackoff()
        } catch {
            NSLog("BackgroundAudioManager: recovery failed: %@", error.localizedDescription)
            if startEngine() {
                resetRecoveryBackoff()
            } else {
                recordRecoveryFailure()
            }
        }
    }
    
    private func recordRecoveryFailure() {
        consecutiveFailures += 1
        let exponent = Double(min(consecutiveFailures, 6))
        let delay = min(pow(2, exponent), Self.maximumRecoveryDelay)
        nextRecoveryAttempt = Date().addingTimeInterval(delay)
    }
    
    private func resetRecoveryBackoff() {
        consecutiveFailures = 0
        nextRecoveryAttempt = nil
    }
    
    @objc private func handleInterruption(_ notification: Notification) {
        guard isRunning,
              let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              AVAudioSession.InterruptionType(rawValue: typeValue) == .ended else {
            return
        }
        
        // The session is available again; retry immediately instead of waiting
        // for the backoff window from failures during the interruption.
        resetRecoveryBackoff()
        recoverIfNeeded()
    }
    
    @objc private func handleMediaServicesReset() {
        guard isRunning else {
            return
        }
        
        engine = AVAudioEngine()
        player = AVAudioPlayerNode()
        resetRecoveryBackoff()
        if !startEngine() {
            recordRecoveryFailure()
        }
    }
}
