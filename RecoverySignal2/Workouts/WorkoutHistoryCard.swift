//
//  WorkoutHistoryCard.swift
//  RecoverySignal2
//
//  Past workouts — sessions logged in the app and Apple Watch workouts —
//  shown in Workouts and Trends, with a full list behind "See all".
//

import SwiftUI
import SwiftData

enum WorkoutHistoryRoute: Hashable { case all }

enum WorkoutHistoryItem: Identifiable {
    case app(WorkoutLog)
    case watch(HealthWorkout)

    var id: String {
        switch self {
        case .app(let log): "app-\(log.id)"
        case .watch(let w): "watch-\(w.id)"
        }
    }

    var date: Date {
        switch self {
        case .app(let log): log.start
        case .watch(let w): w.start
        }
    }

    var searchText: String {
        switch self {
        case .app(let log): ([log.name] + log.exercises.map(\.name)).joined(separator: " ")
        case .watch(let workout): workout.name + " " + workout.source
        }
    }

    static func merged(logs: [WorkoutLog], watch: [HealthWorkout]) -> [WorkoutHistoryItem] {
        let linked = Set(logs.compactMap(\.healthWorkoutID))
        return (logs.map(WorkoutHistoryItem.app) + watch.filter { !linked.contains($0.id) }.map(WorkoutHistoryItem.watch))
            .sorted { $0.date > $1.date }
    }
}

struct WorkoutHistoryCard: View {
    var limit = 6
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var feed = HealthWorkoutFeed.shared

    var body: some View {
        let items = WorkoutHistoryItem.merged(logs: logs, watch: feed.workouts)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Workout history").font(.system(size: 15, weight: .semibold))
                Spacer()
                if items.count > limit {
                    NavigationLink(destination: WorkoutHistoryList()) {
                        HStack(spacing: 3) {
                            Text("See all")
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                        }
                        .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            if items.isEmpty {
                Text("Finished workouts and Apple Watch workouts appear here.")
                    .font(.footnote).foregroundStyle(Theme.textTertiary)
            }
            ForEach(items.prefix(limit)) { WorkoutHistoryRow(item: $0) }
        }
        .card()
        .task { await feed.load() }
    }
}

struct WorkoutHistoryList: View {
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var feed = HealthWorkoutFeed.shared
    @State private var query = ""
    @State private var source: HistorySource = .all
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum HistorySource: String, CaseIterable, Identifiable {
        case all, here, health
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .here: "Logged here"
            case .health: "Apple Health"
            }
        }
    }

    private var filtered: [WorkoutHistoryItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let items = WorkoutHistoryItem.merged(logs: logs, watch: feed.workouts).filter { item in
            switch (source, item) {
            case (.here, .watch), (.health, .app): return false
            default: return true
            }
        }
        guard !search.isEmpty else { return items }
        // Typo-tolerant, any word order: "squat legs" finds a Legs day with squats.
        let documents = items.map { SmartSearch.Document(id: $0.id, name: $0.searchText) }
        let order = Dictionary(uniqueKeysWithValues: SmartSearch.rank(query: search, in: documents, limit: items.count).enumerated().map { ($1.id, $0) })
        return items.filter { order[$0.id] != nil }.sorted { (order[$0.id] ?? 0) < (order[$1.id] ?? 0) }
    }

    var body: some View {
        let grouped = Dictionary(grouping: filtered) {
            Calendar.current.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        List {
            Section {
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        sourcePicker.pickerStyle(.menu)
                    } else {
                        sourcePicker.pickerStyle(.segmented)
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }
            if grouped.isEmpty {
                if feed.isLoading {
                    HStack { Spacer(); ProgressView(); Spacer() }
                        .listRowBackground(Color.clear)
                } else if query.isEmpty && source == .all {
                    ContentUnavailableView("No workouts yet", systemImage: "dumbbell",
                        description: Text("Finished workouts and Apple Watch workouts appear here."))
                        .listRowBackground(Color.clear)
                } else {
                    ContentUnavailableView("No matching workouts", systemImage: "magnifyingglass",
                        description: Text("Try another exercise name or change the source filter."))
                        .listRowBackground(Color.clear)
                }
            }
            ForEach(grouped.keys.sorted(by: >), id: \.self) { month in
                Section(month.formatted(.dateTime.month(.wide).year())) {
                    ForEach(grouped[month] ?? []) { item in
                        WorkoutHistoryRow(item: item, showsChevron: false)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Workout history")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, prompt: "Workout or exercise")
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.selection, trigger: source)
        .task { await feed.load() }
        .refreshable { await feed.load() }
    }

    private var sourcePicker: some View {
        Picker("Workout source", selection: $source) {
            ForEach(HistorySource.allCases) { Text($0.label).tag($0) }
        }
    }
}

struct WorkoutHistoryRow: View {
    let item: WorkoutHistoryItem
    var showsChevron = true

    var body: some View {
        switch item {
        case .app(let log):
            NavigationLink(destination: WorkoutLogDetailView(log: log)) {
                row(date: log.start, title: log.name, symbol: "dumbbell.fill", color: Theme.accent,
                    detail: String(localized: "\(durationText(log.duration / 60)) · \(log.setCount) sets · \(DetailFormat.whole(log.volume)) kg"),
                    badge: log.healthWorkoutID != nil)
            }
            .buttonStyle(.plain)
        case .watch(let workout):
            NavigationLink(destination: HealthWorkoutDetailView(workout: workout)) {
                row(date: workout.start, title: workout.name, symbol: workout.symbol, color: Theme.good,
                    detail: durationText(workout.duration / 60) + (workout.calories.map { " · \(Int($0.rounded())) kcal" } ?? ""),
                    badge: false)
            }
            .buttonStyle(.plain)
        }
    }

    private func row(date: Date, title: String, symbol: String, color: Color, detail: String, badge: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(verbatim: title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(2)
                    if badge { Image(systemName: "applewatch").font(.system(size: 10)).foregroundStyle(Theme.good) }
                }
                Text(verbatim: detail).font(.caption).foregroundStyle(Theme.textTertiary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Text(date.formatted(.dateTime.day().month(.abbreviated)))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            if showsChevron {
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(minHeight: 48)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}
