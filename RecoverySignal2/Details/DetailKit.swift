//
//  DetailKit.swift
//  RecoverySignal2
//
//  Shared building blocks for the detail pages you reach by tapping a Today
//  card: a gradient hero, stat tiles, chart cards and a range picker, so the
//  five pages feel like one designed set.
//

import SwiftUI

enum DetailRoute: String, Hashable, Codable {
    case recovery, sleep, activity, nutrition, body, workouts, weight, food
}

enum DetailRange: Int, CaseIterable, Identifiable {
    case week = 7, twoWeeks = 14, month = 30, quarter = 90

    var id: Int { rawValue }
    var label: String { "\(rawValue)D" }
}

/// Scrolling page with the app's background and a large title.
struct DetailPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                content
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
    }
}

/// The big coloured banner at the top of each detail page.
struct DetailHero<Accessory: View>: View {
    let glyph: Glyph
    let eyebrow: String
    let value: String
    var unit: String = ""
    let caption: String
    var colors: [Color] = [Theme.accentDeep, Theme.accent]
    @ViewBuilder var accessory: Accessory
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .largeTitle) private var valueSize = 48

    private var layout: AnyLayout {
        typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20)) : AnyLayout(HStackLayout(spacing: 20))
    }

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    GlyphView(glyph, size: 20)
                    Text(eyebrow.uppercased())
                        .font(.eyebrow)
                        .tracking(1)
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(value)
                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(LocalizedStringKey(unit))
                            .font(.subheadline.weight(.medium))
                            .opacity(0.8)
                    }
                }
                .foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(caption))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            accessory
        }
        .card(padding: 22)
    }
}

extension DetailHero where Accessory == EmptyView {
    init(glyph: Glyph, eyebrow: String, value: String, unit: String = "", caption: String,
         colors: [Color] = [Theme.accentDeep, Theme.accent]) {
        self.init(glyph: glyph, eyebrow: eyebrow, value: value, unit: unit, caption: caption,
                  colors: colors, accessory: { EmptyView() })
    }
}

struct RangePicker: View {
    @Binding var range: DetailRange

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(DetailRange.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
    }
}

struct StatTile: Identifiable {
    let id = UUID()
    let label: String
    let value: String
    var unit: String = ""
    var caption: String? = nil
    var glyph: Glyph? = nil
}

struct StatGrid: View {
    let tiles: [StatTile]
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
            ForEach(tiles) { tile in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 5) {
                        if let glyph = tile.glyph { GlyphView(glyph, size: 14) }
                        Text(LocalizedStringKey(tile.label))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 3) {
                        Text(tile.value)
                            .font(.display(24))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        if !tile.unit.isEmpty {
                            Text(LocalizedStringKey(tile.unit))
                                .font(.caption.weight(.medium))
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    if let caption = tile.caption {
                        Text(LocalizedStringKey(caption))
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(2)
                    }
                }
                // Fill the row, so tiles with and without a caption line up.
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .card(padding: 14)
            }
        }
    }
}

/// A titled card that holds one chart.
struct ChartCard<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            content
        }
        .card(padding: 16)
    }
}

/// Small coloured dot + label + value, for chart legends.
struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(LocalizedStringKey(label))
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

nonisolated enum DetailFormat {
    static func hoursMinutes(_ hours: Double) -> String {
        guard hours > 0 else { return "—" }
        let total = Int((hours * 60).rounded())
        return "\(total / 60)h \(String(format: "%02d", total % 60))m"
    }

    static func whole(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0)))
    }

    static func decimal(_ value: Double, _ digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func signed(_ value: Double, _ digits: Int = 1) -> String {
        (value >= 0 ? "+" : "−") + abs(value).formatted(.number.precision(.fractionLength(digits)))
    }

    /// `Int(value.rounded())`, but never traps. A bad barcode scan, a wild AI
    /// estimate, or a stray manual-entry typo can produce a value that's NaN,
    /// infinite, or outside Int's range — converting one of those with a bare
    /// `Int(...)` crashes the app outright. This clamps first.
    static func safeInt(_ value: Double) -> Int {
        guard value.isFinite else { return 0 }
        return Int(min(max(value, -999_999_999), 999_999_999).rounded())
    }
}

extension Array where Element == DailyMetrics {
    /// The last `range` days, oldest first.
    func last(_ range: DetailRange) -> [DailyMetrics] {
        Array(sorted { $0.date < $1.date }.suffix(range.rawValue))
    }
}
