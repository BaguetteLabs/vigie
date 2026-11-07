import OSLog
import SwiftUI
import VigieCore
import Wire

/// App assembly entry point (AD-2, AD-4). Agent app (`LSUIElement`): no Dock icon, no window.
/// The Notch Host and module registry are composed here in later stories.
@main
struct VigieApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let env = AppEnvironment.current
        Logger(subsystem: env.logSubsystem, category: "app")
            .info("Launching \(env.displayName, privacy: .public) (\(env.bundleID, privacy: .public))")
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
