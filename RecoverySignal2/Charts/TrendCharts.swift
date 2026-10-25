//
//  TrendCharts.swift
//  RecoverySignal2
//
//  The chart vocabulary used by Today and Trends. Each metric gets the chart
//  that suits what kind of number it is, rather than one style for everything:
//
//   • Totals per day (sleep, steps, calories, protein, training) → bars from
//     zero, because the length of the bar IS the amount, plus a dashed average.
//   • Physiological signals judged against your own normal (HRV, resting HR,
//     breathing rate) → faint daily dots, a 7-day average line and a shaded
//     band for your normal range.
//   • Noisy measurements of a slow-moving state (body weight) → dots for the
//     scale readings and a smoothed "trend weight" line through them.
//   • Scores with meaningful zones (recovery, strain) → bars coloured by zone.
//   • Sparse estimates (VO₂ max) → dots joined by a line.
//
//  Long ranges roll bars up into weekly or monthly averages so a year of
//  steps is 12 readable bars rather than 365 slivers.
//

import SwiftUI
import Charts

// MARK: - Ranges

enum TrendRange: Int, CaseIterable, Identifiable {
    case week = 7, twoWeeks = 14, month = 30, quarter = 91, half = 182, year = 365

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .week:     String(localized: "7D")
        case .twoWeeks: String(localized: "14D")
        case .month:    String(localized: "1M")
        case .quarter:  String(localized: "3M")
        case .half:     String(localized: "6M")
        case .year:     String(localized: "1Y")
        }
    }

    var longLabel: String {
        switch self {
        case .week:     "7-day"
        case .twoWeeks: "14-day"
        case .month:    "1-month"
        case .quarter:  "3-month"
        case .half:     "6-month"
        case .year:     "1-year"
        }
    }

    /// How bars are grouped at this range.
    var bucket: TrendBucket {
        switch self {
        case .week, .twoWeeks, .month: .day
        case .quarter, .half:          .week
        case .year:                    .month
        }
    }

    func startDate(from end: Date = Date(), calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -(rawValue - 1), to: calendar.startOfDay(for: end)) ?? end
    }

    /// Ranges offered as "compare with" references.
    static let comparisons: [TrendRange] = [.month, .quarter, .half, .year]
}

enum TrendBucket {
    case day, week, month

    var calendarUnit: Calendar.Component {
        switch self {
        case .day:   .day
        case .week:  .weekOfYear
        case .month: .month
        }
    }

    func start(of date: Date, calendar: Calendar = .current) -> Date {
        switch self {
        case .day:   calendar.startOfDay(for: date)
        case .week:  calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
        case .month: calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
        }
    }

    func caption(for date: Date) -> String {
        switch self {
        case .day:   date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .week:  String(localized: "Week of \(date.formatted(.dateTime.day().month(.abbreviated))) · avg/day")
        case .month: String(localized: "\(date.formatted(.dateTime.month(.wide).year())) · avg/day")
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .day, .week: .dateTime.day().month(.abbreviated)
        case .month:      .dateTime.month(.abbreviated)
        }
    }
}

extension Array where Element == TrendPoint {
    /// Points inside a range ending today.
    func within(_ range: TrendRange) -> [TrendPoint] {
        let start = range.startDate()
        return filter { $0.date >= start && $0.date <= Date() && $0.value.isFinite }
    }

    /// Mean per day / week / month, dated at the start of each bucket.
    func bucketed(_ bucket: TrendBucket) -> [TrendPoint] {
        guard bucket != .day else { return self }
        let groups = Dictionary(grouping: self) { bucket.start(of: $0.date) }
        return groups
            .map { TrendPoint(date: $0.key, value: $0.value.reduce(0) { $0 + $1.value } / Double($0.value.count)) }
            .sorted { $0.date < $1.date }
    }

    var mean: Double? { Stats.mean(map(\.value)) }
}

// MARK: - Value formatting

struct ValueStyle {
    var unit: String = ""
    var decimals: Int = 0
    /// Hours shown as "7h 12m".
    var duration = false

    func number(_ value: Double) -> String {
        duration ? DetailFormat.hoursMinutes(value) : value.formatted(.number.precision(.fractionLength(decimals)))
    }

    /// Unit to print after `number`, empty for durations.
    var suffix: String { duration ? "" : unit }

    func full(_ value: Double) -> String {
        suffix.isEmpty ? number(value) : String(localized: "\(number(value)) \(suffix)")
    }
}

// MARK: - Card shell with its own range switch

/// A titled card whose range switch sits on the card itself, so changing one
/// chart never means scrolling back to the top. The choice is remembered.
struct TrendCard<Content: View>: View {
    let title: String
    var glyph: Glyph? = nil
    /// One line on how to read this chart.
    var note: String? = nil
    let style: ValueStyle
    let daily: [TrendPoint]
    var higherIsBetter: Bool? = nil
    /// Opens from the ⓘ in the header.
    var explainer: Explainer? = nil
    @ViewBuilder let content: (TrendRange) -> Content

    @AppStorage private var storedRange: Int
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(title: String, glyph: Glyph? = nil, explainer: Explainer? = nil, note: String? = nil, style: ValueStyle,
         daily: [TrendPoint], higherIsBetter: Bool? = nil,
         defaultRange: TrendRange = .month,
         @ViewBuilder content: @escaping (TrendRange) -> Content) {
        self.explainer = explainer
        self.title = title
        self.glyph = glyph
        self.note = note
        self.style = style
        self.daily = daily
        self.higherIsBetter = higherIsBetter
        self.content = content
        _storedRange = AppStorage(wrappedValue: defaultRange.rawValue, "trendRange.\(title)")
    }

    private var range: TrendRange { TrendRange(rawValue: storedRange) ?? .month }

    /// Average of the range against the same-length stretch before it.
    private var changePercent: Double? {
        let calendar = Calendar.current
        let start = range.startDate()
        guard let previousStart = calendar.date(byAdding: .day, value: -range.rawValue, to: start) else { return nil }
        let current = daily.within(range)
        let previous = daily.filter { $0.date >= previousStart && $0.date < start }
        guard current.count >= 3, previous.count >= 3,
              let a = current.mean, let b = previous.mean, b != 0 else { return nil }
        return (a - b) / abs(b) * 100
    }

    var body: some View {
        let visible = daily.within(range)
        let recordedDays = Set(visible.map { Calendar.current.startOfDay(for: $0.date) }).count
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                if let glyph { GlyphView(glyph, size: 20) }
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                if let explainer { InfoButton(explainer: explainer) }
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(visible.mean.map { style.full($0) } ?? "—")
                        .font(.title2.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("Average")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 4) {
                    DeltaChip(percent: changePercent, higherIsBetter: higherIsBetter)
                    if changePercent != nil {
                        Text("vs previous period")
                            .font(.caption2)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }

            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    rangePicker.pickerStyle(.menu)
                } else {
                    rangePicker.pickerStyle(.segmented)
                }
            }
            .sensoryFeedback(.selection, trigger: storedRange)

            content(range)
                .padding(.top, 6)

            Label("\(recordedDays) of \(range.rawValue) days recorded", systemImage: "calendar")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)

            if let note {
                DisclosureGroup("How to read this chart") {
                    Text(LocalizedStringKey(note))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 6)
                }
                .font(.caption.weight(.medium))
                .tint(Theme.textSecondary)
            }
        }
        .card(padding: 20)
    }

    private var rangePicker: some View {
        Picker("Range", selection: $storedRange) {
            ForEach(TrendRange.allCases) { Text($0.label).tag($0.rawValue) }
        }
    }
}

// MARK: - Bars with average and comparison

/// Daily totals as bars from zero with a dashed average line. Optionally a
/// column on the left compares this range with a longer average you pick
/// (1, 3, 6 months or a year).
struct BarTrendChart: View {
    /// Daily values across all history, oldest first.
    let history: [TrendPoint]
    let range: TrendRange
    let style: ValueStyle
    var color: Color = Theme.accent
    /// Colour per bar value, for zone-coloured scores.
    var barColor: ((Double) -> Color)? = nil
    var showsAverage = true
    var compare = false
    var target: (value: Double, label: String)? = nil
    /// Fixed y ceiling, for bounded scores like strain or recovery.
    var ceiling: Double? = nil
    var guides: [Double] = []
    var height: CGFloat = 180
    var showsXAxis = true
    var compareStorageKey: String = "compare"

    @State private var selectedDate: Date?
    @AppStorage private var compareRaw: Int

    init(history: [TrendPoint], range: TrendRange, style: ValueStyle, color: Color = Theme.accent,
         barColor: ((Double) -> Color)? = nil, showsAverage: Bool = true, compare: Bool = false,
         target: (value: Double, label: String)? = nil, ceiling: Double? = nil, guides: [Double] = [],
         height: CGFloat = 180, showsXAxis: Bool = true, compareStorageKey: String = "compare") {
        self.history = history
        self.range = range
        self.style = style
        self.color = color
        self.barColor = barColor
        self.showsAverage = showsAverage
        self.compare = compare
        self.target = target
        self.ceiling = ceiling
        self.guides = guides
        self.height = height
        self.showsXAxis = showsXAxis
        _compareRaw = AppStorage(wrappedValue: TrendRange.half.rawValue, "compareRange.\(compareStorageKey)")
    }

    private var compareRange: TrendRange { TrendRange(rawValue: compareRaw) ?? .half }
    private var daily: [TrendPoint] { history.within(range) }
    private var bars: [TrendPoint] { daily.bucketed(range.bucket) }
    private var average: Double? { daily.mean }
    private var compareAverage: Double? { compare ? history.within(compareRange).mean : nil }

    private var domainTop: Double {
        if let ceiling { return ceiling }
        let top = [bars.map(\.value).max(), compareAverage, target?.value, average].compactMap { $0 }.max() ?? 1
        return max(top * 1.15, 0.0001)
    }

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        return bars.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        if daily.isEmpty {
            EmptyChart(height: height)
        } else {
            HStack(alignment: .top, spacing: 12) {
                if compare, let compareAverage {
                    compareColumn(compareAverage)
                }
                mainChart
            }
        }
    }

    private var mainChart: some View {
        Chart {
            ForEach(guides, id: \.self) { guide in
                RuleMark(y: .value("Guide", guide))
                    .foregroundStyle(Theme.separator)
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
            }

            ForEach(bars) { bar in
                let isLast = bar.id == bars.last?.id
                BarMark(x: .value("Date", bar.date, unit: range.bucket.calendarUnit),
                        y: .value("Value", bar.value))
                    .foregroundStyle(fill(for: bar.value, isLast: isLast))
                    .cornerRadius(bars.count > 40 ? 1 : 3)
                    .opacity(selected == nil || selected?.id == bar.id ? 1 : 0.4)
            }

            if let target {
                RuleMark(y: .value("Target", target.value))
                    .foregroundStyle(Theme.good)
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 3]))
                    .annotation(position: .top, alignment: .trailing, spacing: 2) {
                        Text("\(target.label) \(style.number(target.value))")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.good)
                    }
            }

            if showsAverage, let average {
                RuleMark(y: .value("Average", average))
                    .foregroundStyle(Theme.textPrimary.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text("avg \(style.number(average))")
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 4)
                            .background(Theme.surface.opacity(0.85), in: Capsule())
                    }
            }

            if let selected {
                RuleMark(x: .value("Date", selected.date, unit: range.bucket.calendarUnit))
                    .foregroundStyle(Theme.textSecondary.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .annotation(position: .top, spacing: 0,
                                overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                        ChartCallout(point: selected, unit: style.suffix, decimals: style.decimals,
                                     valueText: style.number(selected.value),
                                     dateText: range.bucket.caption(for: selected.date))
                    }
            }
        }
        .chartYScale(domain: 0...domainTop)
        .chartXSelection(value: $selectedDate)
        .onChange(of: range) { _, _ in selectedDate = nil }
        .sensoryFeedback(.selection, trigger: selected?.id)
        .chartXAxis {
            if showsXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: range.bucket.axisFormat)
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.separator.opacity(0.7))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(style.duration ? String(localized: "\(Int(v.rounded()))h") : compact(v))
                    }
                }
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(height: height)
    }

    /// The reference bar on the left: a longer-term average to hold this range against.
    private func compareColumn(_ value: Double) -> some View {
        VStack(spacing: 4) {
            Menu {
                Picker("Compare with", selection: $compareRaw) {
                    ForEach(TrendRange.comparisons) { Text("\($0.longLabel) average").tag($0.rawValue) }
                }
            } label: {
                HStack(spacing: 2) {
                    Text("\(compareRange.label) avg")
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 7, weight: .bold))
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Theme.accent.opacity(0.1), in: Capsule())
                .fixedSize()
            }

            Chart {
                BarMark(x: .value("Series", "ref"), y: .value("Value", value), width: .fixed(26))
                    .foregroundStyle(Theme.textSecondary.opacity(0.35))
                    .cornerRadius(3)
                if let average {
                    RuleMark(y: .value("Average", average))
                        .foregroundStyle(Theme.textPrimary.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [4, 3]))
                }
            }
            .chartYScale(domain: 0...domainTop)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(width: 44, height: height - (showsXAxis ? 18 : 0) - 24)

            Text(style.number(value))
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let average, value != 0 {
                let diff = (average - value) / abs(value) * 100
                Text("now \(diff >= 0 ? "+" : "−")\(Int(abs(diff).rounded()))%")
                    .font(.system(size: 9, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(width: 58)
    }

    private func fill(for value: Double, isLast: Bool) -> AnyShapeStyle {
        if let barColor { return AnyShapeStyle(barColor(value)) }
        return AnyShapeStyle(LinearGradient(colors: [color.opacity(isLast ? 1 : 0.8), color.opacity(0.45)],
                                            startPoint: .top, endPoint: .bottom))
    }
}

// MARK: - Line against your normal range

/// Faint daily readings, a 7-day average line and a shaded band for your
/// normal range (trailing 30-day mean ± 1 SD).
struct BaselineLineChart: View {
    let history: [TrendPoint]
    let range: TrendRange
    let style: ValueStyle
    var color: Color = Theme.accent
    var height: CGFloat = 180

    @State private var selectedDate: Date?

    struct BandPoint: Identifiable {
        var id: Date { date }
        let date: Date
        let average: Double
        let low: Double?
        let high: Double?
    }

    /// Rolling 7-day average and trailing 30-day band for every day in history.
    static func band(for history: [TrendPoint]) -> [BandPoint] {
        history.indices.map { i in
            let day = history[i].date
            let week = history[...i].reversed().prefix { $0.date > day.addingTimeInterval(-7 * 86_400) }.map(\.value)
            let month = history[..<i].reversed().prefix { $0.date > day.addingTimeInterval(-30 * 86_400) }.map(\.value)
            let mean = Stats.mean(month)
            let sd = Stats.standardDeviation(month)
            let hasBand = month.count >= 7
            return BandPoint(date: day, average: Stats.mean(week) ?? history[i].value,
                             low: hasBand ? mean.flatMap { m in sd.map { m - $0 } } : nil,
                             high: hasBand ? mean.flatMap { m in sd.map { m + $0 } } : nil)
        }
    }

    private var start: Date { range.startDate() }
    private var daily: [TrendPoint] { history.within(range) }
    private var bandPoints: [BandPoint] { Self.band(for: history).filter { $0.date >= start } }

    private var domain: ClosedRange<Double> {
        let values = daily.map(\.value) + bandPoints.flatMap { [$0.low, $0.high].compactMap { $0 } }
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.15, abs(hi) * 0.02, 0.5)
        return (lo - pad)...(hi + pad)
    }

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        return daily.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        if daily.count < 2 {
            EmptyChart(height: height)
        } else {
            let bands = bandPoints
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(bands.filter { $0.low != nil }) { p in
                        AreaMark(x: .value("Date", p.date),
                                 yStart: .value("Low", p.low ?? 0),
                                 yEnd: .value("High", p.high ?? 0),
                                 series: .value("Series", "Normal"))
                            .interpolationMethod(.linear)
                            .foregroundStyle(color.opacity(0.12))
                    }
                    ForEach(daily) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                            .symbolSize(range.rawValue > 91 ? 8 : 18)
                            .foregroundStyle(color.opacity(selected == nil || selected?.id == p.id ? 0.45 : 0.2))
                    }
                    ForEach(bands) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Average", p.average),
                                 series: .value("Series", "Average"))
                            .interpolationMethod(.linear)
                            .foregroundStyle(color)
                            .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                    }
                    if let selected {
                        RuleMark(x: .value("Date", selected.date))
                            .foregroundStyle(Theme.textTertiary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartCallout(point: selected, unit: style.suffix, decimals: style.decimals)
                            }
                        PointMark(x: .value("Date", selected.date), y: .value("Value", selected.value))
                            .symbolSize(80)
                            .foregroundStyle(Theme.accentDeep)
                    }
                }
                .chartYScale(domain: domain)
                .chartXSelection(value: $selectedDate)
        .onChange(of: range) { _, _ in selectedDate = nil }
                .sensoryFeedback(.selection, trigger: selected?.id)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: range.bucket.axisFormat)
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator.opacity(0.7))
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: height)

                HStack(spacing: 14) {
                    ChartLegendKey(kind: .dot, color: color.opacity(0.45), label: String(localized: "Daily"))
                    ChartLegendKey(kind: .line, color: color, label: String(localized: "7-day average"))
                    ChartLegendKey(kind: .band, color: color.opacity(0.25), label: String(localized: "Your normal range"))
                }
            }
        }
    }
}

// MARK: - Dots with a trend line

/// Scale readings as dots with an exponentially smoothed trend line through
/// them — day-to-day water swings stay visible but don't read as the trend.
struct TrendWeightChart: View {
    let history: [TrendPoint]
    let range: TrendRange
    let style: ValueStyle
    var height: CGFloat = 180

    @State private var selectedDate: Date?

    private var daily: [TrendPoint] { history.within(range) }

    /// EWMA over all history (span 10), then windowed, so the line doesn't
    /// restart at the left edge of every range.
    private var smoothed: [TrendPoint] {
        let values = Stats.ewmaSeries(history.map(\.value), span: 10)
        let start = range.startDate()
        return zip(history, values).map { TrendPoint(date: $0.date, value: $1) }.filter { $0.date >= start }
    }

    /// Least-squares slope through the range, kg per week.
    private var weeklySlope: Double? {
        guard daily.count >= 5, let first = daily.first?.date else { return nil }
        let xs = daily.map { $0.date.timeIntervalSince(first) / 86_400 }
        let ys = daily.map(\.value)
        let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
        let sxx = xs.reduce(0) { $0 + ($1 - mx) * ($1 - mx) }
        guard sxx > 0 else { return nil }
        return zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) } / sxx * 7
    }

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        return daily.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    private var domain: ClosedRange<Double> {
        let values = daily.map(\.value) + smoothed.map(\.value)
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.2, 0.3)
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        if daily.count < 2 {
            EmptyChart(height: height)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(daily) { p in
                        PointMark(x: .value("Date", p.date), y: .value("Weight", p.value))
                            .symbolSize(range.rawValue > 91 ? 10 : 22)
                            .foregroundStyle(Theme.accent.opacity(selected == nil || selected?.id == p.id ? 0.55 : 0.25))
                    }
                    ForEach(smoothed) { p in
                        LineMark(x: .value("Date", p.date), y: .value("Trend", p.value), series: .value("Series", "Trend"))
                            .interpolationMethod(.linear)
                            .foregroundStyle(Theme.accentDeep)
                            .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round, lineJoin: .round))
                    }
                    if let selected {
                        RuleMark(x: .value("Date", selected.date))
                            .foregroundStyle(Theme.textTertiary.opacity(0.6))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                            .annotation(position: .top, spacing: 2,
                                        overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                                ChartCallout(point: selected, unit: style.suffix, decimals: style.decimals)
                            }
                    }
                }
                .chartYScale(domain: domain)
                .chartXSelection(value: $selectedDate)
        .onChange(of: range) { _, _ in selectedDate = nil }
                .sensoryFeedback(.selection, trigger: selected?.id)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: range.bucket.axisFormat)
                            .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator.opacity(0.7))
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: height)

                HStack(spacing: 14) {
                    ChartLegendKey(kind: .dot, color: Theme.accent.opacity(0.55), label: String(localized: "Scale reading"))
                    ChartLegendKey(kind: .line, color: Theme.accentDeep, label: String(localized: "Trend weight"))
                    if let weeklySlope {
                        Spacer(minLength: 0)
                        Text("\(weeklySlope >= 0 ? "+" : "−")\(abs(weeklySlope).formatted(.number.precision(.fractionLength(2)))) \(style.unit)/week")
                            .font(.system(size: 10, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
    }
}

// MARK: - Sparse estimate line

/// Dots joined by a line, for estimates the Watch only updates now and then.
struct SparseLineChart: View {
    let history: [TrendPoint]
    let range: TrendRange
    let style: ValueStyle
    var height: CGFloat = 130

    @State private var selectedDate: Date?

    private var daily: [TrendPoint] { history.within(range) }

    private var selected: TrendPoint? {
        guard let selectedDate else { return nil }
        return daily.min { abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate)) }
    }

    var body: some View {
        if daily.isEmpty {
            EmptyChart(height: height)
        } else {
            let values = daily.map(\.value)
            let lo = values.min() ?? 0, hi = values.max() ?? 1
            let pad = max((hi - lo) * 0.25, 1)
            Chart {
                ForEach(daily) { p in
                    LineMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .interpolationMethod(.linear)
                        .foregroundStyle(Theme.accent.opacity(0.6))
                    PointMark(x: .value("Date", p.date), y: .value("Value", p.value))
                        .symbolSize(30)
                        .foregroundStyle(Theme.accent)
                }
                if let selected {
                    RuleMark(x: .value("Date", selected.date))
                        .foregroundStyle(Theme.textTertiary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartCallout(point: selected, unit: style.suffix, decimals: style.decimals)
                        }
                }
            }
            .chartYScale(domain: (lo - pad)...(hi + pad))
            .chartXSelection(value: $selectedDate)
        .onChange(of: range) { _, _ in selectedDate = nil }
            .sensoryFeedback(.selection, trigger: selected?.id)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisValueLabel(format: range.bucket.axisFormat)
                        .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.separator.opacity(0.7))
                    AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                }
            }
            .frame(height: height)
        }
    }
}

// MARK: - Stacked bars

struct StackedPoint: Identifiable {
    struct ID: Hashable { let date: Date; let series: String }
    var id: ID { ID(date: date, series: series) }
    let date: Date
    let series: String
    let value: Double
}

/// Composition over time — e.g. strength vs cardio minutes.
struct StackedBarTrendChart: View {
    /// Daily values per series, oldest first.
    let history: [StackedPoint]
    let range: TrendRange
    let style: ValueStyle
    let series: [(name: String, color: Color)]
    var guide: (value: Double, label: String)? = nil
    var height: CGFloat = 180

    /// Bars in a fixed series order within each date, so the same series always
    /// stacks in the same place — grouping by bucket otherwise shuffles it.
    private var bars: [StackedPoint] {
        let order = Dictionary(uniqueKeysWithValues: series.enumerated().map { ($1.name, $0) })
        return stackedBars.sorted { a, b in
            a.date != b.date ? a.date < b.date : (order[a.series] ?? 0) < (order[b.series] ?? 0)
        }
    }

    private var stackedBars: [StackedPoint] {
        let start = range.startDate()
        let inRange = history.filter { $0.date >= start }
        guard range.bucket != .day else { return inRange }
        let bucket = range.bucket
        let dayCount = Dictionary(grouping: Set(inRange.map { Calendar.current.startOfDay(for: $0.date) })) { bucket.start(of: $0) }
            .mapValues { Double($0.count) }
        let groups = Dictionary(grouping: inRange) { "\(bucket.start(of: $0.date).timeIntervalSince1970)|\($0.series)" }
        return groups.values.compactMap { group in
            guard let first = group.first else { return nil }
            let start = bucket.start(of: first.date)
            return StackedPoint(date: start, series: first.series,
                                value: group.reduce(0) { $0 + $1.value } / max(dayCount[start] ?? 1, 1))
        }
        .sorted { $0.date < $1.date }
    }

    var body: some View {
        let data = bars
        if data.isEmpty {
            EmptyChart(height: height)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Chart {
                    ForEach(data) { p in
                        BarMark(x: .value("Date", p.date, unit: range.bucket.calendarUnit),
                                y: .value("Value", p.value))
                            .foregroundStyle(by: .value("Series", p.series))
                            .cornerRadius(data.count > 60 ? 1 : 2)
                    }
                    if let guide {
                        RuleMark(y: .value("Guide", guide.value))
                            .foregroundStyle(Theme.good)
                            .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 3]))
                            .annotation(position: .top, alignment: .leading, spacing: 2) {
                                Text(LocalizedStringKey(guide.label))
                                    .font(.system(size: 9, weight: .semibold))
                                    .foregroundStyle(Theme.good)
                            }
                    }
                }
                .chartForegroundStyleScale(domain: series.map(\.name), range: series.map(\.color))
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                        AxisValueLabel(format: range.bucket.axisFormat)
                            .font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                        AxisGridLine().foregroundStyle(Theme.separator.opacity(0.7))
                        AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(height: height)

                HStack(spacing: 14) {
                    ForEach(series, id: \.name) { ChartLegendKey(kind: .square, color: $0.color, label: $0.name) }
                    if range.bucket != .day {
                        Spacer(minLength: 0)
                        Text("avg per day").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
        }
    }
}

// MARK: - Small pieces

struct ChartLegendKey: View {
    enum Kind { case dot, line, band, square }
    let kind: Kind
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 5) {
            switch kind {
            case .dot:    Circle().fill(color).frame(width: 6, height: 6)
            case .line:   Capsule().fill(color).frame(width: 14, height: 2.5)
            case .band:   RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 14, height: 8)
            case .square: RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            }
            Text(LocalizedStringKey(label))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
        }
    }
}

struct EmptyChart: View {
    var height: CGFloat = 130

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .font(.title2)
                .foregroundStyle(Theme.accent.opacity(0.65))
            Text("Not enough data in this range yet")
                .font(.subheadline.weight(.medium))
            Text("Try a longer range or sync more readings.")
                .font(.caption)
        }
        .multilineTextAlignment(.center)
        .foregroundStyle(Theme.textSecondary)
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity, minHeight: height)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius))
    }
}

/// Short axis labels: 12500 → "12.5k".
func compact(_ value: Double) -> String {
    abs(value) >= 1000
        ? String(localized: "\((value / 1000).formatted(.number.precision(.fractionLength(abs(value) >= 10_000 ? 0 : 1))))k")
        : value.formatted(.number.precision(.fractionLength(value < 10 && value != value.rounded() ? 1 : 0)))
}
