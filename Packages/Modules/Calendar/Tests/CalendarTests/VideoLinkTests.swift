import CoreGraphics
import Foundation
import Testing

@testable import Calendar

@Suite struct VideoLinkTests {
    static let meet = "https://meet.google.com/abc-defg-hij"
    static let zoom = "https://acme.zoom.us/j/81234567890?pwd=xyz"
    static let teams = "https://teams.microsoft.com/l/meetup-join/19%3ameeting_abc%40thread.v2/0?context=%7b%7d"

    @Test(arguments: [
        (meet, VideoService.meet), (zoom, .zoom), (teams, .teams),
        ("https://zoom.us/my/someone", .zoom), ("https://teams.live.com/meet/9876543210", .teams),
        ("zoommtg://zoom.us/join?confno=81234567890", .zoom),
    ])
    func linkInURLField(link: String, service: VideoService) {
        let url = URL(string: link)!
        #expect(VideoLink.service(of: url) == service)
        #expect(VideoLink.extract(url: url, location: nil, notes: nil) == url)
    }

    @Test(arguments: [meet, zoom, teams])
    func linkInLocation(link: String) {
        let found = VideoLink.extract(url: nil, location: "Room 4 / \(link)", notes: nil)
        #expect(found == URL(string: link))
    }

    @Test(arguments: [meet, zoom, teams])
    func linkInNotes(link: String) {
        let notes = """
            Agenda: roadmap.
            Docs: https://docs.example.com/roadmap
            Join: \(link)
            """
        #expect(VideoLink.extract(url: nil, location: "Office", notes: notes) == URL(string: link))
    }

    @Test func urlWinsOverLocationAndNotes() {
        let found = VideoLink.extract(
            url: URL(string: Self.zoom), location: Self.meet, notes: "Join \(Self.teams)")
        #expect(found == URL(string: Self.zoom))
    }

    @Test func nonMeetingURLFieldFallsBackToTheText() {
        let found = VideoLink.extract(
            url: URL(string: "https://example.com/event"), location: nil, notes: "Call: \(Self.meet)")
        #expect(found == URL(string: Self.meet))
    }

    @Test(arguments: [
        "https://example.com/meet", "https://meet.google.com/", "https://zoom.us/pricing",
        "https://teams.microsoft.com/v2/", "https://www.microsoft.com/teams", "mailto:a@example.com",
    ])
    func notAMeetingLink(link: String) {
        let url = URL(string: link)!
        #expect(VideoLink.service(of: url) == nil)
        #expect(VideoLink.extract(url: url, location: link, notes: link) == nil)
    }

    @Test func noLinkAnywhere() {
        #expect(VideoLink.extract(url: nil, location: nil, notes: nil) == nil)
        #expect(VideoLink.extract(url: nil, location: "Room 4", notes: "Bring slides.") == nil)
    }

    @Test func alarmFireDates() {
        let start = Date(timeIntervalSince1970: 1_000_000)
        #expect(AlarmInfo.relative(-600).fireDate(eventStart: start) == start.addingTimeInterval(-600))
        #expect(AlarmInfo.absolute(start).fireDate(eventStart: .distantFuture) == start)
    }

    @Test func colorConvertsToSRGBComponents() {
        let color = EventKitCalendarSource.color(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        #expect(abs(color.red - 0.2) < 0.001 && abs(color.green - 0.4) < 0.001 && abs(color.blue - 0.6) < 0.001)
        #expect(EventKitCalendarSource.color(nil) == CalendarColor(sRGBRed: 0.5, green: 0.5, blue: 0.5))
    }
}
