//
//  AnalysisView.swift
//  RecoverySignal2
//
//  The deeper layer: training load, fatigue modelling, metabolic estimates and
//  discovered correlations. Everything here is computed from your own baseline.
//

import SwiftUI
import SwiftData

struct AnalysisView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @Query private var dayTags: [DayTag]
    @AppStorage(DeviceProfile.heartKey) private var tracksHeart = true

    private var days: [DailyMetrics] { allDays }

    /// Each model runs once per data change rather than on every redraw.
    private func memo<T>(_ key: String, _ compute: () -> T) -> T {
        DerivedCache.value("analysis.\(key)", inputs: [DaysSignature(allDays).hashValue, dayTags.count], compute)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                ScrollView {
                    // Lazy: a tab's first open only builds the cards on screen.
                    LazyVStack(alignment: .leading, spacing: 24) {
                        // Both are built on heart rate (TRIMP load, HRV and resting HR).
                        if tracksHeart { trainingLoadSection.id("Training load") }
                        if tracksHeart { fatigueSection.id("Fatigue & stability") }
                        energySection.id("Energy")
                        discoveriesSection.id("Discoveries")
                        AdvancedAnalysisSections(days: days).id("Long-term analysis")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 4)
                    .padding(.bottom, 36)
                }
                .safeAreaInset(edge: .top, spacing: 0) {
                    SectionJumpBar(sections: (tracksHeart ? ["Training load", "Fatigue & stability"] : []) + ["Energy", "Discoveries", "Long-term analysis"], proxy: proxy)
                }
                .background(Theme.background.ignoresSafeArea())
            }
            .navigationTitle("Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { TabInfoButton() } }
        }
    }

    // MARK: - Training load

    private var trainingLoadSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Training load", icon: .trainingLoad)

            if let acwr = memo("acwr") { TrainingLoadModel.compute(from: days) } {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("ACWR")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(acwr.ratio.formatted(.number.precision(.fractionLength(2))))
                                .font(.display(32))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                        Text(LocalizedStringKey(acwr.zone.label))
                            .font(.caption)
                            .foregroundStyle(acwr.zone.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(acwr.zone.color.opacity(0.13), in: Capsule())
                    }

                    ACWRScale(ratio: acwr.ratio, color: acwr.zone.color)

                    Text(LocalizedStringKey(acwr.zone.explanation))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    footnote(String(localized: "Acute \(Int(acwr.acute)) vs chronic \(Int(acwr.chronic)) TRIMP.") +
                             (acwr.provisional ? " Provisional — based on \(acwr.daysOfData) days, not a full 28-day chronic window." : ""))

                    HowItWorks(explainer: .acwr)
                }
                .card(padding: 18)
            } else {
                lockedCard(
                    icon: .trainingLoad,
                    title: String(localized: "Needs ~2 weeks of training data"),
                    message: String(localized: "Acute:chronic workload ratio compares your last 7 days against a 28-day baseline, so it needs history before it says anything useful."),
                    explainer: .acwr
                )
            }
        }
    }

    // MARK: - Fatigue

    private var fatigueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Fatigue & stability", icon: .fatigue)

            if let fatigue = memo("fatigue") { ReadinessModel.fatigue(from: days) } {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Composite fatigue")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text(fatigue.composite.formatted(.number.precision(.fractionLength(2))))
                                .font(.display(32))
                                .monospacedDigit()
                                .foregroundStyle(fatigue.isStrained ? Theme.bad : Theme.textPrimary)
                        }
                        Spacer()
                        Text(fatigue.isStrained ? "Strained" : "Within range")
                            .font(.caption)
                            .foregroundStyle(fatigue.isStrained ? Theme.bad : Theme.good)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background((fatigue.isStrained ? Theme.bad : Theme.good).opacity(0.13), in: Capsule())
                    }

                    VStack(spacing: 8) {
                        ForEach(fatigue.components) { component in
                            HStack(spacing: 10) {
                                Text(LocalizedStringKey(component.label))
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(width: 78, alignment: .leading)
                                ZScoreBar(z: component.z)
                                Text(component.z.formatted(.number.precision(.fractionLength(1))))
                                    .font(.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(component.z < -1 ? Theme.bad : Theme.textTertiary)
                                    .frame(width: 30, alignment: .trailing)
                            }
                        }
                    }

                    if fatigue.consecutiveStrainedDays >= 2 {
                        Text("Below −1.5 SD for \(fatigue.consecutiveStrainedDays) consecutive days — the pattern that suggests accumulating rather than momentary fatigue.")
                            .font(.footnote)
                            .foregroundStyle(Theme.bad)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    footnote(String(localized: "Each input is scored against your own trailing baseline, not population norms. Negative means worse than your normal."))

                    HowItWorks(explainer: .fatigue)
                }
                .card(padding: 18)
            } else {
                lockedCard(
                    icon: .fatigue,
                    title: String(localized: "Needs ~2 weeks of history"),
                    message: String(localized: "The composite score is measured against your own rolling baseline, which takes a couple of weeks to establish."),
                    explainer: .fatigue
                )
            }

            if let stability = memo("stability") { ReadinessModel.hrvStability(from: days) } {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("HRV variability (CV)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text("\(stability.currentCV.formatted(.number.precision(.fractionLength(1))))%")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(stability.isDestabilising ? Theme.warn : Theme.textPrimary)
                    }

                    Text(stability.isDestabilising
                         ? "Your day-to-day HRV is swinging more than usual (baseline \(stability.baselineCV.formatted(.number.precision(.fractionLength(1))))%). Rising variability often precedes a drop in the average — it can flag overreaching while the mean still looks fine."
                         : "Day-to-day HRV is as stable as your baseline (\(stability.baselineCV.formatted(.number.precision(.fractionLength(1))))%). Stable variability is a good sign even when the average moves around.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    footnote(String(localized: "Method follows the ln-rMSSD CV literature, but Apple Watch reports SDNN — so this compares against your own baseline rather than published thresholds."))

                    HowItWorks(explainer: .hrvStability)
                }
                .card(padding: 18)
            }

            if let debt = memo("debt") { ReadinessModel.sleepDebt(from: days) } {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 14) {
                        GlyphTile(glyph: .sleep, color: debt.hours > 5 ? Theme.warn : Theme.good)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(debt.hours.formatted(.number.precision(.fractionLength(1))))h sleep debt")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text("Accumulated over \(debt.nights) nights against an \(Int(debt.target))h target.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }

                    HowItWorks(explainer: .sleepDebt)
                }
                .card()
            }
        }
    }

    // MARK: - Energy

    private var energySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Energy & metabolism", icon: .energy)

            if let tdee = memo("tdee") { EnergyModel.adaptiveTDEE(from: days) } {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Adaptive TDEE")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 5) {
                                Text("\(Int(tdee.value.rounded()))")
                                    .font(.display(32))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary)
                                Text("± \(Int(tdee.uncertainty.rounded())) kcal")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                    }

                    HStack(spacing: 0) {
                        miniStat(String(localized: "Avg intake"), "\(Int(tdee.averageIntake.rounded()))")
                        Rectangle().fill(Theme.separator).frame(width: 1, height: 26)
                        miniStat(String(localized: "Weight/wk"), "\(tdee.weightChangePerWeek >= 0 ? "+" : "")\(tdee.weightChangePerWeek.formatted(.number.precision(.fractionLength(2))))kg")
                        Rectangle().fill(Theme.separator).frame(width: 1, height: 26)
                        miniStat(String(localized: "Window"), "\(tdee.windowDays)d")
                    }

                    footnote(String(localized: "Derived from how your smoothed weight actually responded to logged intake — so it already includes any metabolic adaptation, unlike a fixed formula. Accuracy depends entirely on how honestly you log."))

                    HowItWorks(explainer: .tdee)
                }
                .card(padding: 18)
            } else {
                lockedCard(
                    icon: .energy,
                    title: String(localized: "Needs 2+ weeks of weight and intake"),
                    message: String(localized: "Adaptive TDEE regresses your weight trend against logged calories, so it needs both on most days before it can estimate anything."),
                    explainer: .tdee
                )
            }

            if let ea = memo("ea") { EnergyModel.energyAvailability(from: days) } {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Energy availability")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(ea.kcalPerKgFFM.formatted(.number.precision(.fractionLength(1))))
                                    .font(.display(32))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.textPrimary)
                                Text("kcal/kg FFM")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Spacer()
                        Text(LocalizedStringKey(ea.status.label))
                            .font(.caption)
                            .foregroundStyle(ea.status.color)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(ea.status.color.opacity(0.13), in: Capsule())
                    }

                    Text(LocalizedStringKey(ea.status.explanation))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    footnote(String(localized: "Fat-free mass \(ea.fatFreeMass.formatted(.number.precision(.fractionLength(1))))kg, averaged over \(ea.days) days. This is a screening signal, not a diagnosis — persistent low EA is worth a clinician's opinion."))

                    HowItWorks(explainer: .energyAvailability)
                }
                .card(padding: 18)
            } else {
                lockedCard(
                    icon: .body,
                    title: String(localized: "Energy availability needs body composition"),
                    message: String(localized: "EA divides intake minus exercise energy by fat-free mass. Health has no body-fat or lean-mass data yet — a smart scale that syncs to Apple Health would switch this on, along with P-ratio."),
                    explainer: .energyAvailability
                )
            }

            if let pRatio = memo("pRatio") { EnergyModel.pRatio(from: days) } {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("P-ratio")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Text("\(Int((pRatio.value * 100).rounded()))%")
                                .font(.display(32))
                                .monospacedDigit()
                                .foregroundStyle(Theme.textPrimary)
                        }
                        Spacer()
                    }

                    Text(LocalizedStringKey(pRatio.interpretation))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    footnote(String(localized: "Lean \(pRatio.deltaFFM >= 0 ? "+" : "")\(pRatio.deltaFFM.formatted(.number.precision(.fractionLength(1))))kg, fat \(pRatio.deltaFatMass >= 0 ? "+" : "")\(pRatio.deltaFatMass.formatted(.number.precision(.fractionLength(1))))kg over \(pRatio.windowDays) days. Bioimpedance is noisy — only read this over weeks."))

                    HowItWorks(explainer: .pRatio)
                }
                .card(padding: 18)
            }
        }
    }

    // MARK: - Discoveries

    private var discoveriesSection: some View {
        let findings = memo("findings") { LagCorrelationMiner.mine(from: days, tags: dayTags) }

        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Discovered patterns", icon: .patterns)

            if findings.isEmpty {
                lockedCard(
                    icon: .patterns,
                    title: String(localized: "No reliable patterns yet"),
                    message: String(localized: "This looks for relationships between what you eat, sleep and train on one day and how your body responds on later days. It needs roughly a month of overlapping data before anything survives statistical correction."),
                    explainer: .patterns
                )
            } else {
                ForEach(findings) { finding in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(LocalizedStringKey(finding.sentence))
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 6) {
                            tag(String(localized: "ρ \(finding.correlation.formatted(.number.precision(.fractionLength(2))))"),
                                color: finding.isPositive ? Theme.good : Theme.bad)
                            tag(finding.strength, color: Theme.textTertiary)
                            tag(String(localized: "n=\(finding.sampleSize)"), color: Theme.textTertiary)
                        }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Exploratory only. These are correlations in your own data, not causes — hard days move sleep, intake and HRV together. Findings are corrected for testing many combinations, but treat them as hypotheses to test deliberately, not instructions.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                    HowItWorks(explainer: .patterns)
                }
                .card()
            }
        }
    }

    // MARK: - Shared pieces

    private func miniStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 10, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private func footnote(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Shown before a metric has enough data — still explains what's coming.
    private func lockedCard(icon: Glyph, title: String, message: String, explainer: Explainer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                GlyphView(icon, size: 26, palette: .muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(LocalizedStringKey(message))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HowItWorks(explainer: explainer)
        }
        .card()
    }
}

// MARK: - Small charts

/// Horizontal ACWR scale with the standard zones and a marker for where you are.
struct ACWRScale: View {
    let ratio: Double
    let color: Color

    private let maxRatio = 2.0

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let position = min(max(ratio / maxRatio, 0), 1) * width

            ZStack(alignment: .leading) {
                HStack(spacing: 0) {
                    Rectangle().fill(Theme.textSecondary.opacity(0.25))
                        .frame(width: width * (0.8 / maxRatio))
                    Rectangle().fill(Theme.good.opacity(0.45))
                        .frame(width: width * (0.5 / maxRatio))
                    Rectangle().fill(Theme.warn.opacity(0.45))
                        .frame(width: width * (0.2 / maxRatio))
                    Rectangle().fill(Theme.bad.opacity(0.45))
                }
                .clipShape(Capsule())

                Capsule()
                    .fill(color)
                    .frame(width: 3, height: 18)
                    .offset(x: min(max(position - 1.5, 0), width - 3))
            }
        }
        .frame(height: 18)
    }
}

/// Centre-anchored bar for a z-score, negative to the left.
struct ZScoreBar: View {
    let z: Double

    var body: some View {
        GeometryReader { geo in
            let half = geo.size.width / 2
            let clamped = min(max(z / 3.0, -1), 1)
            let barWidth = abs(clamped) * half

            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Rectangle()
                    .fill(Theme.separator)
                    .frame(width: 1)
                    .offset(x: half)
                Capsule()
                    .fill(z < 0 ? Theme.bad.opacity(0.75) : Theme.good.opacity(0.75))
                    .frame(width: max(2, barWidth))
                    .offset(x: z < 0 ? half - barWidth : half)
            }
        }
        .frame(height: 7)
    }
}

#Preview {
    AnalysisView()
        .modelContainer(for: [DailyMetrics.self, Insight.self, WeeklyNarrative.self], inMemory: true)
}
