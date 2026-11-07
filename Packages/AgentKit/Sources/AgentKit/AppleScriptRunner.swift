import Foundation

/// Runs AppleScript source in process (AD-20, AD-23). Terminal adapters use it only inside `focus` / `openTab`,
/// which run only from a user action. Injected so tests never send an Apple Event.
public protocol AppleScriptRunning: Sendable {
    /// Compiles and runs `source`. Returns the result as text (nil when the script returns nothing or a
    /// non-text value). Throws `AppleScriptError` when compiling or running fails.
    func run(source: String) async throws -> String?
}

/// An AppleScript compile or run failure, with the OSA error number.
public struct AppleScriptError: Error, Equatable, Sendable {
    /// `errAEEventNotPermitted`: the user denied (or has not yet granted) Automation for the target app.
    public static let eventNotPermitted = -1743
    /// `errAEEventWouldRequireUserConsent`: consent would be needed but the caller asked not to prompt.
    public static let eventWouldRequireUserConsent = -1744

    public let number: Int
    public let message: String

    public init(number: Int, message: String) {
        self.number = number
        self.message = message
    }

    /// True when the failure means Automation permission for the target app is missing.
    public var isPermissionDenied: Bool {
        number == Self.eventNotPermitted || number == Self.eventWouldRequireUserConsent
    }
}

/// The production `AppleScriptRunning`, backed by `NSAppleScript` on the main actor (NSAppleScript is not
/// thread-safe). Needs the `com.apple.security.automation.apple-events` entitlement and
/// `NSAppleEventsUsageDescription` in the app; macOS asks the user for Automation once per target app.
public struct NSAppleScriptRunner: AppleScriptRunning {
    public init() {}

    public func run(source: String) async throws -> String? {
        try await MainActor.run {
            guard let script = NSAppleScript(source: source) else {
                throw AppleScriptError(number: -2700, message: "Could not create the script")
            }
            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)
            if let errorInfo {
                let number = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? -2700
                let message = errorInfo[NSAppleScript.errorMessage] as? String ?? ""
                throw AppleScriptError(number: number, message: message)
            }
            return result.stringValue
        }
    }
}
