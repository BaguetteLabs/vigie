import AgentKit
import Foundation

/// The unofficial Claude plan-usage endpoint (Story 7.3, SPEC §14.2). Everything that depends on its shape is in
/// this file; see `PLAN-ENDPOINT.md` next to it before patching a break.
///
/// The response is untrusted: an entry is a window only when it is an object with a numeric `utilization` and a
/// `resets_at` key (an ISO-8601 string, or null when the window has not started). Unknown windows are kept under
/// their key; other entries are ignored. A 200 with no window is a format change.
public struct ClaudePlanUsageClient: Sendable {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    public static let betaHeader = "anthropic-beta"
    public static let betaValue = "oauth-2025-04-20"
    static let timeout: TimeInterval = 15

    /// Endpoint keys with a Vigie window name (SPEC §7.2); any other key is kept as is.
    public static let windowNames: [String: String] = ["five_hour": "5h", "seven_day": "weekly"]

    let http: any HTTPClient

    public init(http: any HTTPClient) {
        self.http = http
    }

    /// The request for `token`. The token lives in this request only.
    static func request(token: String) -> URLRequest {
        var request = URLRequest(url: endpoint, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(betaValue, forHTTPHeaderField: betaHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    /// Fetches and decodes the windows. Throws ``PlanUsageError``.
    public func fetch(token: String, now: Date) async throws -> UsageSnapshot {
        let data: Data
        let response: HTTPURLResponse
        do {
            (data, response) = try await http.data(for: Self.request(token: token))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PlanUsageError.unavailable(status: nil)
        }
        switch response.statusCode {
        case 200: return UsageSnapshot(windows: try Self.decode(data), fetchedAt: now)
        case 401, 403: throw PlanUsageError.unauthorized
        default: throw PlanUsageError.unavailable(status: response.statusCode)
        }
    }

    /// Pure: the windows in a 200 body, sorted `5h`, `weekly`, then the others by key.
    public static func decode(_ data: Data) throws(PlanUsageError) -> [UsageWindow] {
        guard let object = try? JSONSerialization.jsonObject(with: data), let root = object as? [String: Any] else {
            throw .formatChanged
        }
        var windows: [UsageWindow] = []
        for (key, value) in root {
            guard let entry = value as? [String: Any], let utilization = number(entry["utilization"]),
                entry.keys.contains("resets_at")
            else { continue }
            let resetsAt: Date?
            switch entry["resets_at"] {
            case let text as String:
                guard let date = parseDate(text) else { continue }
                resetsAt = date
            case is NSNull, nil:
                resetsAt = nil
            default:
                continue
            }
            windows.append(
                UsageWindow(name: windowNames[key] ?? key, used: utilization, limit: nil, resetsAt: resetsAt))
        }
        guard !windows.isEmpty else { throw .formatChanged }
        let rank: (String) -> Int = { name in ["5h": 0, "weekly": 1][name] ?? 2 }
        return windows.sorted { (rank($0.name), $0.name) < (rank($1.name), $1.name) }
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// ISO-8601 with or without fractional seconds (the endpoint sends microseconds, e.g.
    /// `2026-11-08T15:00:00.123456+00:00`).
    static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        if let date = plain.date(from: text) { return date }
        // Drop the fraction, parse, add it back (formatters disagree on more than 3 digits).
        guard let dot = text.firstIndex(of: ".") else { return nil }
        let digits = text[text.index(after: dot)...].prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = text[text.index(dot, offsetBy: digits.count + 1)...]
        guard let base = plain.date(from: String(text[..<dot]) + rest), let fraction = Double("0." + digits) else {
            return nil
        }
        return base.addingTimeInterval(fraction)
    }
}
