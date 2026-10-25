//
//  NutritionCards.swift
//  RecoverySignal2
//
//  Today's intake as rings that fill toward your maintenance targets, and the
//  maintenance-calorie card that explains where those targets come from.
//  Both take plain values rather than querying data, so they preview easily.
//

import SwiftUI

// MARK: - Ring

/// Fills toward a target and keeps going past it, like Activity rings: the
/// second lap is drawn over the first with a soft shadow so the overlap reads.
struct ProgressRing: View {
    let fraction: Double
    let color: Color
    let lineWidth: CGFloat

    var body: some View {
        let f = max(0, fraction.isFinite ? fraction : 0)
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round)

        ZStack {
            Circle()
                .stroke(color.opacity(0.14), lineWidth: lineWidth)
            if f > 0 {
                Circle()
                    .trim(from: 0, to: min(f, 1))
                    .stroke(color, style: style)
                    .rotationEffect(.degrees(-90))
            }
            if f > 1 {
                Circle()
                    .trim(from: 0, to: min(f - 1, 1))
                    .stroke(color, style: style)
                    .rotationEffect(.degrees(-90))
                    .shadow(color: .black.opacity(0.28), radius: lineWidth * 0.22)
            }
        }
        .padding(lineWidth / 2)
        .animation(.easeOut(duration: 0.7), value: f)
    }
}

private func whole(_ value: Double) -> String {
    value.formatted(.number.precision(.fractionLength(0)))
}

// MARK: - Nutrition rings

struct NutritionRingsCard: View {
    let calories: Double?
    let protein: Double?
    let carbs: Double?
    let fat: Double?
    let targets: NutritionTargets?
    var goal: GoalSettings.Phase = .maintain
    var showsCalories = true
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var summaryLayout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16)) : AnyLayout(HStackLayout(spacing: 16))
    }

    var body: some View {
        VStack(spacing: 18) {
            if showsCalories {
            summaryLayout {
                calorieGauge
                    .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(status.title))
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(status.color)
                        Text(LocalizedStringKey(status.detail))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let targets {
                        HStack(spacing: 0) {
                            miniStat(whole(calories ?? 0), "eaten")
                            miniStat(whole(targets.calories), "target")
                            miniStat(whole(max(targets.calories - (calories ?? 0), 0)), "left")
                        }
                        .padding(.vertical, 8)
                        .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
                Spacer(minLength: 0)
            }

            }
            VStack(spacing: 12) {
                macroBar("Protein", glyph: .protein, eaten: protein, target: targets?.proteinGrams,
                         colors: [Theme.protein, Theme.protein])
                macroBar("Carbs", glyph: .carbs, eaten: carbs, target: targets?.carbsGrams,
                         colors: [Theme.carbs, Theme.carbs])
                macroBar("Fat", glyph: .fat, eaten: fat, target: targets?.fatGrams,
                         colors: [Theme.fat, Theme.fat])
            }
        }
        .card(padding: 18)
    }

    /// A 270° gauge with a gradient sweep and a glowing tip.
    private var calorieGauge: some View {
        let f = max(0, fraction(calories, targets?.calories))
        let shown = min(f, 1)
        let arc = 0.75
        let over = f > 1.05
        let colors = over ? [Theme.warn.opacity(0.7), Theme.warn] : [Theme.mint, Theme.accent, Theme.accentDeep]
        return ZStack {
            Circle()
                .trim(from: 0, to: arc)
                .stroke(Theme.track, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
            Circle()
                .trim(from: 0, to: arc * shown)
                .stroke(AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(270 * max(shown, 0.01))),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round))
                .rotationEffect(.degrees(135))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.9), value: shown)
            VStack(spacing: 0) {
                Text(whole(calories ?? 0))
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                    .contentTransition(.numericText())
                Text("kcal eaten")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .padding(.horizontal, 22)
            if targets != nil {
                Text(verbatim: "\(Int((f * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(over ? Theme.warn : Theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background((over ? Theme.warn : Theme.accent).opacity(0.12), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.bottom, 2)
            }
        }
        .padding(7)
    }

    private func miniStat(_ value: String, _ label: LocalizedStringKey) -> some View {
        VStack(spacing: 1) {
            Text(verbatim: value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func macroBar(_ label: String, glyph: Glyph, eaten: Double?, target: Double?, colors: [Color]) -> some View {
        let f = max(0, fraction(eaten, target))
        let over = target != nil && f > 1.1
        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                GlyphView(glyph, size: 15, palette: .mono(colors[1], soft: 0.22))
                Text(LocalizedStringKey(label))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let target {
                    let eatenText = Text(verbatim: "\(whole(eaten ?? 0))")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    let targetText = Text(verbatim: " / \(whole(target)) g")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Theme.textTertiary)
                    Text("\(eatenText)\(targetText)")
                    Text(over ? String(localized: "\(whole((eaten ?? 0) - target)) over") : String(localized: "\(whole(max(target - (eaten ?? 0), 0))) left"))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(over ? Theme.warn : colors[1])
                        .frame(minWidth: 52, alignment: .trailing)
                } else {
                    Text(verbatim: "\(whole(eaten ?? 0)) g")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .monospacedDigit()

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(colors[1].opacity(0.12))
                    Capsule()
                        .fill(LinearGradient(colors: over ? [colors[1], Theme.warn] : colors, startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(geo.size.width * min(f, 1), f > 0 ? 8 : 0))
                        .animation(.easeOut(duration: 0.8), value: f)
                }
            }
            .frame(height: 6)
        }
    }

    private func fraction(_ eaten: Double?, _ target: Double?) -> Double {
        guard let target, target > 0 else { return 0 }
        return (eaten ?? 0) / target
    }

    private var status: (title: String, detail: String, color: Color) {
        guard let targets else {
            return ("Calories today",
                    "Targets appear after about a week of Apple Watch wear — they're built from what you actually burn.",
                    Theme.textPrimary)
        }
        guard let eaten = calories, eaten > 0 else {
            return ("Nothing logged yet",
                    "Log food with the fork button on Today, or in any app that writes to Apple Health.",
                    Theme.textPrimary)
        }
        let target = targets.calories
        let gap = target - eaten
        let goalName = goalTargetName
        if eaten > target * 1.05 {
            return ("\(whole(-gap)) kcal over",
                    "Above your \(goalName) of \(whole(target)) kcal today.",
                    Theme.warn)
        }
        if eaten >= target * 0.95 {
            return ("Right on target",
                    "Within 5% of your \(whole(target)) kcal \(goalName).",
                    Theme.good)
        }
        return ("\(whole(gap)) kcal left",
                "To reach your \(goalName) of \(whole(target)) kcal.",
                Theme.textPrimary)
    }

    private var goalTargetName: String {
        switch goal {
        case .cut:      String(localized: "cutting target")
        case .maintain: "maintenance"
        case .bulk:     String(localized: "building target")
        }
    }
}

// MARK: - Maintenance calories

struct MaintenanceCard: View {
    let estimate: MaintenanceEstimate?
    /// Adaptive TDEE from the weight trend, when there's enough history for it.
    var trendKcal: Double? = nil
    var trendUncertainty: Double? = nil
    /// False when Health has no biological sex, so the formula used the midpoint.
    var sexKnown: Bool = true

    var body: some View {
        if let estimate {
            content(estimate)
        } else {
            HStack(alignment: .top, spacing: 13) {
                GlyphTile(glyph: .energy, color: Theme.textTertiary, size: 40)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Needs about a week of Apple Watch data")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Maintenance is built from the resting and active energy your Watch records, so it needs at least 5 days of wear to average.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card()
        }
    }

    private func content(_ e: MaintenanceEstimate) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(whole(e.total))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("kcal / day")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Text("Eat about this much to hold your weight at your usual activity.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            breakdownBar(e)

            VStack(spacing: 8) {
                legendRow(String(localized: "Resting energy"), e.resting, Theme.accentDeep)
                legendRow(String(localized: "Activity"), e.activity, Theme.accent)
                legendRow(String(localized: "Digesting food"), e.digestion, Theme.mint)
            }

            if let trendKcal {
                Divider().overlay(Theme.separator)
                crossCheck(total: e.total, trend: trendKcal)
            }

            Text(sourceNote(e))
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 18)
    }

    private func breakdownBar(_ e: MaintenanceEstimate) -> some View {
        GeometryReader { geo in
            let parts: [(Double, Color)] = [(e.resting, Theme.accentDeep), (e.activity, Theme.accent), (e.digestion, Theme.mint)]
            let gaps = CGFloat(parts.count - 1) * 2
            HStack(spacing: 2) {
                ForEach(parts.indices, id: \.self) { i in
                    Rectangle()
                        .fill(parts[i].1)
                        .frame(width: max(2, (geo.size.width - gaps) * parts[i].0 / max(e.total, 1)))
                }
            }
            .clipShape(Capsule())
        }
        .frame(height: 10)
    }

    private func legendRow(_ label: String, _ value: Double, _ color: Color) -> some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(whole(value))
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("kcal")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func crossCheck(total: Double, trend: Double) -> some View {
        let diff = (trend - total) / total
        let percent = whole(abs(diff) * 100)
        let spread = trendUncertainty.map { " ± \(whole($0))" } ?? ""
        let explanation: String
        if abs(diff) <= 0.07 {
            explanation = "Within \(percent)% — two independent methods agree, so this number is solid."
        } else if diff < 0 {
            explanation = "That's \(percent)% lower. Watch activity often reads high, and unlogged food makes the trend read low — the truth usually sits in between."
        } else {
            explanation = "That's \(percent)% higher. Water and glycogen swings can make weight lag behind intake — give it another week or two before reading much into it."
        }

        return HStack(alignment: .top, spacing: 11) {
            GlyphView(.body, size: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text("Your weight trend says \(whole(trend))\(spread) kcal")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(explanation))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sourceNote(_ e: MaintenanceEstimate) -> String {
        switch e.restingSource {
        case .watch:
            return String(localized: "Resting and active energy from your Apple Watch, averaged over \(e.daysUsed) full days of wear. Digestion is estimated at 10% of intake. Watch energy readings can be off by 10–20%.")
        case .formula:
            let sexNote = sexKnown ? "" : String(localized: " Health has no sex set, so it averages the male and female versions.")
            return String(localized: "No Watch resting-energy data, so resting energy is estimated from your height, age and weight (Mifflin–St Jeor).\(sexNote) Activity is your Watch's active energy averaged over \(e.daysUsed) days; digestion is 10% of intake.")
        }
    }
}
