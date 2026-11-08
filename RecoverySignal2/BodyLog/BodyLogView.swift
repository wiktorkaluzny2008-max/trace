//
//  BodyLogView.swift
//  RecoverySignal2
//
//  The weight page you reach from the scale button on Today. It's for logging
//  only: add weight and body fat (±0.1 steps), set a weigh-in reminder, and fix or delete
//  recent entries. Weight and body-fat trends live in Today and Trends.
//

import SwiftUI
import SwiftData

struct BodyLogView: View {
    @State private var log = BodyLogStore.shared
    @State private var weightTenths = 750
    @State private var fatTenths = 180
    @State private var includeFat = false
    @State private var date = Date()
    @State private var prefilled = false
    @State private var saving = false
    @State private var saved = false
    @State private var saveError: String?
    @State private var reminderOn = BodyLogStore.reminderEnabled
    @State private var reminderTime: Date = {
        let t = BodyLogStore.reminderTime
        return Calendar.current.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 15, second: 0, of: Date()) ?? Date()
    }()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                logCard
                reminderCard
                historySection
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Weight")
        .navigationBarTitleDisplayMode(.large)
        .task { await log.load(days: 60) }
        .refreshable { await log.load(days: 60) }
        .onChange(of: log.latestWeight?.id) { _, _ in prefill() }
        .onAppear(perform: prefill)
    }

    /// Logging only — trends for weight and body fat live in Today and Trends.
    private var logCard: some View {
        VStack(spacing: 16) {
            StepperValueCard(title: "Weight", unit: "kg", tenths: $weightTenths, range: 300...2500, color: Theme.accent,
                             caption: log.latestWeight.map { String(localized: "\(DetailFormat.signed(Double(weightTenths) / 10 - $0.value)) kg since last weigh-in") })

            Divider().overlay(Theme.separator)

            if includeFat {
                StepperValueCard(title: "Body fat", unit: "%", tenths: $fatTenths, range: 30...600, color: Theme.warn,
                                 caption: String(localized: "Lean mass \(DetailFormat.decimal(Double(weightTenths) / 10 * (1 - Double(fatTenths) / 1000))) kg · fat mass \(DetailFormat.decimal(Double(weightTenths) / 10 * Double(fatTenths) / 1000)) kg"))
                Button("Don't log body fat") { withAnimation(.snappy) { includeFat = false } }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textTertiary)
                    .buttonStyle(.plain)
            } else {
                Button {
                    withAnimation(.snappy) { includeFat = true }
                } label: {
                    Label("Add body fat", systemImage: "plus.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.warn)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(Theme.separator)

            DatePicker("Time", selection: $date, in: ...Date())
                .font(.subheadline)

            Button {
                Task { await save() }
            } label: {
                HStack(spacing: 8) {
                    if saving {
                        ProgressView().tint(Theme.onAction)
                    } else {
                        Image(systemName: saved ? "checkmark.circle.fill" : "heart.text.square.fill")
                    }
                    Text(saved ? "Saved to Apple Health" : "Save")
                }
            }
            .buttonStyle(.primary)
            .disabled(saving)

            if let saveError {
                Text(LocalizedStringKey(saveError)).font(.footnote).foregroundStyle(Theme.bad)
            }
        }
        .card()
        .onChange(of: weightTenths) { _, _ in saved = false }
        .onChange(of: fatTenths) { _, _ in saved = false }
    }

    /// Start from your last entries, so a normal weigh-in is a tap or two.
    private func prefill() {
        guard !prefilled, let last = log.latestWeight else { return }
        prefilled = true
        weightTenths = Int((last.value * 10).rounded())
        if let fat = log.latestBodyFat {
            includeFat = true
            fatTenths = Int((fat.value * 10).rounded())
        }
    }

    private func save() async {
        saving = true
        saveError = nil
        defer { saving = false }
        do {
            try await log.save(weightKg: Double(weightTenths) / 10, bodyFatPercent: includeFat ? Double(fatTenths) / 10 : nil,
                               at: date)
            // Today, Trends and the energy models pick the new weight up from a
            // background refresh; the button doesn't wait for it.
            let daysBack = (Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 0) + 2
            HealthSync.shared.refreshSoon(after: .milliseconds(400), days: min(max(daysBack, 3), 365))
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.snappy) { saved = true }
            date = Date()
        } catch {
            saveError = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }

    // MARK: Reminder

    private var reminderCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle(isOn: $reminderOn) {
                Label("Morning weigh-in reminder", systemImage: "bell.badge")
                    .font(.subheadline.weight(.medium))
            }
            .tint(Theme.accent)
            .onChange(of: reminderOn) { _, on in
                BodyLogStore.reminderEnabled = on
                Task {
                    if await !BodyLogStore.scheduleReminder() { reminderOn = false; BodyLogStore.reminderEnabled = false }
                }
            }
            if reminderOn {
                DatePicker("Remind me at", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                    .onChange(of: reminderTime) { _, time in
                        BodyLogStore.reminderTime = Calendar.current.dateComponents([.hour, .minute], from: time)
                        Task { _ = await BodyLogStore.scheduleReminder() }
                    }
            }
            Text("Weigh in after the bathroom and before eating or drinking, at the same time each day.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    // MARK: History

    private var historySection: some View {
        let grouped = Dictionary(grouping: log.weights + log.bodyFat) { Calendar.current.startOfDay(for: $0.date) }
        let days = grouped.keys.sorted(by: >).prefix(14)
        return VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Recent entries", icon: .trainingLoad)
            if days.isEmpty {
                Text(log.isLoading ? "Loading…" : "No entries in Apple Health yet.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary).card()
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.element) { index, day in
                        if index > 0 { Divider().overlay(Theme.separator) }
                        ForEach((grouped[day] ?? []).sorted { $0.date > $1.date }) { entry in
                            historyRow(entry)
                        }
                    }
                }
                .card(padding: 6)
                Text("Swipe or hold an entry you logged here to delete it. Entries from other apps can be removed in the Health app.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func historyRow(_ entry: BodyEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .weight ? "figure.stand" : "percent")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(entry.kind == .weight ? Theme.accent : Theme.warn)
                .frame(width: 30, height: 30)
                .background((entry.kind == .weight ? Theme.accent : Theme.warn).opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).hour().minute()))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text(verbatim: entry.source)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(DetailFormat.decimal(entry.value)).font(.system(size: 17, weight: .semibold)).monospacedDigit()
                Text(entry.kind == .weight ? "kg" : "%").font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .modifier(OptionalSwipeDelete(enabled: entry.isOwn) { Task { await log.delete(entry) } })
        .contextMenu {
            if entry.isOwn {
                Button("Delete", systemImage: "trash", role: .destructive) { Task { await log.delete(entry) } }
            }
        }
    }

    private func relative(_ date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? String(localized: "today \(date.formatted(date: .omitted, time: .shortened))")
            : date.formatted(.relative(presentation: .named))
    }
}

private struct OptionalSwipeDelete: ViewModifier {
    let enabled: Bool
    let action: () -> Void

    func body(content: Content) -> some View {
        if enabled {
            content.swipeToDelete(action)
        } else {
            content
        }
    }
}

/// A big value with − and + either side. Each tap is 0.1; hold to keep going.
struct StepperValueCard: View {
    let title: LocalizedStringKey
    let unit: String
    @Binding var tenths: Int
    let range: ClosedRange<Int>
    let color: Color
    var caption: String?

    var body: some View {
        VStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .textCase(.uppercase)
            HStack(spacing: 0) {
                stepButton("minus", enabled: tenths > range.lowerBound) { tenths -= 1 }
                Spacer(minLength: 8)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(verbatim: DetailFormat.decimal(Double(tenths) / 10))
                        .font(.system(size: 46, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(tenths)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    Text(verbatim: unit)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer(minLength: 8)
                stepButton("plus", enabled: tenths < range.upperBound) { tenths += 1 }
            }
            if let caption {
                Text(caption)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .sensoryFeedback(.selection, trigger: tenths)
    }

    private func stepButton(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.15)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(enabled ? color : Theme.textTertiary)
                .frame(width: 56, height: 56)
                .background(color.opacity(enabled ? 0.13 : 0.05), in: Circle())
        }
        .buttonStyle(.borderless)
        .buttonRepeatBehavior(.enabled)
        .disabled(!enabled)
    }
}
