//
//  HomeWidgets.swift
//  HealthWidgets (widget extension)
//
//  Home Screen, Lock Screen and StandBy widgets.
//
//  Matching the Home Screen: iOS doesn't let widgets read the wallpaper, but it
//  does tell them how they're being drawn —
//    • full colour: the theme you pick in Edit Widget, in its light or dark
//      version to match the Home Screen's appearance ("Automatic" is a quiet
//      white or graphite card like Apple's own widgets);
//    • tinted or clear Home Screen: iOS supplies the colour. The widget drops
//      its background and marks what should take the tint (numbers, rings,
//      bars), so it picks up whatever tint you've chosen.
//

import WidgetKit
import SwiftUI
import AppIntents

// MARK: - Themes

enum WidgetTheme: String, AppEnum {
    case automatic, glass, ocean, mint, sunset, lavender, graphite

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Colour"
    static let caseDisplayRepresentations: [WidgetTheme: DisplayRepresentation] = [
        .automatic: "Automatic",
        .glass: "Glass",
        .ocean: "Ocean",
        .mint: "Mint",
        .sunset: "Sunset",
        .lavender: "Lavender",
        .graphite: "Graphite"
    ]
}

/// Every colour a widget draws with, resolved for a theme and light/dark.
struct WidgetPalette {
    let top: Color
    let bottom: Color
    let primary: Color
    let secondary: Color
    let track: Color
    let accent: Color
    let protein: Color
    let carbs: Color
    let fat: Color
    let moon: Color

    static func make(_ theme: WidgetTheme, dark: Bool) -> WidgetPalette {
        func rgb(_ hex: UInt32) -> Color {
            Color(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
        }
        // Macro tints tuned to sit well on light or dark grounds.
        let macrosDark = (rgb(0xD9807A), rgb(0x5F9BCB), rgb(0xD4AE57))
        let macrosLight = (rgb(0xC0605A), rgb(0x3F7BAA), rgb(0xB8913A))

        func light(_ top: UInt32, _ bottom: UInt32, ink: UInt32, accent: UInt32) -> WidgetPalette {
            WidgetPalette(top: rgb(top), bottom: rgb(bottom), primary: rgb(ink), secondary: rgb(ink).opacity(0.62),
                          track: rgb(ink).opacity(0.1), accent: rgb(accent),
                          protein: macrosLight.0, carbs: macrosLight.1, fat: macrosLight.2, moon: rgb(accent))
        }
        func darkPalette(_ top: UInt32, _ bottom: UInt32, accent: UInt32) -> WidgetPalette {
            WidgetPalette(top: rgb(top), bottom: rgb(bottom), primary: .white, secondary: .white.opacity(0.6),
                          track: .white.opacity(0.12), accent: rgb(accent),
                          protein: macrosDark.0, carbs: macrosDark.1, fat: macrosDark.2, moon: rgb(accent))
        }

        switch (theme, dark) {
        case (.automatic, false): return light(0xFFFFFF, 0xF4F6F9, ink: 0x14161A, accent: 0x1F6BFF)
        case (.automatic, true):  return darkPalette(0x1E2024, 0x131417, accent: 0x5A9BFF)
        case (.ocean, false):     return light(0xE8F2FF, 0xCFE2FB, ink: 0x0E2A4E, accent: 0x2266D6)
        case (.ocean, true):      return darkPalette(0x16345E, 0x0A1A33, accent: 0x6FB0FF)
        case (.mint, false):      return light(0xE6F7F2, 0xCBEDE3, ink: 0x0F3B32, accent: 0x14967A)
        case (.mint, true):       return darkPalette(0x124A40, 0x08261F, accent: 0x5FE0BF)
        case (.sunset, false):    return light(0xFFF1E8, 0xFBD9CC, ink: 0x4A1F1A, accent: 0xE0603C)
        case (.sunset, true):     return darkPalette(0x5A2A3A, 0x2A1320, accent: 0xFF9A6E)
        case (.lavender, false):  return light(0xF1EDFF, 0xDDD5FB, ink: 0x2B2253, accent: 0x6A50E0)
        case (.lavender, true):   return darkPalette(0x3A2F70, 0x1B1638, accent: 0xB3A2FF)
        case (.graphite, _):      return darkPalette(0x2A2C31, 0x16171A, accent: 0xE8E9EC)
        // Frosted blue-mint glass: bright ink, pastel macros, white rings.
        case (.glass, false):
            return WidgetPalette(top: rgb(0x9FD4DC), bottom: rgb(0x5C86E0), primary: .white, secondary: .white.opacity(0.78),
                                 track: .white.opacity(0.24), accent: .white,
                                 protein: rgb(0xFFC4BE), carbs: rgb(0xC4E0F8), fat: rgb(0xF8E4B0), moon: .white)
        case (.glass, true):
            return WidgetPalette(top: rgb(0x2C4F6E), bottom: rgb(0x14203F), primary: .white, secondary: .white.opacity(0.7),
                                 track: .white.opacity(0.16), accent: rgb(0xCFE6FF),
                                 protein: rgb(0xF2A9A3), carbs: rgb(0xA9D0F0), fat: rgb(0xF0D48A), moon: rgb(0xCFE6FF))
        }
    }
}

/// Liquid-glass look for the full-colour "Glass" theme: a tinted translucent
/// body, a bright specular sweep across the top, and a light rim that fades
/// down the sides. (See-through glass that refracts the wallpaper is what iOS
/// draws itself when the Home Screen uses the Clear style.)
struct GlassBackground: View {
    let palette: WidgetPalette
    let dark: Bool

    var body: some View {
        ZStack {
            LinearGradient(colors: [palette.top, palette.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            // Frost: lifts the colour towards white like light scattered in glass.
            LinearGradient(colors: [.white.opacity(dark ? 0.16 : 0.34), .white.opacity(dark ? 0.03 : 0.08)],
                           startPoint: .top, endPoint: .bottom)
            // Specular highlight in the top-left corner.
            RadialGradient(colors: [.white.opacity(dark ? 0.28 : 0.55), .clear],
                           center: UnitPoint(x: 0.12, y: -0.05), startRadius: 4, endRadius: 190)
            // Soft caustic glow low on the right.
            RadialGradient(colors: [Color(red: 0.7, green: 0.95, blue: 1).opacity(dark ? 0.18 : 0.3), .clear],
                           center: UnitPoint(x: 0.95, y: 1.05), startRadius: 2, endRadius: 170)
            // Rim light: bright at the top edge, fading down.
            ContainerRelativeShape()
                .strokeBorder(LinearGradient(colors: [.white.opacity(dark ? 0.55 : 0.85), .white.opacity(0.08), .white.opacity(dark ? 0.2 : 0.35)],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1.2)
            ContainerRelativeShape()
                .inset(by: 1.2)
                .strokeBorder(.white.opacity(dark ? 0.08 : 0.16), lineWidth: 0.6)
        }
    }
}

// MARK: - Configuration

struct TodayWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Today"
    static let description = IntentDescription("Choose the colour and what the widget shows.")

    @Parameter(title: "Colour", default: .automatic)
    var theme: WidgetTheme

    @Parameter(title: "Show recovery and sleep", default: true)
    var showRecovery: Bool

    @Parameter(title: "Show bedtime", default: true)
    var showBedtime: Bool
}

struct BedtimeWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "Bedtime"
    static let description = IntentDescription("Choose the widget's colour.")

    @Parameter(title: "Colour", default: .automatic)
    var theme: WidgetTheme
}

// MARK: - Data

struct TodayEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    var theme: WidgetTheme = .automatic
    var showRecovery = true
    var showBedtime = true
}

extension WidgetSnapshot {
    static var sample: WidgetSnapshot {
        WidgetSnapshot(updatedAt: .now, score: 78, bandLabel: "Recovered",
                       caloriesEaten: 1640, caloriesTarget: 2600,
                       proteinEaten: 112, proteinTarget: 160,
                       carbsEaten: 180, carbsTarget: 290,
                       fatEaten: 52, fatTarget: 85,
                       sleepHours: 7.53,
                       bedtime: Calendar.current.date(bySettingHour: 22, minute: 45, second: 0, of: .now),
                       wakeTime: Calendar.current.date(bySettingHour: 6, minute: 45, second: 0, of: .now.addingTimeInterval(86_400)),
                       sleepNeedHours: 8.1,
                       recentCalories: [2310, 2540, 1980, 2620, 2450, 2190, 1640])
    }
}

/// What the widget shows, with yesterday's numbers zeroed after midnight.
struct WidgetNumbers {
    let snapshot: WidgetSnapshot?

    private var isToday: Bool {
        guard let updated = snapshot?.updatedAt else { return false }
        return Calendar.current.isDateInToday(updated)
    }

    var score: Int? { isToday ? snapshot?.score : nil }
    var sleep: Double? { isToday ? snapshot?.sleepHours : nil }
    var kcal: Int { Int((isToday ? (snapshot?.caloriesEaten ?? 0) : 0).rounded()) }
    var protein: Int { Int((isToday ? (snapshot?.proteinEaten ?? 0) : 0).rounded()) }
    var carbs: Int { Int((isToday ? (snapshot?.carbsEaten ?? 0) : 0).rounded()) }
    var fat: Int { Int((isToday ? (snapshot?.fatEaten ?? 0) : 0).rounded()) }

    var kcalTarget: Int? { snapshot?.caloriesTarget.map { Int($0.rounded()) } }
    var proteinTarget: Int? { snapshot?.proteinTarget.map { Int($0.rounded()) } }
    var carbsTarget: Int? { snapshot?.carbsTarget.map { Int($0.rounded()) } }
    var fatTarget: Int? { snapshot?.fatTarget.map { Int($0.rounded()) } }

    private func fraction(_ eaten: Int, _ target: Int?, fallback: Double) -> Double {
        min(Double(eaten) / max(Double(target ?? 0) > 0 ? Double(target!) : fallback, 1), 1)
    }
    var kcalFraction: Double { fraction(kcal, kcalTarget, fallback: 2500) }
    var proteinFraction: Double { fraction(protein, proteinTarget, fallback: 150) }
    var carbsFraction: Double { fraction(carbs, carbsTarget, fallback: 280) }
    var fatFraction: Double { fraction(fat, fatTarget, fallback: 80) }

    var kcalText: String { kcal.formatted(.number.grouping(.automatic)) }
    var kcalLeft: Int? { kcalTarget.map { max($0 - kcal, 0) } }

    var sleepText: String {
        guard let sleep, sleep > 0 else { return "–" }
        let minutes = Int((sleep * 60).rounded())
        return "\(minutes / 60)h \(String(format: "%02d", minutes % 60))"
    }

    /// Tonight's bedtime, while it's still relevant (up to 3 h after).
    var bedtime: Date? {
        guard let bed = snapshot?.bedtime, bed > .now.addingTimeInterval(-3 * 3600) else { return nil }
        return bed
    }
    var bedtimeText: String { bedtime?.formatted(date: .omitted, time: .shortened) ?? "–" }
    var wakeText: String? {
        guard bedtime != nil, let wake = snapshot?.wakeTime else { return nil }
        return wake.formatted(date: .omitted, time: .shortened)
    }

    var week: [Double] {
        guard let recent = snapshot?.recentCalories, recent.count == 7 else { return [] }
        return isToday ? recent : Array(recent.dropFirst()) + [0]
    }
}

struct TodayIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample)
    }

    func snapshot(for configuration: TodayWidgetIntent, in context: Context) async -> TodayEntry {
        entry(configuration, snapshot: context.isPreview ? .sample : (WidgetSnapshot.load() ?? .sample))
    }

    func timeline(for configuration: TodayWidgetIntent, in context: Context) async -> Timeline<TodayEntry> {
        // The app reloads widgets when numbers change; this is a backstop, and
        // a refresh just after midnight clears yesterday's totals.
        let midnight = Calendar.current.startOfDay(for: .now.addingTimeInterval(86_400))
        let next = min(Date.now.addingTimeInterval(30 * 60), midnight.addingTimeInterval(60))
        return Timeline(entries: [entry(configuration, snapshot: WidgetSnapshot.load())], policy: .after(next))
    }

    private func entry(_ c: TodayWidgetIntent, snapshot: WidgetSnapshot?) -> TodayEntry {
        TodayEntry(date: .now, snapshot: snapshot, theme: c.theme, showRecovery: c.showRecovery, showBedtime: c.showBedtime)
    }
}

struct BedtimeIntentProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodayEntry {
        TodayEntry(date: .now, snapshot: .sample)
    }

    func snapshot(for configuration: BedtimeWidgetIntent, in context: Context) async -> TodayEntry {
        TodayEntry(date: .now, snapshot: context.isPreview ? .sample : (WidgetSnapshot.load() ?? .sample), theme: configuration.theme)
    }

    func timeline(for configuration: BedtimeWidgetIntent, in context: Context) async -> Timeline<TodayEntry> {
        let entry = TodayEntry(date: .now, snapshot: WidgetSnapshot.load(), theme: configuration.theme)
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(30 * 60)))
    }
}

// MARK: - Widgets

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "TodayWidget", intent: TodayWidgetIntent.self, provider: TodayIntentProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today")
        .description("Calories and macros eaten, recovery, sleep and tonight's bedtime.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge,
                            .accessoryCircular, .accessoryRectangular, .accessoryInline])
        .containerBackgroundRemovable()
    }
}

struct BedtimeWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "BedtimeWidget", intent: BedtimeWidgetIntent.self, provider: BedtimeIntentProvider()) { entry in
            BedtimeWidgetView(entry: entry)
        }
        .configurationDisplayName("Bedtime")
        .description("When to be in bed tonight to get the sleep you need.")
        .supportedFamilies([.systemSmall, .accessoryCircular, .accessoryInline, .accessoryRectangular])
        .containerBackgroundRemovable()
    }
}

// MARK: - Building blocks

/// Keeps white text crisp on bright glass with a faint, tight shadow.
private struct GlassInk: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on {
            content.shadow(color: .black.opacity(0.18), radius: 1.5, y: 0.5)
        } else {
            content
        }
    }
}

/// True when iOS is tinting the Home Screen (or it's in StandBy / Lock Screen):
/// no backgrounds, and colour comes from the system.
private struct TintAware {
    let mode: WidgetRenderingMode
    var isTinted: Bool { mode != .fullColor }
}

private struct WidgetRing: View {
    let fraction: Double
    let color: Color
    let track: Color
    let width: CGFloat

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: width)
            Circle()
                .trim(from: 0, to: max(fraction, 0.002))
                .stroke(color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .widgetAccentable()
        }
        .padding(width / 2)
    }
}

private struct WidgetBar: View {
    let fraction: Double
    let color: Color
    let track: Color
    var height: CGFloat = 5

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule().fill(color)
                    .frame(width: max(geo.size.width * fraction, fraction > 0 ? height : 0))
                    .widgetAccentable()
            }
        }
        .frame(height: height)
    }
}

/// A number that never wraps: it shrinks to fit instead of dropping a line.
private struct FitNumber: View {
    let text: String
    let size: CGFloat
    var weight: Font.Weight = .semibold

    var body: some View {
        Text(text)
            .font(.system(size: size, weight: weight, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .allowsTightening(true)
            .contentTransition(.numericText())
    }
}

// MARK: - Today widget views

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var environmentFamily
    @Environment(\.widgetRenderingMode) private var environmentMode
    @Environment(\.colorScheme) private var colorScheme
    let entry: TodayEntry
    /// For drawing outside a real widget (design checks).
    var familyOverride: WidgetFamily? = nil
    var tintedOverride: Bool? = nil

    private var family: WidgetFamily { familyOverride ?? environmentFamily }

    private var n: WidgetNumbers { WidgetNumbers(snapshot: entry.snapshot) }
    private var tinted: Bool { tintedOverride ?? (environmentMode != .fullColor) }
    private var glassInk: Bool { !tinted && entry.theme == .glass }

    /// Full colour uses the theme; tinted mode uses the system's colour with
    /// hierarchy from opacity.
    private var p: WidgetPalette {
        if tinted {
            // Tinted or Clear Home Screen: iOS draws the glass and supplies the colour.
            return WidgetPalette(top: .clear, bottom: .clear, primary: .primary, secondary: .primary.opacity(0.65),
                                 track: .primary.opacity(0.15), accent: .primary, protein: .primary,
                                 carbs: .primary, fat: .primary, moon: .primary)
        }
        return WidgetPalette.make(entry.theme, dark: colorScheme == .dark)
    }

    var body: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryRectangular: rectangular
        case .accessoryInline: inline
        case .systemMedium: medium.modifier(GlassInk(on: glassInk)).containerBackground(for: .widget) { background }.background { if familyOverride != nil { background } }
        case .systemLarge: large.modifier(GlassInk(on: glassInk)).containerBackground(for: .widget) { background }.background { if familyOverride != nil { background } }
        default: small.modifier(GlassInk(on: glassInk)).containerBackground(for: .widget) { background }.background { if familyOverride != nil { background } }
        }
    }

    @ViewBuilder
    private var background: some View {
        if tinted {
            Color.clear
        } else if entry.theme == .glass {
            GlassBackground(palette: p, dark: colorScheme == .dark)
        } else {
            LinearGradient(colors: [p.top, p.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    // MARK: Home Screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: true)
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                ZStack {
                    WidgetRing(fraction: n.kcalFraction, color: p.accent, track: p.track, width: 7)
                    VStack(spacing: -1) {
                        FitNumber(text: n.kcalText, size: 15)
                            .foregroundStyle(p.primary)
                        Text("kcal").font(.system(size: 8, weight: .semibold)).foregroundStyle(p.secondary)
                    }
                    .padding(.horizontal, 9)
                }
                .frame(width: 66, height: 66)
                VStack(alignment: .leading, spacing: 6) {
                    miniMacro("P", n.protein, n.proteinFraction, p.protein)
                    miniMacro("C", n.carbs, n.carbsFraction, p.carbs)
                    miniMacro("F", n.fat, n.fatFraction, p.fat)
                }
            }
            Spacer(minLength: 4)
            footer
        }
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(compact: false)
            Spacer(minLength: 6)
            HStack(spacing: 16) {
                ZStack {
                    WidgetRing(fraction: n.kcalFraction, color: p.accent, track: p.track, width: 9)
                    VStack(spacing: 0) {
                        FitNumber(text: n.kcalText, size: 22)
                            .foregroundStyle(p.primary)
                        Text(n.kcalTarget.map { "of \($0.formatted())" } ?? "kcal")
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(p.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .padding(.horizontal, 12)
                }
                .frame(width: 96, height: 96)

                VStack(spacing: 9) {
                    macroRow("Protein", n.protein, n.proteinTarget, n.proteinFraction, p.protein)
                    macroRow("Carbs", n.carbs, n.carbsTarget, n.carbsFraction, p.carbs)
                    macroRow("Fat", n.fat, n.fatTarget, n.fatFraction, p.fat)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 14) {
            header(compact: false)

            HStack(spacing: 18) {
                ZStack {
                    WidgetRing(fraction: n.kcalFraction, color: p.accent, track: p.track, width: 12)
                    VStack(spacing: 1) {
                        FitNumber(text: n.kcalText, size: 30)
                            .foregroundStyle(p.primary)
                        Text("kcal eaten").font(.system(size: 10, weight: .medium)).foregroundStyle(p.secondary)
                    }
                    .padding(.horizontal, 16)
                }
                .frame(width: 128, height: 128)

                VStack(alignment: .leading, spacing: 10) {
                    if let left = n.kcalLeft, let target = n.kcalTarget {
                        stat(left.formatted(), String(localized: "kcal left"))
                        stat(target.formatted(), String(localized: "daily target"))
                    }
                    if entry.showBedtime, n.bedtime != nil {
                        stat(n.bedtimeText, String(localized: "in bed by"))
                    }
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 10) {
                macroRow("Protein", n.protein, n.proteinTarget, n.proteinFraction, p.protein)
                macroRow("Carbs", n.carbs, n.carbsTarget, n.carbsFraction, p.carbs)
                macroRow("Fat", n.fat, n.fatTarget, n.fatFraction, p.fat)
            }

            weekChart
        }
    }

    private func header(compact: Bool) -> some View {
        HStack(spacing: compact ? 8 : 12) {
            if entry.showRecovery {
                HStack(spacing: 4) {
                    Circle()
                        .fill(tinted ? AnyShapeStyle(.primary) : AnyShapeStyle(band(n.score)))
                        .frame(width: 6, height: 6)
                        .widgetAccentable()
                    FitNumber(text: n.score.map { "\($0)%" } ?? "–", size: 12)
                        .foregroundStyle(p.primary)
                }
                HStack(spacing: 3) {
                    Image(systemName: "moon.fill").font(.system(size: 8)).foregroundStyle(p.moon)
                        .widgetAccentable()
                    FitNumber(text: n.sleepText, size: 12)
                        .foregroundStyle(p.primary)
                }
            } else {
                Text("Today").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
            }
            Spacer(minLength: 0)
            if !compact, entry.showBedtime, n.bedtime != nil {
                HStack(spacing: 3) {
                    Image(systemName: "bed.double.fill").font(.system(size: 9)).foregroundStyle(p.secondary)
                    FitNumber(text: n.bedtimeText, size: 12)
                        .foregroundStyle(p.primary)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if entry.showBedtime, n.bedtime != nil {
            HStack(spacing: 4) {
                Image(systemName: "bed.double.fill").font(.system(size: 9)).widgetAccentable()
                Text("Bed \(n.bedtimeText)").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
            }
            .foregroundStyle(p.secondary)
        } else if let left = n.kcalLeft {
            Text("\(left.formatted()) kcal left")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(p.secondary)
        }
    }

    private func miniMacro(_ letter: String, _ grams: Int, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 3) {
                Text(verbatim: letter).font(.system(size: 9, weight: .bold)).foregroundStyle(tinted ? p.secondary : color)
                Text(verbatim: "\(grams)g").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(p.primary).lineLimit(1).minimumScaleFactor(0.7)
            }
            WidgetBar(fraction: fraction, color: color, track: p.track, height: 3.5)
        }
    }

    private func macroRow(_ label: LocalizedStringKey, _ grams: Int, _ target: Int?, _ fraction: Double, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
                Spacer(minLength: 2)
                Text(verbatim: "\(grams)").font(.system(size: 13, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(p.primary)
                Text(verbatim: target.map { "/ \($0) g" } ?? "g").font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit().foregroundStyle(p.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            WidgetBar(fraction: fraction, color: color, track: p.track, height: 5)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            FitNumber(text: value, size: 18).foregroundStyle(p.primary)
            Text(verbatim: label).font(.system(size: 10, weight: .medium)).foregroundStyle(p.secondary)
        }
    }

    @ViewBuilder
    private var weekChart: some View {
        let week = n.week
        if !week.isEmpty {
            let top = max(week.max() ?? 1, Double(n.kcalTarget ?? 0), 1)
            VStack(alignment: .leading, spacing: 6) {
                Text("Last 7 days").font(.system(size: 10, weight: .semibold)).foregroundStyle(p.secondary)
                HStack(alignment: .bottom, spacing: 6) {
                    ForEach(Array(week.enumerated()), id: \.offset) { index, kcal in
                        VStack(spacing: 3) {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(index == week.count - 1 ? p.accent : p.accent.opacity(0.45))
                                .frame(height: max(CGFloat(kcal / top) * 44, kcal > 0 ? 3 : 1))
                                .widgetAccentable(index == week.count - 1)
                            Text(dayLetter(offset: week.count - 1 - index))
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(p.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .bottom)
                    }
                }
                .frame(height: 58, alignment: .bottom)
                .overlay(alignment: .bottom) {
                    if let target = n.kcalTarget, target > 0 {
                        GeometryReader { geo in
                            Rectangle()
                                .fill(p.secondary.opacity(0.5))
                                .frame(height: 1)
                                .offset(y: geo.size.height - 12 - CGFloat(Double(target) / top) * 44)
                        }
                    }
                }
            }
        }
    }

    private func dayLetter(offset: Int) -> String {
        let day = Calendar.current.date(byAdding: .day, value: -offset, to: .now) ?? .now
        return String(day.formatted(.dateTime.weekday(.narrow)))
    }

    private func band(_ score: Int?) -> Color {
        guard let score else { return p.secondary }
        return score >= 67 ? Color(red: 0.2, green: 0.75, blue: 0.48) : (score >= 34 ? Color(red: 0.96, green: 0.68, blue: 0.2) : Color(red: 0.95, green: 0.38, blue: 0.36))
    }

    // MARK: Lock Screen

    private var circular: some View {
        Gauge(value: n.kcalFraction) {
            Text("kcal")
        } currentValueLabel: {
            FitNumber(text: n.kcalText, size: 14)
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .containerBackground(for: .widget) { AccessoryWidgetBackground() }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                FitNumber(text: n.kcalText, size: 20)
                    .widgetAccentable()
                Text("kcal eaten")
                    .font(.system(size: 10, weight: .medium))
                    .opacity(0.7)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if entry.showBedtime, n.bedtime != nil {
                    HStack(spacing: 2) {
                        Image(systemName: "moon.fill").font(.system(size: 8, weight: .semibold))
                        Text(n.bedtimeText)
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .opacity(0.85)
                }
            }
            HStack(spacing: 7) {
                lockMacro("P", n.protein, n.proteinFraction)
                lockMacro("C", n.carbs, n.carbsFraction)
                lockMacro("F", n.fat, n.fatFraction)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var inline: some View {
        if entry.showBedtime, n.bedtime != nil {
            Text("\(n.kcalText) kcal · P \(n.protein) · bed \(n.bedtimeText)")
                .containerBackground(for: .widget) { Color.clear }
        } else {
            Text("\(n.kcalText) kcal · P \(n.protein) C \(n.carbs) F \(n.fat)")
                .containerBackground(for: .widget) { Color.clear }
        }
    }

    private func lockMacro(_ letter: String, _ grams: Int, _ fraction: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 2) {
                Text(verbatim: letter).font(.system(size: 9, weight: .semibold)).opacity(0.6)
                Text(verbatim: "\(grams)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            WidgetBar(fraction: fraction, color: .primary, track: .primary.opacity(0.22), height: 2.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Bedtime widget views

struct BedtimeWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.colorScheme) private var colorScheme
    let entry: TodayEntry

    private var n: WidgetNumbers { WidgetNumbers(snapshot: entry.snapshot) }
    private var tinted: Bool { renderingMode != .fullColor }
    private var p: WidgetPalette {
        tinted
            ? WidgetPalette(top: .clear, bottom: .clear, primary: .primary, secondary: .primary.opacity(0.6),
                            track: .primary.opacity(0.18), accent: .primary, protein: .primary, carbs: .primary,
                            fat: .primary, moon: .primary)
            : WidgetPalette.make(entry.theme, dark: colorScheme == .dark)
    }

    var body: some View {
        switch family {
        case .accessoryInline:
            Label("Bed by \(n.bedtimeText)", systemImage: "moon.fill")
                .containerBackground(for: .widget) { Color.clear }
        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 1) {
                Label("Bed by", systemImage: "moon.fill")
                    .font(.system(size: 11, weight: .medium))
                    .opacity(0.7)
                FitNumber(text: n.bedtimeText, size: 24)
                    .widgetAccentable()
                if let wake = n.wakeText {
                    Text("wake \(wake)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .opacity(0.7)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .containerBackground(for: .widget) { Color.clear }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: "moon.fill").font(.system(size: 11, weight: .semibold))
                        .widgetAccentable()
                    FitNumber(text: n.bedtimeText, size: 14)
                        .padding(.horizontal, 4)
                }
            }
            .containerBackground(for: .widget) { Color.clear }
        default:
            small
                .containerBackground(for: .widget) {
                    if tinted {
                        Color.clear
                    } else if entry.theme == .glass {
                        GlassBackground(palette: p, dark: colorScheme == .dark)
                    } else {
                        LinearGradient(colors: [p.top, p.bottom], startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                }
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(p.moon)
                    .widgetAccentable()
                Text("Tonight").font(.system(size: 12, weight: .semibold)).foregroundStyle(p.secondary)
            }
            Spacer(minLength: 4)
            Text("In bed by").font(.system(size: 11, weight: .medium)).foregroundStyle(p.secondary)
            FitNumber(text: n.bedtimeText, size: 34)
                .foregroundStyle(p.primary)
                .widgetAccentable()
            Spacer(minLength: 4)
            HStack(spacing: 10) {
                if let wake = n.wakeText {
                    detail("sunrise.fill", wake)
                }
                if let need = n.snapshot?.sleepNeedHours, n.bedtime != nil {
                    let minutes = Int((need * 60).rounded())
                    detail("zzz", "\(minutes / 60)h \(String(format: "%02d", minutes % 60))")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func detail(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 9, weight: .semibold))
            Text(verbatim: text).font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundStyle(p.secondary)
    }
}

// MARK: - Previews

#Preview("Small", as: .systemSmall) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample, theme: .ocean)
}

#Preview("Medium", as: .systemMedium) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample, theme: .mint)
}

#Preview("Large", as: .systemLarge) {
    TodayWidget()
} timeline: {
    TodayEntry(date: .now, snapshot: .sample, theme: .automatic)
}
