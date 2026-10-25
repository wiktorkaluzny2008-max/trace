//
//  CategoryCard.swift
//  RecoverySignal2
//
//  One card per Today category: the metric that matters most shown large with
//  its recent trend, and the supporting metrics in a compact row underneath —
//  instead of a loose grid of same-sized boxes.
//

import SwiftUI
import Charts

/// How the Today card draws its headline metric's recent history.
enum CategoryChartStyle {
    /// Dots joined by straight lines over a soft fade.
    case line
    /// Bars from zero with a dashed average; `history` is all daily values,
    /// oldest first, so the optional compare column can reach back months.
    case bars(history: [TrendPoint], style: ValueStyle, color: Color, compare: Bool, key: String)
}

struct CategoryCard: View {
    let hero: MetricItem
    /// Hero metric history, oldest first.
    let trend: [TrendPoint]
    let others: [MetricItem]
    var chart: CategoryChartStyle = .line

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 6) {
                if let glyph = hero.glyph { GlyphView(glyph, size: 18) }
                Text(LocalizedStringKey(hero.label))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Last \(max(trend.count, 1)) days")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(shown(hero))
                    .font(.display(32))
                    .monospacedDigit()
                    .foregroundStyle(hero.value == nil ? Theme.textTertiary : Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if hero.value != nil, !hero.unit.isEmpty, hero.unit != "h" {
                    Text(LocalizedStringKey(hero.unit))
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                if hero.value != nil, let asOf = hero.asOf {
                    Text(asOf.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.track, in: Capsule())
                }
                Spacer(minLength: 8)
                if hero.delta.map({ abs($0) >= 1 }) == true {
                    DeltaChip(percent: hero.delta, higherIsBetter: hero.higherIsBetter)
                    Text("vs 7-day avg")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            // Full card width so the trend is actually readable.
            switch chart {
            case .line:
                Sparkline(points: trend, unit: hero.unit, decimals: hero.decimals)
                    .frame(maxWidth: .infinity)
                    .frame(height: 96)
            case .bars(let history, let style, let color, let compare, let key):
                BarTrendChart(history: history, range: .twoWeeks, style: style, color: color,
                              compare: compare, height: 132, compareStorageKey: "today.\(key)")
                    .frame(maxWidth: .infinity)
            }

            if !others.isEmpty {
                Divider().overlay(Theme.separator)

                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(others.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Rectangle()
                                .fill(Theme.separator)
                                .frame(width: 1, height: 38)
                                .padding(.top, 2)
                        }
                        SubMetric(item: item)
                            .padding(.leading, index > 0 ? 12 : 0)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .card(padding: 20)
    }
}

private struct SubMetric: View {
    let item: MetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                if let glyph = item.glyph { GlyphView(glyph, size: 13) }
                Text(LocalizedStringKey(item.label))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(shown(item))
                    .font(.headline)
                    .monospacedDigit()
                    .foregroundStyle(item.value == nil ? Theme.textTertiary : Theme.textPrimary)
                if item.value != nil, !item.unit.isEmpty, item.unit != "h" {
                    Text(LocalizedStringKey(item.unit))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                if item.value != nil, let asOf = item.asOf {
                    Text(asOf.formatted(.dateTime.weekday(.abbreviated)))
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.75)

            DeltaChip(percent: item.delta, higherIsBetter: item.higherIsBetter)
        }
    }
}

/// Minimal trend: no axes, a dot per day over a smoothed 7-day line, today
/// emphasised. Touch and slide along it to read any day's value.
struct Sparkline: View {
    let points: [TrendPoint]
    var unit: String = ""
    var decimals: Int = 0

    @State private var selectedIndex: Int?

    private var values: [Double] { points.map(\.value) }

    /// Trailing average over up to 7 readings — the signal under the day-to-day noise.
    private var smoothed: [Double] {
        points.indices.map { i in
            let window = values[max(0, i - 6)...i]
            return window.reduce(0, +) / Double(window.count)
        }
    }

    private var domain: ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        let pad = max((hi - lo) * 0.25, abs(hi) * 0.02, 0.01)
        return (lo - pad)...(hi + pad)
    }

    /// The selection snapped to a real data point.
    private var selected: (index: Int, point: TrendPoint)? {
        guard let selectedIndex, !points.isEmpty else { return nil }
        let index = min(max(selectedIndex, 0), points.count - 1)
        return (index, points[index])
    }

    var body: some View {
        if points.count >= 2 {
            // Measured days as dots, with the smoothed average on a soft fade and
            // a faint baseline so the trend is grounded rather than floating.
            Chart {
                RuleMark(y: .value("Baseline", domain.lowerBound))
                    .foregroundStyle(Theme.separator)
                    .lineStyle(StrokeStyle(lineWidth: 1))

                // Each day is a dot, never joined to its neighbours: single readings are noisy.
                // The line is the trailing 7-day average, which is what actually moves.
                ForEach(Array(smoothed.enumerated()), id: \.offset) { index, value in
                    AreaMark(x: .value("Day", index),
                             yStart: .value("Base", domain.lowerBound),
                             yEnd: .value("Value", value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.16), Theme.accent.opacity(0.0)],
                                                        startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("Day", index), y: .value("Average", value))
                        .interpolationMethod(.catmullRom)
                        .foregroundStyle(Theme.accent)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }

                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    let isLast = index == points.count - 1
                    PointMark(x: .value("Day", index), y: .value("Value", point.value))
                        .symbolSize(isLast && selected == nil ? 44 : 16)
                        .foregroundStyle(isLast ? Theme.accentDeep : Theme.accent.opacity(0.45))
                        .opacity(selected == nil || selected?.index == index ? 1 : 0.5)
                }

                if let selected {
                    RuleMark(x: .value("Day", selected.index))
                        .foregroundStyle(Theme.textTertiary.opacity(0.6))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top, spacing: 2,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            ChartCallout(point: selected.point, unit: unit, decimals: decimals)
                        }
                    PointMark(x: .value("Day", selected.index), y: .value("Value", selected.point.value))
                        .symbolSize(80)
                        .foregroundStyle(Theme.accentDeep)
                }
            }
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartYScale(domain: domain)
            .chartLegend(.hidden)
            .chartXSelection(value: $selectedIndex)
            .sensoryFeedback(.selection, trigger: selected?.index)
            .accessibilityLabel("Trend over the last \(points.count) days")
        } else {
            Text("Trend builds\nover a few days")
                .font(.system(size: 10))
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Theme.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
        }
    }
}

/// The little value-and-date bubble shown while touching a chart.
struct ChartCallout: View {
    let point: TrendPoint
    let unit: String
    let decimals: Int
    /// Overrides for durations ("7h 12m") and grouped bars ("Week of 3 Mar").
    var valueText: String? = nil
    var dateText: String? = nil

    var body: some View {
        VStack(spacing: 1) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(valueText ?? point.value.formatted(.number.precision(.fractionLength(decimals))))
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                }
            }
            Text(dateText ?? point.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.75))
        .fixedSize()
    }
}

private func format(_ value: Double, _ decimals: Int) -> String {
    value.formatted(.number.precision(.fractionLength(decimals)))
}

/// Hours read as "9h 42m", not "9.7 h".
private func hoursAndMinutes(_ hours: Double) -> String {
    let total = DetailFormat.safeInt(hours * 60)
    return "\(total / 60)h \(total % 60)m"
}

private func shown(_ item: MetricItem) -> String {
    guard let value = item.value else { return "—" }
    return item.unit == "h" ? hoursAndMinutes(value) : format(value, item.decimals)
}
