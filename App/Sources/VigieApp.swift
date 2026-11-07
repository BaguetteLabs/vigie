import SwiftUI
import VigieCore

/// App assembly entry point (AD-2, AD-4). Agent app (`LSUIElement`): no Dock icon, no window.
/// The Notch Host and module registry are composed here in later stories.
@main
struct VigieApp: App {
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
