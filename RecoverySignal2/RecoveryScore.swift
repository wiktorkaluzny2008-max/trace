//
//  RecoveryScore.swift
//  RecoverySignal2
//
//  Recovery (0–100%). It is about deviation from YOUR normal, not
//  absolute values: each input is compared with a rolling 30-day personal
//  baseline, and the size of the deviation (in standard deviations) decides
//  the component's score.
//
//    HRV                     Φ(z)          — above your normal scores high
//    Resting heart rate      Φ(−z)         — below your normal scores high
//    Respiratory rate        e^(−z²/2)     — consistency: any drift scores lower
//    Sleep performance       asleep ÷ sleep need, capped at 100%
//
//  Φ is the normal distribution: a perfectly typical reading (z = 0) scores
//  50%, one standard deviation better scores 84%, two score 98%. So an average
//  day lands around 60–70% overall and 100% needs everything clearly better
//  than normal at once — a good night's sleep alone can't get you there.
//
//  Weights (renormalised over whichever inputs have data): HRV 50%, resting
//  HR 20%, sleep 20%, respiratory rate 10%. Bands: green ≥ 67,
//  yellow 34–66, red ≤ 33.
//

import Foundation
import SwiftUI

struct RecoveryScore {

    enum Band {
        case strong, moderate, strained

        var label: String {
            switch self {
            case .strong:   String(localized: "Recovered")
            case .moderate: String(localized: "Moderate")
            case .strained: String(localized: "Strained")
            }
        }

        /// Battery metaphor: full charge, part charge, running on empty.
        var glyph: Glyph {
            switch self {
            case .strong:   .batteryFull
            case .moderate: .batteryHalf
            case .strained: .batteryLow
            }
        }

        var color: Color {
            switch self {
            case .strong:   Theme.good
            case .moderate: Theme.warn
            case .strained: Theme.bad
            }
        }

        static func of(_ value: Int) -> Band {
            value >= 67 ? .strong : (value >= 34 ? .moderate : .strained)
        }
    }

    struct Driver: Identifiable {
        let id = UUID()
        let label: String
        let detail: String
        /// 0...1 — this component's own score.
        let fraction: Double
        /// Standard deviations from your normal, signed so positive is better.
        let deviation: Double?
        /// The raw reading this driver is based on, so two days can be diffed
        /// in real units (ms, bpm, hours) rather than just their scores.
        let rawValue: Double?
        let unit: String
    }

    let value: Int
    let band: Band
    let headline: String
    let drivers: [Driver]
    let sleepNeed: SleepNeedModel.Need?
    let sleepPerformance: Double?

    var progress: Double { Double(value) / 100 }

    // MARK: Tunables

    static let baselineDays = 30
    static let minimumBaseline = 7
    private static let hrvWeight = 0.50
    private static let rhrWeight = 0.20
    private static let sleepWeight = 0.20
    private static let respiratoryWeight = 0.10

    // MARK: Computation

    /// Pass at least a month of days; the last one is scored against the rest.
    /// `excluded` (sick/travel days, say) is left out of the baseline history
    /// so it can't skew what's "normal" — the excluded day can still be the
    /// one being scored, only its influence on other days' baseline is removed.
    static func compute(from days: [DailyMetrics], excluded: Set<Date> = []) -> RecoveryScore? {
        let sorted = days.sorted { $0.date < $1.date }
        guard let today = sorted.last else { return nil }
        let candidates = sorted.dropLast().filter { !excluded.contains(Calendar.current.startOfDay(for: $0.date)) }
        let history = Array(candidates.suffix(baselineDays))

        var components: [(score: Double, weight: Double)] = []
        var drivers: [Driver] = []

        if let hrv = today.hrvSDNN, let z = zScore(hrv, history.compactMap(\.hrvSDNN)) {
            let score = Stats.normalCDF(z)
            components.append((score, hrvWeight))
            drivers.append(Driver(label: String(localized: "HRV"), detail: String(localized: "\(Int(hrv.rounded())) ms · \(describe(z))"),
                                  fraction: score, deviation: z, rawValue: hrv, unit: String(localized: "ms")))
        }

        if let rhr = today.restingHeartRate, let z = zScore(rhr, history.compactMap(\.restingHeartRate)) {
            let score = Stats.normalCDF(-z)
            components.append((score, rhrWeight))
            drivers.append(Driver(label: String(localized: "Resting HR"), detail: String(localized: "\(Int(rhr.rounded())) bpm · \(describe(-z))"),
                                  fraction: score, deviation: -z, rawValue: rhr, unit: String(localized: "bpm")))
        }

        var need: SleepNeedModel.Need?
        var performance: Double?
        if let asleep = today.sleepAsleepHours, asleep > 0 {
            let n = SleepNeedModel.need(forNightEnding: today.date, days: sorted)
            let p = SleepNeedModel.performance(asleep: asleep, need: n)
            need = n
            performance = p
            components.append((p, sleepWeight))
            drivers.append(Driver(label: String(localized: "Sleep"), detail: String(localized: "\(Int((p * 100).rounded()))% of \(hoursText(n.total)) need"),
                                  fraction: p, deviation: nil, rawValue: asleep, unit: String(localized: "h")))
        }

        if let rate = today.respiratoryRate, let z = zScore(rate, history.compactMap(\.respiratoryRate)) {
            let score = exp(-z * z / 2)
            components.append((score, respiratoryWeight))
            drivers.append(Driver(label: String(localized: "Breathing"), detail: String(localized: "\(rate.formatted(.number.precision(.fractionLength(1)))) /min · \(abs(z) < 1 ? String(localized: "steady") : String(localized: "off your normal"))"),
                                  fraction: score, deviation: -abs(z), rawValue: rate, unit: String(localized: "/min")))
        }

        // Without HRV there's too little signal to call recovery.
        guard components.count >= 2, drivers.contains(where: { $0.label == "HRV" }) else { return nil }

        let totalWeight = components.reduce(0) { $0 + $1.weight }
        let weighted = components.reduce(0) { $0 + $1.score * $1.weight } / totalWeight
        let value = min(max(Int((weighted * 100).rounded()), 1), 100)
        let band = Band.of(value)

        return RecoveryScore(value: value, band: band,
                             headline: headline(for: band, drivers: drivers),
                             drivers: drivers, sleepNeed: need, sleepPerformance: performance)
    }

    // MARK: Helpers

    /// Standard deviations from the personal baseline. The spread has a floor
    /// (4% of the mean) so an unusually steady fortnight can't make tiny
    /// wobbles look dramatic.
    private static func zScore(_ value: Double, _ baseline: [Double]) -> Double? {
        guard baseline.count >= minimumBaseline, let mean = Stats.mean(baseline), mean != 0 else { return nil }
        let sd = max(Stats.standardDeviation(baseline) ?? 0, abs(mean) * 0.04)
        return (value - mean) / sd
    }

    private static func describe(_ z: Double) -> String {
        switch z {
        case 1...:     String(localized: "well above your normal")
        case 0.4..<1:  String(localized: "above your normal")
        case -0.4..<0.4: String(localized: "at your normal")
        case -1 ..< -0.4: String(localized: "below your normal")
        default:       String(localized: "well below your normal")
        }
    }

    private static func headline(for band: Band, drivers: [Driver]) -> String {
        let base: String
        switch band {
        case .strong:   base = String(localized: "Your body is primed — a good day to take on strain.")
        case .moderate: base = String(localized: "Maintaining. Train normally, but don't chase a personal best.")
        case .strained: base = String(localized: "Your body is under-recovered. Favour rest and easy movement today.")
        }
        guard let weakest = drivers.min(by: { $0.fraction < $1.fraction }), weakest.fraction < 0.4 else { return base }
        return String(localized: "\(base) \(weakest.label) is what's holding it back.")
    }

    private static func hoursText(_ hours: Double) -> String {
        let total = Int((hours * 60).rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }
}
