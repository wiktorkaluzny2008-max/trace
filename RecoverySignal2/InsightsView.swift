//
//  InsightsView.swift
//  RecoverySignal2
//
//  Two layers of interpretation: fast, deterministic rule-engine flags at the
//  top, and a slower, richer AI-written weekly narrative below (generated on
//  demand to avoid surprise API costs).
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var allDays: [DailyMetrics]
    @Query(sort: \WeeklyNarrative.generatedAt, order: .reverse) private var narratives: [WeeklyNarrative]

    /// A narrative lasts for the day it was written; tomorrow it's gone.
    private var todaysNarrative: WeeklyNarrative? {
        narratives.first { Calendar.current.isDateInToday($0.generatedAt) }
    }
    @Query private var dayTags: [DayTag]
    @Environment(\.modelContext) private var context

    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var recentDays: [DailyMetrics] { Array(allDays.prefix(14)) }
    private var flags: [Insight] { InsightRules.evaluate(recentDays: recentDays) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    storySection
                    weekSummarySection
                    flagsSection
                    consistencySection
                    highlightsSection
                    narrativeSection
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Insights")
            .task {
                // Yesterday's narrative is stale — clear it out.
                for narrative in narratives where !Calendar.current.isDateInToday(narrative.generatedAt) {
                    context.delete(narrative)
                }
            }
        }
    }

    // MARK: - 30-day story

    /// "Here's what 30 days of your data revealed": the shifts over the month,
    /// and the patterns that held up statistically, each with how much data
    /// stands behind it.
    private var storySection: some View {
        let window = Array(allDays.prefix(30)).sorted { $0.date < $1.date }
        let daysWithData = window.filter { $0.hrvSDNN != nil || $0.sleepAsleepHours != nil }.count
        return VStack(alignment: .leading, spacing: 0) {
            if daysWithData < 14 {
                storyLocked(daysWithData)
            } else {
                storyBody(window, daysWithData)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func storyBanner(_ subtitle: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOUR 30-DAY STORY")
                .font(.eyebrow).tracking(1.2).foregroundStyle(Theme.textSecondary)
            Text("Here's what 30 days of your data revealed")
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).font(.footnote).opacity(0.85).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surfaceRaised)
    }

    private func storyLocked(_ have: Int) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            storyBanner("Your Apple Watch records the numbers. Trace explains them, once it has enough of your days to be sure.")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Building your story").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text(verbatim: "\(have)/14").font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: Double(min(have, 14)), total: 14).tint(Theme.accent)
                Text("It unlocks after 14 days of Watch data. Log your food and training too, since the interesting findings come from connecting all of it.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private func storyBody(_ window: [DailyMetrics], _ daysWithData: Int) -> some View {
        let half = window.count / 2
        let first = Array(window.prefix(half)), last = Array(window.suffix(half))
        func shift(_ keyPath: KeyPath<DailyMetrics, Double?>, _ label: String, unit: String, decimals: Int = 0,
                   higherIsBetter: Bool?, duration: Bool = false) -> (String, String, Color)? {
            guard let a = Stats.mean(first.compactMap { $0[keyPath: keyPath] }),
                  let b = Stats.mean(last.compactMap { $0[keyPath: keyPath] }), a != 0 else { return nil }
            let change = (b - a) / abs(a) * 100
            guard abs(change) >= 2 else { return nil }
            let color: Color = higherIsBetter.map { (change > 0) == $0 ? Theme.good : Theme.bad } ?? Theme.textSecondary
            let from = duration ? DetailFormat.hoursMinutes(a) : "\(DetailFormat.decimal(a, decimals)) \(unit)"
            let to = duration ? DetailFormat.hoursMinutes(b) : "\(DetailFormat.decimal(b, decimals)) \(unit)"
            return (label, "\(from) → \(to)  (\(change > 0 ? "+" : "−")\(Int(abs(change).rounded()))%)", color)
        }
        let shifts = [
            shift(\.hrvSDNN, String(localized: "HRV"), unit: "ms", higherIsBetter: true),
            shift(\.restingHeartRate, String(localized: "Resting heart rate"), unit: "bpm", higherIsBetter: false),
            shift(\.sleepAsleepHours, String(localized: "Sleep"), unit: "", higherIsBetter: true, duration: true),
            shift(\.bodyMassKg, String(localized: "Weight"), unit: "kg", decimals: 1, higherIsBetter: nil)
        ].compactMap { $0 }
        let findings = Array(LagCorrelationMiner.mine(from: allDays.sorted { $0.date < $1.date }, tags: dayTags)
            .sorted { abs($0.correlation) > abs($1.correlation) }.prefix(3))

        return VStack(alignment: .leading, spacing: 0) {
            storyBanner("Compared with your own normal, from \(daysWithData) days of Watch data plus what you logged.")
            VStack(alignment: .leading, spacing: 16) {
                if !shifts.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("WHAT MOVED").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.textTertiary)
                        ForEach(Array(shifts.enumerated()), id: \.offset) { _, item in
                            HStack(alignment: .firstTextBaseline) {
                                Text(item.0).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Spacer(minLength: 8)
                                Text(item.1).font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(item.2)
                            }
                        }
                        Text("Averages of the first and last two weeks.").font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("WHAT SEEMS TO DRIVE IT").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.textTertiary)
                    if findings.isEmpty {
                        Text("No pattern is strong enough to call yet. More days of food, training and sleep logged together is what turns up the connections.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        ForEach(findings) { finding in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(LocalizedStringKey(finding.sentence))
                                    .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                HStack(spacing: 6) {
                                    storyTag(finding.strength, finding.isPositive ? Theme.good : Theme.bad)
                                    storyTag(String(localized: "\(finding.sampleSize) days of data"), Theme.textTertiary)
                                }
                            }
                        }
                    }
                }

                Text("Patterns in your own data, not proof of cause. Each one is a hypothesis worth testing for a couple of weeks.")
                    .font(.caption).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
    }

    private func storyTag(_ text: String, _ color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    // MARK: - This week

    private var week: [DailyMetrics] { Array(allDays.prefix(7)) }
    private var priorWeek: [DailyMetrics] { Array(allDays.dropFirst(7).prefix(7)) }

    private func average(_ keyPath: KeyPath<DailyMetrics, Double?>, in days: [DailyMetrics]) -> Double? {
        Stats.mean(days.compactMap { $0[keyPath: keyPath] })
    }

    /// "▲ 4% vs last week", or nil without a comparison.
    private func change(_ keyPath: KeyPath<DailyMetrics, Double?>, decimals: Int = 0, suffix: String = "%", absolute: Bool = false) -> String? {
        guard let now = average(keyPath, in: week), let before = average(keyPath, in: priorWeek), before != 0 else { return nil }
        let delta = absolute ? now - before : (now - before) / abs(before) * 100
        guard abs(delta) >= (absolute ? 0.5 : 1) else { return String(localized: "Same as last week") }
        let value = abs(delta).formatted(.number.precision(.fractionLength(decimals)))
        return "\(delta > 0 ? "▲" : "▼") \(value)\(suffix) " + String(localized: "vs last week")
    }

    private var weekSummarySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "This week", icon: .trainingLoad)
            let sessions = week.reduce(0) { $0 + $1.workoutCount }
            StatGrid(tiles: [
                StatTile(label: String(localized: "Sleep"),
                         value: average(\.sleepAsleepHours, in: week).map { DetailFormat.hoursMinutes($0) } ?? "—",
                         caption: change(\.sleepAsleepHours), glyph: .sleep),
                StatTile(label: String(localized: "HRV"),
                         value: average(\.hrvSDNN, in: week).map { DetailFormat.whole($0) } ?? "—", unit: "ms",
                         caption: change(\.hrvSDNN), glyph: .hrv),
                StatTile(label: String(localized: "Resting HR"),
                         value: average(\.restingHeartRate, in: week).map { DetailFormat.whole($0) } ?? "—", unit: "bpm",
                         caption: change(\.restingHeartRate), glyph: .heartRate),
                StatTile(label: String(localized: "Steps per day"),
                         value: average(\.steps, in: week).map { DetailFormat.whole($0) } ?? "—",
                         caption: change(\.steps), glyph: .steps),
                StatTile(label: String(localized: "Calories per day"),
                         value: average(\.dietaryEnergyKcal, in: week).map { DetailFormat.whole($0) } ?? "—", unit: "kcal",
                         caption: change(\.dietaryEnergyKcal), glyph: .energy),
                StatTile(label: String(localized: "Workouts"), value: "\(sessions)",
                         caption: sessions == 1 ? String(localized: "session in the last 7 days") : String(localized: "sessions in the last 7 days"),
                         glyph: .training)
            ])
        }
    }

    // MARK: - Consistency

    private var consistencySection: some View {
        let trainingDays = week.filter(\.hadWorkout).count
        let sleepNights = week.filter { ($0.sleepAsleepHours ?? 0) >= 7 }.count
        let loggedDays = week.filter { ($0.dietaryEnergyKcal ?? 0) > 0 }.count
        let stepDays = week.filter { ($0.steps ?? 0) >= 7_000 }.count
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Consistency", icon: .target)
            VStack(spacing: 16) {
                habit("Trained", trainingDays, of: 7, goal: 3, color: Theme.accent, detail: "days · aim for 3 or more")
                habit("Slept 7 hours or more", sleepNights, of: 7, goal: 5, color: Theme.mint, detail: "nights · aim for 5 or more")
                habit("Logged food", loggedDays, of: 7, goal: 6, color: Theme.carbs, detail: "days · the more you log, the better the estimates")
                habit("7,000+ steps", stepDays, of: 7, goal: 5, color: Theme.protein, detail: "days · aim for 5 or more")
            }
            .card(padding: 18)
        }
    }

    private func habit(_ title: LocalizedStringKey, _ count: Int, of total: Int, goal: Int, color: Color, detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(verbatim: "\(count)/\(total)")
                    .font(.subheadline.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(count >= goal ? Theme.good : Theme.textPrimary)
            }
            HStack(spacing: 4) {
                ForEach(0..<total, id: \.self) { i in
                    Capsule().fill(i < count ? color : color.opacity(0.14)).frame(height: 6)
                }
            }
            Text(detail).font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    // MARK: - Highlights

    private var highlightsSection: some View {
        let fortnight = Array(allDays.prefix(14))
        func best(_ keyPath: KeyPath<DailyMetrics, Double?>) -> (day: DailyMetrics, value: Double)? {
            fortnight.compactMap { day in day[keyPath: keyPath].map { (day, $0) } }.max { $0.1 < $1.1 }
        }
        func when(_ day: DailyMetrics) -> String { day.date.formatted(.dateTime.weekday(.wide).day().month(.abbreviated)) }
        let rows: [(Glyph, String, String, String)] = [
            best(\.sleepAsleepHours).map { (.sleep, String(localized: "Longest night"), DetailFormat.hoursMinutes($0.value), when($0.day)) },
            best(\.hrvSDNN).map { (.hrv, String(localized: "Highest HRV"), "\(DetailFormat.whole($0.value)) ms", when($0.day)) },
            best(\.steps).map { (.steps, String(localized: "Most active day"), "\(DetailFormat.whole($0.value)) steps", when($0.day)) },
            best(\.proteinGrams).map { (.protein, String(localized: "Most protein"), "\(DetailFormat.whole($0.value)) g", when($0.day)) }
        ].compactMap { $0 }

        return VStack(alignment: .leading, spacing: 10) {
            if !rows.isEmpty {
                SectionLabel(text: "Best of the last 2 weeks", icon: .spotlight)
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        if index > 0 { Divider().overlay(Theme.separator) }
                        HStack(spacing: 12) {
                            GlyphView(row.0, size: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.1).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text(row.3).font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            Text(row.2).font(.subheadline.weight(.semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                        }
                        .padding(.vertical, 12)
                    }
                }
                .padding(.horizontal, 16)
                .card(padding: 0)
            }
        }
    }

    // MARK: - Rule engine flags

    private var flagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "What stands out", icon: .spotlight)

            if flags.isEmpty {
                HStack(spacing: 12) {
                    GlyphView(.allClear, size: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nothing flagged")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("No thresholds crossed in the last two weeks.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .card()
            } else {
                ForEach(flags, id: \.title) { insight in
                    InsightCard(insight: insight)
                }
            }
        }
    }

    // MARK: - AI narrative

    private var narrativeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Weekly narrative", icon: .narrative)
                .overlay(alignment: .trailing) { PoweredByGemini() }

            VStack(alignment: .leading, spacing: 14) {
                if let latest = todaysNarrative {
                    NarrativeParagraphs(text: latest.text)

                    Text("Generated \(latest.generatedAt.formatted(.relative(presentation: .named)))")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                } else {
                    HStack(spacing: 12) {
                        GeminiMark(size: 26)
                        Text("Get a plain-language read on what this week's numbers actually mean.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Button {
                    Task { await generateNarrative() }
                } label: {
                    HStack(spacing: 8) {
                        if isGenerating {
                            ProgressView().tint(.white)
                        } else {
                            GeminiMark(size: 17)
                        }
                        Text(todaysNarrative == nil ? "Generate narrative" : "Regenerate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        LinearGradient(colors: [Theme.accentDeep, Theme.accent],
                                       startPoint: .leading, endPoint: .trailing),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                    )
                    .opacity(isGenerating || recentDays.isEmpty ? 0.55 : 1)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating || recentDays.isEmpty)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(Theme.bad)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .card(padding: 18)
        }
    }

    private func generateNarrative() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let input = NarrativeService.WeekSummaryInput(days: Array(recentDays.prefix(7)), insights: flags)
            let text = try await NarrativeService().generateWeeklyNarrative(input)

            let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            context.insert(WeeklyNarrative(weekStartDate: weekStart, text: text))
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Components

struct InsightCard: View {
    let insight: Insight

    private var color: Color {
        switch insight.severity {
        case .info:    Theme.accent
        case .notice:  Theme.warn
        case .warning: Theme.bad
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            GlyphTile(glyph: .topic(insight.category), color: color, size: 38)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(insight.detail)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card()
    }
}

/// The AI narrative, one paragraph per row beside its topic icon.
struct NarrativeParagraphs: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(NarrativeFormat.paragraphs(text).enumerated()), id: \.offset) { _, paragraph in
                HStack(alignment: .top, spacing: 11) {
                    if let glyph = paragraph.glyph {
                        GlyphView(glyph, size: 20)
                            .padding(.top, 1)
                    }
                    Text(paragraph.body)
                        .font(.callout)
                        .foregroundStyle(Theme.textPrimary)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

}

#Preview {
    InsightsView()
        .modelContainer(for: [DailyMetrics.self, Insight.self, WeeklyNarrative.self], inMemory: true)
}
