import Foundation

public enum MemoryGraphWindow {
    /// Calendar-month paging, bounded by deck creation and the forecast horizon.
    public static func interval(anchor: Date, months: Int, start: Date, end: Date, calendar: Calendar = .current) -> DateInterval {
        let end = max(end, start.addingTimeInterval(1))
        guard months > 0 else { return DateInterval(start: start, end: end) }
        let latest = max(start, calendar.date(byAdding: .month, value: -months, to: end) ?? start)
        let lower = min(max(anchor, start), latest)
        let upper = min(end, calendar.date(byAdding: .month, value: months, to: lower) ?? end)
        return DateInterval(start: lower, end: max(upper, lower.addingTimeInterval(1)))
    }
}
