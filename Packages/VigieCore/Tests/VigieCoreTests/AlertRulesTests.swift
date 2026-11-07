import Foundation
import ModuleKit
import Testing

@testable import VigieCore

let parisCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
    return calendar
}()

/// 2026-11-07 at `hour:minute` in Paris.
func parisDate(_ hour: Int, _ minute: Int, day: Int = 7) -> Date {
    parisCalendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
}

@Suite struct AlertRulesTests {
    @Test func quietHoursAcrossMidnight() throws {
        let quiet = try #require(QuietHours("22:00-08:00"))
        #expect(quiet.contains(parisDate(23, 30), calendar: parisCalendar))
        #expect(quiet.contains(parisDate(22, 0), calendar: parisCalendar))
        #expect(quiet.contains(parisDate(0, 0), calendar: parisCalendar))
        #expect(quiet.contains(parisDate(7, 59), calendar: parisCalendar))
        #expect(!quiet.contains(parisDate(8, 0), calendar: parisCalendar))
        #expect(!quiet.contains(parisDate(21, 59), calendar: parisCalendar))
        #expect(!quiet.contains(parisDate(12, 0), calendar: parisCalendar))
    }

    @Test func quietHoursSameDayWindow() throws {
        let quiet = try #require(QuietHours("12:00-13:00"))
        #expect(!quiet.contains(parisDate(11, 59), calendar: parisCalendar))
        #expect(quiet.contains(parisDate(12, 0), calendar: parisCalendar))
        #expect(quiet.contains(parisDate(12, 59), calendar: parisCalendar))
        #expect(!quiet.contains(parisDate(13, 0), calendar: parisCalendar))
        #expect(!quiet.contains(parisDate(23, 30), calendar: parisCalendar))
    }

    @Test func quietHoursUseTheGivenTimeZone() throws {
        let quiet = try #require(QuietHours("22:00-08:00"))
        // 23:30 in Paris is 22:30 UTC (winter), 17:30 in New York.
        let date = parisDate(23, 30)
        #expect(quiet.contains(date, calendar: parisCalendar, timeZone: TimeZone(identifier: "UTC")!))
        #expect(!quiet.contains(date, calendar: parisCalendar, timeZone: TimeZone(identifier: "America/New_York")!))
    }

    @Test func quietHoursParsing() {
        #expect(QuietHours("22:00-08:00")?.description == "22:00-08:00")
        #expect(QuietHours(" 7:05 - 9:30 ")?.description == "07:05-09:30")
        #expect(QuietHours("") == nil)
        #expect(QuietHours("22:00") == nil)
        #expect(QuietHours("24:00-08:00") == nil)
        #expect(QuietHours("22:60-08:00") == nil)
        #expect(QuietHours("22h00-08h00") == nil)
        #expect(QuietHours("10:00-10:00") == nil)
        #expect(QuietHours("-1:00-08:00") == nil)
    }

    @Test func moduleKindRuleOverridesGlobalFieldByField() throws {
        let quiet = try #require(QuietHours("22:00-08:00"))
        let global = GlobalNotifyRules(
            defaults: NotifyRule(minSeverity: .warn, quietHours: quiet, cooldown: .seconds(60)))
        let rules = StaticNotifyRules(
            global: global,
            kinds: [
                "agents.sessions": [
                    "session.done": NotifyRule(
                        cooldown: .seconds(5), reminder: .seconds(600), outputs: [.peek],
                        conditions: [.minWorkingTime(.seconds(30))])
                ]
            ])
        let done = rules.rule(module: "agents.sessions", kind: "session.done")
        #expect(done.minSeverity == .warn)
        #expect(done.quietHours == quiet)
        #expect(done.cooldown == .seconds(5))
        #expect(done.reminder == .seconds(600))
        #expect(done.outputs == [.peek])
        #expect(done.effectiveConditions == [.minMetric(name: "working_duration", value: 30)])
        #expect(!done.isMuted)

        let blocked = rules.rule(module: "agents.sessions", kind: "session.blocked")
        #expect(blocked == global.defaults)
        #expect(blocked.effectiveOutputs(for: .critical) == [.peek, .sound])
    }

    @Test func specDefaultsForGlobalNotify() {
        let global = GlobalNotifyRules()
        #expect(global.defaults.minSeverity == .info)
        #expect(global.defaults.cooldown == .zero)
        #expect(global.defaults.quietHours == nil)
        #expect(global.afterFocus == .drop)
    }

    @Test func conditionKeysMapToMetrics() {
        #expect(RuleCondition.metricName(forConfigKey: "min_working_time") == "working_duration")
        #expect(RuleCondition.metricName(forConfigKey: "min_tokens") == "tokens")
        #expect(RuleCondition.metricName(forConfigKey: "min_severity") == nil)
        #expect(RuleCondition.metricName(forConfigKey: "cooldown") == nil)
        #expect(RuleCondition.metricName(forConfigKey: "min_") == nil)
    }

    @Test func defaultOutputsNeverIncludeSystem() {
        for severity in [AlertSeverity.info, .warn, .critical] {
            #expect(NotifyRule.defaultOutputs(for: severity) == [.peek, .sound])
        }
    }
}
