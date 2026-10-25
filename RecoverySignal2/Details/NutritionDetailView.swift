//
//  NutritionDetailView.swift
//  RecoverySignal2
//
//  Nutrition in depth: today's rings, where your calories come from versus
//  where your targets say they should, calories by macro day by day, protein
//  per kilo of bodyweight, and a calendar of how often you hit your target.
//

import SwiftUI
import SwiftData
import Charts

struct NutritionDetailView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @State private var range: DetailRange = .twoWeeks

    private var goal: GoalSettings { GoalSettings.load() }
    private var maintenance: MaintenanceEstimate? { EnergyModel.maintenance(from: allDays) }
    private var targets: NutritionTargets? { maintenance.map { EnergyModel.targets(from: allDays, maintenance: $0) } }
    private var today: DailyMetrics? { allDays.last }

    var body: some View {
        DetailPage(title: String(localized: "Nutrition")) {
            hero
            NutritionRingsCard(calories: today?.dietaryEnergyKcal, protein: today?.proteinGrams,
                               carbs: today?.carbsGrams, fat: today?.fatGrams,
                               targets: targets, goal: goal.phase, showsCalories: false)
            splitCard
            RangePicker(range: $range)
            caloriesCard
            proteinCard
            adherenceCard
            MaintenanceCard(estimate: maintenance,
                            trendKcal: EnergyModel.adaptiveTDEE(from: allDays)?.value,
                            trendUncertainty: EnergyModel.adaptiveTDEE(from: allDays)?.uncertainty,
                            sexKnown: BodyProfile.load().isFemale != nil)
        }
    }

    // MARK: Hero

    private var hero: some View {
        let eaten = today?.dietaryEnergyKcal ?? 0
        let target = targets?.calories
        return DetailHero(
            glyph: .nutrition,
            eyebrow: String(localized: "Eaten today"),
            value: DetailFormat.whole(eaten),
            unit: "kcal",
            caption: target.map { "Target \(DetailFormat.whole($0)) kcal · \(goal.phase.label)" } ?? "Targets appear after a week of Watch data",
            colors: [Theme.accentDeep, Theme.accent]
        ) {
            if let target, target > 0 {
                ZStack {
                    Circle().stroke(Theme.track, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: min(eaten / target, 1))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    RingValueText(text: "\(Int((eaten / target * 100).rounded()))%", size: 18, color: Theme.textPrimary)
                    .padding(.horizontal, 8)
                }
                .frame(width: 76, height: 76)
            }
        }
    }

    // MARK: Macro split

    private struct Slice: Identifiable {
        let id = UUID()
        let macro: String
        let kcal: Double
    }

    private func slices(protein: Double, carbs: Double, fat: Double) -> [Slice] {
        [Slice(macro: "Protein", kcal: protein * 4), Slice(macro: "Carbs", kcal: carbs * 4), Slice(macro: "Fat", kcal: fat * 9)]
    }

    private var splitCard: some View {
        let eaten = slices(protein: today?.proteinGrams ?? 0, carbs: today?.carbsGrams ?? 0, fat: today?.fatGrams ?? 0)
        let target = targets.map { slices(protein: $0.proteinGrams, carbs: $0.carbsGrams, fat: $0.fatGrams) } ?? []

        return ChartCard(title: String(localized: "Where your calories come from"), subtitle: String(localized: "Share of calories from each macro, today versus your target.")) {
            HStack(spacing: 12) {
                donut(eaten, label: String(localized: "Today"))
                donut(target, label: String(localized: "Target"))
            }
            HStack(spacing: 14) {
                macroKey(String(localized: "Protein"), Theme.protein)
                macroKey(String(localized: "Carbs"), Theme.carbs)
                macroKey(String(localized: "Fat"), Theme.fat)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func donut(_ slices: [Slice], label: String) -> some View {
        let total = slices.reduce(0) { $0 + $1.kcal }
        return VStack(spacing: 8) {
            if total > 0 {
                Chart(slices) { slice in
                    SectorMark(angle: .value("kcal", slice.kcal), innerRadius: .ratio(0.62), angularInset: 2)
                        .foregroundStyle(by: .value("Macro", slice.macro))
                        .cornerRadius(4)
                }
                .chartForegroundStyleScale(domain: ["Protein", "Carbs", "Fat"], range: [Theme.protein, Theme.carbs, Theme.fat])
                .chartLegend(.hidden)
                .frame(height: 120)
                .overlay {
                    VStack(spacing: 0) {
                        ForEach(slices) { slice in
                            Text("\(Int((slice.kcal / total * 100).rounded()))%")
                                .font(.system(size: 11, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(color(slice.macro))
                        }
                    }
                }
            } else {
                Circle()
                    .stroke(Theme.track, lineWidth: 16)
                    .frame(height: 104)
                    .padding(8)
            }
            Text(LocalizedStringKey(label)).font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func macroKey(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 9, height: 9)
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.textSecondary)
        }
    }

    private func color(_ macro: String) -> Color {
        switch macro {
        case "Protein": Theme.protein
        case "Carbs":   Theme.carbs
        default:        Theme.fat
        }
    }

    // MARK: Calories by macro

    private struct MacroBar: Identifiable {
        let id = UUID()
        let date: Date
        let macro: String
        let kcal: Double
    }

    private var caloriesCard: some View {
        let days = allDays.last(range).filter { ($0.dietaryEnergyKcal ?? 0) > 0 }
        let bars = days.flatMap { day in
            slices(protein: day.proteinGrams ?? 0, carbs: day.carbsGrams ?? 0, fat: day.fatGrams ?? 0)
                .map { MacroBar(date: day.date, macro: $0.macro, kcal: $0.kcal) }
        }
        return ChartCard(title: String(localized: "Calories by macro"), subtitle: String(localized: "Each day's intake split into protein, carbs and fat, against your calorie target.")) {
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("Day", bar.date, unit: .day), y: .value("kcal", bar.kcal))
                        .foregroundStyle(by: .value("Macro", bar.macro))
                        .cornerRadius(2)
                }
                if let target = targets?.calories {
                    RuleMark(y: .value("Target", target))
                        .foregroundStyle(Theme.textSecondary)
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .annotation(position: .top, alignment: .trailing) {
                            Text("Target").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
                        }
                }
            }
            .chartForegroundStyleScale(domain: ["Protein", "Carbs", "Fat"], range: [Theme.protein, Theme.carbs, Theme.fat])
            .chartLegend(position: .bottom, alignment: .leading)
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

    // MARK: Protein per kg

    private var proteinCard: some View {
        let target = goal.phase.proteinGramsPerKg
        let points = allDays.last(range).compactMap { day -> TrendPoint? in
            guard let p = day.proteinGrams, p > 0,
                  let kg = day.bodyMassKg ?? allDays.last(where: { $0.bodyMassKg != nil })?.bodyMassKg, kg > 0 else { return nil }
            return TrendPoint(date: day.date, value: p / kg)
        }
        let hitDays = points.filter { $0.value >= target * 0.9 }.count

        return ChartCard(title: String(localized: "Protein per kg of bodyweight"),
                         subtitle: String(localized: "Target \(DetailFormat.decimal(target)) g/kg for your \(goal.phase.label.lowercased()) goal · hit on \(hitDays) of \(points.count) days.")) {
            Chart {
                ForEach(points) { point in
                    BarMark(x: .value("Day", point.date, unit: .day), y: .value("g/kg", point.value))
                        .foregroundStyle(point.value >= target * 0.9 ? Theme.protein : Theme.protein.opacity(0.35))
                        .cornerRadius(3)
                }
                RuleMark(y: .value("Target", target))
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
            .frame(height: 170)
        }
    }

    // MARK: Adherence calendar

    private var adherenceCard: some View {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let dates = (0..<28).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: todayStart) }
        let byDay = Dictionary(allDays.map { (calendar.startOfDay(for: $0.date), $0) }, uniquingKeysWith: { a, _ in a })
        let target = targets?.calories
        let onTarget = dates.filter { date in
            guard let target, let kcal = byDay[date]?.dietaryEnergyKcal, kcal > 0 else { return false }
            return abs(kcal - target) / target <= 0.1
        }.count

        return ChartCard(title: String(localized: "Last 4 weeks"), subtitle: String(localized: "Within 10% of target on \(onTarget) of 28 days.")) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                ForEach(dates, id: \.self) { date in
                    let kcal = byDay[date]?.dietaryEnergyKcal
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(cellColor(kcal: kcal, target: target))
                        .aspectRatio(1, contentMode: .fit)
                        .overlay {
                            Text("\(calendar.component(.day, from: date))")
                                .font(.system(size: 10, weight: .medium))
                                .monospacedDigit()
                                .foregroundStyle(kcal == nil ? Theme.textTertiary : .white)
                        }
                }
            }
            HStack(spacing: 12) {
                macroKey(String(localized: "Under"), Theme.accent.opacity(0.45))
                macroKey(String(localized: "On target"), Theme.good)
                macroKey(String(localized: "Over"), Theme.warn)
                macroKey(String(localized: "No log"), Theme.track)
            }
        }
    }

    private func cellColor(kcal: Double?, target: Double?) -> Color {
        guard let kcal, kcal > 0 else { return Theme.track }
        guard let target, target > 0 else { return Theme.accent }
        let diff = (kcal - target) / target
        if abs(diff) <= 0.1 { return Theme.good }
        return diff < 0 ? Theme.accent.opacity(0.35 + min(abs(diff), 0.5)) : Theme.warn.opacity(0.5 + min(diff, 0.5))
    }
}
