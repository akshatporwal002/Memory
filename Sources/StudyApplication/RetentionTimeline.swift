import Foundation

public enum RetentionTimeline {
    /// A calendar month at today determines the scrollable viewport duration.
    public static func duration(months: Int, now: Date, start: Date, end: Date, calendar: Calendar = .current) -> TimeInterval {
        let full = max(1, end.timeIntervalSince(start))
        guard months > 0 else { return full }
        let until = calendar.date(byAdding: .month, value: months, to: now) ?? now.addingTimeInterval(30 * 86_400)
        return min(full, max(1, until.timeIntervalSince(now)))
    }
}
