//
//  RecoveryDetailView.swift
//  RecoverySignal2
//
//  Recovery in depth: score history coloured by band, and HRV / resting heart
//  rate drawn against your own personal normal range (baseline ± 1 SD), so an
//  off day stands out as leaving the band rather than as an abstract number.
//

import SwiftUI
import SwiftData
import Charts

struct RecoveryDetailView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @Query private var tags: [DayTag]
    @Query(sort: \WorkoutLog.start, order: .reverse) private var workoutLogs: [WorkoutLog]
    @State private var range: DetailRange = .month

    private var excludedDates: Set<Date> { DayTagStore.excludedDates(tags) }

    /// Today's score, or the most recent day that has one (early in the
    /// morning today's HRV may not have synced yet).
    private var latestScore: (date: Date, score: RecoveryScore)? {
        scoreOnOrBefore(index: allDays.count - 1)
    }

    /// The score for the most recent day *before* the given index — used to
    /// show what changed since last time.
    private var previousScore: (date: Date, score: RecoveryScore)? {
        guard let latest = latestScore else { return nil }
        let sorted = allDays.sorted { $0.date < $1.date }
        guard let latestIndex = sorted.firstIndex(where: { $0.date == latest.date }) else { return nil }
        return scoreOnOrBefore(index: latestIndex - 1)
    }

    private func scoreOnOrBefore(index startIndex: Int) -> (date: Date, score: RecoveryScore)? {
        let sorted = allDays.sorted { $0.date < $1.date }
        guard sorted.indices.contains(startIndex) else { return nil }
        for index in stride(from: startIndex, through: 0, by: -1) {
            let window = Array(sorted[max(0, index - RecoveryScore.baselineDays)...index])
            if let score = RecoveryScore.compute(from: window, excluded: excludedDates),
               sorted[index].hrvSDNN != nil || sorted[index].sleepAsleepHours != nil {
                return (sorted[index].date, score)
            }
        }
        return nil
    }

    var body: some View {
        DetailPage(title: String(localized: "Recovery")) {
            hero
            scoreChangeCard
            stillLoadedCard
            ChartCard(title: String(localized: "How recovery is calculated")) {
                HowItWorks(explainer: .recovery)
            }
            RangePicker(range: $range)
            scoreHistoryCard
            strainCard
            baselineCard(title: String(localized: "Heart rate variability"), unit: "ms", higherIsBetter: true, value: \.hrvSDNN,
                         subtitle: String(localized: "Shaded band is your normal range (4-week average ± 1 SD). Dropping below it is the clearest early sign of fatigue."))
            baselineCard(title: String(localized: "Resting heart rate"), unit: "bpm", higherIsBetter: false, value: \.restingHeartRate,
                         subtitle: String(localized: "Rising above your band often shows up a day or two before you feel run down."))
            baselineCard(title: String(localized: "Breathing rate"), unit: "/min", higherIsBetter: nil, value: \.respiratoryRate,
                         subtitle: String(localized: "Measured overnight. It's normally very steady, so a jump out of your band is worth noticing — it can come before illness."))
            stats
        }
    }

    // MARK: Hero

    private var hero: some View {
        let latest = latestScore
        let score = latest?.score
        let color = score?.band.color ?? Theme.accent
        let isToday = latest.map { Calendar.current.isDateInToday($0.date) } ?? true
        let eyebrow = isToday ? "Recovery today"
            : "Recovery · \(latest!.date.formatted(.dateTime.weekday(.wide)))"
        return DetailHero(
            glyph: .recovery,
            eyebrow: eyebrow,
            value: score.map { "\($0.value)" } ?? "—",
            unit: score.map { $0.band.label } ?? "",
            caption: score?.headline ?? "Needs a few days of HRV, heart rate and sleep.",
            colors: [color.opacity(0.95), color.opacity(0.65)]
        ) {
            if let score {
                ScoreRing(progress: score.progress, color: color)
                    .frame(width: 76, height: 76)
            }
        }
    }

    // MARK: Why did it change

    private var scoreChangeCard: some View {
        Group {
            if let latest = latestScore, let previous = previousScore, Calendar.current.isDateInToday(latest.date) {
                let diff = latest.score.value - previous.score.value
                ChartCard(title: String(localized: "Why did it change?"),
                          subtitle: previous.date.formatted(.relative(presentation: .named)) == "yesterday"
                              ? String(localized: "Since yesterday")
                              : String(localized: "Since \(previous.date.formatted(.dateTime.weekday(.wide)))")) {
                    HStack(spacing: 8) {
                        Image(systemName: diff == 0 ? "equal.circle.fill" : (diff > 0 ? "arrow.up.circle.fill" : "arrow.down.circle.fill"))
                            .font(.system(size: 20))
                            .foregroundStyle(diff == 0 ? Theme.textTertiary : (diff > 0 ? Theme.good : Theme.bad))
                        Text(diff == 0 ? String(localized: "Unchanged at \(latest.score.value)")
                             : String(localized: "\(diff > 0 ? "Up" : "Down") \(abs(diff)) to \(latest.score.value)"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    VStack(spacing: 8) {
                        ForEach(latest.score.drivers) { driver in
                            if let previousDriver = previous.score.drivers.first(where: { $0.label == driver.label }) {
                                driverDeltaRow(driver, previousDriver)
                            }
                        }
                    }
                    if latest.score.drivers.contains(where: { d in !previous.score.drivers.contains { $0.label == d.label } })
                        || previous.score.drivers.contains(where: { d in !latest.score.drivers.contains { $0.label == d.label } }) {
                        Text("Some inputs are only present on one of the two days, so they're left out above.")
                            .font(.caption2).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }

    private func driverDeltaRow(_ today: RecoveryScore.Driver, _ yesterday: RecoveryScore.Driver) -> some View {
        let delta: Double? = {
            guard let a = today.rawValue, let b = yesterday.rawValue else { return nil }
            return a - b
        }()
        let better = today.fraction > yesterday.fraction + 0.03
        let worse = today.fraction < yesterday.fraction - 0.03
        return HStack {
            Text(LocalizedStringKey(today.label)).font(.subheadline).foregroundStyle(Theme.textPrimary)
            Spacer()
            if let delta {
                Text(deltaText(delta, unit: today.unit))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(worse ? Theme.bad : (better ? Theme.good : Theme.textSecondary))
            } else {
                Text("—").font(.subheadline).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func deltaText(_ delta: Double, unit: String) -> String {
        let sign = delta > 0 ? "+" : (delta < 0 ? "−" : "")
        if unit == String(localized: "h") {
            let totalMinutes = Int((abs(delta) * 60).rounded())
            return totalMinutes == 0 ? String(localized: "no change")
                : "\(sign)\(totalMinutes / 60)h \(String(format: "%02d", totalMinutes % 60))m"
        }
        let rounded = Int(abs(delta).rounded())
        return rounded == 0 ? String(localized: "no change") : "\(sign)\(rounded) \(unit)"
    }

    // MARK: Still loaded

    private var stillLoadedCard: some View {
        let statuses = MuscleFatigueModel.stillLoaded(logs: workoutLogs)
        return Group {
            if !statuses.isEmpty {
                ChartCard(title: String(localized: "Still loaded"),
                          subtitle: String(localized: "A rough estimate from your logged sets — not a measurement. HRV-based recovery doesn't see local muscle fatigue, so a heavy leg day can leave your legs under-recovered even when your overall score looks fine.")) {
                    VStack(spacing: 8) {
                        ForEach(statuses.prefix(3)) { status in
                            HStack {
                                Text(LocalizedStringKey(status.muscle.name)).font(.subheadline).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(status.daysAgo == 0 ? String(localized: "Trained today")
                                     : (status.daysAgo == 1 ? String(localized: "Trained yesterday") : String(localized: "Trained \(status.daysAgo) days ago")))
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                                Capsule().fill(Theme.warn.opacity(0.15 + status.load * 0.5)).frame(width: 34, height: 6)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Score history

    private struct ScorePoint: Identifiable {
        let id = UUID()
        let date: Date
        let score: RecoveryScore
    }

    private var scoreHistory: [ScorePoint] {
        let sorted = allDays.sorted { $0.date < $1.date }
        let start = max(sorted.count - range.rawValue, 0)
        return (start..<sorted.count).compactMap { index in
            let window = Array(sorted[max(0, index - RecoveryScore.baselineDays)...index])
            return RecoveryScore.compute(from: window, excluded: excludedDates).map { ScorePoint(date: sorted[index].date, score: $0) }
        }
    }

    private var scoreHistoryCard: some View {
        let history = scoreHistory
        return ChartCard(title: String(localized: "Recovery score"), subtitle: String(localized: "Green 67–100 recovered · yellow 34–66 · red 0–33.")) {
            Chart {
                RectangleMark(yStart: .value("Low", 67), yEnd: .value("High", 100))
                    .foregroundStyle(Theme.good.opacity(0.06))
                ForEach(history) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("Score", point.score.value))
                        .foregroundStyle(point.score.band.color.gradient)
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Recovered", 67))
                    .foregroundStyle(Theme.good.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                RuleMark(y: .value("Moderate", 34))
                    .foregroundStyle(Theme.warn.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            .chartYScale(domain: 0...100)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 34, 67, 100]) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 200)

            if !history.isEmpty {
                let counts = Dictionary(grouping: history, by: { $0.score.band.label }).mapValues(\.count)
                HStack(spacing: 14) {
                    bandCount(String(localized: "Recovered"), counts["Recovered"] ?? 0, Theme.good)
                    bandCount(String(localized: "Moderate"), counts["Moderate"] ?? 0, Theme.warn)
                    bandCount(String(localized: "Strained"), counts["Strained"] ?? 0, Theme.bad)
                }
            }
        }
    }

    private func bandCount(_ label: String, _ count: Int, _ color: Color) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text("\(count)").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    // MARK: Strain

    private var strainCard: some View {
        let days = allDays.last(range).filter { $0.strain != nil }
        let average = Stats.mean(days.compactMap(\.strain))
        return ChartCard(title: String(localized: "Day strain"),
                         subtitle: average.map { "Average \(DetailFormat.decimal($0)) over \(range.rawValue) days on a 0–21 scale." }) {
            if days.isEmpty {
                Text("Strain needs heart-rate data from your Watch through the day.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            } else {
                Chart {
                    ForEach(days, id: \.date) { day in
                        let strain = day.strain ?? 0
                        BarMark(x: .value("Day", day.date, unit: .day), y: .value("Strain", strain))
                            .foregroundStyle(strainColor(strain).gradient)
                            .cornerRadius(3)
                    }
                }
                .chartYScale(domain: 0...21)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: [0, 10, 14, 18, 21]) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 170)
            }
            HowItWorks(explainer: .strain)
        }
    }

    private func strainColor(_ strain: Double) -> Color {
        switch StrainModel.Level(strain) {
        case .light:    Theme.mint
        case .moderate: Theme.accent
        case .high:     Theme.accentDeep
        case .allOut:   Theme.fat
        }
    }

    // MARK: Baseline charts

    private struct BandPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double?
        let low: Double?
        let mean: Double?
        let high: Double?
        /// Trailing 7-day average of the readings, needs at least 3 of them.
        let average: Double?
    }

    private func bandPoints(_ keyPath: KeyPath<DailyMetrics, Double?>) -> [BandPoint] {
        let sorted = allDays.sorted { $0.date < $1.date }
        let start = max(sorted.count - range.rawValue, 0)
        return (start..<sorted.count).map { index in
            let history = sorted[max(0, index - 28)..<index].compactMap { $0[keyPath: keyPath] }
            let mean = history.count >= 5 ? Stats.mean(history) : nil
            let sd = history.count >= 5 ? Stats.standardDeviation(history) : nil
            let week = sorted[max(0, index - 6)...index].compactMap { $0[keyPath: keyPath] }
            return BandPoint(date: sorted[index].date, value: sorted[index][keyPath: keyPath],
                             low: mean.flatMap { m in sd.map { m - $0 } }, mean: mean,
                             high: mean.flatMap { m in sd.map { m + $0 } },
                             average: week.count >= 3 ? Stats.mean(week) : nil)
        }
    }

    private func baselineCard(title: String, unit: String, higherIsBetter: Bool?,
                              value keyPath: KeyPath<DailyMetrics, Double?>, subtitle: String) -> some View {
        let points = bandPoints(keyPath)
        let latest = points.last(where: { $0.value != nil })
        let status: (String, Color)? = {
            guard let latest, let v = latest.value, let low = latest.low, let high = latest.high else { return nil }
            guard let higherIsBetter else {
                return (v < low || v > high) ? ("Outside your normal", Theme.warn) : ("Within your normal", Theme.textSecondary)
            }
            if v < low { return (higherIsBetter ? "Below your normal" : "Better than normal", higherIsBetter ? Theme.bad : Theme.good) }
            if v > high { return (higherIsBetter ? "Above your normal" : "Above your normal", higherIsBetter ? Theme.good : Theme.bad) }
            return ("Within your normal", Theme.textSecondary)
        }()

        return ChartCard(title: title, subtitle: subtitle) {
            if let latest, let v = latest.value {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DetailFormat.whole(v)).font(.system(size: 30, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                    Text(LocalizedStringKey(unit)).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if let status {
                        Text(LocalizedStringKey(status.0))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(status.1)
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(status.1.opacity(0.12), in: Capsule())
                    }
                }
            }

            let values = points.compactMap(\.value) + points.compactMap(\.low) + points.compactMap(\.high)
            let lo = (values.min() ?? 0), hi = (values.max() ?? 1)
            let pad = max((hi - lo) * 0.15, 1)

            // Daily readings are noisy, so they're drawn as dots and never joined up.
            // The signal is the 7-day average against your shaded normal range.
            Chart {
                ForEach(points.filter { $0.low != nil }) { p in
                    AreaMark(x: .value("Day", p.date, unit: .day),
                             yStart: .value("Low", p.low ?? 0),
                             yEnd: .value("High", p.high ?? 0),
                             series: .value("Series", "Normal"))
                        .foregroundStyle(Theme.accent.opacity(0.12))
                        .interpolationMethod(.linear)
                }
                ForEach(points.filter { $0.value != nil }) { p in
                    PointMark(x: .value("Day", p.date, unit: .day), y: .value(title, p.value ?? 0))
                        .foregroundStyle(pointColor(p, higherIsBetter: higherIsBetter).opacity(0.55))
                        .symbolSize(range.rawValue > 30 ? 12 : 22)
                }
                ForEach(points.filter { $0.average != nil }) { p in
                    LineMark(x: .value("Day", p.date, unit: .day), y: .value("7-day average", p.average ?? 0),
                             series: .value("Series", "Average"))
                        .foregroundStyle(Theme.accentDeep)
                        .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.catmullRom)
                }
            }
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 190)

            HStack(spacing: 14) {
                ChartLegendKey(kind: .dot, color: Theme.accent.opacity(0.55), label: "Daily reading")
                ChartLegendKey(kind: .line, color: Theme.accentDeep, label: "7-day average")
                ChartLegendKey(kind: .band, color: Theme.accent.opacity(0.2), label: "Your normal range")
            }
        }
    }

    /// Points outside the personal band take a status colour.
    private func pointColor(_ p: BandPoint, higherIsBetter: Bool?) -> Color {
        guard let v = p.value, let low = p.low, let high = p.high else { return Theme.accent }
        guard let higherIsBetter else { return (v < low || v > high) ? Theme.warn : Theme.accent }
        if v < low { return higherIsBetter ? Theme.bad : Theme.good }
        if v > high { return higherIsBetter ? Theme.good : Theme.bad }
        return Theme.accent
    }

    // MARK: Stats

    private var stats: some View {
        let days = allDays.last(range)
        let latestVO2 = allDays.last(where: { $0.vo2Max != nil })?.vo2Max
        return StatGrid(tiles: [
            StatTile(label: String(localized: "Average HRV"), value: Stats.mean(days.compactMap(\.hrvSDNN)).map { DetailFormat.whole($0) } ?? "—", unit: "ms", glyph: .hrv),
            StatTile(label: String(localized: "Average resting HR"), value: Stats.mean(days.compactMap(\.restingHeartRate)).map { DetailFormat.whole($0) } ?? "—", unit: "bpm", glyph: .heartRate),
            StatTile(label: String(localized: "Blood oxygen"), value: Stats.mean(days.compactMap(\.oxygenSaturation)).map { DetailFormat.decimal($0 * 100) } ?? "—", unit: "%",
                     caption: String(localized: "95–100% is typical"), glyph: .oxygen),
            StatTile(label: String(localized: "VO₂ max"), value: latestVO2.map { DetailFormat.decimal($0) } ?? "—", unit: "ml/kg/min",
                     caption: String(localized: "Latest Watch estimate"), glyph: .lungs)
        ])
    }
}
