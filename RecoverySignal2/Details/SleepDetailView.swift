//
//  SleepDetailView.swift
//  RecoverySignal2
//
//  Everything about sleep: last night's stage timeline (hypnogram), how the
//  night split between stages, stages night by night, how regular your
//  bedtime and wake time are, and accumulated sleep debt.
//

import SwiftUI
import SwiftData
import Charts

private enum StageStyle {
    static let order: [HealthKitManager.SleepStage] = [.awake, .rem, .core, .deep]

    static func name(_ stage: HealthKitManager.SleepStage) -> String {
        switch stage {
        case .awake: "Awake"
        case .rem:   "REM"
        case .core:  "Core"
        case .deep:  "Deep"
        }
    }

    static func color(_ stage: HealthKitManager.SleepStage) -> Color {
        switch stage {
        case .awake: Theme.warn
        case .rem:   Theme.sleepREM
        case .core:  Theme.sleepCore
        case .deep:  Theme.sleepDeep
        }
    }
}

struct SleepDetailView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]
    @State private var range: DetailRange = .twoWeeks
    @State private var part: Part = .lastNight

    /// Last night, tonight's plan and the history are three separate views of sleep.
    private enum Part: String, CaseIterable, Identifiable {
        case lastNight, tonight, history
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .lastNight: "Last night"
            case .tonight:   "Tonight"
            case .history:   "History"
            }
        }
    }
    @State private var segments: [HealthKitManager.SleepSegment] = []
    @State private var loadedSegments = false
    @State private var nightHeartRate: [TrendPoint] = []

    private var nights: [DailyMetrics] { allDays.filter { ($0.sleepAsleepHours ?? 0) > 0 } }
    private var lastNight: DailyMetrics? { nights.last }
    private var rangeNights: [DailyMetrics] { Array(nights.suffix(range.rawValue)) }

    var body: some View {
        DetailPage(title: String(localized: "Sleep")) {
            Picker("Section", selection: $part.animation(.snappy)) {
                ForEach(Part.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)

            switch part {
            case .lastNight:
                hero
                hypnogramCard
                stageBreakdownCard
                sleepNeedCard
            case .tonight:
                TonightPlanCard(days: allDays)
            case .history:
                RangePicker(range: $range)
                stats
                nightlyStagesCard
                scheduleCard
                debtCard
            }
        }
        .task(id: lastNight?.date) {
            guard let day = lastNight?.date else { return }
            segments = (try? await HealthKitManager.shared.sleepSegments(forNightEnding: day)) ?? []
            loadedSegments = true
            if let window = nightWindow {
                nightHeartRate = ((try? await HealthKitManager.shared.heartRateSamples(from: window.lowerBound, to: window.upperBound)) ?? [])
                    .map { TrendPoint(date: $0.date, value: $0.bpm) }
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let night = lastNight
        let efficiency = efficiencyPercent(night)
        let times: String = {
            guard let start = night?.sleepStart, let end = night?.sleepEnd else { return "Last night" }
            return "\(start.formatted(date: .omitted, time: .shortened)) → \(end.formatted(date: .omitted, time: .shortened))"
        }()
        return DetailHero(
            glyph: .sleep,
            eyebrow: String(localized: "Last night"),
            value: DetailFormat.hoursMinutes(night?.sleepAsleepHours ?? 0),
            caption: efficiency.map { "\(times) · \($0)% efficiency" } ?? times,
            colors: [Theme.sleepNight, Theme.sleepDeep]
        ) {
            if let night, let asleep = night.sleepAsleepHours {
                let need = SleepNeedModel.need(forNightEnding: night.date, days: allDays)
                let performance = SleepNeedModel.performance(asleep: asleep, need: need)
                ZStack {
                    Circle().stroke(Theme.track, lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: performance)
                        .stroke(Theme.sleepREM, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        RingValueText(text: "\(Int((performance * 100).rounded()))%", size: 18, color: Theme.textPrimary)
                        Text("of need")
                            .font(.system(size: 9))
                            .opacity(0.8)
                    }
                    .foregroundStyle(Theme.textPrimary)
                }
                .frame(width: 78, height: 78)
            }
        }
    }

    // MARK: Hypnogram

    private var hypnogramCard: some View {
        ChartCard(title: String(localized: "Last night, stage by stage"),
                  subtitle: String(localized: "Each bar is a stretch of time in that stage. Deep sleep clusters early in the night, REM later.")) {
            if segments.isEmpty {
                Text(loadedSegments ? "No stage data for last night — stages need an Apple Watch worn to bed." : "Loading…")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart {
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        RectangleMark(
                            xStart: .value("Start", segment.start),
                            xEnd: .value("End", segment.end),
                            y: .value("Stage", StageStyle.name(segment.stage))
                        )
                        .foregroundStyle(StageStyle.color(segment.stage))
                        .cornerRadius(3)
                    }
                }
                .chartYScale(domain: StageStyle.order.map { StageStyle.name($0) })
                .chartXAxis {
                    AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel(format: .dateTime.hour())
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks { _ in
                        AxisValueLabel()
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .chartXScale(domain: nightWindow ?? Date()...Date())
                .frame(height: 180)

                heartRateOverlay
            }
        }
    }

    // MARK: Overnight heart rate

    /// The span of last night, padded slightly, shared by both charts so
    /// stages and heart rate line up minute for minute.
    private var nightWindow: ClosedRange<Date>? {
        let start = segments.first?.start ?? lastNight?.sleepStart
        let end = segments.map(\.end).max() ?? lastNight?.sleepEnd
        guard let start, let end, end > start else { return nil }
        return start.addingTimeInterval(-600)...end.addingTimeInterval(600)
    }

    @ViewBuilder
    private var heartRateOverlay: some View {
        let lowest = nightHeartRate.min { $0.value < $1.value }
        let average = Stats.mean(nightHeartRate.map(\.value))

        Divider().overlay(Theme.separator)

        HStack(alignment: .firstTextBaseline) {
            HStack(spacing: 5) {
                GlyphView(.heartRate, size: 15, palette: .mono(Theme.bad, soft: 0.2))
                Text("Heart rate")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Text("Your heart rate should drift down through the night — the lowest point usually falls in deep sleep.")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 190, alignment: .trailing)
        }

        if nightHeartRate.count < 2 {
            Text("No overnight heart rate recorded.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        } else {
            let values = nightHeartRate.map(\.value)
            let lo = (values.min() ?? 40) - 4, hi = (values.max() ?? 90) + 4
            Chart {
                ForEach(nightHeartRate) { point in
                    AreaMark(x: .value("Time", point.date), yStart: .value("Base", lo), yEnd: .value("bpm", point.value))
                        .foregroundStyle(LinearGradient(colors: [Theme.bad.opacity(0.22), Theme.bad.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.linear)
                    LineMark(x: .value("Time", point.date), y: .value("bpm", point.value))
                        .foregroundStyle(Theme.bad.opacity(0.8))
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineJoin: .round))
                        .interpolationMethod(.linear)
                }
                if let lowest {
                    PointMark(x: .value("Time", lowest.date), y: .value("bpm", lowest.value))
                        .foregroundStyle(Theme.bad)
                        .symbolSize(60)
                        .annotation(position: .bottom, spacing: 2) {
                            Text("\(Int(lowest.value))")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.bad)
                        }
                }
            }
            .chartXScale(domain: nightWindow ?? Date()...Date())
            .chartYScale(domain: lo...hi)
            .chartXAxis {
                AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel(format: .dateTime.hour()).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 120)

            HStack {
                nightStat(String(localized: "Lowest"), lowest.map { "\(Int($0.value)) bpm" } ?? "—")
                Spacer()
                nightStat(String(localized: "Average"), average.map { "\(Int($0.rounded())) bpm" } ?? "—")
                Spacer()
                nightStat(String(localized: "Breathing"), lastNight?.respiratoryRate.map { "\($0.formatted(.number.precision(.fractionLength(1)))) /min" } ?? "—")
            }
        }
    }

    private func nightStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.textTertiary)
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: Sleep need

    private var sleepNeedCard: some View {
        let need = lastNight.map { SleepNeedModel.need(forNightEnding: $0.date, days: allDays) }
        let asleep = lastNight?.sleepAsleepHours ?? 0
        let performance = need.map { SleepNeedModel.performance(asleep: asleep, need: $0) }

        return ChartCard(title: String(localized: "Last night's need"),
                         subtitle: String(localized: "Your baseline, plus extra after a hard day and for sleep debt, minus any nap.")) {
            if let need {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DetailFormat.hoursMinutes(need.total))
                        .font(.system(size: 30, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("needed")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                    Spacer()
                    if let performance {
                        Text("\(Int((performance * 100).rounded()))% met")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(performance >= 0.85 ? Theme.good : (performance >= 0.7 ? Theme.warn : Theme.bad))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background((performance >= 0.85 ? Theme.good : (performance >= 0.7 ? Theme.warn : Theme.bad)).opacity(0.12), in: Capsule())
                    }
                }

                GeometryReader { geo in
                    let scale = geo.size.width / max(need.total, asleep, 0.1)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 2) {
                            needSegment(need.baseline * scale, Theme.sleepDeep)
                            if need.debtExtra > 0 { needSegment(need.debtExtra * scale, Theme.warn) }
                            if need.strainExtra > 0 { needSegment(need.strainExtra * scale, Theme.sleepCore) }
                        }
                        Capsule()
                            .fill(Theme.sleepREM)
                            .frame(width: max(4, asleep * scale), height: 10)
                    }
                }
                .frame(height: 30)

                VStack(spacing: 8) {
                    LegendRow(color: Theme.sleepDeep, label: String(localized: "Baseline"), value: DetailFormat.hoursMinutes(need.baseline))
                    LegendRow(color: Theme.warn, label: String(localized: "Sleep debt catch-up"), value: need.debtExtra > 0 ? "+" + DetailFormat.hoursMinutes(need.debtExtra) : "—")
                    LegendRow(color: Theme.sleepCore, label: String(localized: "Yesterday's strain"), value: need.strainExtra > 0 ? "+" + DetailFormat.hoursMinutes(need.strainExtra) : "—")
                    LegendRow(color: Theme.good, label: String(localized: "Nap credit"), value: need.napCredit > 0 ? "−" + DetailFormat.hoursMinutes(need.napCredit) : "—")
                    LegendRow(color: Theme.sleepREM, label: String(localized: "Actually slept"), value: DetailFormat.hoursMinutes(asleep))
                }
            }
        }
    }

    private func needSegment(_ width: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(color)
            .frame(width: max(width, 3), height: 10)
    }

    // MARK: Stage breakdown

    private struct StageSlice: Identifiable {
        let id = UUID()
        let stage: HealthKitManager.SleepStage
        let hours: Double
    }

    private var slices: [StageSlice] {
        guard let night = lastNight, let asleep = night.sleepAsleepHours else { return [] }
        let deep = night.sleepDeepHours ?? 0
        let rem = night.sleepREMHours ?? 0
        return [
            StageSlice(stage: .deep, hours: deep),
            StageSlice(stage: .core, hours: max(asleep - deep - rem, 0)),
            StageSlice(stage: .rem, hours: rem),
            StageSlice(stage: .awake, hours: night.sleepAwakeHours ?? 0)
        ].filter { $0.hours > 0 }
    }

    private var stageBreakdownCard: some View {
        let total = slices.reduce(0) { $0 + $1.hours }
        return ChartCard(title: String(localized: "Where the night went")) {
            HStack(spacing: 18) {
                Chart(slices) { slice in
                    SectorMark(angle: .value("Hours", slice.hours), innerRadius: .ratio(0.64), angularInset: 2)
                        .foregroundStyle(StageStyle.color(slice.stage))
                        .cornerRadius(4)
                }
                .chartLegend(.hidden)
                .frame(width: 130, height: 130)
                .overlay {
                    VStack(spacing: 0) {
                        Text(DetailFormat.hoursMinutes(total))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("in bed")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                VStack(spacing: 10) {
                    ForEach(slices) { slice in
                        LegendRow(color: StageStyle.color(slice.stage),
                                  label: StageStyle.name(slice.stage),
                                  value: "\(Int((slice.hours / max(total, 0.01) * 100).rounded()))% · \(DetailFormat.hoursMinutes(slice.hours))")
                    }
                }
            }
        }
    }

    // MARK: Stats

    private var stats: some View {
        let asleep = rangeNights.compactMap(\.sleepAsleepHours)
        let deepShare = rangeNights.compactMap { n -> Double? in
            guard let a = n.sleepAsleepHours, a > 0, let d = n.sleepDeepHours else { return nil }
            return d / a * 100
        }
        let remShare = rangeNights.compactMap { n -> Double? in
            guard let a = n.sleepAsleepHours, a > 0, let r = n.sleepREMHours else { return nil }
            return r / a * 100
        }
        let efficiency = rangeNights.compactMap { efficiencyPercent($0).map(Double.init) }

        return StatGrid(tiles: [
            StatTile(label: String(localized: "Average asleep"), value: DetailFormat.hoursMinutes(Stats.mean(asleep) ?? 0), glyph: .sleep),
            StatTile(label: String(localized: "Efficiency"), value: efficiency.isEmpty ? "—" : DetailFormat.whole(Stats.mean(efficiency) ?? 0), unit: "%",
                     caption: String(localized: "Time asleep ÷ time in bed")),
            StatTile(label: String(localized: "Deep sleep"), value: deepShare.isEmpty ? "—" : DetailFormat.whole(Stats.mean(deepShare) ?? 0), unit: "%",
                     caption: String(localized: "Typical adult range 13–23%"), glyph: .deepSleep),
            StatTile(label: String(localized: "REM sleep"), value: remShare.isEmpty ? "—" : DetailFormat.whole(Stats.mean(remShare) ?? 0), unit: "%",
                     caption: String(localized: "Typical adult range 20–25%"), glyph: .remSleep)
        ])
    }

    // MARK: Nightly stages

    private struct StageBar: Identifiable {
        let id = UUID()
        let date: Date
        let stage: String
        let hours: Double
    }

    private var nightlyStagesCard: some View {
        let bars: [StageBar] = rangeNights.flatMap { night -> [StageBar] in
            let asleep = night.sleepAsleepHours ?? 0
            let deep = night.sleepDeepHours ?? 0
            let rem = night.sleepREMHours ?? 0
            return [
                StageBar(date: night.date, stage: "Deep", hours: deep),
                StageBar(date: night.date, stage: "Core", hours: max(asleep - deep - rem, 0)),
                StageBar(date: night.date, stage: "REM", hours: rem)
            ]
        }
        return ChartCard(title: String(localized: "Night by night"), subtitle: String(localized: "Stacked stages each night against an 8-hour target.")) {
            Chart {
                ForEach(bars) { bar in
                    BarMark(x: .value("Night", bar.date, unit: .day), y: .value("Hours", bar.hours))
                        .foregroundStyle(by: .value("Stage", bar.stage))
                        .cornerRadius(2)
                }
                RuleMark(y: .value("Target", 8))
                    .foregroundStyle(Theme.textSecondary)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .trailing) {
                        Text("8h").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.textSecondary)
                    }
            }
            .chartForegroundStyleScale(domain: ["Deep", "Core", "REM"], range: [Theme.sleepDeep, Theme.sleepCore, Theme.sleepREM])
            .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: [0, 4, 8, 10]) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator)
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: 210)
        }
    }

    // MARK: Schedule

    /// Hours relative to midnight: 23:30 → −0.5, 07:15 → 7.25.
    private func clockOffset(_ date: Date) -> Double {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        let hours = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60
        return hours >= 15 ? hours - 24 : hours
    }

    private func clockLabel(_ offset: Double) -> String {
        let hour = (Int(offset.rounded()) + 24) % 24
        return String(format: "%02d:00", hour)
    }

    private var scheduleCard: some View {
        let recent = Array(rangeNights.filter { $0.sleepStart != nil && $0.sleepEnd != nil }.suffix(21))
        let bedtimes = recent.compactMap { $0.sleepStart.map(clockOffset) }
        let wakes = recent.compactMap { $0.sleepEnd.map(clockOffset) }
        let spread = Stats.standardDeviation(bedtimes).map { Int(($0 * 60).rounded()) }

        return ChartCard(title: String(localized: "Sleep schedule"),
                         subtitle: spread.map { "Bedtime varies by about ±\($0) min. Under ±30 min is considered consistent." }) {
            if recent.isEmpty {
                Text("Bedtime and wake times appear once a few nights have synced.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            } else {
                Chart {
                    ForEach(recent, id: \.date) { night in
                        if let start = night.sleepStart, let end = night.sleepEnd {
                            BarMark(xStart: .value("Asleep", clockOffset(start)),
                                    xEnd: .value("Awake", clockOffset(end)),
                                    y: .value("Night", night.date, unit: .day))
                                .foregroundStyle(LinearGradient(colors: [Theme.sleepDeep, Theme.sleepREM],
                                                                startPoint: .leading, endPoint: .trailing))
                                .cornerRadius(4)
                        }
                    }
                    if let avgBed = Stats.mean(bedtimes) {
                        RuleMark(x: .value("Avg bedtime", avgBed))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                    if let avgWake = Stats.mean(wakes) {
                        RuleMark(x: .value("Avg wake", avgWake))
                            .foregroundStyle(Theme.textSecondary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }
                }
                .chartXScale(domain: -4...11)
                .chartXAxis {
                    AxisMarks(values: [-4, -2, 0, 2, 4, 6, 8, 10]) { value in
                        AxisGridLine().foregroundStyle(Theme.separator)
                        AxisValueLabel {
                            if let v = value.as(Double.self) {
                                Text(clockLabel(v)).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                    }
                }
                .chartYAxis {
                    AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                        AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: CGFloat(max(recent.count, 5)) * 16 + 40)

                HStack {
                    if let avgBed = Stats.mean(bedtimes) {
                        scheduleStat(String(localized: "Average bedtime"), clockText(avgBed))
                    }
                    Spacer()
                    if let avgWake = Stats.mean(wakes) {
                        scheduleStat(String(localized: "Average wake-up"), clockText(avgWake))
                    }
                }
            }
        }
    }

    private func clockText(_ offset: Double) -> String {
        let minutes = Int((offset * 60).rounded())
        let normalized = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    private func scheduleStat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(label)).font(.caption).foregroundStyle(Theme.textTertiary)
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: Debt

    private var debtCard: some View {
        let debt = ReadinessModel.sleepDebt(from: allDays)
        let hours = debt?.hours ?? 0
        let color: Color = hours >= 5 ? Theme.bad : (hours >= 3 ? Theme.warn : Theme.good)

        return ChartCard(title: String(localized: "Sleep debt"),
                         subtitle: String(localized: "Shortfall against 8 hours over the last 14 nights. A long night pays back at most an hour.")) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(DetailFormat.decimal(hours))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(color)
                    Text("hours")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Gauge(value: min(hours, 10), in: 0...10) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                } minimumValueLabel: {
                    Text("0h").font(.caption2).foregroundStyle(Theme.textTertiary)
                } maximumValueLabel: {
                    Text("10h").font(.caption2).foregroundStyle(Theme.textTertiary)
                }
                .gaugeStyle(.linearCapacity)
                .tint(LinearGradient(colors: [Theme.good, Theme.warn, Theme.bad], startPoint: .leading, endPoint: .trailing))
            }
        }
    }

    // MARK: Helpers

    private func efficiencyPercent(_ night: DailyMetrics?) -> Int? {
        guard let asleep = night?.sleepAsleepHours, let inBed = night?.sleepDurationHours, inBed > 0 else { return nil }
        return Int((min(asleep / inBed, 1) * 100).rounded())
    }
}
