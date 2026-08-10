import Foundation
import FumbleCore

/// Presentation-only formatting. Pure functions, no SwiftUI — so the UI's text is unit-testable.
public enum Format {

    /// Menu-bar WPM. Nil input means "not enough data yet" and shows a dash, not a zero:
    /// a fresh install reading `0 WPM` looks like a broken app.
    public static func wpm(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))"
    }

    public static func accuracy(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.1f%%", value * 100)
    }

    /// Latency in ms. Sub-millisecond precision would be false confidence given bucketing.
    public static func milliseconds(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return "\(Int(value.rounded()))ms"
    }

    public static func percentage(_ value: Double?) -> String {
        guard let value, value.isFinite else { return "—" }
        return String(format: "%.0f%%", value * 100)
    }

    /// Human-scale durations for the time-cost figure. The unit changes so the number stays
    /// legible: "340ms" and "1.4s" and "2m 05s" are all more readable than raw seconds.
    public static func duration(seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        if seconds < 1 { return "\(Int((seconds * 1000).rounded()))ms" }
        if seconds < 60 { return String(format: "%.1fs", seconds) }
        let minutes = Int(seconds) / 60
        let remainder = Int(seconds) % 60
        return String(format: "%dm %02ds", minutes, remainder)
    }

    public static func count(_ value: UInt64) -> String {
        if value < 1_000 { return "\(value)" }
        if value < 1_000_000 { return String(format: "%.1fk", Double(value) / 1_000) }
        return String(format: "%.1fM", Double(value) / 1_000_000)
    }

    public static func bytes(_ value: UInt64) -> String {
        if value < 1_024 { return "\(value) B" }
        if value < 1_024 * 1_024 { return String(format: "%.0f KB", Double(value) / 1_024) }
        return String(format: "%.1f MB", Double(value) / (1_024 * 1_024))
    }

    /// Turns a bundle identifier into something a human recognises. Best-effort: the app may
    /// not be installed or running any more, in which case the last path component is the
    /// least-bad option.
    public static func appName(bundleID: String) -> String {
        bundleID.split(separator: ".").last.map(String.init) ?? bundleID
    }
}
