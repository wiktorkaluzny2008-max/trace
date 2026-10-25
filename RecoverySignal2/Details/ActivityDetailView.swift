//
//  ActivityDetailView.swift
//  RecoverySignal2
//
//  Movement and training: steps against a daily goal, active energy,
//  strength-versus-cardio minutes, and recent sessions.
//

import SwiftUI
import SwiftData
import Charts

struct ActivityDetailView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @State private var range: DetailRange = .twoWeeks

    private let stepGoal = 10_000.0
    private var days: [DailyMetrics] { allDays.last(range) }
    private var today: DailyMetrics? { allDays.last }

    var body: some View {
        DetailPage(title: String(localized: "Activity")) {
            hero
            RangePicker(range: $range)
            stats
            stepsCard
            energyCard
            trainingCard
            sessionsCard
        }
    }

    private var hero: some View {
        let steps = today?.steps ?? 0
        return DetailHero(
            glyph: .steps,
            eyebrow: String(localized: "Steps today"),
            value: steps.formatted(.number.precision(.fractionLength(0))),
            caption: String(localized: "\(DetailFormat.whole(today?.activeEnergyBurned ?? 0)) kcal active · goal \(stepGoal.formatted(.number.precision(.fractionLength(0))))"),
            colors: [Theme.activityDeep, Theme.activity]
        ) {
            ZStack {
                Circle().stroke(Theme.track, lineWidth: 8)
                Circle()
                    .trim(from: 0, to: min(steps / stepGoal, 1))
                    .stroke(Theme.activity, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                RingValueText(text: "\(Int((steps / stepGoal * 100).rounded()))%", size: 18, color: Theme.textPrimary)
                    .padding(.horizontal, 8)
            }
            .frame(width: 76, height: 76)
        }
    }

    private var stats: some View {
        let steps = days.compactMap(\.steps)
        let goalDays = steps.filter { $0 >= stepGoal }.count
        return StatGrid(tiles: [
            StatTile(label: String(localized: "Average steps"), value: DetailFormat.whole(Stats.mean(steps) ?? 0),
                     caption: String(localized: "Goal hit \(goalDays) of \(steps.count) days"), glyph: .steps),
            StatTile(label: String(localized: "Active energy"), value: DetailFormat.whole(days.compactMap(\.activeEnergyBurned).reduce(0, +)), unit: "kcal",
                     caption: String(localized: "Total over \(range.rawValue) days"), glyph: .energy),
            StatTile(label: String(localized: "Sessions"), value: "\(days.reduce(0) { $0 + $1.workoutCount })", glyph: .training),
            StatTile(label: String(localized: "Training time"), value: DetailFormat.hoursMinutes(days.compactMap(\.workoutMinutes).reduce(0, +) / 60),
                     glyph: .trainingLoad)
        ])
    }

    private var stepsCard: some View {
        ChartCard(title: String(localized: "Steps"), subtitle: String(localized: "Bars that reach the dashed line hit \(stepGoal.formatted(.number.precision(.fractionLength(0)))) steps.")) {
            Chart {
                ForEach(days.filter { $0.steps != nil }, id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Steps", day.steps ?? 0))
                        .foregroundStyle((day.steps ?? 0) >= stepGoal ? AnyShapeStyle(Theme.activity.gradient) : AnyShapeStyle(Theme.activity.opacity(0.35)))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Goal", stepGoal))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
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
            .frame(height: 200)
        }
    }

    private var energyCard: some View {
        ChartCard(title: String(localized: "Active energy"), subtitle: String(localized: "Calories burned through movement, on top of what your body burns at rest.")) {
            Chart {
                ForEach(days.filter { $0.activeEnergyBurned != nil }, id: \.date) { day in
                    AreaMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.activeEnergyBurned ?? 0))
                        .foregroundStyle(LinearGradient(colors: [Theme.warn.opacity(0.35), Theme.warn.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.activeEnergyBurned ?? 0))
                        .foregroundStyle(Theme.warn)
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Day", day.date, unit: .day), y: .value("kcal", day.activeEnergyBurned ?? 0))
                        .foregroundStyle(Theme.warn)
                        .symbolSize(20)
                }
            }
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
            .frame(height: 170)
        }
    }

    private struct TrainingBar: Identifiable {
        let id = UUID()
        let date: Date
        let kind: String
        let minutes: Double
    }

    private var trainingCard: some View {
        let bars = days.flatMap { day -> [TrainingBar] in
            [TrainingBar(date: day.date, kind: "Strength", minutes: day.strengthMinutes ?? 0),
             TrainingBar(date: day.date, kind: "Cardio", minutes: day.cardioMinutes ?? 0)]
        }.filter { $0.minutes > 0 }

        return ChartCard(title: String(localized: "Training minutes"), subtitle: String(localized: "Strength and cardio stacked per day. Gaps are rest days.")) {
            if bars.isEmpty {
                Text("No workouts in this range.").font(.footnote).foregroundStyle(Theme.textTertiary)
            } else {
                Chart(bars) { bar in
                    BarMark(x: .value("Day", bar.date, unit: .day), y: .value("Minutes", bar.minutes))
                        .foregroundStyle(by: .value("Type", bar.kind))
                        .cornerRadius(3)
                }
                .chartForegroundStyleScale(domain: ["Strength", "Cardio"], range: [Theme.accent, Theme.activity])
                .chartLegend(position: .bottom, alignment: .leading)
                .chartXScale(domain: (days.first?.date ?? Date())...(Calendar.current.date(byAdding: .day, value: 1, to: days.last?.date ?? Date()) ?? Date()))
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
                .frame(height: 180)
            }
        }
    }

    private var sessionsCard: some View {
        let sessions = allDays.filter(\.hadWorkout).suffix(8).reversed()
        return ChartCard(title: String(localized: "Recent sessions")) {
            if sessions.isEmpty {
                Text("No workouts yet.").font(.footnote).foregroundStyle(Theme.textTertiary)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(sessions), id: \.date) { day in
                        HStack(spacing: 12) {
                            GlyphTile(glyph: day.workoutIsResistance ? .training : .activity, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(day.primaryWorkoutName ?? "Workout")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(day.date.formatted(.dateTime.weekday(.wide).day().month()))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(durationText(day.workoutMinutes ?? 0))
                                    .font(.subheadline.weight(.semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary)
                                if let hr = day.workoutAvgHeartRate {
                                    Text("avg \(Int(hr)) bpm").font(.caption).monospacedDigit().foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
        }
    }
}
