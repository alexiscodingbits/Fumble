import AppKit
import FumbleCore
import SwiftUI

/// An on-screen QWERTY keyboard. Colour and emphasis are injected, so the same view renders the
/// trainer's confidence colours, an error/speed heatmap in Stats, or a next-key highlight.
struct VirtualKeyboardView: View {
    /// The key to highlight as "type this next" (the trainer's focus).
    var focusKeyCode: Int?
    /// Fill colour per key code.
    var keyColor: (Int) -> Color
    /// Foreground (letter) colour per key code.
    var keyForeground: (Int) -> Color = { _ in .primary }

    // Physical QWERTY rows as keycodes, with the usual staggered offsets.
    private static let rows: [(offset: CGFloat, keys: [Int])] = [
        (0.0, [12, 13, 14, 15, 17, 16, 32, 34, 31, 35]),   // q w e r t y u i o p
        (0.5, [0, 1, 2, 3, 5, 4, 38, 40, 37]),             // a s d f g h j k l
        (1.5, [6, 7, 8, 9, 11, 45, 46]),                   // z x c v b n m
    ]

    private let keySize: CGFloat = 40
    private let gap: CGFloat = 6

    var body: some View {
        // Intrinsic width, rows left-aligned against each other (the stagger offsets), so the
        // caller's `.frame(maxWidth: .infinity)` centres the whole board. The old stretchy
        // trailing spacer pinned it to the left edge instead.
        VStack(alignment: .leading, spacing: gap) {
            ForEach(Array(Self.rows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: gap) {
                    Color.clear.frame(width: row.offset * (keySize + gap), height: 1)
                    ForEach(row.keys, id: \.self) { keyCode in
                        key(keyCode)
                    }
                }
                .fixedSize()
            }
        }
    }

    private func key(_ keyCode: Int) -> some View {
        let isFocus = keyCode == focusKeyCode
        return Text(KeyIdentity(keyCode: keyCode).label)
            .font(.system(size: 16, weight: isFocus ? .bold : .medium, design: .monospaced))
            .foregroundStyle(keyForeground(keyCode))
            .frame(width: keySize, height: keySize)
            .background(keyColor(keyCode), in: RoundedRectangle(cornerRadius: 7))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(isFocus ? Color.accentColor : Color.black.opacity(0.08),
                                  lineWidth: isFocus ? 3 : 1)
            )
            .scaleEffect(isFocus ? 1.08 : 1)
            .animation(.easeOut(duration: 0.15), value: isFocus)
    }
}

/// Shared colour ramp: confidence/skill 0…1 → red → amber → green.
enum SkillColor {
    static func color(_ value: Double) -> Color {
        let v = min(max(value, 0), 1)
        // Hue 0 (red) → 0.33 (green). Dark mode mutes the ramp: the light-mode saturation
        // glows like traffic lights against monkeytype grey.
        return Color(nsColor: Theme.dynamic(
            light: NSColor(hue: 0.33 * v, saturation: 0.72, brightness: 0.85, alpha: 1),
            dark: NSColor(hue: 0.33 * v, saturation: 0.40, brightness: 0.58, alpha: 1)
        ))
    }

    static let locked = Color.secondary.opacity(0.18)
}
