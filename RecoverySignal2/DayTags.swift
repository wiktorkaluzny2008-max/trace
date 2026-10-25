//
//  DayTags.swift
//  RecoverySignal2
//
//  Mark a day as sick, travelling, or having had a habit like alcohol or a
//  late meal. Two different jobs, one small model:
//
//    EXCLUDING tags (sick, travel) remove that day from the personal
//    baselines that RecoveryScore, the sleep-need baseline and adaptive
//    maintenance learn from — so a flu week doesn't get treated as your new
//    "normal" and a jet-lagged night doesn't count as a bad sleep habit.
//    The day still gets scored normally; it just stops teaching the models
//    what's typical for you.
//
//    HABIT tags (alcohol, late meal) do the opposite: they become inputs to
//    the lag-correlation miner, so "alcohol nights: HRV −9ms on average" is
//    something the app can actually go and check against your own history.
//
//  Multiple tags per day are fine — a sick day while travelling is common.
//

import Foundation
import SwiftUI
import SwiftData

enum DayTagKind: String, Codable, CaseIterable, Identifiable {
    case sick, travel, alcohol, lateMeal, highStress

    var id: String { rawValue }

    /// Sick and travel days are excluded from the baselines that learn what's
    /// "normal" for you; the rest are habits the correlation miner can test.
    var excludesFromBaselines: Bool {
        switch self {
        case .sick, .travel: true
        case .alcohol, .lateMeal, .highStress: false
        }
    }

    var label: String {
        switch self {
        case .sick:       String(localized: "Sick")
        case .travel:     String(localized: "Travel")
        case .alcohol:    String(localized: "Alcohol")
        case .lateMeal:   String(localized: "Late meal")
        case .highStress: String(localized: "Stressful day")
        }
    }

    var symbol: String {
        switch self {
        case .sick:       "cross.case.fill"
        case .travel:     "airplane"
        case .alcohol:    "wineglass.fill"
        case .lateMeal:   "moon.stars.fill"
        case .highStress: "bolt.fill"
        }
    }

    var explanation: String {
        switch self {
        case .sick, .travel:
            String(localized: "Won't count toward your normal ranges for recovery, sleep or maintenance calories.")
        case .alcohol, .lateMeal, .highStress:
            String(localized: "Tracked so the app can show you its actual effect on your recovery, over time.")
        }
    }
}

@Model
final class DayTag {
    var id: UUID = UUID()
    var date: Date = Date() // normalised to midnight local time
    var kindRaw: String = DayTagKind.sick.rawValue

    init(date: Date, kind: DayTagKind) {
        self.date = Calendar.current.startOfDay(for: date)
        self.kindRaw = kind.rawValue
    }

    var kind: DayTagKind { DayTagKind(rawValue: kindRaw) ?? .sick }
}

/// Pure helpers over an already-fetched `[DayTag]` array — no ModelContext,
/// so RecoveryScore/SleepNeedModel/AdaptiveMaintenance can stay unit-testable
/// pure functions and just take the result as a plain `Set<Date>`.
enum DayTagStore {
    static func excludedDates(_ tags: [DayTag]) -> Set<Date> {
        Set(tags.filter { $0.kind.excludesFromBaselines }.map(\.date))
    }

    static func dates(_ tags: [DayTag], with kind: DayTagKind) -> Set<Date> {
        Set(tags.filter { $0.kind == kind }.map(\.date))
    }

    static func kinds(_ tags: [DayTag], on date: Date) -> Set<DayTagKind> {
        let day = Calendar.current.startOfDay(for: date)
        return Set(tags.filter { $0.date == day }.map(\.kind))
    }

    /// Adds or removes one tag for one day.
    static func toggle(_ kind: DayTagKind, on date: Date, tags: [DayTag], context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        if let existing = tags.first(where: { $0.date == day && $0.kind == kind }) {
            context.delete(existing)
        } else {
            context.insert(DayTag(date: day, kind: kind))
        }
        try? context.save()
    }
}

// MARK: - UI

/// A row of toggleable chips for one day's tags, plus a short explainer for
/// whichever chip is selected.
struct DayTagPicker: View {
    let date: Date
    let tags: [DayTag]
    @Environment(\.modelContext) private var context

    private var active: Set<DayTagKind> { DayTagStore.kinds(tags, on: date) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(DayTagKind.allCases) { kind in
                        chip(kind)
                    }
                }
            }
            if let selected = DayTagKind.allCases.first(where: active.contains) {
                Text(selected.explanation)
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
    }

    private func chip(_ kind: DayTagKind) -> some View {
        let isOn = active.contains(kind)
        return Button {
            DayTagStore.toggle(kind, on: date, tags: tags, context: context)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Label(kind.label, systemImage: kind.symbol)
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isOn ? .white : Theme.textSecondary)
                .background(isOn ? Theme.accent : Theme.track, in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

/// Today's tags, plus the last few days in case something needs a retroactive
/// tag (symptoms often show up a day after the fact).
struct DayTagsCard: View {
    @Query(sort: \DayTag.date, order: .reverse) private var tags: [DayTag]
    @State private var expanded = false

    private var recentDays: [Date] {
        (0..<7).compactMap { Calendar.current.date(byAdding: .day, value: -$0, to: Calendar.current.startOfDay(for: Date())) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Day tags")
            VStack(alignment: .leading, spacing: 14) {
                dayRow(recentDays[0], label: String(localized: "Today"))
                if expanded {
                    ForEach(recentDays.dropFirst(), id: \.self) { day in
                        Divider()
                        dayRow(day, label: day.formatted(.dateTime.weekday(.wide)))
                    }
                } else {
                    Button {
                        withAnimation(.snappy) { expanded = true }
                    } label: {
                        Text("Tag an earlier day")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                }
                Text("Sick and travel days are left out of your normal ranges for recovery, sleep and maintenance calories, so one rough week doesn't skew what's typical for you. Alcohol and late meals feed the correlation finder in Analysis.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 16)
        }
    }

    private func dayRow(_ date: Date, label: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            DayTagPicker(date: date, tags: tags)
        }
    }
}
