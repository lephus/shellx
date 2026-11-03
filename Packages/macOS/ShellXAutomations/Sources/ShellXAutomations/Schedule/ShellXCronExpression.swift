public import Foundation

/// A five-field numeric cron expression that launchd can schedule.
///
/// Supports `*`, `n`, `a-b`, comma lists, `*/n` and `a-b/n`. Day-of-week is `0-7` with `7` meaning Sunday.
/// Names, `@` shortcuts and restricting both day fields are rejected.
public struct ShellXCronExpression: Sendable, Equatable {
    private struct Field: Sendable, Equatable {
        let key: String
        let values: [Int]
        let isWildcard: Bool
    }

    private let minute: Field
    private let hour: Field
    private let dayOfMonth: Field
    private let month: Field
    private let weekday: Field

    /// Parses `text`.
    public init(_ text: String) throws(ShellXCronError) {
        let parts = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard parts.count == 5 else {
            if parts.count == 1, parts[0].hasPrefix("@") { throw .unsupported }
            throw .malformed
        }
        minute = try Self.parse(parts[0], key: "Minute", range: 0...59)
        hour = try Self.parse(parts[1], key: "Hour", range: 0...23)
        dayOfMonth = try Self.parse(parts[2], key: "Day", range: 1...31)
        month = try Self.parse(parts[3], key: "Month", range: 1...12)
        weekday = try Self.parse(parts[4], key: "Weekday", range: 0...7)
        if !dayOfMonth.isWildcard && !weekday.isWildcard { throw .bothDayFields }
    }

    /// Expands to launchd `StartCalendarInterval` dictionaries; wildcard fields are omitted.
    public func launchdCalendarIntervals(limit: Int = 200) throws(ShellXCronError) -> [[String: Int]] {
        let fields = [minute, hour, dayOfMonth, month, weekday].filter { !$0.isWildcard }
        var count = 1
        for field in fields {
            count *= field.values.count
            if count > limit { throw .tooManyEntries }
        }
        var entries: [[String: Int]] = [[:]]
        for field in fields {
            entries = entries.flatMap { entry in
                field.values.map { value in
                    var copy = entry
                    copy[field.key] = value
                    return copy
                }
            }
        }
        return entries
    }

    /// The first date strictly after `after` that matches, in `calendar`'s time zone, or nil if none within four years.
    public func nextFireDate(after: Date, calendar: Calendar) -> Date? {
        let startOfToday = calendar.startOfDay(for: after)
        for offset in 0...(366 * 4 + 1) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfToday) else { return nil }
            let parts = calendar.dateComponents([.month, .day, .weekday], from: day)
            guard let m = parts.month, let d = parts.day, let w = parts.weekday,
                  month.values.contains(m), dayOfMonth.values.contains(d), weekday.values.contains(w - 1) else { continue }
            for h in hour.values {
                for mi in minute.values {
                    guard let candidate = calendar.date(bySettingHour: h, minute: mi, second: 0, of: day),
                          candidate > after else { continue }
                    return candidate
                }
            }
        }
        return nil
    }

    private static func parse(_ text: String, key: String, range: ClosedRange<Int>) throws(ShellXCronError) -> Field {
        if text.contains(where: { $0.isLetter }) || text.hasPrefix("@") { throw .unsupported }
        var values = Set<Int>()
        for item in text.split(separator: ",", omittingEmptySubsequences: false) {
            let halves = item.split(separator: "/", omittingEmptySubsequences: false)
            guard halves.count <= 2 else { throw .malformed }
            var step = 1
            if halves.count == 2 {
                guard let s = Int(halves[1]), s > 0 else { throw .malformed }
                step = s
            }
            let base = String(halves[0])
            let low: Int
            let high: Int
            if base == "*" {
                if step > 1, key == "Minute" || key == "Hour", range.count % step != 0 { throw .unevenStep(field: key) }
                (low, high) = (range.lowerBound, range.upperBound)
            } else if halves.count == 2 && !base.contains("-") {
                throw .malformed
            } else if base.contains("-") {
                let ends = base.split(separator: "-", omittingEmptySubsequences: false)
                guard ends.count == 2, let a = Int(ends[0]), let b = Int(ends[1]), a <= b else { throw .malformed }
                (low, high) = (a, b)
            } else {
                guard let n = Int(base) else { throw .malformed }
                (low, high) = (n, n)
            }
            guard range.contains(low), range.contains(high) else { throw .outOfRange(field: key) }
            var v = low
            while v <= high {
                values.insert(key == "Weekday" && v == 7 ? 0 : v)
                v += step
            }
        }
        let normalizedCount = key == "Weekday" ? 7 : range.count
        return Field(key: key, values: values.sorted(), isWildcard: values.count == normalizedCount)
    }
}
