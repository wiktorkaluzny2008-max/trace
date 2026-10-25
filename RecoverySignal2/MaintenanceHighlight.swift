//
//  MaintenanceHighlight.swift
//  RecoverySignal2
//
//  The maintenance card in the weight section: adaptive maintenance calories,
//  how they've moved as you ate and weighed in, and the target they set.
//

import SwiftUI
import Charts

struct AdaptiveMaintenanceCard: View {
    let days: [DailyMetrics]
    /// Today's shorter version; the Body page shows the full one.
    var compact = false
    var excludedDates: Set<Date> = []

    private var profile: BodyProfile { BodyProfile.load() }

    var body: some View {
        let watch = EnergyModel.watchMaintenance(from: days, profile: profile)
        if let watch {
            let adaptive = AdaptiveMaintenance.compute(from: days, starting: watch.total, excluded: excludedDates)
            content(watch: watch, adaptive: adaptive)
        } else {
            MaintenanceCard(estimate: nil)
        }
    }

    private func content(watch: MaintenanceEstimate, adaptive: AdaptiveMaintenance.Estimate?) -> some View {
        let value = (adaptive?.isActive == true ? adaptive?.value : nil) ?? watch.total
        let goal = GoalSettings.load()
        let target = NutritionTargets(maintenance: watch.adapted(to: value),
                                      bodyMassKg: days.compactMap(\.bodyMassKg).last, goal: goal)
        let recent = adaptive?.series.suffix(compact ? 42 : 90) ?? []

        return VStack(alignment: .leading, spacing: 0) {
            // Header: calm, like every other card — the number does the talking.
            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                HStack(spacing: 6) {
                    GlyphView(.energy, size: 16)
                    Text("MAINTENANCE")
                        .font(.eyebrow)
                        .tracking(0.9)
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    Text(adaptive?.isActive == true ? "Adaptive" : "Watch estimate")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Theme.track, in: Capsule())
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(Int(value.rounded()).formatted())
                        .font(.system(size: compact ? 26 : 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Theme.textPrimary)
                    Text("kcal / day")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if let change = adaptive?.changeTwoWeeks, abs(change) >= 5 {
                        HStack(spacing: 2) {
                            Image(systemName: change > 0 ? "arrow.up.right" : "arrow.down.right")
                                .font(.system(size: 9, weight: .bold))
                            Text("\(Int(abs(change).rounded())) vs 2 wk")
                                .font(.system(size: 11, weight: .medium))
                                .monospacedDigit()
                        }
                        .foregroundStyle(Theme.textSecondary)
                    }
                }

                if !compact {
                    if recent.count >= 5 {
                        maintenanceChart(Array(recent), watch: watch.total)
                    }

                    Text(adaptive?.explanation ?? "Log food and weigh in for a couple of weeks and this starts adjusting to how your body actually responds.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        confidenceDots(adaptive?.confidence ?? .learning)
                        Text("\(adaptive?.confidence.label ?? "Learning") · \(adaptive?.loggedDays ?? 0) logged days in 4 weeks")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .padding(compact ? 14 : 16)

            Divider().overlay(Theme.separator)

            // Goal target strip
            HStack(spacing: 12) {
                GlyphTile(glyph: .target, color: Theme.good, size: compact ? 30 : 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(goal.phase == .maintain ? "Your target: eat at maintenance"
                         : "\(goal.phase.label) · \(goal.rateKgPerWeek.formatted(.number.precision(.fractionLength(0...2)))) kg/week")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(Int(target.calories.rounded()).formatted())
                            .font(.system(size: compact ? 17 : 20, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("kcal target").font(.system(size: 12)).foregroundStyle(Theme.textTertiary)
                        if goal.phase != .maintain {
                            Text("(\(goal.signedDailyAdjustment >= 0 ? "+" : "−")\(Int(abs(goal.signedDailyAdjustment).rounded())))")
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(target.proteinGrams.rounded())) g").font(.system(size: 15, weight: .semibold)).monospacedDigit()
                    Text("protein").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(compact ? 12 : 16)

            if !compact {
                Divider().overlay(Theme.separator)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 0) {
                        stat(String(localized: "Watch estimate"), Int(watch.total.rounded()).formatted(), "kcal")
                        stat(String(localized: "Avg intake · 14d"), adaptive?.averageIntake.map { Int($0.rounded()).formatted() } ?? "—", "kcal")
                        stat(String(localized: "Trend weight"), adaptive?.trendChangePerWeek.map { DetailFormat.signed($0, 2) } ?? "—", "kg/wk")
                    }
                    if recent.count >= 5 {
                        trendWeightChart(Array(recent))
                    }
                    HowItWorks(explainer: .adaptiveMaintenance)
                }
                .padding(16)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }

    private func maintenanceChart(_ points: [AdaptiveMaintenance.Point], watch: Double) -> some View {
        let values = points.map(\.maintenance) + [watch]
        let lo = (values.min() ?? 0) - 60, hi = (values.max() ?? 1) + 60
        return Chart {
            ForEach(points) { p in
                AreaMark(x: .value("Date", p.date), yStart: .value("Base", lo), yEnd: .value("kcal", p.maintenance))
                    .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.18), Theme.accent.opacity(0)], startPoint: .top, endPoint: .bottom))
                LineMark(x: .value("Date", p.date), y: .value("kcal", p.maintenance))
                    .foregroundStyle(Theme.accent)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            }
            RuleMark(y: .value("Watch", watch))
                .foregroundStyle(Theme.textTertiary.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading, spacing: 3) {
                    Text("Watch estimate")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Theme.surface.opacity(0.92), in: Capsule())
                }
            if let last = points.last {
                PointMark(x: .value("Date", last.date), y: .value("kcal", last.maintenance))
                    .symbolSize(40)
                    .foregroundStyle(Theme.accent)
            }
        }
        .chartYScale(domain: lo...hi)
        // Room on the right so the last date label isn't clipped.
        .chartXScale(range: .plotDimension(endPadding: 18))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .chartYAxis(.hidden)
        .frame(height: compact ? 70 : 96)
    }

    private func trendWeightChart(_ points: [AdaptiveMaintenance.Point]) -> some View {
        let values = points.map(\.trendWeight)
        let lo = (values.min() ?? 0) - 0.3, hi = (values.max() ?? 1) + 0.3
        return VStack(alignment: .leading, spacing: 6) {
            Text("What it learned from")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            Chart {
                ForEach(points) { p in
                    if let intake = p.intake {
                        BarMark(x: .value("Date", p.date, unit: .day), y: .value("Intake", intake))
                            .foregroundStyle(Theme.accent.opacity(0.35))
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator.opacity(0.6))
                    AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartXAxis(.hidden)
            .frame(height: 70)
            .overlay {
                Chart {
                    ForEach(points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Trend", p.trendWeight))
                            .foregroundStyle(Theme.fat)
                            .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round))
                    }
                }
                .chartYScale(domain: lo...hi)
                .chartXAxis(.hidden)
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisValueLabel().font(.system(size: 9)).foregroundStyle(Theme.fat)
                    }
                }
            }
            HStack(spacing: 14) {
                ChartLegendKey(kind: .square, color: Theme.accent.opacity(0.35), label: String(localized: "Calories logged"))
                ChartLegendKey(kind: .line, color: Theme.fat, label: String(localized: "Trend weight (kg)"))
            }
        }
    }

    private func confidenceDots(_ confidence: AdaptiveMaintenance.Confidence) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(Theme.accent.opacity(i <= confidence.rawValue ? 1 : 0.25))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func stat(_ label: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text(LocalizedStringKey(unit)).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
            }
            .foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(label)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
