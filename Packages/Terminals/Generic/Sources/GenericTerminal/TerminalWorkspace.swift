import AppKit
import Foundation

/// The app-activation seam of ``GenericTerminalAdapter`` (tests use a fake).
public protocol TerminalWorkspace: Sendable {
    /// Activates the running app with this bundle id; false when it does not run.
    @MainActor func activateApp(bundleID: String) -> Bool
    /// Activates the nearest regular (Dock) app among `pid` and its ancestors; false when there is none.
    @MainActor func activateAncestorApp(of pid: Int32) -> Bool
}

/// `NSRunningApplication` activation. Only ever called from a user action (Focus), never at launch.
public struct SystemTerminalWorkspace: TerminalWorkspace {
    /// Ancestor walk bound, so a broken process table can never loop.
    static let maxAncestors = 32

    public init() {}

    @MainActor public func activateApp(bundleID: String) -> Bool {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            return false
        }
        return app.activate(options: [.activateAllWindows])
    }

    @MainActor public func activateAncestorApp(of pid: Int32) -> Bool {
        var current = pid
        for _ in 0..<Self.maxAncestors {
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app.activate(options: [.activateAllWindows])
            }
            guard let parent = Self.parentPID(of: current), parent > 1, parent != current else { return false }
            current = parent
        }
        return false
    }

    /// The parent pid from `sysctl(KERN_PROC_PID)`; nil when the process is gone.
    static func parentPID(of pid: Int32) -> Int32? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
