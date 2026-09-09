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

/// Plays practice feedback via the built-in system sounds — no bundled audio, nothing to license.
///
/// Reliability matters more than it looks: a naive `NSSound(named:).play()` per keystroke
/// allocates a fresh player each press and silently drops plays under fast typing (the instance
/// can be collected before or while playing). So each sound gets a small preloaded pool used
/// round-robin — `stop()` then `play()` on the next instance guarantees a sound on every press,
/// and overlapping presses use different instances instead of cutting each other off.
@MainActor
final class SoundPlayer {
    /// "Pop" is the closest built-in to a key click; "Tink" (the old choice) is a ding.
    private let keySoundName = "Pop"
    /// Distinctly negative for an error.
    private let errorSoundName = "Basso"

    private var pools: [String: (sounds: [NSSound], next: Int)] = [:]
    private let poolSize = 4

    func key(volume: Double) {
        play(named: keySoundName, volume: volume)
    }

    func error(volume: Double) {
        play(named: errorSoundName, volume: volume)
    }

    private func play(named name: String, volume: Double) {
        guard volume > 0 else { return }

        if pools[name] == nil {
            // Distinct instances via copy(): NSSound(named:) can hand back shared storage, and a
            // shared instance can't overlap with itself.
            let instances = (0..<poolSize).compactMap { _ in
                NSSound(named: name)?.copy() as? NSSound
            }
            guard !instances.isEmpty else { return }
            pools[name] = (instances, 0)
        }
        guard var pool = pools[name], !pool.sounds.isEmpty else { return }

        let sound = pool.sounds[pool.next]
        pool.next = (pool.next + 1) % pool.sounds.count
        pools[name] = pool

        sound.stop()   // rewind if this instance is still playing from poolSize presses ago
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }
}
