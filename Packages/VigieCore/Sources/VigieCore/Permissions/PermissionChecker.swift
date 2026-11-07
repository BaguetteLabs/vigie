import ApplicationServices
import CoreGraphics
import EventKit
import Foundation
import ModuleKit
import Synchronization
import UserNotifications
import os

/// Reads and requests system permissions. Production uses `SystemPermissionChecker`; tests inject a fake.
public protocol PermissionChecker: Sendable {
    func status(of permission: Permission) async -> PermissionStatus
    func request(_ permission: Permission) async -> PermissionStatus
}

/// The real macOS APIs (AD-19, AD-20). Safe to call under `swift test`: APIs that trap or crash outside an app
/// bundle or without a usage description are guarded and report `.denied`.
public final class SystemPermissionChecker: PermissionChecker {
    private let promptedThisRun = Mutex<Set<Permission>>([])
    private let logger = Logger(subsystem: "fr.baguettelabs.vigie", category: "permissions")

    public init() {}

    public func status(of permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            if AXIsProcessTrusted() { return .granted }
            return promptedThisRun.withLock { $0.contains(.accessibility) } ? .denied : .notDetermined
        case .automation(let bundleID):
            return automationStatus(bundleID: bundleID, askUser: false)
        case .calendar:
            return Self.map(EKEventStore.authorizationStatus(for: .event))
        case .notifications:
            guard hasBundle else { return noBundle() }
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            return Self.map(settings.authorizationStatus)
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        }
    }

    public func request(_ permission: Permission) async -> PermissionStatus {
        switch permission {
        case .accessibility:
            _ = promptedThisRun.withLock { $0.insert(.accessibility) }
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options) ? .granted : .denied
        case .automation(let bundleID):
            return automationStatus(bundleID: bundleID, askUser: true)
        case .calendar:
            guard Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") != nil else {
                logger.error("NSCalendarsFullAccessUsageDescription is missing; not requesting calendar access")
                return .denied
            }
            do {
                let granted = try await EKEventStore().requestFullAccessToEvents()
                return granted ? .granted : .denied
            } catch {
                logger.error("Calendar access request failed: \(error, privacy: .public)")
                return .denied
            }
        case .notifications:
            guard hasBundle else { return noBundle() }
            let center = UNUserNotificationCenter.current()
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
            return Self.map(await center.notificationSettings().authorizationStatus)
        case .screenRecording:
            return CGRequestScreenCaptureAccess() ? .granted : .denied
        }
    }

    private var hasBundle: Bool { Bundle.main.bundleIdentifier != nil }

    private func noBundle() -> PermissionStatus {
        logger.error("Not running inside an app bundle; notifications are unavailable")
        return .denied
    }

    private func automationStatus(bundleID: String, askUser: Bool) -> PermissionStatus {
        var address = AEAddressDesc()
        let created = Array(bundleID.utf8).withUnsafeBufferPointer {
            AECreateDesc(DescType(typeApplicationBundleID), $0.baseAddress, $0.count, &address)
        }
        guard created == noErr else { return .denied }
        defer { AEDisposeDesc(&address) }
        let wildcard = AEEventClass(typeWildCard)
        let result = AEDeterminePermissionToAutomateTarget(&address, wildcard, AEEventID(typeWildCard), askUser)
        switch result {
        case noErr: return .granted
        case -1743: return .denied  // errAEEventNotPermitted
        case -1744: return .notDetermined  // errAEEventWouldRequireUserConsent
        case -600: return .targetNotRunning  // procNotFound
        default: return .denied
        }
    }

    static func map(_ status: EKAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .fullAccess: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }

    static func map(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }
    }
}
