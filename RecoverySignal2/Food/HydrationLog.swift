//
//  HydrationLog.swift
//  RecoverySignal2
//
//  Quick-add water and caffeine: two buttons, a few presets, straight to
//  Apple Health. Mirrors FoodLogger's optimistic update — today's total
//  updates in the app immediately, and Health confirms a moment later.
//
//  Caffeine taken at or after 2pm is also tallied separately (see
//  MetricsAggregator), since when it was taken matters for sleep more than
//  how much overall — that figure feeds a note on the Tonight card and, over
//  time, the correlation finder in Analysis.
//

import Foundation
import HealthKit
import SwiftData
import SwiftUI

enum HydrationLogger {
    enum Kind: String, Identifiable {
        case water, caffeine
        var id: String { rawValue }

        var identifier: HKQuantityTypeIdentifier { self == .water ? .dietaryWater : .dietaryCaffeine }
        var unit: HKUnit { self == .water ? .literUnit(with: .milli) : .gramUnit(with: .milli) }
        var label: String { self == .water ? String(localized: "Water") : String(localized: "Caffeine") }
        var color: Color { Theme.accent }
    }

    struct Preset: Identifiable {
        let id = UUID()
        let label: String
        let amount: Double
    }

    static let waterPresets = [Preset(label: String(localized: "Glass · 200 ml"), amount: 200),
                               Preset(label: String(localized: "Bottle · 500 ml"), amount: 500),
                               Preset(label: String(localized: "Large bottle · 750 ml"), amount: 750)]

    static let caffeinePresets = [Preset(label: String(localized: "Coffee · 95 mg"), amount: 95),
                                  Preset(label: String(localized: "Espresso · 63 mg"), amount: 63),
                                  Preset(label: String(localized: "Tea · 30 mg"), amount: 30),
                                  Preset(label: String(localized: "Energy drink · 80 mg"), amount: 80)]

    /// Writes the sample to Health (if allowed) and bumps today's total right away.
    @MainActor
    static func log(_ kind: Kind, amount: Double, at date: Date = Date(), context: ModelContext) async {
        guard amount > 0 else { return }
        let type = HKQuantityType(kind.identifier)
        if let writable = await HealthAccess.writable([type]).first {
            let sample = HKQuantitySample(type: writable, quantity: HKQuantity(unit: kind.unit, doubleValue: amount), start: date, end: date)
            try? await HealthKitManager.shared.store.save(sample)
        }
        adjustDay(kind, amount: amount, at: date, context: context)
        HealthSync.shared.refreshSoon(after: .seconds(2))
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private static func adjustDay(_ kind: Kind, amount: Double, at date: Date, context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date == day })
        guard let metrics = try? context.fetch(descriptor).first else { return }
        switch kind {
        case .water:
            metrics.waterMl = (metrics.waterMl ?? 0) + amount
        case .caffeine:
            metrics.caffeineMg = (metrics.caffeineMg ?? 0) + amount
            if Calendar.current.component(.hour, from: date) >= 14 {
                metrics.lateCaffeineMg = (metrics.lateCaffeineMg ?? 0) + amount
            }
        }
        try? context.save()
    }
}

// MARK: - UI

/// The two quick-add buttons, with today's totals underneath each.
struct HydrationQuickAddRow: View {
    let days: [DailyMetrics]
    @Environment(\.modelContext) private var context
    @State private var adding: HydrationLogger.Kind?

    private var today: DailyMetrics? { days.first { Calendar.current.isDateInToday($0.date) } }

    var body: some View {
        HStack(spacing: 10) {
            button(.water, total: today?.waterMl, unit: String(localized: "ml"))
            button(.caffeine, total: today?.caffeineMg, unit: String(localized: "mg"))
        }
        .sheet(item: $adding) { kind in
            HydrationAddSheet(kind: kind)
        }
    }

    private func button(_ kind: HydrationLogger.Kind, total: Double?, unit: String) -> some View {
        Button { adding = kind } label: {
            HStack(spacing: 10) {
                Group {
                    if kind == .water {
                        Image(systemName: "drop.fill").font(.system(size: 15, weight: .semibold))
                    } else {
                        CoffeeBeanIcon(color: kind.color, backing: Theme.surface, size: 16)
                    }
                }
                .foregroundStyle(kind.color)
                .frame(width: 32, height: 32)
                .background(kind.color.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(kind.label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                    Text(total.map { "\(DetailFormat.safeInt($0)) \(unit)" } ?? String(localized: "Add"))
                        .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// SF Symbols has no coffee bean glyph, so this draws one: a rotated capsule
/// with a curved crease, coloured to match the button's own circle so it
/// reads as a cut-out rather than a solid stripe.
private struct CoffeeBeanIcon: View {
    let color: Color
    let backing: Color
    var size: CGFloat = 16

    var body: some View {
        let width = size * 0.72
        ZStack {
            Capsule().fill(color)
            Path { path in
                path.move(to: CGPoint(x: width * 0.5, y: size * 0.08))
                path.addQuadCurve(to: CGPoint(x: width * 0.5, y: size * 0.92),
                                  control: CGPoint(x: width * 0.12, y: size * 0.5))
            }
            .stroke(backing, style: StrokeStyle(lineWidth: max(size * 0.11, 1), lineCap: .round))
        }
        .frame(width: width, height: size)
        .rotationEffect(.degrees(-28))
    }
}

private struct HydrationAddSheet: View {
    let kind: HydrationLogger.Kind
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var custom: Double?
    @State private var logging = false

    private var presets: [HydrationLogger.Preset] { kind == .water ? HydrationLogger.waterPresets : HydrationLogger.caffeinePresets }
    private var unit: String { kind == .water ? String(localized: "ml") : String(localized: "mg") }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(presets) { preset in
                        Button {
                            Task { await add(preset.amount) }
                        } label: {
                            HStack {
                                Group {
                                    if kind == .water {
                                        Image(systemName: "drop.fill")
                                    } else {
                                        CoffeeBeanIcon(color: kind.color, backing: Theme.surface, size: 14)
                                    }
                                }
                                .foregroundStyle(kind.color)
                                .frame(width: 18)
                                Text(preset.label).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Image(systemName: "plus.circle.fill").foregroundStyle(kind.color)
                            }
                        }
                        .disabled(logging)
                    }
                }
                Section {
                    HStack {
                        Text("Custom amount")
                        Spacer()
                        LiveNumberField("0", value: $custom)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 80)
                        Text(verbatim: unit).foregroundStyle(Theme.textTertiary)
                        Button("Add") { Task { await add(custom ?? 0) } }
                            .disabled((custom ?? 0) <= 0 || logging)
                            .fontWeight(.semibold)
                    }
                }
                if kind == .caffeine {
                    Section {
                        Text("Caffeine after 2pm is tracked separately, since it's more likely to affect tonight's sleep than the total for the day.")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(kind.label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }

    private func add(_ amount: Double) async {
        guard amount > 0 else { return }
        logging = true
        await HydrationLogger.log(kind, amount: amount, context: context)
        logging = false
        dismiss()
    }
}
