import AVFAudio
import CoreHaptics
import UIKit

@MainActor
protocol TurnFeedbackPlaying: AnyObject {
    func play(soundEnabled: Bool, hapticsEnabled: Bool)
    func stop()
}

/// Plays one foreground-only reminder. Interruptions discard it instead of resuming it.
@MainActor
final class TurnFeedbackPlayer: NSObject, TurnFeedbackPlaying {
    private let audioSession = AVAudioSession.sharedInstance()
    private var audioPlayer: AVAudioPlayer?
    private var hapticEngine: CHHapticEngine?
    private var hapticEngineID: UUID?
    private var hapticPlayer: (any CHHapticPatternPlayer)?
    private var finishTask: Task<Void, Never>?
    private var playbackID = UUID()
    private var stoppingHapticEngines: [UUID: CHHapticEngine] = [:]
    private var hasActiveAudioSession = false

    override init() {
        super.init()
        let center = NotificationCenter.default
        center.addObserver(
            self, selector: #selector(stopForSystemEvent),
            name: UIApplication.willResignActiveNotification, object: nil
        )
        center.addObserver(
            self, selector: #selector(audioSessionInterrupted),
            name: AVAudioSession.interruptionNotification, object: audioSession
        )
        for name in [
            AVAudioSession.mediaServicesWereLostNotification,
            AVAudioSession.mediaServicesWereResetNotification
        ] {
            center.addObserver(
                self, selector: #selector(stopForSystemEvent), name: name, object: nil
            )
        }
    }

    deinit {
        finishTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    func play(soundEnabled: Bool, hapticsEnabled: Bool) {
        stop()
        guard soundEnabled || hapticsEnabled,
              UIApplication.shared.applicationState == .active else { return }

        do {
            // Ambient respects the silent switch and mixes with other apps by default.
            try audioSession.setCategory(.ambient, mode: .default)
            try audioSession.setActive(true)
            hasActiveAudioSession = true
        } catch {
            return
        }

        let id = playbackID
        var duration: TimeInterval = 0
        if soundEnabled,
           let url = Bundle.main.url(forResource: "turn-reminder", withExtension: "wav"),
           let player = try? AVAudioPlayer(contentsOf: url) {
            player.numberOfLoops = 0
            player.prepareToPlay()
            if player.play() {
                audioPlayer = player
                duration = player.duration
            }
        }
        if hapticsEnabled, CHHapticEngine.capabilitiesForHardware().supportsHaptics {
            do {
                let engine = try CHHapticEngine(audioSession: audioSession)
                let engineID = UUID()
                hapticEngine = engine
                hapticEngineID = engineID
                engine.playsHapticsOnly = true
                engine.isAutoShutdownEnabled = true
                engine.stoppedHandler = { [weak self] _ in
                    Task { @MainActor [weak self] in
                        self?.stopForHapticEvent(playbackID: id, engineID: engineID)
                    }
                }
                engine.resetHandler = { [weak self] in
                    Task { @MainActor [weak self] in
                        self?.stopForHapticEvent(playbackID: id, engineID: engineID)
                    }
                }
                let parameters = [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ]
                let pattern = try CHHapticPattern(events: [
                    CHHapticEvent(
                        eventType: .hapticTransient, parameters: parameters,
                        relativeTime: 0
                    ),
                    // Keep the second tap's onset unchanged.
                    CHHapticEvent(
                        eventType: .hapticTransient, parameters: parameters,
                        relativeTime: 0.55
                    )
                ], parameters: [])
                let player = try engine.makePlayer(with: pattern)
                hapticPlayer = player
                // A synchronous start leaves no queued start that could fire after stop().
                try engine.start()
                try player.start(atTime: CHHapticTimeImmediate)
                duration = max(duration, pattern.duration)
            } catch {
                stopHaptics()
            }
        }

        guard duration > 0 else {
            stop()
            return
        }
        finishTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(for: .seconds(duration + 0.1))
            } catch {
                return
            }
            self?.stopPlayback(ifCurrent: id)
        }
    }

    func stop() {
        playbackID = UUID()
        finishTask?.cancel()
        finishTask = nil
        audioPlayer?.stop()
        audioPlayer = nil
        stopHaptics()
        deactivateAudioSessionIfIdle()
    }

    private func stopPlayback(ifCurrent id: UUID) {
        guard playbackID == id else { return }
        stop()
    }

    private func stopForHapticEvent(playbackID id: UUID, engineID: UUID) {
        // A failure from a discarded haptic engine must not cancel successful audio.
        guard hapticEngineID == engineID else { return }
        stopPlayback(ifCurrent: id)
    }

    private func stopHaptics() {
        hapticEngineID = nil
        // Cancel removes the second pulse as well as stopping a pulse already underway.
        try? hapticPlayer?.cancel()
        hapticPlayer = nil
        guard let engine = hapticEngine else { return }
        hapticEngine = nil
        engine.stoppedHandler = { _ in }
        engine.resetHandler = { }
        let stoppingID = UUID()
        // Keep the engine alive until its asynchronous stop has completed.
        stoppingHapticEngines[stoppingID] = engine
        engine.stop { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                stoppingHapticEngines.removeValue(forKey: stoppingID)
                deactivateAudioSessionIfIdle()
            }
        }
    }

    private func deactivateAudioSessionIfIdle() {
        // A previous engine may still be stopping while a new reminder is playing.
        guard stoppingHapticEngines.isEmpty, audioPlayer == nil, hapticEngine == nil,
              hasActiveAudioSession else { return }
        try? audioSession.setActive(false)
        hasActiveAudioSession = false
    }

    @objc nonisolated private func audioSessionInterrupted(_ notification: Notification) {
        guard let value = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              value == AVAudioSession.InterruptionType.began.rawValue else { return }
        stopForSystemEvent(notification)
    }

    @objc nonisolated private func stopForSystemEvent(_ notification: Notification) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { stop() }
        } else {
            Task { @MainActor [weak self] in self?.stop() }
        }
    }
}
