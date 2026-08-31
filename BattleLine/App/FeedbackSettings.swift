import Foundation
import Observation

@MainActor
@Observable
final class FeedbackSettings {
    static let soundKey = "turnReminder.soundEnabled"
    static let hapticsKey = "turnReminder.hapticsEnabled"

    var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: Self.soundKey) }
    }
    var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Self.hapticsKey) }
    }
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundEnabled = defaults.object(forKey: Self.soundKey) as? Bool ?? true
        hapticsEnabled = defaults.object(forKey: Self.hapticsKey) as? Bool ?? true
    }
}
