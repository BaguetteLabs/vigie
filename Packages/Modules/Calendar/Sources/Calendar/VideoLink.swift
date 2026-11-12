import Foundation

/// The video-call services whose links get `JOIN CALL` (SPEC §7.5 [ASSUMPTION]: Meet, Zoom, Teams).
public enum VideoService: String, Hashable, Sendable, CaseIterable {
    case meet
    case zoom
    case teams
}

/// Finds a video-call link in an event's fields. Pure: no I/O, no EventKit.
public enum VideoLink {
    /// The first Meet, Zoom or Teams link, looking at the event `url`, then `location`, then `notes`.
    public static func extract(url: URL?, location: String?, notes: String?) -> URL? {
        if let url, service(of: url) != nil { return url }
        for text in [location, notes] {
            guard let text, !text.isEmpty else { continue }
            if let found = links(in: text).first(where: { service(of: $0) != nil }) { return found }
        }
        return nil
    }

    /// The service a link joins, or nil when it is not a meeting link of a known service.
    public static func service(of url: URL) -> VideoService? {
        switch url.scheme?.lowercased() {
        case "zoommtg", "zoomus": return .zoom
        case "msteams": return .teams
        case "https", "http": break
        default: return nil
        }
        guard let host = url.host()?.lowercased() else { return nil }
        let path = url.path().lowercased()
        if host == "meet.google.com" {
            return path.count > 1 ? .meet : nil
        }
        if host == "zoom.us" || host.hasSuffix(".zoom.us") || host == "zoom.com" || host.hasSuffix(".zoom.com") {
            let prefixes = ["/j/", "/my/", "/w/", "/s/", "/wc/join/"]
            return prefixes.contains(where: path.hasPrefix) ? .zoom : nil
        }
        if host == "teams.microsoft.com" || host == "teams.live.com" {
            let prefixes = ["/l/meetup-join/", "/meet/", "/l/meet/"]
            return prefixes.contains(where: path.hasPrefix) ? .teams : nil
        }
        return nil
    }

    /// Every link Foundation's data detector finds in `text`, in order.
    static func links(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range).compactMap(\.url)
    }
}
