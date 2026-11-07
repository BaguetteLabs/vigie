import Darwin
import Foundation

/// Whether an agent process still runs (AD-5 liveness). A pid alone is not enough: pids are recycled, so a
/// process counts as the same one only when its start time matches the one recorded with the session.
public protocol ProcessLiveness: Sendable {
    func isAlive(_ ref: AgentProcessRef) -> Bool
}

/// The real check, through `sysctl(KERN_PROC_PID)`: the pid exists, is not a zombie, and its
/// `kp_proc.p_starttime` matches `ref.startTime` within ``startTimeTolerance`` (the Wire format keeps
/// milliseconds). A ref without a start time is alive while its pid exists.
public struct SystemProcessLiveness: ProcessLiveness {
    /// Recorded start times went through the Wire date format (millisecond precision).
    public static let startTimeTolerance: TimeInterval = 0.5

    public init() {}

    public func isAlive(_ ref: AgentProcessRef) -> Bool {
        guard let started = Self.startTime(of: ref.pid) else { return false }
        guard let expected = ref.startTime else { return true }
        return abs(started.timeIntervalSince(expected)) <= Self.startTimeTolerance
    }

    /// The start time of a live (non-zombie) process, or nil when there is none with this pid.
    public static func startTime(of pid: pid_t) -> Date? {
        guard pid > 0 else { return nil }
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0,
            info.kp_proc.p_pid == pid, info.kp_proc.p_stat != SZOMB
        else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: TimeInterval(start.tv_sec) + TimeInterval(start.tv_usec) / 1_000_000)
    }
}
