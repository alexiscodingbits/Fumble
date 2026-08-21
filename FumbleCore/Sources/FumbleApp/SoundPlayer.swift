import AppKit

/// What practice sounds to play. Mirrors keybr's off / errors-only / keys-only / all.
enum SoundMode: String, CaseIterable, Identifiable {
    case off, errors, keys, all
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: "Off"
        case .errors: "Errors only"
        case .keys: "Keys only"
        case .all: "All"
        }
    }
    var playsErrors: Bool { self == .errors || self == .all }
    var playsKeys: Bool { self == .keys || self == .all }
}

/// Plays practice feedback via the built-in system sounds — no bundled audio assets, nothing to
/// license or ship. A fresh NSSound per play so rapid keystrokes overlap instead of cutting off.
@MainActor
final class SoundPlayer {
    /// Quiet, short tick for a keystroke.
    private let keySoundName = "Tink"
    /// Distinctly negative for an error.
    private let errorSoundName = "Basso"

    func key(volume: Double) {
        play(named: keySoundName, volume: volume)
    }

    func error(volume: Double) {
        play(named: errorSoundName, volume: volume)
    }

    private func play(named name: String, volume: Double) {
        guard volume > 0, let sound = NSSound(named: name) else { return }
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }
}
