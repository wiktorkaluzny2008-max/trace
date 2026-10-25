//
//  LagCorrelation.swift
//  RecoverySignal2
//
//  Mines your own history for lagged relationships: does protein on Monday
//  predict HRV on Tuesday? Uses Spearman (rank) correlation so a single
//  outlier day can't manufacture a finding.
//
//  THIS IS EXPLORATORY, AND THE UI SAYS SO. Three reasons to distrust any
//  single result here:
//   1. Correlation isn't causation — hard training days move intake, sleep and
//      HRV together, so confounding is the rule rather than the exception.
//   2. Many combinations are tested at once, so some will clear any threshold
//      by chance. Findings are Benjamini-Hochberg corrected to limit that, but
//      correction reduces false positives, it doesn't eliminate them.
//   3. n is small. A relationship needs months of data before it means much.
//

import Foundation

struct LagFinding: Identifiable {
    let id = UUID()
    let inputLabel: String
    let outputLabel: String
    let lagDays: Int
    let correlation: Double
    let sampleSize: Int
    let pValue: Double

    var isPositive: Bool { correlation > 0 }

    var strength: String {
        switch abs(correlation) {
        case 0.5...:  "strong"
        case 0.35...: "moderate"
        default:      "weak"
        }
    }

    var sentence: String {
        let direction = isPositive ? "higher" : "lower"
        let lagText = lagDays == 1 ? "next-day" : String(localized: "\(lagDays)-day-later")
        return String(localized: "Higher \(inputLabel.lowercased()) tends to precede \(direction) \(lagText) \(outputLabel.lowercased()).")
    }
}

enum LagCorrelationMiner {

    private struct Series {
        let label: String
        let values: [Double?]
    }

    /// Minimum paired observations before a combination is even considered.
    private static let minimumPairs = 21

    /// `tags` excludes sick/travel days from every series (illness or travel
    /// disrupts everything at once, which would otherwise show up as a false
    /// "finding" linking whatever changed together) and adds alcohol/late-meal
    /// as their own 0/1 input series, so a habit's actual effect on your own
    /// history can be checked rather than just asserted.
    static func mine(from days: [DailyMetrics], tags: [DayTag] = [], maxLag: Int = 3) -> [LagFinding] {
        let sorted = days.sorted { $0.date < $1.date }
        guard sorted.count >= minimumPairs + maxLag else { return [] }

        let excluded = DayTagStore.excludedDates(tags)
        func maskExcluded(_ values: [Double?]) -> [Double?] {
            zip(sorted, values).map { day, value in excluded.contains(Calendar.current.startOfDay(for: day.date)) ? nil : value }
        }
        func indicator(_ kind: DayTagKind) -> [Double?] {
            let onDates = DayTagStore.dates(tags, with: kind)
            return maskExcluded(sorted.map { onDates.contains(Calendar.current.startOfDay(for: $0.date)) ? 1.0 : 0.0 })
        }

        var inputs: [Series] = [
            Series(label: String(localized: "Protein"), values: maskExcluded(sorted.map(\.proteinGrams))),
            Series(label: String(localized: "Carbs"), values: maskExcluded(sorted.map(\.carbsGrams))),
            Series(label: String(localized: "Calories"), values: maskExcluded(sorted.map(\.dietaryEnergyKcal))),
            Series(label: String(localized: "Sleep"), values: maskExcluded(sorted.map(\.sleepAsleepHours))),
            Series(label: String(localized: "Training load"), values: maskExcluded(sorted.map { $0.trainingLoad })),
            Series(label: String(localized: "Steps"), values: maskExcluded(sorted.map(\.steps))),
            Series(label: String(localized: "Late caffeine"), values: maskExcluded(sorted.map(\.lateCaffeineMg)))
        ]
        if !DayTagStore.dates(tags, with: .alcohol).isEmpty {
            inputs.append(Series(label: String(localized: "Alcohol"), values: indicator(.alcohol)))
        }
        if !DayTagStore.dates(tags, with: .lateMeal).isEmpty {
            inputs.append(Series(label: String(localized: "Late meal"), values: indicator(.lateMeal)))
        }

        let outputs: [Series] = [
            Series(label: String(localized: "HRV"), values: maskExcluded(sorted.map(\.hrvSDNN))),
            Series(label: String(localized: "Resting HR"), values: maskExcluded(sorted.map(\.restingHeartRate))),
            Series(label: String(localized: "Sleep quality"), values: maskExcluded(sorted.map(\.sleepDeepHours)))
        ]

        var candidates: [LagFinding] = []

        for input in inputs {
            for output in outputs {
                // Skip pairing a series against itself at a lag.
                if input.label == output.label { continue }

                for lag in 1...maxLag {
                    guard let finding = correlate(input: input, output: output, lag: lag) else { continue }
                    candidates.append(finding)
                }
            }
        }

        return benjaminiHochberg(candidates, falseDiscoveryRate: 0.10)
    }

    private static func correlate(input: Series, output: Series, lag: Int) -> LagFinding? {
        var x: [Double] = []
        var y: [Double] = []

        for index in 0..<(input.values.count - lag) {
            guard let inputValue = input.values[index],
                  let outputValue = output.values[index + lag] else { continue }
            x.append(inputValue)
            y.append(outputValue)
        }

        guard x.count >= minimumPairs,
              let r = Stats.spearman(x, y),
              let p = Stats.correlationPValue(r: r, n: x.count),
              abs(r) >= 0.3 else { return nil }

        return LagFinding(
            inputLabel: input.label,
            outputLabel: output.label,
            lagDays: lag,
            correlation: r,
            sampleSize: x.count,
            pValue: p
        )
    }

    /// Controls the false discovery rate across the whole set of tests rather
    /// than letting each one clear p < 0.05 on its own.
    private static func benjaminiHochberg(_ findings: [LagFinding], falseDiscoveryRate: Double) -> [LagFinding] {
        guard !findings.isEmpty else { return [] }
        let sorted = findings.sorted { $0.pValue < $1.pValue }
        let m = Double(sorted.count)

        var cutoffIndex = -1
        for (i, finding) in sorted.enumerated() {
            let threshold = (Double(i + 1) / m) * falseDiscoveryRate
            if finding.pValue <= threshold { cutoffIndex = i }
        }
        guard cutoffIndex >= 0 else { return [] }

        return Array(sorted.prefix(cutoffIndex + 1))
            .sorted { abs($0.correlation) > abs($1.correlation) }
    }
}
