//
//  ExerciseViews.swift
//  RecoverySignal2
//
//  Browsing the exercise library: search and filter, the animated demo and
//  instructions for each movement, and your own history with it.
//

import SwiftUI
import SwiftData
import Charts

struct ExercisePickerView: View {
    /// Nil when browsing only.
    var onAdd: (([Exercise]) -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var library = ExerciseLibrary.shared
    @State private var search = ""
    @State private var muscle: String?
    @State private var equipment: String?
    @State private var selected: [Exercise] = []
    @State private var showsCreate = false
    @State private var viewing: Exercise?
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    @State private var joints: [String: ExerciseRanking.JointHistory] = [:]
    /// The library prepared for typo-tolerant search, rebuilt when it changes.
    @State private var documents: [SmartSearch.Document<String>] = []

    /// Exercises passing the muscle and equipment chips.
    private var pool: [Exercise] {
        library.all.filter { e in
            (muscle == nil || e.primaryMuscles.contains(muscle!) || e.secondaryMuscles.contains(muscle!)) &&
            (equipment == nil || (e.equipment ?? "other") == equipment)
        }
    }

    private var results: [Exercise] {
        let query = search.trimmingCharacters(in: .whitespaces)
        if query.isEmpty {
            return pool.sorted { a, b in
                // Primary-muscle matches before secondary ones.
                if let muscle {
                    let pa = a.primaryMuscles.contains(muscle), pb = b.primaryMuscles.contains(muscle)
                    if pa != pb { return pa }
                }
                return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
            }
        }
        // Smart search: words in any order, typos tolerated, abbreviations
        // expanded ("db incline", "tricep pushdwon", "rdl"), best matches first.
        let allowed = Set(pool.map(\.id))
        let candidates = documents.filter { allowed.contains($0.id) }
        return SmartSearch.rank(query: query, in: candidates, limit: 80).compactMap { library.exercise(id: $0.id) }
    }

    /// Exercises you've logged rank a little higher.
    private func buildDocuments() {
        var usage: [String: Int] = [:]
        for log in logs { for exercise in log.exercises { usage[exercise.exerciseID, default: 0] += 1 } }
        documents = library.all.map { exercise in
            SmartSearch.Document(id: exercise.id, name: exercise.name,
                                 extra: [exercise.muscleLabel, exercise.equipment ?? "", exercise.category ?? ""],
                                 boost: min(Double(usage[exercise.id] ?? 0) / 5, 1))
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    filters
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 6, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                if case .failed(let message) = library.state {
                    Text(LocalizedStringKey(message)).font(.footnote).foregroundStyle(Theme.warn)
                }
                if library.state == .loading {
                    HStack { ProgressView(); Text("Downloading 876 exercises…").font(.footnote).foregroundStyle(Theme.textSecondary) }
                }

                Section {
                    Button { showsCreate = true } label: {
                        Label("Create custom exercise", systemImage: "plus.circle.fill")
                    }
                    ForEach(results) { exercise in
                        row(exercise)
                    }
                } header: {
                    Text("\(results.count) exercises")
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search exercises or muscles")
            .navigationTitle(onAdd == nil ? "Exercises" : "Add exercises")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(item: $viewing) { ExerciseDetailView(exercise: $0) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(onAdd == nil ? "Done" : "Cancel") { dismiss() } }
                if onAdd != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add \(selected.isEmpty ? "" : "(\(selected.count))")") {
                            onAdd?(selected)
                            dismiss()
                        }
                        .disabled(selected.isEmpty)
                        .fontWeight(.semibold)
                    }
                }
            }
            .task { await library.loadIfNeeded() }
            .task(id: logs.count) { joints = ExerciseRanking.jointHistories(logs: logs) }
            .task(id: library.all.count + logs.count) { buildDocuments() }
            #if DEBUG
            // Development only: `-previewExerciseQuery "tricep pushdwon"` fills the search box.
            .onAppear {
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-previewExerciseQuery"), i + 1 < args.count { search = args[i + 1] }
            }
            #endif
            .sheet(isPresented: $showsCreate) {
                CustomExerciseSheet { created in
                    if onAdd != nil { selected.append(created) }
                }
            }
            .sensoryFeedback(.selection, trigger: selected.count)
        }
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(String(localized: "All muscles"), active: muscle == nil) { muscle = nil }
                    ForEach(ExerciseLibrary.muscles, id: \.self) { m in
                        chip(m.capitalized, active: muscle == m) { muscle = muscle == m ? nil : m }
                    }
                }
                .padding(.horizontal, 4)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    chip(String(localized: "All equipment"), active: equipment == nil) { equipment = nil }
                    ForEach(ExerciseLibrary.equipment, id: \.self) { e in
                        chip(e.capitalized, active: equipment == e) { equipment = equipment == e ? nil : e }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    private func chip(_ title: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(active ? .white : Theme.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(active ? Theme.accent : Theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(active ? .clear : Theme.border, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
    }

    private func row(_ exercise: Exercise) -> some View {
        let isSelected = selected.contains { $0.id == exercise.id }
        return HStack(spacing: 12) {
            // Picture and name open the how-to. When adding to a workout, the
            // circle on the right selects — two separate targets, no guessing.
            Button {
                viewing = exercise
            } label: {
                HStack(spacing: 12) {
                    ExerciseDemo(exercise: exercise, animated: false, cornerRadius: 8)
                        .frame(width: 52, height: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text("\(exercise.muscleLabel) · \(exercise.equipmentLabel)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                            .lineLimit(1)
                        if coachEnabled, let history = joints[exercise.id], history.flagged {
                            JointWarningBadge(history: history)
                        }
                    }
                    Spacer(minLength: 4)
                    if onAdd == nil {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Image(systemName: "info.circle").foregroundStyle(Theme.textTertiary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)

            if onAdd != nil {
                Button {
                    if isSelected { selected.removeAll { $0.id == exercise.id } } else { selected.append(exercise) }
                } label: {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 24))
                        .foregroundStyle(isSelected ? Theme.accent : Theme.separator)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isSelected ? "Deselect" : "Select")
            }
        }
        .swipeActions {
            if exercise.isCustom {
                Button("Delete", role: .destructive) { library.deleteCustom(exercise) }
            }
        }
    }
}

struct CustomExerciseSheet: View {
    var onCreate: (Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var muscle = "chest"
    @State private var equipment = "barbell"
    @State private var tracking: SetTracking = .weightReps

    var body: some View {
        NavigationStack {
            Form {
                TextField("Exercise name", text: $name)
                Picker("Main muscle", selection: $muscle) {
                    ForEach(ExerciseLibrary.muscles, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Picker("Equipment", selection: $equipment) {
                    ForEach(ExerciseLibrary.equipment, id: \.self) { Text($0.capitalized).tag($0) }
                }
                Picker("Track", selection: $tracking) {
                    Text("Weight × reps").tag(SetTracking.weightReps)
                    Text("Reps only").tag(SetTracking.reps)
                    Text("Time").tag(SetTracking.duration)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Custom exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        onCreate(ExerciseLibrary.shared.addCustom(name: name.trimmingCharacters(in: .whitespaces),
                                                                  muscle: muscle, equipment: equipment, tracking: tracking))
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

struct ExerciseDetailView: View {
    let exercise: Exercise
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]

    var body: some View {
        let best = WorkoutHistory.best(for: exercise.id, in: logs)
        let history = WorkoutHistory.oneRepMaxHistory(for: exercise.id, in: logs)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ExerciseDemo(exercise: exercise, cornerRadius: Theme.cornerRadius)
                    .frame(maxWidth: .infinity)
                    .aspectRatio(4 / 3, contentMode: .fit)

                FlowChips(items: [exercise.level?.capitalized, exercise.equipmentLabel, exercise.mechanic?.capitalized,
                                  exercise.force.map { "\($0.capitalized)" }, exercise.category?.capitalized].compactMap { $0 })

                VStack(alignment: .leading, spacing: 8) {
                    muscleRow("Primary", exercise.primaryMuscles, Theme.accent)
                    if !exercise.secondaryMuscles.isEmpty {
                        muscleRow("Secondary", exercise.secondaryMuscles, Theme.textTertiary)
                    }
                }
                .card()

                setCredit

                if !exercise.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("How to do it").font(.headline)
                        ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { i, step in
                            HStack(alignment: .top, spacing: 10) {
                                Text("\(i + 1)")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(.white)
                                    .frame(width: 22, height: 22)
                                    .background(Theme.accent, in: Circle())
                                Text(step)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    .card()
                }

                if best.oneRepMax != nil || best.mostReps != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Your records").font(.headline)
                        StatGrid(tiles: [
                            StatTile(label: String(localized: "Est. 1RM"), value: best.oneRepMax.map { DetailFormat.decimal($0) } ?? "—", unit: "kg"),
                            StatTile(label: String(localized: "Heaviest"), value: best.heaviest.map { DetailFormat.decimal($0) } ?? "—", unit: "kg"),
                            StatTile(label: String(localized: "Most reps"), value: best.mostReps.map(String.init) ?? "—"),
                            StatTile(label: String(localized: "Best set volume"), value: best.bestVolumeSet.map { DetailFormat.whole($0) } ?? "—", unit: "kg")
                        ])
                        if history.count >= 2 {
                            Chart(history) { p in
                                LineMark(x: .value("Date", p.date), y: .value("1RM", p.value))
                                    .foregroundStyle(Theme.accent)
                                PointMark(x: .value("Date", p.date), y: .value("1RM", p.value))
                                    .foregroundStyle(Theme.accent)
                            }
                            .chartYScale(domain: .automatic(includesZero: false))
                            .frame(height: 140)
                            Text("Estimated one-rep max per session (Epley: weight × (1 + reps ÷ 30)).")
                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .card()
                }

                if !exercise.imageURLs.isEmpty {
                    Text("Demonstration images: free-exercise-db, public domain.")
                        .font(.caption2).foregroundStyle(Theme.textTertiary)
                }
            }
            .padding(18)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    /// How much one hard set counts toward each muscle's weekly volume.
    @ViewBuilder
    private var setCredit: some View {
        let credits = LoggedMuscleVolume.weights(for: exercise).sorted { $0.value != $1.value ? $0.value > $1.value : $0.key.name < $1.key.name }
        if !credits.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Each set counts as").font(.headline)
                ForEach(credits, id: \.key) { muscle, sets in
                    HStack(spacing: 10) {
                        Text(muscle.name)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 96, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.track)
                                Capsule().fill(Theme.accent.opacity(0.35 + 0.65 * sets))
                                    .frame(width: geo.size.width * sets)
                            }
                        }
                        .frame(height: 7)
                        Text(verbatim: "\(sets.formatted(.number.precision(.fractionLength(0...2)))) set")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                            .frame(width: 58, alignment: .trailing)
                    }
                }
                Text("Indirect work counts as a fraction of a set, the method that best predicted muscle growth in the largest volume meta-analysis (Pelland et al., 2025).")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card()
        }
    }

    private func muscleRow(_ label: String, _ muscles: [String], _ color: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(LocalizedStringKey(label)).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textTertiary).frame(width: 74, alignment: .leading)
            Text(muscles.map(\.capitalized).joined(separator: ", "))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

struct FlowChips: View {
    let items: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accentDeep)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.1), in: Capsule())
                }
            }
        }
    }
}
