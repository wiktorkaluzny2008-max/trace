//
//  WorkoutsHomeView.swift
//  RecoverySignal2
//
//  The workout tracker's front door: start a session, your routines, the
//  exercise library and past workouts. Plus the routine editor.
//

import SwiftUI
import SwiftData
import Charts

struct WorkoutsHomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \WorkoutRoutine.createdAt, order: .reverse) private var routines: [WorkoutRoutine]
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var recorder = WorkoutRecorder.shared
    @State private var editing: RoutineEditTarget?
    @State private var showsLibrary = false
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    @AppStorage("workouts.guidanceExpanded") private var guidanceExpanded = false

    struct RoutineEditTarget: Identifiable {
        let id = UUID()
        let routine: WorkoutRoutine?
    }

    /// True when pushed onto Today's navigation stack rather than shown as a sheet.
    var embedded = false
    /// True when this is the Train tab itself: large title, no back button.
    var asTab = false

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if recorder.isActive {
                        resumeCard
                    } else {
                        startCard
                    }
                    TrainingWeekSummary()
                    routinesSection
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "Personal records", icon: .target)
                        RecordsCard()
                    }
                    WorkoutHistoryCard(limit: 5)
                    libraryRow
                    trainingGuidance
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 36)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle(asTab ? "Train" : "Workouts")
            .navigationBarTitleDisplayMode(asTab ? .large : .inline)
            .toolbar {
                if !embedded && !asTab {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink(destination: WorkoutHistoryList()) {
                        Image(systemName: "clock.arrow.circlepath")
                    }
                    .accessibilityLabel("Workout history")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = RoutineEditTarget(routine: nil) } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New routine")
                }
            }
            .sheet(item: $editing) { target in
                RoutineEditorView(routine: target.routine)
            }
            .sheet(isPresented: $showsLibrary) {
                ExercisePickerView()
            }
            .task { await ExerciseLibrary.shared.loadIfNeeded() }
            #if DEBUG
            // Development only: `-previewExercisePicker` opens the library for a screen check.
            .task {
                if ProcessInfo.processInfo.arguments.contains("-previewExercisePicker") {
                    try? await Task.sleep(for: .milliseconds(400))
                    showsLibrary = true
                }
            }
            #endif
    }

    private var trainingGuidance: some View {
        VStack(spacing: 12) {
            Button {
                guidanceExpanded.toggle()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Training guidance").font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Targets, feedback and progress")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: guidanceExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                }
                .card(padding: 16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(guidanceExpanded ? "Expanded" : "Collapsed")
            .sensoryFeedback(.selection, trigger: guidanceExpanded)

            if guidanceExpanded {
                if coachEnabled {
                    TrainingBlockCard()
                    WeeklyVolumeCard()
                } else {
                    CoachOffCard()
                }
                PerformanceCard()
            }
        }
    }

    private var startCard: some View {
        Button {
            recorder.start(name: defaultName, routine: nil, logs: logs)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .frame(width: 48, height: 48)
                    .background(Theme.onAction.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Start empty workout").font(.headline)
                    Text("Add exercises as you go").font(.footnote).opacity(0.85)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).opacity(0.8)
            }
            .foregroundStyle(Theme.onAction)
            .padding(20)
            .background(Theme.actionFill, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var resumeCard: some View {
        Button {
            if embedded {
                recorder.showsActive = true
            } else {
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(450))
                    recorder.showsActive = true
                }
            }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.system(size: 22, weight: .semibold))
                    .frame(width: 48, height: 48)
                    .background(Theme.onAction.opacity(0.08), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text("Resume \(recorder.active?.name ?? "workout")").font(.headline)
                    if let start = recorder.active?.start {
                        Text(start, style: .timer).font(.footnote.monospacedDigit()).opacity(0.85)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
            }
            .foregroundStyle(Theme.textPrimary)
            .padding(20)
            .background(Theme.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "My routines", icon: .training)
                Button { editing = RoutineEditTarget(routine: nil) } label: {
                    Label("New routine", systemImage: "plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Theme.accent.opacity(0.12), in: Capsule())
                }
                .fixedSize()
            }
            if routines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("No routines yet").font(.subheadline.weight(.semibold))
                    Text("Build one for each session — Push, Pull, Legs, Upper, Lower — with the exercises and how many sets of each.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .card()
            }
            ForEach(routines) { routine in
                routineCard(routine)
            }
        }
    }

    private func routineCard(_ routine: WorkoutRoutine) -> some View {
        let exercises = routine.exercises
        let library = ExerciseLibrary.shared
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(routine.name)
                        .font(.display(22))
                        .foregroundStyle(Theme.textPrimary)
                    HStack(spacing: 10) {
                        Label("\(exercises.count)", systemImage: "dumbbell.fill")
                        Label("\(exercises.reduce(0) { $0 + $1.sets }) sets", systemImage: "square.stack.3d.up.fill")
                    }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
                    .labelStyle(.titleAndIcon)
                    if let last = routine.lastPerformed {
                        Text(last.formatted(.relative(presentation: .named)))
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                Spacer()
                Menu {
                    Button("Edit", systemImage: "pencil") { editing = RoutineEditTarget(routine: routine) }
                    Button("Duplicate", systemImage: "plus.square.on.square") {
                        context.insert(WorkoutRoutine(name: "\(routine.name) copy", exercises: routine.exercises))
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { context.delete(routine) }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(Theme.track, in: Circle())
                }
                .accessibilityLabel("Routine options")
            }

            // Exercise preview: thumbnails with names and set counts.
            VStack(spacing: 8) {
                ForEach(exercises.prefix(4)) { planned in
                    HStack(spacing: 10) {
                        if let exercise = library.exercise(id: planned.exerciseID) {
                            ExerciseDemo(exercise: exercise, animated: false, cornerRadius: 6)
                                .frame(width: 34, height: 34)
                        }
                        Text(planned.name)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        Text("\(planned.sets) sets")
                            .font(.footnote.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                if exercises.count > 4 {
                    Text("+ \(exercises.count - 4) more")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Button {
                recorder.start(name: routine.name, routine: routine, logs: logs)
            } label: {
                Label("Start routine", systemImage: "play.fill")
            }
            .buttonStyle(.primary)
            .disabled(recorder.isActive)
            .opacity(recorder.isActive ? 0.5 : 1)
        }
        .card(padding: 16)
        .contentShape(Rectangle())
        .onTapGesture { editing = RoutineEditTarget(routine: routine) }
    }

    private var libraryRow: some View {
        Button { showsLibrary = true } label: {
            HStack(spacing: 13) {
                GlyphTile(glyph: .training)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Exercise library").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    Text("\(max(ExerciseLibrary.shared.all.count, 876)) exercises with demos and instructions")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.textTertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    private var defaultName: String {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour < 12 ? "Morning workout" : (hour < 17 ? "Afternoon workout" : "Evening workout")
    }
}

// MARK: - Routine editor

struct RoutineEditorView: View {
    let routine: WorkoutRoutine?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var exercises: [PlannedExercise] = []
    @State private var showsPicker = false
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    @State private var viewing: Exercise?
    @State private var loaded = false
    @FocusState private var nameFocused: Bool

    private var totalSets: Int { exercises.reduce(0) { $0 + $1.sets } }
    @State private var joints: [String: ExerciseRanking.JointHistory] = [:]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("ROUTINE NAME")
                            .font(.eyebrow).tracking(0.8)
                            .foregroundStyle(Theme.textTertiary)
                        TextField("e.g. Push Day", text: $name)
                            .font(.system(size: 22, weight: .semibold))
                            .focused($nameFocused)
                        if !exercises.isEmpty {
                            Text("\(exercises.count) exercise\(exercises.count == 1 ? "" : "s") · \(totalSets) sets")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    ForEach($exercises) { $planned in
                        PlannedExerciseRow(planned: $planned, joints: coachEnabled ? joints[planned.exerciseID] : nil) { viewing = $0 }
                            .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { remove(planned.id) } label: { Label("Remove", systemImage: "trash") }
                            }
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button(role: .destructive) { remove(planned.id) } label: { Label("Remove", systemImage: "trash") }
                            }
                    }
                    .onMove { exercises.move(fromOffsets: $0, toOffset: $1) }

                    Button { showsPicker = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(Theme.accent, in: Circle())
                            Text("Add exercises")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                } header: {
                    Text("Exercises")
                } footer: {
                    Text(exercises.isEmpty
                         ? "Add the exercises for this session. You'll log weight and reps while you train."
                         : "Tap an exercise to see how to do it · hold and drag to reorder · swipe either way to remove.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(routine == nil ? "New routine" : "Edit routine")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || exercises.isEmpty)
                }
            }
            .navigationDestination(item: $viewing) { ExerciseDetailView(exercise: $0) }
            .sheet(isPresented: $showsPicker) {
                ExercisePickerView { picked in
                    exercises += picked.map { e in
                        PlannedExercise(exerciseID: e.id, name: e.name, sets: 3,
                                        restSeconds: e.mechanic == "isolation" ? 60 : 120)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: totalSets)
            .task(id: logs.count) { joints = ExerciseRanking.jointHistories(logs: logs) }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                name = routine?.name ?? ""
                exercises = routine?.exercises ?? []
                if routine == nil { nameFocused = true }
            }
        }
    }

    private func remove(_ id: UUID) {
        withAnimation { exercises.removeAll { $0.id == id } }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if let routine {
            routine.name = trimmed
            routine.exercises = exercises
        } else {
            context.insert(WorkoutRoutine(name: trimmed, exercises: exercises))
        }
        try? context.save()
        dismiss()
    }
}

/// One exercise in the routine: demo, name, muscle, and a sets counter.
private struct PlannedExerciseRow: View {
    @Binding var planned: PlannedExercise
    var joints: ExerciseRanking.JointHistory? = nil
    let onShow: (Exercise) -> Void

    var body: some View {
        let exercise = ExerciseLibrary.shared.exercise(id: planned.exerciseID)
        HStack(spacing: 12) {
            // Demo and name open the how-to; the sets counter stays separate.
            Button {
                if let exercise { onShow(exercise) }
            } label: {
                info(exercise)
            }
            .buttonStyle(.borderless)
            .disabled(exercise == nil)
            VStack(spacing: 5) {
                SetsCounter(value: $planned.sets)
                RepRangeMenu(planned: $planned)
            }
        }
    }

    private func info(_ exercise: Exercise?) -> some View {
        HStack(spacing: 12) {
            if let exercise {
                ExerciseDemo(exercise: exercise, animated: false, cornerRadius: 8)
                    .frame(width: 48, height: 48)
            } else {
                RoundedRectangle(cornerRadius: 8).fill(Theme.track).frame(width: 48, height: 48)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(planned.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                if let exercise {
                    HStack(spacing: 4) {
                        Text(exercise.muscleLabel).lineLimit(1)
                        Image(systemName: "info.circle")
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    if let joints, joints.flagged {
                        JointWarningBadge(history: joints)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
    }
}

/// A compact − 3 sets + control. Separate borderless buttons, so taps never
/// land on the row or the neighbouring button.
struct SetsCounter: View {
    @Binding var value: Int
    var range: ClosedRange<Int> = 1...12

    var body: some View {
        HStack(spacing: 0) {
            button("minus", enabled: value > range.lowerBound) { value -= 1 }
            VStack(spacing: -2) {
                Text("\(value)")
                    .font(.system(size: 17, weight: .semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(value == 1 ? "set" : "sets")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(width: 38)
            button("plus", enabled: value < range.upperBound) { value += 1 }
        }
        .padding(3)
        .background(Theme.track, in: Capsule())
        .fixedSize()
    }

    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { action() }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(enabled ? Theme.accent : Theme.textTertiary.opacity(0.5))
                .frame(width: 32, height: 32)
                .background(Theme.surface, in: Circle())
        }
        .buttonStyle(.borderless)
        .disabled(!enabled)
    }
}
