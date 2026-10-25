//
//  SleepNeed.swift
//  RecoverySignal2
//
//  How much sleep you need tonight, and when to go to bed to get it.
//
//  SLEEP NEED — rebuilt every day from your own data:
//
//    need = baseline + strain + sleep debt − naps
//
//    baseline  Learned from your history: the typical length of the nights
//              after which you woke up well recovered (HRV above and resting
//              HR below your 30-day normal) and that had restorative
//              architecture (deep + REM ≥ 30% when stages are recorded).
//              Blended toward 7.6 h until there are enough such nights.
//    strain    Extra repair after a hard day: 1.4 h × ((strain − 8) ÷ 13)^1.5,
//              capped at 1¼ h — about 35 min after a 15 strain day.
//    debt      What you missed of your need on recent nights. A new shortfall
//              carries in full; older unpaid debt halves each night, and
//              sleeping longer than needed pays it down. Capped at 2 h.
//    naps      Daytime sleep today is subtracted.
//
//  BEDTIME — worked backwards from your wake time:
//
//    sleep target = need × goal (100% peak · 85% perform · 70% get by)
//    time in bed  = sleep target ÷ your typical sleep efficiency
//    bedtime      = wake time − time in bed, as a 30-minute window
//
//  If that's far earlier than your usual bedtime, a realistic step toward it
//  is offered too, since a regular schedule matters as much as the hours.
//

import Foundation

enum SleepNeedModel {

    static let populationBaseline = 7.6
    static let maximumDebt = 2.0
    static let maximumStrainExtra = 1.25

    struct Need {
        let baseline: Double
        let strainExtra: Double
        let debtExtra: Double
        let napCredit: Double
        var total: Double { max(baseline + strainExtra + debtExtra - napCredit, 4) }
    }

    // MARK: Baseline

    struct Baseline {
        let hours: Double
        /// Well-recovered nights it's learned from.
        let nights: Int
        var isPersonal: Bool { nights >= 5 }
    }

    private static let baselineKey = "sleep.baselineHours"
    private static let baselineNightsKey = "sleep.baselineNights"

    static var baseline: Baseline {
        let d = UserDefaults.standard
        return Baseline(hours: d.object(forKey: baselineKey) as? Double ?? populationBaseline,
                        nights: d.integer(forKey: baselineNightsKey))
    }

    /// Called after each refresh with the whole history. `excluded` (sick or
    /// travel nights) is skipped as a training example — a feverish night
    /// scoring "well recovered" by pure coincidence shouldn't teach the model
    /// that's a night you need less sleep.
    static func learnBaseline(from all: [DailyMetrics], excluded: Set<Date> = []) {
        let days = all.sorted { $0.date < $1.date }
        var restorativeNights: [Double] = []
        for (i, day) in days.enumerated() {
            guard let asleep = day.sleepAsleepHours, asleep >= 4,
                  !excluded.contains(Calendar.current.startOfDay(for: day.date)) else { continue }
            let history = days[max(0, i - 30)..<i]
            var z = 0.0, count = 0
            if let hrv = day.hrvSDNN, let zh = Stats.zScore(hrv, in: history.compactMap(\.hrvSDNN)) { z += zh; count += 1 }
            if let rhr = day.restingHeartRate, let zr = Stats.zScore(rhr, in: history.compactMap(\.restingHeartRate)) { z -= zr; count += 1 }
            guard count > 0, z / Double(count) >= 0.5 else { continue }
            if let deep = day.sleepDeepHours, let rem = day.sleepREMHours, deep + rem > 0,
               (deep + rem) / asleep < 0.3 { continue }
            restorativeNights.append(asleep)
        }

        let recent = Array(restorativeNights.suffix(60))
        let hours: Double
        if let median = median(recent) {
            // Shrink toward the population value while evidence is thin.
            let n = Double(recent.count), k = 10.0
            hours = min(max((n * median + k * populationBaseline) / (n + k), 6.5), 9.5)
        } else {
            hours = populationBaseline
        }
        UserDefaults.standard.set(hours, forKey: baselineKey)
        UserDefaults.standard.set(recent.count, forKey: baselineNightsKey)
    }

    // MARK: Components

    static func strainExtra(_ strain: Double?) -> Double {
        guard let strain, strain > 8 else { return 0 }
        return min(1.4 * pow((strain - 8) / 13, 1.5), maximumStrainExtra)
    }

    /// Need for the night ending on the morning of `wakeDay`.
    static func need(forNightEnding wakeDay: Date, days: [DailyMetrics], calendar: Calendar = .current) -> Need {
        let morning = calendar.startOfDay(for: wakeDay)
        let byDay = Dictionary(days.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let base = baseline.hours

        /// Need before debt: baseline + the previous day's strain − its naps.
        func core(_ night: Date) -> (strain: Double, nap: Double) {
            let previous = calendar.date(byAdding: .day, value: -1, to: night) ?? night
            return (strainExtra(byDay[previous]?.strain), byDay[previous]?.napHours ?? 0)
        }

        // Walk the last two weeks of nights to carry debt forward.
        var debt = 0.0
        for back in stride(from: 14, through: 1, by: -1) {
            guard let night = calendar.date(byAdding: .day, value: -back, to: morning) else { continue }
            let c = core(night)
            let nightCore = max(base + c.strain - c.nap, 4)
            guard let asleep = byDay[night]?.sleepAsleepHours, asleep > 0 else {
                debt *= 0.5          // no data: let old debt fade rather than invent more
                continue
            }
            let shortfall = max(nightCore - asleep, 0)
            let surplus = max(asleep - nightCore, 0)
            debt = min(shortfall + 0.5 * max(debt - surplus, 0), maximumDebt)
        }

        let tonight = core(morning)
        return Need(baseline: base, strainExtra: tonight.strain, debtExtra: debt, napCredit: tonight.nap)
    }

    /// Hours asleep as a share of what was needed, capped at 100%.
    static func performance(asleep: Double, need: Need) -> Double {
        guard need.total > 0 else { return 0 }
        return min(asleep / need.total, 1)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let s = values.sorted()
        return s.count.isMultiple(of: 2) ? (s[s.count / 2 - 1] + s[s.count / 2]) / 2 : s[s.count / 2]
    }
}

// MARK: - Bedtime planner

enum SleepPlanner {

    enum Goal: String, CaseIterable, Identifiable {
        case peak, perform, getBy

        var id: String { rawValue }

        var label: String {
            switch self {
            case .peak:    String(localized: "Peak")
            case .perform: String(localized: "Perform")
            case .getBy:   String(localized: "Get by")
            }
        }

        var detail: String {
            switch self {
            case .peak:    String(localized: "Meet 100% of your need")
            case .perform: String(localized: "Meet 85% — a solid night")
            case .getBy:   String(localized: "Meet 70% — the minimum")
            }
        }

        var share: Double {
            switch self {
            case .peak:    1.0
            case .perform: 0.85
            case .getBy:   0.70
            }
        }
    }

    // MARK: Settings

    private static let goalKey = "sleepPlan.goal"
    private static let useTypicalWakeKey = "sleepPlan.useTypicalWake"

    static var goal: Goal {
        get { UserDefaults.standard.string(forKey: goalKey).flatMap(Goal.init) ?? .perform }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: goalKey) }
    }

    private static let oneOffWakeKey = "sleepPlan.oneOffWake"

    /// When true, wake time comes from your recent mornings; otherwise from
    /// the every-day wake time.
    static var useTypicalWake: Bool {
        get { UserDefaults.standard.object(forKey: useTypicalWakeKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: useTypicalWakeKey) }
    }

    /// A wake-up set for the next morning only. Ignored once it has passed.
    static var oneOffWake: Date? {
        get {
            guard let t = UserDefaults.standard.object(forKey: oneOffWakeKey) as? Double else { return nil }
            let date = Date(timeIntervalSince1970: t)
            return date > Date().addingTimeInterval(3600) ? date : nil
        }
        set {
            if let newValue { UserDefaults.standard.set(newValue.timeIntervalSince1970, forKey: oneOffWakeKey) }
            else { UserDefaults.standard.removeObject(forKey: oneOffWakeKey) }
        }
    }

    /// The next time this clock time comes round, at least 3 hours from now.
    static func nextOccurrence(of time: DateComponents, after now: Date = Date(), calendar: Calendar = .current) -> Date? {
        let minuteOfDay = (time.hour ?? 7) * 60 + (time.minute ?? 0)
        for offset in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)),
                  let candidate = calendar.date(byAdding: .minute, value: minuteOfDay, to: day),
                  candidate > now.addingTimeInterval(3 * 3600) else { continue }
            return candidate
        }
        return nil
    }

    /// Typical minutes to fall asleep when there isn't enough of your own data.
    static let defaultLatencyMinutes = 15.0

    // MARK: Plan

    struct Option: Identifiable {
        let id = UUID()
        let wake: Date
        let bedtime: Date
    }

    enum WakeSource { case usual, everyDay, tomorrowOnly }

    struct Plan {
        let need: SleepNeedModel.Need
        let goal: Goal
        let wake: Date
        let wakeSource: WakeSource
        /// Median minutes to fall asleep over recent nights (or the default).
        let latencyMinutes: Double
        let latencyIsPersonal: Bool
        /// Expected awake time during the night, in minutes.
        let nightWakingMinutes: Double
        let sleepTarget: Double
        let efficiency: Double
        let timeInBed: Double
        let bedtime: Date
        let windowStart: Date
        let windowEnd: Date
        let typicalBedtime: Date?
        /// A step toward the ideal bedtime when it's far from your habit.
        let realisticBedtime: Date?
        let realisticShare: Double?
        let consistencyMinutes: Double?
        let options: [Option]

        var awakeInBedMinutes: Double { (timeInBed - sleepTarget) * 60 }
    }

    static func plan(days: [DailyMetrics], goal: Goal = SleepPlanner.goal, now: Date = Date(),
                     calendar: Calendar = .current) -> Plan? {
        let sorted = days.sorted { $0.date < $1.date }
        let recent = sorted.filter { $0.date >= (calendar.date(byAdding: .day, value: -28, to: now) ?? now) }

        // Typical wake time and bedtime, as minutes from midnight.
        let wakeMinutes = recent.compactMap(\.sleepEnd).map { minutesOfDay($0, calendar) }
        let bedMinutes = recent.compactMap(\.sleepStart).map { minutesOfDay($0, calendar, eveningBased: true) }
        let typicalWake = SleepNeedModel.median(wakeMinutes.map(Double.init))
        let typicalBed = SleepNeedModel.median(bedMinutes.map(Double.init))

        let useTypical = useTypicalWake && wakeMinutes.count >= 5
        let fixed = BedtimeAlarm.wakeTime
        let wakeMinuteOfDay = useTypical ? Int(typicalWake ?? 420) : (fixed.hour ?? 7) * 60 + (fixed.minute ?? 0)

        // A wake-up set just for tomorrow wins; otherwise the next usual or
        // every-day wake-up that's at least 3 hours away.
        let source: WakeSource
        let wake: Date
        if let oneOff = oneOffWake, oneOff > now {
            wake = oneOff
            source = .tomorrowOnly
        } else if let next = nextOccurrence(of: DateComponents(hour: wakeMinuteOfDay / 60, minute: wakeMinuteOfDay % 60),
                                            after: now, calendar: calendar) {
            wake = next
            source = useTypical ? .usual : .everyDay
        } else {
            return nil
        }

        let need = SleepNeedModel.need(forNightEnding: wake, days: sorted, calendar: calendar)
        // Time in bed = sleep you need + how long you take to fall asleep +
        // how long you're usually awake during the night.
        let latencies = recent.compactMap(\.sleepLatencyMinutes).filter { $0 >= 0 && $0 <= 120 }
        let latencyIsPersonal = latencies.count >= 3
        let latency = latencyIsPersonal ? (SleepNeedModel.median(latencies) ?? defaultLatencyMinutes) : defaultLatencyMinutes
        let wakingShares = recent.compactMap { d -> Double? in
            guard let asleep = d.sleepAsleepHours, asleep > 2, let waso = d.sleepWakeAfterOnsetHours else { return nil }
            return waso / asleep
        }
        let wakingShare = min(max(SleepNeedModel.median(wakingShares) ?? 0.05, 0), 0.15)
        let target = need.total * goal.share
        let nightWaking = target * wakingShare
        // Sanity limit: no plan asks for more than 11½ hours in bed, however
        // odd the recorded nights look.
        let inBed = min(target + nightWaking + latency / 60, 11.5)
        let efficiency = target / inBed
        let bedtime = wake.addingTimeInterval(-inBed * 3600)

        var typicalBedtime: Date?
        var realistic: Date?
        var realisticShare: Double?
        if let typicalBed, bedMinutes.count >= 5 {
            let eveningStart = calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: wake)) ?? wake
            let habit = eveningStart.addingTimeInterval(Double(Int(typicalBed)) * 60)
            typicalBedtime = habit
            // More than an hour earlier than usual is rarely achievable in one
            // go: suggest moving 45 minutes toward it instead.
            if habit.timeIntervalSince(bedtime) > 3600 {
                let step = habit.addingTimeInterval(-45 * 60)
                realistic = step
                realisticShare = min(wake.timeIntervalSince(step) / 3600 * efficiency / need.total, 1)
            }
        }

        // Regularity: spread of recent bedtimes.
        let consistency = bedMinutes.count >= 5 ? Stats.standardDeviation(bedMinutes.map(Double.init)) : nil

        let options = [-30, 30].map { shift -> Option in
            let w = wake.addingTimeInterval(Double(shift) * 60)
            return Option(wake: w, bedtime: w.addingTimeInterval(-inBed * 3600))
        }

        return Plan(need: need, goal: goal, wake: wake, wakeSource: source, latencyMinutes: latency,
                    latencyIsPersonal: latencyIsPersonal, nightWakingMinutes: nightWaking * 60, sleepTarget: target,
                    efficiency: efficiency, timeInBed: inBed, bedtime: bedtime,
                    windowStart: bedtime.addingTimeInterval(-15 * 60), windowEnd: bedtime.addingTimeInterval(15 * 60),
                    typicalBedtime: typicalBedtime, realisticBedtime: realistic, realisticShare: realisticShare,
                    consistencyMinutes: consistency, options: options)
    }

    /// Minutes after midnight. Evening-based puts 01:30 at 25:30 so bedtimes
    /// either side of midnight average sensibly.
    private static func minutesOfDay(_ date: Date, _ calendar: Calendar, eveningBased: Bool = false) -> Int {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        return eveningBased && minutes < 12 * 60 ? minutes + 24 * 60 : minutes
    }
}
