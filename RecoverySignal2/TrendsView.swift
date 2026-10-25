//
//  TrendsView.swift
//  RecoverySignal2
//
//  The history of each metric, one chart at a time. Every card has its own
//  range switch, and each metric uses the chart type that suits it — see the
//  header of Charts/TrendCharts.swift for the reasoning.
//

import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @AppStorage(DeviceProfile.heartKey) private var tracksHeart = true
    @AppStorage(DeviceProfile.sleepKey) private var tracksSleep = true

    var body: some View {
        // Derived series are computed once per data change, not per chart
        // interaction — touching a chart only redraws that chart.
        let recovery = recoverySeries
        let targets = EnergyModel.maintenance(from: allDays).map { EnergyModel.targets(from: allDays, maintenance: $0) }

        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if tracksHeart {
                        SectionLabel(text: "Recovery", icon: .recovery)
                            .id("Recovery")

                        TrendCard(title: String(localized: "Recovery"), glyph: .recovery, explainer: .recovery,
                                  note: String(localized: "Bars coloured by zone: green 67+, yellow 34–66, red 33 and under."),
                                  style: ValueStyle(unit: "%"), daily: recovery, higherIsBetter: true,
                                  defaultRange: .month) { range in
                            BarTrendChart(history: recovery, range: range, style: ValueStyle(unit: "%"),
                                          barColor: { RecoveryScore.Band.of(Int($0.rounded())).color },
                                          ceiling: 100, guides: [34, 67])
                        }

                        baselineCard("HRV", glyph: .hrv, unit: "ms", higherIsBetter: true, \.hrvSDNN,
                                     note: String(localized: "Judge HRV by the 7-day line against your shaded normal range, not by single days — one low reading means little."),
                                     explainer: .hrv)
                        baselineCard("Resting heart rate", glyph: .heartRate, unit: "bpm", higherIsBetter: false, \.restingHeartRate,
                                     note: String(localized: "A 7-day line creeping above your normal range often means fatigue, illness or poor sleep."),
                                     explainer: .restingHeartRate)
                        baselineCard("Breathing rate", glyph: .lungs, unit: "/min", decimals: 1, higherIsBetter: nil, \.respiratoryRate,
                                     note: String(localized: "Usually very stable. A clear rise out of your normal range is an early sign of illness."),
                                     explainer: .breathingRate)

                        let vo2 = points(\.vo2Max)
                        if !vo2.isEmpty {
                            TrendCard(title: String(localized: "VO₂ max"), glyph: .lungs, explainer: .vo2Max,
                                      note: String(localized: "The Watch estimates this after outdoor walks, runs and hikes, so readings are sparse."),
                                      style: ValueStyle(unit: "ml/kg/min", decimals: 1), daily: vo2, higherIsBetter: true,
                                      defaultRange: .year) { range in
                                SparseLineChart(history: vo2, range: range, style: ValueStyle(unit: "ml/kg/min", decimals: 1))
                            }
                        }

                        }
                        if tracksSleep {
                        SectionLabel(text: "Sleep", icon: .sleep)
                            .id("Sleep")
                            .padding(.top, 8)

                        let sleep = points(\.sleepAsleepHours)
                        TrendCard(title: String(localized: "Sleep"), glyph: .sleep, explainer: .sleepDuration,
                                  note: String(localized: "Time actually asleep each night. The grey bar on the left is your longer-term average — tap it to choose the period."),
                                  style: ValueStyle(unit: "h", decimals: 1, duration: true), daily: sleep, higherIsBetter: true,
                                  defaultRange: .twoWeeks) { range in
                            BarTrendChart(history: sleep, range: range, style: ValueStyle(unit: "h", decimals: 1, duration: true),
                                          color: Theme.accent, compare: true, compareStorageKey: "sleep")
                        }

                        }
                        SectionLabel(text: "Activity & training", icon: .activity)
                            .id("Activity & training")
                            .padding(.top, 8)

                        let steps = points(\.steps)
                        TrendCard(title: String(localized: "Steps"), glyph: .steps, explainer: .steps,
                                  note: String(localized: "Longer ranges show the average per day for each week or month."),
                                  style: ValueStyle(), daily: steps, higherIsBetter: true, defaultRange: .twoWeeks) { range in
                            BarTrendChart(history: steps, range: range, style: ValueStyle(), color: Theme.activity,
                                          compare: true, compareStorageKey: "steps")
                        }

                        let strain = points(\.strain)
                        // Strain comes from heart rate, so it's only shown with a heart-rate tracker.
                        if tracksHeart && !strain.isEmpty {
                            TrendCard(title: String(localized: "Day strain"), glyph: .trainingLoad, explainer: .strain,
                                      note: String(localized: "0–21 scale. Light under 10, moderate 10–13, high 14–17, all out 18+."),
                                      style: ValueStyle(decimals: 1), daily: strain, defaultRange: .month) { range in
                                BarTrendChart(history: strain, range: range, style: ValueStyle(decimals: 1),
                                              barColor: strainColor, ceiling: StrainModel.maximum, guides: [10, 14, 18])
                            }
                        }

                        MuscleVolumeSection()

                        let training = trainingStack
                        TrendCard(title: String(localized: "Training"), glyph: .training, explainer: .training,
                                  note: String(localized: "Minutes per day, split into strength and cardio. Rest days count as zero."),
                                  style: ValueStyle(unit: "min"), daily: points { $0.workoutMinutes ?? 0 }, defaultRange: .month) { range in
                            StackedBarTrendChart(history: training, range: range, style: ValueStyle(unit: "min"),
                                                 series: [("Strength", Theme.training), ("Cardio", Theme.activity)])
                        }

                        WorkoutHistoryCard()

                        SectionLabel(text: "Nutrition", icon: .nutrition)
                            .id("Nutrition")
                            .padding(.top, 8)

                        let calories = points(\.dietaryEnergyKcal)
                        TrendCard(title: String(localized: "Calories"), glyph: .energy, explainer: .calories,
                                  note: String(localized: "Logged intake. The green line is your calorie target for your goal."),
                                  style: ValueStyle(unit: "kcal"), daily: calories, defaultRange: .twoWeeks) { range in
                            BarTrendChart(history: calories, range: range, style: ValueStyle(unit: "kcal"),
                                          color: Theme.accent,
                                          target: targets.map { ($0.calories, "Target") })
                        }

                        let protein = points(\.proteinGrams)
                        TrendCard(title: String(localized: "Protein"), glyph: .protein, explainer: .protein,
                                  note: String(localized: "Bars that reach the green line hit your protein target."),
                                  style: ValueStyle(unit: "g"), daily: protein, higherIsBetter: true, defaultRange: .twoWeeks) { range in
                            BarTrendChart(history: protein, range: range, style: ValueStyle(unit: "g"), color: Theme.protein,
                                          target: targets.map { ($0.proteinGrams, "Target") })
                        }

                        SectionLabel(text: "Body", icon: .body)
                            .id("Body")
                            .padding(.top, 8)

                        let weight = points(\.bodyMassKg)
                        TrendCard(title: String(localized: "Body weight"), glyph: .body, explainer: .bodyWeight,
                                  note: String(localized: "Dots are scale readings; the line is trend weight, which smooths out day-to-day water swings."),
                                  style: ValueStyle(unit: "kg", decimals: 1), daily: weight, defaultRange: .quarter) { range in
                            TrendWeightChart(history: weight, range: range, style: ValueStyle(unit: "kg", decimals: 1))
                        }

                        let bodyFat = points(\.bodyFatPercent)
                        if !bodyFat.isEmpty {
                            TrendCard(title: String(localized: "Body fat"), glyph: .fat, explainer: .bodyFat,
                                      note: String(localized: "Smart-scale body fat is noisy; read the trend line, not single readings."),
                                      style: ValueStyle(unit: "%", decimals: 1), daily: bodyFat, higherIsBetter: false,
                                      defaultRange: .quarter) { range in
                                TrendWeightChart(history: bodyFat, range: range, style: ValueStyle(unit: "%", decimals: 1))
                            }

                            let composition = compositionStack
                            TrendCard(title: String(localized: "Lean vs fat mass"), glyph: .body, explainer: .compositionSplit,
                                      note: String(localized: "Each weigh-in with body fat, split into lean mass and fat mass."),
                                      style: ValueStyle(unit: "kg", decimals: 1), daily: points { d in d.bodyMassKg.flatMap { w in d.bodyFatPercent.map { w * (1 - $0 / 100) } } },
                                      defaultRange: .quarter) { range in
                                StackedBarTrendChart(history: composition, range: range, style: ValueStyle(unit: "kg", decimals: 1),
                                                     series: [("Lean mass", Theme.accent), ("Fat mass", Theme.warn)])
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    SectionJumpBar(sections: (tracksHeart ? ["Recovery"] : []) + (tracksSleep ? ["Sleep"] : []) + ["Activity & training", "Nutrition", "Body"], proxy: proxy)
                }
                .background(Theme.background.ignoresSafeArea())
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TabInfoButton() } }
            .navigationDestination(for: WorkoutLog.self) { WorkoutLogDetailView(log: $0) }
            .navigationDestination(for: HealthWorkout.self) { HealthWorkoutDetailView(workout: $0) }
            .navigationDestination(for: WorkoutHistoryRoute.self) { _ in WorkoutHistoryList() }
        }
    }

    private func baselineCard(_ title: String, glyph: Glyph, unit: String, decimals: Int = 0,
                              higherIsBetter: Bool?, _ keyPath: KeyPath<DailyMetrics, Double?>, note: String,
                              explainer: Explainer? = nil) -> some View {
        let series = points(keyPath)
        let style = ValueStyle(unit: unit, decimals: decimals)
        return TrendCard(title: title, glyph: glyph, explainer: explainer, note: note, style: style, daily: series,
                         higherIsBetter: higherIsBetter, defaultRange: .month) { range in
            BaselineLineChart(history: series, range: range, style: style)
        }
    }

    private func points(_ keyPath: KeyPath<DailyMetrics, Double?>) -> [TrendPoint] {
        allDays.compactMap { day in day[keyPath: keyPath].map { TrendPoint(date: day.date, value: $0) } }
    }

    private func points(_ value: (DailyMetrics) -> Double?) -> [TrendPoint] {
        allDays.compactMap { day in value(day).map { TrendPoint(date: day.date, value: $0) } }
    }

    /// Recovery for every day that has enough history behind it.
    private var recoverySeries: [TrendPoint] {
        allDays.indices.compactMap { i in
            let window = Array(allDays[max(0, i - RecoveryScore.baselineDays)...i])
            return RecoveryScore.compute(from: window).map { TrendPoint(date: allDays[i].date, value: Double($0.value)) }
        }
    }

    private var compositionStack: [StackedPoint] {
        allDays.flatMap { day -> [StackedPoint] in
            guard let weight = day.bodyMassKg, let fat = day.bodyFatPercent else { return [] }
            return [StackedPoint(date: day.date, series: "Lean mass", value: weight * (1 - fat / 100)),
                    StackedPoint(date: day.date, series: "Fat mass", value: weight * fat / 100)]
        }
    }

    private var trainingStack: [StackedPoint] {
        allDays.flatMap { day in
            [StackedPoint(date: day.date, series: "Strength", value: day.strengthMinutes ?? 0),
             StackedPoint(date: day.date, series: "Cardio", value: day.cardioMinutes ?? 0)]
        }
    }

    private func strainColor(_ value: Double) -> Color {
        switch StrainModel.Level(value) {
        case .light:    Theme.mint
        case .moderate: Theme.accent
        case .high:     Theme.accentDeep
        case .allOut:   Theme.fat
        }
    }
}

struct TrendPoint: Identifiable {
    // Daily series use their timestamp as identity, including after aggregation.
    var id: Date { date }
    let date: Date
    let value: Double
}

/// What, if anything, to draw over the raw daily points.
enum TrendFit {
    case none
    /// Least-squares straight line through the window — for rate of change.
    case linear
    /// Trailing mean over the previous `days` calendar days — for noisy metrics.
    case rollingAverage(days: Int)

    func fitted(_ points: [TrendPoint]) -> [TrendPoint] {
        guard points.count >= 3 else { return [] }
        switch self {
        case .none:
            return []

        case .linear:
            guard let first = points.first?.date else { return [] }
            let xs = points.map { $0.date.timeIntervalSince(first) / 86_400 }
            let ys = points.map(\.value)
            let n = Double(points.count)
            let meanX = xs.reduce(0, +) / n
            let meanY = ys.reduce(0, +) / n
            let sxx = xs.reduce(0) { $0 + ($1 - meanX) * ($1 - meanX) }
            guard sxx > 0 else { return [] }
            let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - meanX) * ($1.1 - meanY) }
            let slope = sxy / sxx
            let intercept = meanY - slope * meanX
            return [points.first!, points.last!].map { p in
                let x = p.date.timeIntervalSince(first) / 86_400
                return TrendPoint(date: p.date, value: intercept + slope * x)
            }

        case .rollingAverage(let days):
            return points.map { p in
                let windowStart = p.date.addingTimeInterval(-Double(days - 1) * 86_400)
                let window = points.filter { $0.date >= windowStart && $0.date <= p.date }.map(\.value)
                return TrendPoint(date: p.date, value: window.reduce(0, +) / Double(window.count))
            }
        }
    }

    /// Slope in units per week, for the linear fit's caption.
    func weeklySlope(_ fitted: [TrendPoint]) -> Double? {
        guard case .linear = self, let a = fitted.first, let b = fitted.last else { return nil }
        let days = b.date.timeIntervalSince(a.date) / 86_400
        guard days > 0 else { return nil }
        return (b.value - a.value) / days * 7
    }
}

#Preview {
    TrendsView()
        .modelContainer(for: [DailyMetrics.self, Insight.self, WeeklyNarrative.self], inMemory: true)
}
