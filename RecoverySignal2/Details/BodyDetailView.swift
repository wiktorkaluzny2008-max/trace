//
//  BodyDetailView.swift
//  RecoverySignal2
//
//  Body in depth: weight with its fitted trend and weekly rate, changes over
//  7 / 30 / 90 days, weekly averages, and body composition when a smart scale
//  provides it.
//

import SwiftUI
import SwiftData
import Charts

struct BodyDetailView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @Query private var tags: [DayTag]
    @State private var range: DetailRange = .month

    private var weights: [TrendPoint] {
        allDays.compactMap { day in day.bodyMassKg.map { TrendPoint(date: day.date, value: $0) } }
    }
    private var rangeWeights: [TrendPoint] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -range.rawValue, to: Date()) else { return weights }
        return weights.filter { $0.date >= cutoff }
    }

    var body: some View {
        DetailPage(title: String(localized: "Body")) {
            hero
            RangePicker(range: $range)
            weightCard
            changes
            weeklyCard
            compositionCard
            AdaptiveMaintenanceCard(days: allDays, excludedDates: DayTagStore.excludedDates(tags))
        }
    }

    private func change(overDays days: Int) -> Double? {
        guard let latest = weights.last,
              let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: latest.date),
              let earlier = weights.last(where: { $0.date <= cutoff }) else { return nil }
        return latest.value - earlier.value
    }

    private var hero: some View {
        let latest = weights.last
        let weekly = TrendFit.linear.weeklySlope(TrendFit.linear.fitted(rangeWeights))
        return DetailHero(
            glyph: .body,
            eyebrow: String(localized: "Latest weight"),
            value: latest.map { DetailFormat.decimal($0.value) } ?? "—",
            unit: "kg",
            caption: weekly.map { "Trend \(DetailFormat.signed($0, 2)) kg per week over \(range.rawValue) days" } ?? "Weigh in a few times to see your trend",
            colors: [Theme.accentDeep, Theme.accent]
        )
    }

    private var weightCard: some View {
        let points = rangeWeights
        let fitted = TrendFit.linear.fitted(points)
        let values = points.map(\.value) + fitted.map(\.value)
        let lo = values.min() ?? 0, hi = values.max() ?? 1
        let pad = max((hi - lo) * 0.2, 0.3)

        return ChartCard(title: String(localized: "Weight"), subtitle: String(localized: "Daily weigh-ins, with the straight-line trend dashed through them.")) {
            Chart {
                ForEach(points) { p in
                    AreaMark(x: .value("Day", p.date), yStart: .value("Base", lo - pad), yEnd: .value("kg", p.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.fat.opacity(0.22), Theme.fat.opacity(0.0)], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Day", p.date), y: .value("kg", p.value), series: .value("S", "Weight"))
                        .foregroundStyle(Theme.fat.opacity(0.7))
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Day", p.date), y: .value("kg", p.value))
                        .foregroundStyle(Theme.fat)
                        .symbolSize(26)
                }
                ForEach(fitted) { p in
                    LineMark(x: .value("Day", p.date), y: .value("kg", p.value), series: .value("S", "Trend"))
                        .foregroundStyle(Theme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 4]))
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
            .frame(height: 220)
        }
    }

    private var changes: some View {
        let height = BodyProfile.load().heightCm
        let bmi: Double? = {
            guard let kg = weights.last?.value, let cm = height, cm > 0 else { return nil }
            return kg / pow(cm / 100, 2)
        }()
        return StatGrid(tiles: [
            StatTile(label: String(localized: "7 days"), value: change(overDays: 7).map { DetailFormat.signed($0) } ?? "—", unit: "kg", glyph: .body),
            StatTile(label: String(localized: "30 days"), value: change(overDays: 30).map { DetailFormat.signed($0) } ?? "—", unit: "kg", glyph: .body),
            StatTile(label: String(localized: "90 days"), value: change(overDays: 90).map { DetailFormat.signed($0) } ?? "—", unit: "kg", glyph: .body),
            StatTile(label: String(localized: "BMI"), value: bmi.map { DetailFormat.decimal($0) } ?? "—",
                     caption: bmi == nil ? "Add your height in Health" : "Doesn't account for muscle mass")
        ])
    }

    private struct WeekAverage: Identifiable {
        let id = UUID()
        let weekStart: Date
        let kg: Double
    }

    private var weeklyCard: some View {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: rangeWeights) { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        let weeks = grouped.compactMap { start, points in
            Stats.mean(points.map(\.value)).map { WeekAverage(weekStart: start, kg: $0) }
        }.sorted { $0.weekStart < $1.weekStart }
        let lo = (weeks.map(\.kg).min() ?? 0) - 0.5

        return ChartCard(title: String(localized: "Weekly average"), subtitle: String(localized: "Averaging a week of weigh-ins cancels out day-to-day water swings.")) {
            if weeks.count < 2 {
                Text("Needs at least two weeks of weigh-ins.").font(.footnote).foregroundStyle(Theme.textTertiary)
            } else {
                Chart(weeks) { week in
                    BarMark(x: .value("Week", week.weekStart, unit: .weekOfYear), yStart: .value("Base", lo), yEnd: .value("kg", week.kg))
                        .foregroundStyle(Theme.fat.gradient)
                        .cornerRadius(4)
                        .annotation(position: .top) {
                            Text(DetailFormat.decimal(week.kg)).font(.system(size: 9, weight: .medium)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                        }
                }
                .chartYScale(domain: lo...((weeks.map(\.kg).max() ?? 1) + 0.4))
                .chartYAxis(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: 160)
            }
        }
    }

    @ViewBuilder
    private var compositionCard: some View {
        let fat = allDays.compactMap { d in d.bodyFatPercent.map { TrendPoint(date: d.date, value: $0) } }
        ChartCard(title: String(localized: "Body composition"),
                  subtitle: fat.isEmpty ? "A smart scale that syncs to Apple Health adds body fat and lean mass here." : "Body fat % from your smart scale — read the trend over weeks, not single days.") {
            if !fat.isEmpty {
                Chart(fat.suffix(range.rawValue)) { p in
                    LineMark(x: .value("Day", p.date), y: .value("%", p.value))
                        .foregroundStyle(Theme.warn)
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Day", p.date), y: .value("%", p.value))
                        .foregroundStyle(Theme.warn)
                        .symbolSize(20)
                }
                .chartYScale(domain: .automatic(includesZero: false))
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
                .frame(height: 150)
            }
        }
    }
}
