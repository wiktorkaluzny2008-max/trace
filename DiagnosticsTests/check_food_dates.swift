import Foundation

@main
struct FoodDateChecks {
    static func main() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        func day(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12) -> Date {
            cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour))!
        }
        let now = day(2026, 10, 6, 18)
        precondition(FoodLogDate.timestamp(on: now, now: now, calendar: cal) == now)
        for offset in [-3, -1, 1, 4] {
            let selected = FoodLogDate.shifted(now, by: offset, calendar: cal)
            let stamped = FoodLogDate.timestamp(on: selected, now: now, calendar: cal)
            precondition(cal.isDate(stamped, inSameDayAs: selected))
            precondition(cal.component(.hour, from: stamped) == 18)
        }
        let spring = day(2026, 3, 28)
        precondition(FoodLogDate.shifted(spring, by: 1, calendar: cal).timeIntervalSince(spring) == 23 * 3600)
        let autumn = day(2026, 10, 24)
        precondition(FoodLogDate.shifted(autumn, by: 1, calendar: cal).timeIntervalSince(autumn) == 25 * 3600)
        precondition(cal.isDate(FoodLogDate.shifted(day(2026, 1, 1), by: -1, calendar: cal), inSameDayAs: day(2025, 12, 31)))
        // A dinner logged yesterday for today must appear even before dinner time.
        let morning = day(2026, 10, 7, 8)
        let preloggedDinner = FoodLogDate.timestamp(on: morning, now: now, calendar: cal)
        let cutoff = FoodLogDate.nutritionQueryEnd(on: morning, calendar: cal)
        precondition(preloggedDinner > morning && preloggedDinner <= cutoff)
        precondition(cutoff < day(2026, 10, 8, 0))
        for (month, date, hours) in [(3, 29, 23), (10, 25, 25)] {
            let start = day(2026, month, date, 0)
            let end = FoodLogDate.nutritionQueryEnd(on: start, calendar: cal)
            precondition(abs(end.timeIntervalSince(start) - (Double(hours) * 3600 - 0.001)) < 0.0001)
        }
        print("PASS: today, past/future timestamps, year boundary and 23/25-hour daylight-saving days")
    }
}
