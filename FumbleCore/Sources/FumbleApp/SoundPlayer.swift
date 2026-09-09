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
    /// The bundled key click (a real keyboard sample). Falls back to the system "Pop" if the
    /// resource can't be found, so a packaging mistake degrades rather than silences.
    private let keyClickResource = "key-click"
    private let keyFallbackName = "Pop"
    /// Distinctly negative for an error.
    private let errorSoundName = "Basso"

    private var pools: [String: (sounds: [NSSound], next: Int)] = [:]
    private let poolSize = 4

    func key(volume: Double) {
        if let url = Self.keyClickURL {
            play(key: "key-click", volume: volume) { NSSound(contentsOf: url, byReference: true) }
        } else {
            play(key: keyFallbackName, volume: volume) { NSSound(named: self.keyFallbackName)?.copy() as? NSSound }
        }
    }

    func error(volume: Double) {
        play(key: errorSoundName, volume: volume) { NSSound(named: self.errorSoundName)?.copy() as? NSSound }
    }

    /// The bundled sample's URL. `Bundle.module` works in dev builds; in the assembled .app the
    /// resource bundle lives under Contents/Resources and `Bundle.module` can miss it (the same
    /// gotcha Claudometer hit), so fall back to searching there by hand.
    private static let keyClickURL: URL? = {
        if let url = Bundle.module.url(forResource: "key-click", withExtension: "wav") {
            return url
        }
        if let resources = Bundle.main.resourceURL {
            for layout in ["FumbleCore_FumbleApp.bundle/Contents/Resources/key-click.wav",
                           "FumbleCore_FumbleApp.bundle/key-click.wav"] {
                let candidate = resources.appendingPathComponent(layout)
                if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
            }
        }
        return nil
    }()

    private func play(key: String, volume: Double, make: () -> NSSound?) {
        guard volume > 0 else { return }

        if pools[key] == nil {
            // Distinct instances so rapid presses overlap instead of cutting each other off.
            let instances = (0..<poolSize).compactMap { _ in make() }
            guard !instances.isEmpty else { return }
            pools[key] = (instances, 0)
        }
        guard var pool = pools[key], !pool.sounds.isEmpty else { return }

        let sound = pool.sounds[pool.next]
        pool.next = (pool.next + 1) % pool.sounds.count
        pools[key] = pool

        sound.stop()   // rewind if this instance is still playing from poolSize presses ago
        sound.volume = Float(min(max(volume, 0), 1))
        sound.play()
    }
}
