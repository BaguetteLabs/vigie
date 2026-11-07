import Foundation
import ModuleKit
import Synchronization
import Testing
import UserNotifications

@testable import VigieCore

struct RequestBox: @unchecked Sendable { let request: UNNotificationRequest }

final class FakeNotificationCenterClient: NotificationCenterClient {
    private struct State {
        var status: UNAuthorizationStatus
        var grantOnRequest: Bool
        var requests = 0
        var added: [RequestBox] = []
        var removed: [String] = []
        var click: (@MainActor @Sendable (String) -> Void)?
    }
    private let state: Mutex<State>

    init(status: UNAuthorizationStatus = .notDetermined, grantOnRequest: Bool = true) {
        state = Mutex(State(status: status, grantOnRequest: grantOnRequest))
    }

    var requestCount: Int { state.withLock { $0.requests } }
    var added: [UNNotificationRequest] { state.withLock { $0.added.map(\.request) } }
    var removed: [String] { state.withLock { $0.removed } }

    func authorizationStatus() async -> UNAuthorizationStatus { state.withLock { $0.status } }
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        state.withLock {
            $0.requests += 1
            $0.status = $0.grantOnRequest ? .authorized : .denied
            return $0.grantOnRequest
        }
    }
    func add(_ request: UNNotificationRequest) async throws {
        let box = RequestBox(request: request)
        state.withLock { $0.added.append(box) }
    }
    func removeDelivered(ids: [String]) async { state.withLock { $0.removed += ids } }
    func setClickHandler(_ handler: @escaping @MainActor @Sendable (String) -> Void) {
        state.withLock { $0.click = handler }
    }
    @MainActor func click(_ id: String) {
        let handler = state.withLock { $0.click }
        handler?(id)
    }
}

@MainActor @Suite struct SystemNotificationTests {
    let router = RecordingActionRouter()
    var denials = DenialLog()

    final class DenialLog { var messages: [String] = [] }

    func alert(action: AlertAction? = nil) -> ActiveAlert {
        ActiveAlert(
            id: UUID(), module: "agents.sessions",
            event: NotifierEvent(
                kind: "session.done", severity: .info, title: "api-refactor", body: "Done", action: action),
            outputs: [.system], postedAt: Date())
    }

    func sink(_ client: FakeNotificationCenterClient) -> SystemNotificationSink {
        let log = denials
        return SystemNotificationSink(client: client, router: router) { log.messages.append($0) }
    }

    @Test func firstShowRequestsAndPostsSecondDoesNotRequest() async {
        let client = FakeNotificationCenterClient()
        let sink = sink(client)
        let first = alert()
        await sink.show(alert: first)
        await sink.show(alert: alert())
        #expect(client.requestCount == 1)
        #expect(client.added.count == 2)
        let request = client.added[0]
        #expect(request.identifier == first.id.uuidString)
        #expect(request.content.title == "api-refactor" && request.content.body == "Done")
        #expect(request.content.userInfo["alertID"] as? String == first.id.uuidString)
        #expect(denials.messages.isEmpty)
    }

    @Test func deniedReportsOnceAndNeverPosts() async {
        let client = FakeNotificationCenterClient(status: .denied)
        let sink = sink(client)
        for _ in 0..<3 { await sink.show(alert: alert()) }
        #expect(client.added.isEmpty && client.requestCount == 0)
        #expect(denials.messages.count == 1)
        #expect(denials.messages[0].contains("denied"))
    }

    @Test func refusedPromptCountsAsDeniedWithoutRerequesting() async {
        let client = FakeNotificationCenterClient(grantOnRequest: false)
        let sink = sink(client)
        for _ in 0..<2 { await sink.show(alert: alert()) }
        #expect(client.requestCount == 1 && client.added.isEmpty && denials.messages.count == 1)
    }

    @Test func clickRoutesTheAlertAction() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let sink = sink(client)
        let url = URL(string: "https://example.com")!
        let a = alert(action: .openURL(url))
        await sink.show(alert: a)
        client.click(a.id.uuidString)
        #expect(router.calls == [.url(url)])
        client.click(UUID().uuidString)
        #expect(router.calls.count == 1)
    }

    @Test func retractRemovesDeliveredById() async {
        let client = FakeNotificationCenterClient(status: .authorized)
        let sink = sink(client)
        let a = alert()
        await sink.show(alert: a)
        sink.retract(alert: a.id)
        await Task.yield()
        for _ in 0..<20 where client.removed.isEmpty { await Task.yield() }
        #expect(client.removed == [a.id.uuidString])
    }

    @Test func neverRequestsWhenNoRuleUsesSystem() async {
        let client = FakeNotificationCenterClient()
        let sink = sink(client)
        let center = AlertCenter(
            rules: StaticNotifyRules(global: GlobalNotifyRules(), kinds: [:]), clock: TestClock(),
            sinks: AlertSinks(system: sink, actionRouter: router), log: testLogger)
        let notifier = center.makeNotifier(
            for: ModuleManifest(id: "agents.sessions", name: "S", icon: "circle", alertKinds: ["session.done"]))
        _ = notifier.post(NotifierEvent(kind: "session.done", severity: .info, title: "t"))
        await Task.yield()
        #expect(client.requestCount == 0 && client.added.isEmpty)
    }
}
