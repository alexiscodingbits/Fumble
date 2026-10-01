import AppKit
import SwiftUI

/// The practice window's colours. Light mode is stock macOS. Dark mode is monkeytype's grey —
/// `#323437` window, `#2c2e31` typing surface — rather than macOS's near-black: a typing app
/// is stared at for minutes at a stretch, and the softer grey is easier on the eyes than a
/// black field with white text. Dynamic `NSColor`s resolve per appearance, so "System" mode
/// picks up the grey automatically when the Mac is dark.
enum Theme {
    static let windowBackground = Color(nsColor: dynamic(
        light: .windowBackgroundColor, dark: NSColor(red: 0x32 / 255, green: 0x34 / 255, blue: 0x37 / 255, alpha: 1)
    ))
    static let surfaceBackground = Color(nsColor: dynamic(
        light: .textBackgroundColor, dark: NSColor(red: 0x2c / 255, green: 0x2e / 255, blue: 0x31 / 255, alpha: 1)
    ))

    /// The brand orange — the "F" keycap in the wordmark and the launch video (`#f2793f`).
    static let fumbleOrange = Color(nsColor: NSColor(red: 0xf2 / 255, green: 0x79 / 255, blue: 0x3f / 255, alpha: 1))

    /// Drill text not yet typed. Light mode is a mid grey rather than the old faint secondary —
    /// it has to stay readable while it's all you're looking at. Dark mode is monkeytype's sub
    /// colour.
    static let untypedText = Color(nsColor: dynamic(
        light: NSColor(red: 0x80 / 255, green: 0x83 / 255, blue: 0x88 / 255, alpha: 1),
        dark: NSColor(red: 0x6e / 255, green: 0x70 / 255, blue: 0x73 / 255, alpha: 1)
    ))

    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }
}
