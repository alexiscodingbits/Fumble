import SwiftUI

/// Light / dark / follow-the-system. Applied via `.preferredColorScheme` on each top-level
/// surface (app window and menu-bar dropdown), so the choice covers the whole UI.
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
    /// nil means "inherit the system setting" to SwiftUI.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
