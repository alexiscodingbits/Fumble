import Foundation

/// A **physical** key on the keyboard, identified by its macOS virtual keycode.
///
/// Deliberately physical, not character-level: `;` and `:` are the same finger movement,
/// and heatmaps and finger-training are about the movement. It also means we never need
/// to resolve what character was actually produced, which would require reading the
/// keyboard layout and the modifier state — i.e. reconstructing text. See PRIVACY.md.
public struct KeyIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let keyCode: Int

    public init(keyCode: Int) { self.keyCode = keyCode }

    /// Stable, human-readable label. Also the persistence key, so **these strings are a
    /// file format** — renaming one silently orphans historical data.
    public var label: String { Self.labels[keyCode] ?? "key\(keyCode)" }
    public var description: String { label }

    public var isModifier: Bool { Self.modifierKeyCodes.contains(keyCode) }
    /// Backspace. Used for error attribution, so it is never itself a "typed" key.
    public var isBackspace: Bool { keyCode == 51 }
    /// Keys that don't produce text and shouldn't count toward speed or drills.
    public var isNavigationOrFunction: Bool { Self.navigationAndFunctionKeyCodes.contains(keyCode) }

    /// True when this key is part of ordinary prose/code typing. Counts toward presses, WPM,
    /// and accuracy. Includes letters, digits, punctuation, Space, Return and Tab.
    public var isTypingKey: Bool {
        !isModifier && !isBackspace && !isNavigationOrFunction
    }

    /// True when this key's *reach latency* is a meaningful motor signal worth measuring and
    /// drilling. Excludes Return and Tab: you pause before them (end of a line, end of a
    /// thought), so their latency is dominated by thinking, not finger movement — and you can't
    /// meaningfully "practise" the Return key anyway. They still count as presses via
    /// `isTypingKey`; they just never become weak-spots or pollute the latency baseline.
    public var isLatencyCandidate: Bool {
        isTypingKey && keyCode != 36 && keyCode != 48   // not Return, not Tab
    }

    /// The finger that should press this key in standard touch-typing, for the heatmap and
    /// for grouping weak spots by finger. Nil for keys with no canonical assignment.
    public var homeFinger: Finger? { Self.fingers[keyCode] }

    public enum Finger: String, Codable, Sendable, CaseIterable {
        case leftPinky, leftRing, leftMiddle, leftIndex
        case leftThumb, rightThumb
        case rightIndex, rightMiddle, rightRing, rightPinky

        public var displayName: String {
            switch self {
            case .leftPinky: "L pinky"
            case .leftRing: "L ring"
            case .leftMiddle: "L middle"
            case .leftIndex: "L index"
            case .leftThumb: "L thumb"
            case .rightThumb: "R thumb"
            case .rightIndex: "R index"
            case .rightMiddle: "R middle"
            case .rightRing: "R ring"
            case .rightPinky: "R pinky"
            }
        }
    }

    // MARK: - Keycode tables

    // Values are the Carbon `kVK_*` virtual keycodes (HIToolbox/Events.h). They describe
    // physical positions on an ANSI board and are layout-independent, which is exactly what
    // we want: a Dvorak user's `keyCode 6` is the same physical key as a QWERTY user's `Z`.
    // Labels below are the ANSI-US legends.
    static let labels: [Int: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
        37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N",
        46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Escape",

        54: "RightCommand", 55: "Command", 56: "Shift", 57: "CapsLock", 58: "Option",
        59: "Control", 60: "RightShift", 61: "RightOption", 62: "RightControl", 63: "Fn",

        65: "Keypad.", 67: "Keypad*", 69: "Keypad+", 71: "Clear", 75: "Keypad/",
        76: "KeypadEnter", 78: "Keypad-", 81: "Keypad=", 82: "Keypad0", 83: "Keypad1",
        84: "Keypad2", 85: "Keypad3", 86: "Keypad4", 87: "Keypad5", 88: "Keypad6",
        89: "Keypad7", 91: "Keypad8", 92: "Keypad9",

        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 107: "F14", 109: "F10", 111: "F12", 113: "F15", 114: "Help",
        115: "Home", 116: "PageUp", 117: "ForwardDelete", 118: "F4", 119: "End",
        120: "F2", 121: "PageDown", 122: "F1", 123: "Left", 124: "Right", 125: "Down",
        126: "Up",
    ]

    /// Reverse of `labels` for single-character legends, lower-cased — so drill text can be
    /// scored against keycode-based weak spots. Letters, digits and punctuation; multi-character
    /// legends (Space, Return, …) are excluded.
    public static let characterToKeyCode: [Character: Int] = {
        var map: [Character: Int] = [:]
        for (code, label) in labels where label.count == 1 {
            map[Character(label.lowercased())] = code
        }
        return map
    }()

    /// The 26 letters in English frequency order (e, t, a, o, …). This is the order the trainer
    /// unlocks them in — most useful first — mirroring how keybr introduces letters.
    public static let alphabetByFrequency: [KeyIdentity] = [
        14, 17, 0, 31, 34, 45, 1, 4, 15, 2, 37, 8, 32,   // e t a o i n s h r d l c u
        46, 13, 3, 5, 16, 35, 11, 9, 40, 38, 7, 12, 6,    // m w f g y p b v k j x q z
    ].map(KeyIdentity.init(keyCode:))

    /// Vowel keys — used by the lesson generator to keep pseudo-words pronounceable.
    public static let vowelKeyCodes: Set<Int> = [0, 14, 34, 31, 32, 16]   // a e i o u y

    public var isVowel: Bool { Self.vowelKeyCodes.contains(keyCode) }

    static let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    static let navigationAndFunctionKeyCodes: Set<Int> = [
        53, 71, 114, 115, 116, 117, 119, 121, 123, 124, 125, 126,
        96, 97, 98, 99, 100, 101, 103, 105, 107, 109, 111, 113,
    ]

    // Standard touch-typing assignment for ANSI-US.
    static let fingers: [Int: Finger] = [
        // Left hand
        50: .leftPinky, 18: .leftPinky, 12: .leftPinky, 0: .leftPinky, 6: .leftPinky,
        48: .leftPinky, 57: .leftPinky, 56: .leftPinky,
        19: .leftRing, 13: .leftRing, 1: .leftRing, 7: .leftRing,
        20: .leftMiddle, 14: .leftMiddle, 2: .leftMiddle, 8: .leftMiddle,
        21: .leftIndex, 15: .leftIndex, 3: .leftIndex, 9: .leftIndex,
        23: .leftIndex, 17: .leftIndex, 5: .leftIndex, 11: .leftIndex,
        49: .leftThumb,
        // Right hand
        22: .rightIndex, 16: .rightIndex, 4: .rightIndex, 45: .rightIndex,
        26: .rightIndex, 32: .rightIndex, 38: .rightIndex, 46: .rightIndex,
        28: .rightMiddle, 34: .rightMiddle, 40: .rightMiddle, 43: .rightMiddle,
        25: .rightRing, 31: .rightRing, 37: .rightRing, 47: .rightRing,
        29: .rightPinky, 35: .rightPinky, 41: .rightPinky, 44: .rightPinky,
        27: .rightPinky, 24: .rightPinky, 33: .rightPinky, 30: .rightPinky,
        42: .rightPinky, 39: .rightPinky, 36: .rightPinky, 51: .rightPinky,
        60: .rightPinky,
    ]

    /// The keys a drill can legitimately ask for — everything with an ANSI legend that
    /// produces text.
    public static var drillableKeys: [KeyIdentity] {
        labels.keys
            .map(KeyIdentity.init(keyCode:))
            .filter(\.isTypingKey)
            .sorted { $0.keyCode < $1.keyCode }
    }
}

/// An ordered pair of physical keys — the transition that carries most of the signal about
/// what's actually slow. `];` and `->` cost real time; the individual keys look fine.
public struct BigramIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let first: KeyIdentity
    public let second: KeyIdentity

    public init(first: KeyIdentity, second: KeyIdentity) {
        self.first = first
        self.second = second
    }

    public var label: String { "\(first.label)\(second.label)" }
    public var description: String { label }

    /// True when both keys are pressed by the same finger — inherently slower, and worth
    /// surfacing separately so we don't tell people to drill away their own anatomy.
    public var isSameFinger: Bool {
        guard let a = first.homeFinger, let b = second.homeFinger else { return false }
        return a == b
    }

    /// Persistence key. Uses a separator that cannot appear in a label.
    public var storageKey: String { "\(first.keyCode)>\(second.keyCode)" }

    public init?(storageKey: String) {
        let parts = storageKey.split(separator: ">")
        guard parts.count == 2, let a = Int(parts[0]), let b = Int(parts[1]) else { return nil }
        self.init(first: KeyIdentity(keyCode: a), second: KeyIdentity(keyCode: b))
    }
}
