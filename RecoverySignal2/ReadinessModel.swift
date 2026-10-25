//
//  ReadinessModel.swift
//  RecoverySignal2
//
//  Fatigue analytics that go past a single recovery number:
//   • HRV coefficient of variation — catches destabilising autonomic control
//     even when the mean looks fine (Plews et al.).
//   • A composite fatigue z-score built only from your own rolling baseline.
//   • Cumulative sleep debt over a trailing window.
//
//  CAVEAT ON HRV: the literature on CV uses ln(rMSSD). Apple Watch publishes
//  SDNN, a different (correlated but not interchangeable) measure. The method
//  transfers; the published thresholds do not, so this compares your CV to
//  your own baseline instead of quoting absolute cut-offs.
//

import Foundation

enum ReadinessModel {

    // MARK: - HRV coefficient of variation

    struct HRVStability {
        let currentCV: Double     // %
        let baselineCV: Double    // %
        let meanHRV: Double
        var isDestabilising: Bool { currentCV > baselineCV * 1.25 }
    }

    static func hrvStability(from days: [DailyMetrics]) -> HRVStability? {
        let sorted = days.sorted { $0.date < $1.date }
        let series = sorted.compactMap(\.hrvSDNN).filter { $0 > 0 }
        guard series.count >= 14 else { return nil }

        // Work in log space: HRV is right-skewed, and log-transforming is
        // standard practice before taking a CV.
        let logs = series.map { log($0) }
        guard let current = cv(Array(logs.suffix(7))) else { return nil }

        // Baseline = the typical 7-day CV across the last month.
        var rollingCVs: [Double] = []
        let window = 7
        if logs.count > window {
            for end in window...(logs.count) {
                let slice = Array(logs[(end - window)..<end])
                if let value = cv(slice) { rollingCVs.append(value) }
            }
        }
        guard let baseline = Stats.mean(rollingCVs), baseline > 0,
              let meanHRV = Stats.mean(Array(series.suffix(7))) else { return nil }

        return HRVStability(currentCV: current, baselineCV: baseline, meanHRV: meanHRV)
    }

    private static func cv(_ values: [Double]) -> Double? {
        guard let m = Stats.mean(values), m != 0,
              let sd = Stats.standardDeviation(values) else { return nil }
        return abs(sd / m) * 100
    }

    // MARK: - Sleep debt

    struct SleepDebt {
        let hours: Double
        let nights: Int
        let target: Double
    }

    /// Cumulative shortfall against a target, with a night of oversleep able to
    /// pay back at most an hour (you can't bank sleep indefinitely).
    static func sleepDebt(from days: [DailyMetrics], target: Double = 8.0, window: Int = 14) -> SleepDebt? {
        let sorted = days.sorted { $0.date < $1.date }
        let nights = sorted.suffix(window).compactMap(\.sleepAsleepHours)
        guard nights.count >= 4 else { return nil }

        let debt = nights.reduce(0.0) { running, actual in
            let delta = target - actual
            return running + (delta >= 0 ? delta : max(delta, -1.0))
        }
        return SleepDebt(hours: max(0, debt), nights: nights.count, target: target)
    }

    // MARK: - Composite fatigue

    struct Fatigue {
        let composite: Double          // normalized; negative = more fatigued
        let components: [Component]
        let consecutiveStrainedDays: Int

        struct Component: Identifiable {
            let id = UUID()
            let label: String
            let z: Double              // already sign-corrected: negative = bad
        }

        var isStrained: Bool { composite <= -1.5 }
    }

    /// z(HRV) − z(RHR) − z(sleep debt) − z(ACWR), each against a trailing
    /// baseline of your own data, then scaled by √n so the composite stays
    /// roughly unit-variance regardless of how many inputs were available.
    static func fatigue(from days: [DailyMetrics], baselineWindow: Int = 42) -> Fatigue? {
        let sorted = days.sorted { $0.date < $1.date }
        guard sorted.count >= 14 else { return nil }

        let composites = dailyComposites(sorted, baselineWindow: baselineWindow)
        guard let latest = composites.last, let value = latest.value else { return nil }

        var streak = 0
        for entry in composites.reversed() {
            guard let v = entry.value, v <= -1.5 else { break }
            streak += 1
        }

        return Fatigue(composite: value, components: latest.components, consecutiveStrainedDays: streak)
    }

    private static func dailyComposites(
        _ sorted: [DailyMetrics],
        baselineWindow: Int
    ) -> [(value: Double?, components: [Fatigue.Component])] {

        var out: [(Double?, [Fatigue.Component])] = []

        for index in sorted.indices {
            let history = Array(sorted[..<index].suffix(baselineWindow))
            guard history.count >= 10 else { out.append((nil, [])); continue }

            var zs: [Fatigue.Component] = []

            if let hrv = sorted[index].hrvSDNN,
               let z = Stats.zScore(hrv, in: history.compactMap(\.hrvSDNN)) {
                zs.append(.init(label: String(localized: "HRV"), z: z))
            }
            if let rhr = sorted[index].restingHeartRate,
               let z = Stats.zScore(rhr, in: history.compactMap(\.restingHeartRate)) {
                zs.append(.init(label: String(localized: "Resting HR"), z: -z))
            }
            if let sleep = sorted[index].sleepAsleepHours,
               let z = Stats.zScore(sleep, in: history.compactMap(\.sleepAsleepHours)) {
                // Short sleep is the fatigue signal, so the z passes through as-is.
                zs.append(.init(label: String(localized: "Sleep"), z: z))
            }
            let loadHistory = history.map { $0.trainingLoad ?? 0 }
            if let z = Stats.zScore(sorted[index].trainingLoad ?? 0, in: loadHistory) {
                zs.append(.init(label: String(localized: "Load"), z: -z))
            }

            guard !zs.isEmpty else { out.append((nil, [])); continue }
            let sum = zs.reduce(0) { $0 + $1.z }
            out.append((sum / Double(zs.count).squareRoot(), zs))
        }

        return out
    }
}
