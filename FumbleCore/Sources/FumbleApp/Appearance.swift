import AppKit

/// Light / dark / follow-the-system.
///
/// Applied by setting `NSApp.appearance` app-wide rather than SwiftUI's
/// `.preferredColorScheme`: passing nil to preferredColorScheme does not reliably clear an
/// explicit override once one has been applied (switching Dark -> System left windows in a
/// half-dark zombie state), while `NSApp.appearance = nil` genuinely reverts to the system.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}
