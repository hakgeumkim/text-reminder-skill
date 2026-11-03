import Foundation

@main
struct ScheduleTests {
    static func main() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let iso = ISO8601DateFormatter()
        func date(_ value: String) -> Date { iso.date(from: value)! }
        var checks = 0
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            checks += 1
            guard condition() else { fatalError("FAIL: \(message)") }
        }
        func next(_ hours: ActiveHours, _ now: String, interval: TimeInterval = 3600,
                  calendar overrideCalendar: Calendar? = nil) -> Date? {
            hours.nextReminder(after: date(now), interval: interval, minimumDisplay: 3,
                               calendar: overrideCalendar ?? calendar)
        }
        let day = ActiveHours(startMinute: 9 * 60, endMinute: 22 * 60)
        check(day.isValid, "daytime configuration")
        check(!ActiveHours(startMinute: 540, endMinute: 540).isValid, "equal endpoints rejected")
        check(!ActiveHours(startMinute: -1, endMinute: 540).isValid, "negative endpoint rejected")
        check(!ActiveHours(startMinute: 540, endMinute: 1440).isValid, "out-of-range endpoint rejected")
        check(next(day, "2026-11-03T08:00:00+09:00") == date("2026-11-03T10:00:00+09:00"), "before opening starts a full interval at opening")
        check(next(day, "2026-11-03T09:00:00+09:00") == date("2026-11-03T10:00:00+09:00"), "opening is inclusive")
        check(next(day, "2026-11-03T12:34:20+09:00") == date("2026-11-03T13:34:20+09:00"), "dismiss/wake restarts a full interval")
        check(next(day, "2026-11-03T21:00:00+09:00") == date("2026-11-04T10:00:00+09:00"), "exact end is excluded")
        check(next(day, "2026-11-03T20:59:58+09:00") == date("2026-11-04T10:00:00+09:00"), "skip a two-second flash at the end")
        check(next(day, "2026-11-03T20:59:57+09:00") == date("2026-11-03T21:59:57+09:00"), "allow the complete three-second minimum")
        check(next(day, "2026-11-03T22:00:00+09:00") == date("2026-11-04T10:00:00+09:00"), "late launch/wake reports tomorrow")
        check(day.window(containing: date("2026-11-03T22:00:00+09:00"), calendar: calendar) == nil, "visible automatic overlay expires at end")
        check(day.nextBoundary(after: date("2026-11-03T08:00:00+09:00"), calendar: calendar) == date("2026-11-03T09:00:00+09:00"), "outside boundary is opening")
        check(day.nextBoundary(after: date("2026-11-03T09:00:00+09:00"), calendar: calendar) == date("2026-11-03T22:00:00+09:00"), "inside boundary is closing")
        check(!day.permitsReminder(at: date("2026-11-03T08:59:59+09:00"), minimumDisplay: 3, calendar: calendar), "callback eligibility checked before opening")
        check(!day.permitsReminder(at: date("2026-11-03T21:59:59+09:00"), minimumDisplay: 3, calendar: calendar), "delayed callback near closing skipped")

        let night = ActiveHours(startMinute: 22 * 60, endMinute: 2 * 60)
        check(night.duration == 4 * 3600, "overnight duration")
        check(next(night, "2026-11-03T21:00:00+09:00") == date("2026-11-03T23:00:00+09:00"), "overnight opening")
        check(next(night, "2026-11-04T00:15:00+09:00") == date("2026-11-04T01:15:00+09:00"), "early morning belongs to yesterday's window")
        check(next(night, "2026-11-04T01:00:00+09:00") == date("2026-11-04T23:00:00+09:00"), "overnight late wake skips to tonight")
        check(night.nextBoundary(after: date("2026-11-04T00:00:00+09:00"), calendar: calendar) == date("2026-11-04T02:00:00+09:00"), "overnight close boundary")
        check(next(night, "2026-11-03T21:00:00+09:00", interval: 4 * 3600) == nil, "interval must leave room to display")
        check(next(day, "2026-11-03T08:00:00+09:00", interval: .infinity) == nil, "invalid interval fails closed")

        var la = Calendar(identifier: .gregorian)
        la.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let spring = ActiveHours(startMinute: 60, endMinute: 4 * 60)
        check(next(spring, "2026-03-08T00:00:00-08:00", interval: 2 * 3600, calendar: la) == date("2026-03-09T03:00:00-07:00"), "short spring day cannot fit interval; next normal day can")
        let missingStart = ActiveHours(startMinute: 150, endMinute: 5 * 60)
        check(next(missingStart, "2026-03-08T00:00:00-08:00", interval: 1800, calendar: la) == date("2026-03-08T03:30:00-07:00"), "nonexistent 02:30 opening advances to 03:00")
        let repeatedStart = ActiveHours(startMinute: 90, endMinute: 180)
        check(repeatedStart.nextBoundary(after: date("2026-11-01T00:00:00-07:00"), calendar: la) == date("2026-11-01T01:30:00-07:00"), "repeated opening uses first occurrence")
        check(next(day, "2026-11-03T00:00:00Z", calendar: la) == date("2026-11-03T01:00:00Z"), "timezone is provided by machine calendar, not fixed to KST")
        print("Passed \(checks) schedule checks (daytime, overnight, boundaries, wake policy, DST, timezone).")
    }
}
