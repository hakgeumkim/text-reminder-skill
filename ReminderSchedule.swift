import Foundation

// Daily wall-clock hours in the Mac's timezone. End is exclusive.
struct ActiveHours {
    let startMinute: Int
    let endMinute: Int

    var isValid: Bool {
        (0..<1440).contains(startMinute) && (0..<1440).contains(endMinute) && startMinute != endMinute
    }

    var duration: TimeInterval {
        TimeInterval((endMinute - startMinute + 1440) % 1440) * 60
    }

    private func window(startingOn day: Date, calendar: Calendar) -> DateInterval? {
        guard isValid,
              let endDay = calendar.date(byAdding: .day, value: endMinute < startMinute ? 1 : 0, to: day),
              let start = calendar.date(bySettingHour: startMinute / 60, minute: startMinute % 60, second: 0,
                                        of: day, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              let end = calendar.date(bySettingHour: endMinute / 60, minute: endMinute % 60, second: 0,
                                      of: endDay, matchingPolicy: .nextTime, repeatedTimePolicy: .first),
              start < end else { return nil }
        return DateInterval(start: start, end: end)
    }

    private func upcomingWindows(from now: Date, calendar: Calendar) -> [DateInterval] {
        let today = calendar.startOfDay(for: now)
        // Yesterday covers overnight hours; subsequent days cover a short DST day.
        return (-1...3).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return window(startingOn: day, calendar: calendar)
        }
    }

    func window(containing now: Date, calendar: Calendar) -> DateInterval? {
        upcomingWindows(from: now, calendar: calendar).first { $0.start <= now && now < $0.end }
    }

    func nextBoundary(after now: Date, calendar: Calendar) -> Date? {
        upcomingWindows(from: now, calendar: calendar)
            .flatMap { [$0.start, $0.end] }.filter { $0 > now }.min()
    }

    func permitsReminder(at now: Date, minimumDisplay: TimeInterval, calendar: Calendar) -> Bool {
        guard let window = window(containing: now, calendar: calendar) else { return false }
        return window.end.timeIntervalSince(now) >= minimumDisplay
    }

    func nextReminder(after now: Date, interval: TimeInterval, minimumDisplay: TimeInterval,
                      calendar: Calendar) -> Date? {
        guard isValid, interval > 0, interval.isFinite, interval + minimumDisplay <= duration else { return nil }
        for window in upcomingWindows(from: now, calendar: calendar) where window.end > now {
            let candidate = max(now, window.start).addingTimeInterval(interval)
            if candidate < window.end && window.end.timeIntervalSince(candidate) >= minimumDisplay {
                return candidate
            }
        }
        return nil
    }
}
