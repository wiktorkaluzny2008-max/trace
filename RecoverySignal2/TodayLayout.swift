//
//  TodayLayout.swift
//  RecoverySignal2
//
//  The order and visibility of Today's sections. The default page is short:
//  today's session, food, weekly sets, recovery, sleep, body and activity.
//  The rest — records, the training log, tonight's plan, maintenance
//  calories, day tags — is a tap away in "Edit Today", or by holding a
//  section to move or hide it.
//

import SwiftUI

enum TodaySection: String, CaseIterable, Identifiable {
    // Declaration order is the default order on the page.
    case session, nutrition, volume, readiness, sleep, body, activity, recovery, records, training, tonight, maintenance, dayTags

    var id: String { rawValue }

    var title: String {
        switch self {
        case .session:     String(localized: "Today's session")
        case .volume:      String(localized: "Weekly sets per muscle")
        case .records:     String(localized: "Personal records")
        case .readiness:   String(localized: "Recovery score")
        case .recovery:    String(localized: "Heart & fitness")
        case .sleep:       String(localized: "Sleep last night")
        case .tonight:     String(localized: "Tonight")
        case .activity:    String(localized: "Activity")
        case .training:    String(localized: "Training log")
        case .nutrition:   String(localized: "Nutrition")
        case .body:        String(localized: "Body")
        case .maintenance: String(localized: "Maintenance calories")
        case .dayTags:     String(localized: "Day tags")
        }
    }

    var symbol: String {
        switch self {
        case .session:     "play.fill"
        case .volume:      "chart.bar.fill"
        case .records:     "trophy.fill"
        case .readiness:   "gauge.with.needle.fill"
        case .recovery:    "heart.fill"
        case .sleep:       "bed.double.fill"
        case .tonight:     "moon.stars.fill"
        case .activity:    "figure.walk"
        case .training:    "dumbbell.fill"
        case .nutrition:   "fork.knife"
        case .body:        "figure.stand"
        case .maintenance: "flame.fill"
        case .dayTags:     "tag.fill"
        }
    }

    /// Sections that need a day of Health rollups before they can draw.
    var needsDailyMetrics: Bool {
        switch self {
        case .session, .volume, .records, .readiness: false
        default: true
        }
    }
}

enum TodayLayout {
    // v3: the shorter default page (fewer sections shown, training first).
    private static let orderKey = "today.order.v3"
    private static let hiddenKey = "today.hidden.v3"
    static let stampKey = "today.layoutStamp"

    /// Sections that start hidden: all reachable from other tabs or pages.
    static let defaultHidden: Set<TodaySection> = [.records, .training, .tonight, .maintenance, .dayTags]

    /// Every section, in your order. Sections added in later versions join at the end.
    static var order: [TodaySection] {
        get {
            let defaults: [TodaySection] = [.readiness, .session, .nutrition, .sleep, .activity, .body, .volume, .recovery, .records, .training, .tonight, .maintenance, .dayTags]
            let saved = UserDefaults.standard.stringArray(forKey: orderKey).map { $0.compactMap(TodaySection.init) } ?? defaults
            return saved + TodaySection.allCases.filter { !saved.contains($0) }
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: orderKey) }
    }

    static var hidden: Set<TodaySection> {
        get {
            guard let saved = UserDefaults.standard.stringArray(forKey: hiddenKey) else { return defaultHidden }
            return Set(saved.compactMap(TodaySection.init))
        }
        set { UserDefaults.standard.set(newValue.map(\.rawValue), forKey: hiddenKey) }
    }

    /// A value that changes with every edit, for views to observe.
    static func stamp() -> String {
        (order.map(\.rawValue) + ["|"] + hidden.map(\.rawValue).sorted()).joined(separator: ",")
    }

    static func reset() {
        UserDefaults.standard.removeObject(forKey: orderKey)
        UserDefaults.standard.removeObject(forKey: hiddenKey)
    }
}

struct TodayLayoutEditor: View {
    var onChange: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var order = TodayLayout.order
    @State private var hidden = TodayLayout.hidden

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(order) { item in
                        let isHidden = hidden.contains(item)
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(isHidden ? Theme.textTertiary : Theme.accent)
                                .frame(width: 30, height: 30)
                                .background((isHidden ? Theme.track : Theme.accent.opacity(0.12)), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            Text(item.title)
                                .foregroundStyle(isHidden ? Theme.textTertiary : Theme.textPrimary)
                            Spacer()
                            Button {
                                UISelectionFeedbackGenerator().selectionChanged()
                                withAnimation(.snappy) {
                                    if isHidden { hidden.remove(item) } else { hidden.insert(item) }
                                }
                                save()
                            } label: {
                                Image(systemName: isHidden ? "eye.slash" : "eye")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(isHidden ? Theme.textTertiary : Theme.accent)
                                    .frame(width: 36, height: 30)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel(isHidden ? "Show" : "Hide")
                        }
                    }
                    .onMove { from, to in
                        order.move(fromOffsets: from, toOffset: to)
                        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                        save()
                    }
                } footer: {
                    Text("Drag ☰ to reorder · tap the eye to show or hide. You can also hold any section on Today to move it.")
                }

                Section {
                    Button("Reset to default", role: .destructive) {
                        TodayLayout.reset()
                        withAnimation {
                            order = TodayLayout.order
                            hidden = TodayLayout.hidden
                        }
                        onChange()
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit Today")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
        .tint(Theme.accent)
    }

    private func save() {
        TodayLayout.order = order
        TodayLayout.hidden = hidden
        onChange()
    }
}
