import SwiftUI

extension EnvironmentValues {
    /// Nil outside the food diary preserves the normal log-now behavior.
    @Entry var foodLoggingDate: Date? = nil
    @Entry var foodLoggingSlot: MealSlot? = nil
}

nonisolated enum FoodLogDate {
    /// Calendar arithmetic preserves local dates across daylight-saving changes.
    static func timestamp(on day: Date, now: Date = Date(), calendar: Calendar = .current) -> Date {
        if calendar.isDate(day, inSameDayAs: now) { return now }
        let time = calendar.dateComponents([.hour, .minute, .second], from: now)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0,
                             second: time.second ?? 0, of: day) ?? calendar.startOfDay(for: day)
    }
    /// Include prelogged meals later on this date without including tomorrow.
    static func nutritionQueryEnd(on day: Date, calendar: Calendar = .current) -> Date {
        let start = calendar.startOfDay(for: day)
        return (calendar.date(byAdding: .day, value: 1, to: start) ?? day).addingTimeInterval(-0.001)
    }

    static func shifted(_ day: Date, by offset: Int, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: offset, to: day) ?? day
    }
}
