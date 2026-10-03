import Foundation

/// Equal-width review intervals. Dates within each interval retain their relative position.
public struct ReviewStepScale: Sendable {
    public let dates: [Date]
    public init(start: Date, now: Date, end: Date, reviews: [Date]) {
        let end = max(end, start.addingTimeInterval(1))
        dates = Array(Set([start, min(max(now, start), end), end] + reviews.filter { $0 >= start && $0 <= end })).sorted()
    }
    public var maximum: Double { Double(max(1, dates.count - 1)) }
    public func position(_ date: Date) -> Double {
        guard let first = dates.first, let last = dates.last, dates.count > 1 else { return 0 }
        if date <= first { return 0 }
        if date >= last { return maximum }
        let upper = dates.firstIndex { $0 >= date }!
        let lower = upper - 1
        return Double(lower) + date.timeIntervalSince(dates[lower]) / dates[upper].timeIntervalSince(dates[lower])
    }
    public func date(at position: Double) -> Date {
        guard let first = dates.first, let last = dates.last, dates.count > 1 else { return dates.first ?? .distantPast }
        if position <= 0 { return first }
        if position >= maximum { return last }
        let index = Int(position.rounded(.down))
        return dates[index].addingTimeInterval(dates[index + 1].timeIntervalSince(dates[index]) * (position - Double(index)))
    }
    public func visibleSteps(months: Int, now: Date, calendar: Calendar = .current) -> Double {
        guard months > 0 else { return maximum }
        let end = calendar.date(byAdding: .month, value: months, to: now) ?? now
        return min(maximum, max(1, position(end) - position(now)))
    }
}
