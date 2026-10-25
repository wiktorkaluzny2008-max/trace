//
//  ActiveWorkoutView.swift
//  RecoverySignal2
//
//  The live session: clock, heart rate, volume, every exercise with its sets
//  (previous / kg / reps / done), a rest timer, then a summary when you finish.
//

import SwiftUI
import SwiftData
import Charts

struct ActiveWorkoutView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var recorder = WorkoutRecorder.shared
    @State private var celebratedSets: Set<UUID> = []
    @State private var recordNotice: String?
    @State private var typeTarget: SetTypeTarget?
    @State private var valueTarget: ValueTarget?
    struct ValueTarget: Identifiable { let id = UUID(); let exercise: LoggedExercise; let set: LoggedSet; let weight: Bool }
    struct SetTypeTarget: Identifiable { let id: UUID; let exercise: LoggedExercise; let set: LoggedSet }
    @State private var showsPicker = false
    @State private var showsFinish = false
    @State private var confirmDiscard = false
    @State private var summary: WorkoutLog?
    @State private var detailExercise: Exercise?
    @State private var reordering = false
    @State private var swapping: SwapRequest?
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    @State private var plateCalcTarget: Double?
    @AppStorage("tip.watchHeartRate.dismissed") private var watchTipDismissed = false

    struct SwapRequest: Identifiable {
        let id: UUID
        let exercise: Exercise
    }

    struct PlateCalcRequest: Identifiable {
        let id = UUID()
        let target: Double
    }

    var body: some View {
        NavigationStack {
            Group {
                if let summary {
                    WorkoutLogDetailView(log: summary, isSummary: true)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { recorder.showsActive = false; self.summary = nil }.fontWeight(.semibold)
                            }
                        }
                } else if let workout = recorder.active {
                    session(workout)
                } else {
                    ContentUnavailableView("No workout running", systemImage: "figure.strengthtraining.traditional")
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) { Button("Close") { recorder.showsActive = false } }
                        }
                }
            }
        }
        .tint(Theme.accent)
    }

    // MARK: Session

    private func session(_ workout: ActiveWorkout) -> some View {
        Group {
            if reordering {
                reorderList(workout)
            } else {
                setList(workout)
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button { recorder.showsActive = false } label: { Image(systemName: "chevron.down") }
                    .accessibilityLabel("Minimise")
            }
            ToolbarItem(placement: .confirmationAction) {
                if reordering {
                    Button("Done") { withAnimation(.snappy) { reordering = false } }.fontWeight(.semibold)
                } else {
                    Button("Finish") { showsFinish = true }
                        .fontWeight(.semibold)
                        .tint(Theme.accent)
                }
            }
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil) }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if !reordering {
                VStack(spacing: 8) {
                    if let recordNotice {
                        Label(recordNotice, systemImage: "trophy.fill")
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                            .padding(10).frame(maxWidth: .infinity).background(Theme.surfaceRaised, in: Capsule())
                    }
                    if recorder.restEndsAt != nil { restBar }
                    if let exercise = focusedExercise(workout), let set = focusedSet(exercise) {
                        activeSetDock(exercise, set: set)
                    } else if !workout.exercises.isEmpty {
                        Button { showsPicker = true } label: { Label("Add exercise", systemImage: "plus") }
                            .buttonStyle(.secondary).padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 6)
            }
        }
        .task(id: recorder.restEndsAt) {
            guard let ends = recorder.restEndsAt else { return }
            try? await Task.sleep(for: .seconds(max(ends.timeIntervalSinceNow, 0)))
            if !Task.isCancelled { recorder.checkRestFinished(now: Date()) }
        }
        .sheet(isPresented: $showsPicker) {
            ExercisePickerView { recorder.addExercises($0, logs: logs) }
        }
        .sheet(isPresented: $showsFinish) {
            FinishWorkoutSheet(workout: workout) { name, notes, feedback, saveToHealth in
                Task {
                    summary = await recorder.finish(name: name, notes: notes, feedback: feedback,
                                                    saveToHealth: saveToHealth, context: context)
                    if summary == nil && recorder.active == nil { recorder.showsActive = false }
                }
            }
        }
        .sheet(item: Binding(get: { plateCalcTarget.map { PlateCalcRequest(target: $0) } }, set: { plateCalcTarget = $0?.target })) { request in
            PlateCalculatorSheet(target: request.target)
        }
        .sheet(item: $swapping) { request in
            SwapExerciseSheet(exercise: request.exercise,
                              excluding: Set(workout.exercises.map(\.exerciseID))) { picked in
                recorder.swapExercise(request.id, to: picked, logs: logs)
            }
        }
        .sheet(item: $detailExercise) { exercise in
            NavigationStack { ExerciseDetailView(exercise: exercise) }
        }
        .confirmationDialog("Discard this workout?", isPresented: $confirmDiscard, titleVisibility: .visible) {
            Button("Discard", role: .destructive) { recorder.discard() }
        } message: {
            Text("Nothing from this session will be saved.")
        }
        .sheet(item: $valueTarget) { target in
            WorkoutValuePicker(exercise: target.exercise, set: target.set, isWeight: target.weight)
                .presentationDetents([.medium, .large])
        }
        .sheet(item: $typeTarget) { target in
            NavigationStack {
                List(SetKind.allCases, id: \.self) { kind in
                    Button {
                        edit(target.exercise, target.set) { $0.kind = kind; if kind == .failure { $0.rir = 0 } }
                        UISelectionFeedbackGenerator().selectionChanged()
                        typeTarget = nil
                    } label: {
                        HStack { Text(kind.label); Spacer(); if target.set.kind == kind { Image(systemName: "checkmark") } }
                            .frame(minHeight: 44)
                    }
                }
                .navigationTitle("Set type").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { typeTarget = nil } } }
            }.presentationDetents([.medium])
        }
        .alert("Workout save", isPresented: Binding(get: { recorder.saveError != nil }, set: { if !$0 { recorder.saveError = nil } })) {
            Button("OK") { recorder.saveError = nil }
        } message: { Text(recorder.saveError ?? "") }
        .sensoryFeedback(.selection, trigger: reordering)
    }

    /// The session as a native list: smooth scrolling, and swipe-to-delete on
    /// sets that can never trigger the tick button underneath.
    private func setList(_ workout: ActiveWorkout) -> some View {
        List {
            Section {
                statsStrip(workout)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if !watchTipDismissed {
                    watchTip
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            ForEach(workout.exercises) { exercise in
                exerciseSection(exercise, workout: workout)
            }

            Section {
                Button { showsPicker = true } label: {
                    Label("Add exercises", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(.borderless)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                Button("Discard workout", role: .destructive) { confirmDiscard = true }
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .buttonStyle(.borderless)
                    .listRowBackground(Color.clear)
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(14)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.interactively)
        .contentMargins(.bottom, 12, for: .scrollContent)
    }

    /// Without a workout running on the Watch it samples heart rate only every few
    /// minutes, which is too sparse for session heart rate and recovery.
    private var watchTip: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "applewatch.radiowaves.left.and.right")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.bad)
                .frame(width: 34, height: 34)
                .background(Theme.bad.opacity(0.12), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text("Wearing your Watch?").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text("Start Traditional Strength Training in the Watch's Workout app too. It then records heart rate every few seconds, and Trace uses it for this session.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { watchTipDismissed = true }
            } label: {
                Image(systemName: "xmark").font(.caption.weight(.bold)).foregroundStyle(Theme.textTertiary)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Don't show this tip again")
        }
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    /// Hold an exercise to get here: just the names, dragged into a new order.
    private func reorderList(_ workout: ActiveWorkout) -> some View {
        List {
            Section {
                ForEach(workout.exercises) { exercise in
                    HStack(spacing: 12) {
                        if let libraryExercise = ExerciseLibrary.shared.exercise(id: exercise.exerciseID) {
                            ExerciseDemo(exercise: libraryExercise, animated: false, cornerRadius: 6)
                                .frame(width: 36, height: 36)
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                            Text("\(exercise.workingSets.count)/\(exercise.sets.filter { $0.kind != .warmup }.count) sets")
                                .font(.caption).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    recorder.update { $0.exercises.move(fromOffsets: from, toOffset: to) }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                .onDelete { offsets in
                    recorder.update { $0.exercises.remove(atOffsets: offsets) }
                }
            } header: {
                Text("Drag the handles to reorder")
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    private func statsStrip(_ workout: ActiveWorkout) -> some View {
        let sets = workout.exercises.reduce(0) { $0 + $1.workingSets.count }
        let volume = workout.exercises.reduce(0) { $0 + $1.volume }
        return HStack(spacing: 0) {
            VStack(spacing: 2) {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text(clock(context.date.timeIntervalSince(workout.start)))
                        .font(.system(size: 20, weight: .semibold))
                        .monospacedDigit()
                }
                Text("Duration").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            divider
            heartRate
            divider
            stat(DetailFormat.whole(volume), "kg volume")
            divider
            stat(String(localized: "\(sets)"), "sets")
        }
        .card(padding: 14)
    }

    private var heartRate: some View {
        let bpm = recorder.heartRate
        let fraction = (bpm ?? 0) / recorder.maxHeartRate
        let color: Color = fraction >= 0.8 ? Theme.bad : (fraction >= 0.65 ? Theme.warn : (fraction >= 0.5 ? Theme.good : Theme.accent))
        return VStack(spacing: 2) {
            HStack(spacing: 3) {
                Image(systemName: "heart.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(bpm == nil ? Theme.textTertiary : color)
                    .symbolEffect(.pulse, isActive: bpm != nil)
                Text(bpm.map { "\(Int($0.rounded()))" } ?? "—")
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
            }
            TimelineView(.periodic(from: .now, by: 15)) { context in
                Text(heartRateCaption(now: context.date))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func heartRateCaption(now: Date) -> String {
        guard let at = recorder.heartRateAt else { return "Needs Watch" }
        let minutes = Int(now.timeIntervalSince(at) / 60)
        return minutes < 2 ? "bpm · live" : "bpm · \(minutes)m ago"
    }

    // MARK: Exercise card

    @ViewBuilder
    private func exerciseSection(_ exercise: LoggedExercise, workout: ActiveWorkout) -> some View {
        let libraryExercise = ExerciseLibrary.shared.exercise(id: exercise.exerciseID)
        let previous = exercise.previous ?? WorkoutHistory.previousSets(for: exercise.exerciseID, in: logs, before: workout.start)
        let best = WorkoutHistory.best(for: exercise.exerciseID, in: logs, before: workout.start)
        let workingTotal = exercise.sets.filter { $0.kind != .warmup }.count
        let workingDone = exercise.workingSets.count

        Section {
            // Header
            HStack(spacing: 12) {
                if let libraryExercise {
                    Button { detailExercise = libraryExercise } label: {
                        ExerciseDemo(exercise: libraryExercise, cornerRadius: 10).frame(width: 54, height: 54)
                    }
                    .buttonStyle(.borderless)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.name)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    HStack(spacing: 6) {
                        Text(LocalizedStringKey(exercise.primaryMuscle.capitalized))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.accentDeep)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Theme.accent.opacity(0.12), in: Capsule())
                        HStack(spacing: 2) {
                            Image(systemName: "timer")
                            Text(verbatim: exercise.restSeconds == 0 ? "–" : "\(exercise.restSeconds)s")
                        }
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Theme.textTertiary)
                        .accessibilityLabel(exercise.restSeconds == 0 ? Text("No rest") : Text("\(exercise.restSeconds)s rest"))
                        Text("\(workingDone)/\(workingTotal)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .foregroundStyle(workingDone == workingTotal && workingDone > 0 ? Theme.good : Theme.textTertiary)
                        if coachEnabled && exercise.tracking != .duration {
                            jointMenu(exercise)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                }
                Spacer(minLength: 4)
                Menu {
                    Menu("Rest timer") {
                        ForEach([0, 30, 60, 90, 120, 180, 240, 300], id: \.self) { seconds in
                            Button(seconds == 0 ? "Off" : "\(seconds / 60):\(String(format: "%02d", seconds % 60))") {
                                recorder.update { w in
                                    if let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) { w.exercises[i].restSeconds = seconds }
                                }
                            }
                        }
                    }
                    if coachEnabled, let libraryExercise, exercise.completedSets.isEmpty {
                        Button("Swap exercise", systemImage: "arrow.triangle.2.circlepath") {
                            swapping = SwapRequest(id: exercise.id, exercise: libraryExercise)
                        }
                    }
                    if exercise.tracking == .weightReps {
                        Button("Plate calculator", systemImage: "square.stack.3d.up") {
                            plateCalcTarget = exercise.target?.weightKg ?? exercise.sets.compactMap(\.weightKg).last ?? 20
                        }
                    }
                    Button("Reorder exercises", systemImage: "arrow.up.arrow.down") { withAnimation(.snappy) { reordering = true } }
                    Button("Remove exercise", systemImage: "trash", role: .destructive) {
                        recorder.update { $0.exercises.removeAll { $0.id == exercise.id } }
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                // Reorder handle, also reachable by holding the header.
                Button { withAnimation(.snappy) { reordering = true } } label: {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 28, height: 32)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reorder exercises")
            }
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: 0.45) {
                withAnimation(.snappy) { reordering = true }
            }
            .listRowSeparator(.hidden)

            if coachEnabled, let target = exercise.target {
                CoachRow(target: target, tracking: exercise.tracking,
                         onSwap: exercise.completedSets.isEmpty ? { picked in recorder.swapExercise(exercise.id, to: picked, logs: logs) } : nil)
                    .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                    .listRowSeparator(.hidden)
            }

            if let oneRM = best.oneRepMax, exercise.tracking == .weightReps {
                Label("Best est. 1RM \(DetailFormat.decimal(oneRM)) kg", systemImage: "trophy")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .listRowSeparator(.hidden)
            }

            HStack(spacing: 6) {
                Text("SET").frame(width: 44)
                Text("PREVIOUS").frame(maxWidth: .infinity, alignment: .leading)
                if exercise.tracking == .weightReps { Text("KG").frame(width: 60) }
                Text(exercise.tracking == .duration ? "SEC" : "REPS").frame(width: 48)
                if exercise.tracking != .duration { Text("RIR").frame(width: 44) }
                Image(systemName: "checkmark").frame(width: 44)
            }
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Theme.textTertiary)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))

            ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { index, set in
                setRow(exercise: exercise, set: set, index: index,
                       previous: previous.indices.contains(index) ? previous[index] : nil,
                       isRecord: isRecord(set, best: best))
                    .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
                    .listRowSeparator(.hidden)
                    .listRowBackground(set.completed ? Theme.accent.opacity(0.08) : Theme.surface)
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) { deleteSet(exercise, set) } label: { Label("Delete", systemImage: "trash") }
                    }
                    .swipeActions(edge: .leading, allowsFullSwipe: false) {
                        Button { typeTarget = SetTypeTarget(id: set.id, exercise: exercise, set: set) } label: { Label("Type", systemImage: "slider.horizontal.3") }.tint(Theme.accent)
                    }
                    .onTapGesture { recorder.selectedSetID = set.id }
            }

            Button {
                withAnimation(.snappy) {
                    recorder.update { w in
                        guard let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                        let last = w.exercises[i].sets.last
                        w.exercises[i].sets.append(LoggedSet(kind: last?.kind == .warmup ? .normal : (last?.kind ?? .normal)))
                    }
                }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Label("Add set", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(Theme.track, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.textSecondary)
            .listRowSeparator(.hidden)
        }
    }

    private func setRow(exercise: LoggedExercise, set: LoggedSet, index: Int, previous: LoggedSet?, isRecord: Bool) -> some View {
        let normalNumber = exercise.sets.prefix(index + 1).filter { $0.kind != .warmup }.count
        // Completed rows lose the grey boxes: the row's soft green carries the state.
        let fieldFill: Color = set.completed ? .clear : Theme.track
        return HStack(spacing: 6) {
            Menu {
                ForEach(SetKind.allCases, id: \.self) { kind in
                    Button(kind.label) {
                        edit(exercise, set) {
                            $0.kind = kind
                            if kind == .failure { $0.rir = 0 }
                        }
                    }
                }
                Button("Delete set", role: .destructive) { deleteSet(exercise, set) }
            } label: {
                Text(set.kind == .normal ? "\(normalNumber)" : set.kind.short)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(set.kind == .warmup ? Theme.warn : (set.kind == .normal ? Theme.textPrimary : Theme.fat))
                    .frame(width: 44, height: 44)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.borderless)

            Group {
                if let previous {
                    Text(previousText(previous, tracking: exercise.tracking))
                } else {
                    Text("—")
                }
            }
            .font(.system(size: 12))
            .foregroundStyle(Theme.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .overlay(alignment: .trailing) {
                if isRecord {
                    Image(systemName: "trophy.fill").font(.system(size: 11)).foregroundStyle(Theme.warn)
                }
            }

            if exercise.tracking == .weightReps {
                LiveNumberField(value: binding(exercise, set, \.weightKg), fractionDigits: 2,
                                prompt: hintText(exercise.hint(for: index)?.weightKg.map { DetailFormat.decimal($0) } ?? "kg"))
                    .multilineTextAlignment(.center)
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .frame(width: 60, height: 44)
                    .background(fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            LiveNumberField(value: exercise.tracking == .duration ? binding(exercise, set, \.seconds) : binding(exercise, set, \.reps),
                            prompt: hintText(exercise.tracking == .duration
                                             ? (exercise.hint(for: index)?.seconds.map(String.init) ?? "sec")
                                             : (exercise.hint(for: index)?.reps.map(String.init) ?? "reps")))
                .multilineTextAlignment(.center)
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .frame(width: 48, height: 44)
                .background(fieldFill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))

            if exercise.tracking != .duration {
                rirMenu(exercise: exercise, set: set, fill: fieldFill)
            }

            Button {
                complete(exercise, set: set)
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(set.completed ? Theme.onAction : Theme.textTertiary)
                    .frame(width: 44, height: 44)
                    .background(set.completed ? Theme.actionFill : Theme.track, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
            .buttonStyle(.borderless)
        }
        .animation(reduceMotion ? nil : Theme.Motion.press, value: set.completed)
    }

    /// Joint pain for this exercise today; feeds swap suggestions.
    private func jointMenu(_ exercise: LoggedExercise) -> some View {
        Menu {
            Section("Joint pain during this exercise") {
                ForEach(MuscleFeedback.JointPain.allCases, id: \.self) { pain in
                    Button {
                        recorder.setJointPain(exercise.jointPain == pain ? nil : pain, exercise: exercise.id)
                    } label: {
                        if exercise.jointPain == pain { Label(pain.label, systemImage: "checkmark") } else { Text(pain.label) }
                    }
                }
            }
        } label: {
            Image(systemName: exercise.jointPain == nil || exercise.jointPain == MuscleFeedback.JointPain.none ? "bandage" : "bandage.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(jointColor(exercise.jointPain))
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Joint pain")
    }

    private func jointColor(_ pain: MuscleFeedback.JointPain?) -> Color {
        switch pain {
        case MuscleFeedback.JointPain.some?: Theme.warn
        case MuscleFeedback.JointPain.alot?: Theme.bad
        case MuscleFeedback.JointPain.none?: Theme.good
        default: Theme.textTertiary
        }
    }

    /// Reps in reserve for a set. Empty shows the target in grey.
    private func rirMenu(exercise: LoggedExercise, set: LoggedSet, fill: Color) -> some View {
        let target = set.kind == .warmup ? nil : exercise.target?.rir
        return Menu {
            Section("Reps in reserve") {
                ForEach(0...5, id: \.self) { value in
                    Button {
                        edit(exercise, set) { $0.rir = value }
                    } label: {
                        if value == set.rir {
                            Label(RIRText.option(value), systemImage: "checkmark")
                        } else {
                            Text(RIRText.option(value))
                        }
                    }
                }
            }
            if set.rir != nil {
                Button("Clear", role: .destructive) { edit(exercise, set) { $0.rir = nil } }
            }
        } label: {
            Text(set.rir.map(RIRText.short) ?? target.map(RIRText.short) ?? "–")
                .font(.system(size: 15, weight: .semibold).monospacedDigit())
                .foregroundStyle(set.rir == nil ? Theme.textTertiary.opacity(0.55)
                                 : (set.rir == 0 ? Theme.bad : Theme.textPrimary))
                .frame(width: 44, height: 44)
                .background(fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Reps in reserve")
    }

    private var restBar: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let remaining = max(Int((recorder.restEndsAt ?? timeline.date).timeIntervalSince(timeline.date).rounded(.up)), 0)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { restTime(remaining); Spacer(minLength: 0); restControls }
                VStack(alignment: .leading, spacing: 8) { restTime(remaining); restControls }
            }
            .padding(12)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(Theme.border, lineWidth: 0.5))
            .padding(.horizontal, 16)
            .onChange(of: remaining) { old, new in
                if scenePhase == .active, (1...4).contains(new), old != new {
                    UIImpactFeedbackGenerator(style: .soft).impactOccurred(intensity: 0.45)
                }
            }
        }
    }

    private func restTime(_ seconds: Int) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "timer").foregroundStyle(Theme.textSecondary)
            Text(clock(TimeInterval(seconds))).font(.title3.weight(.semibold)).monospacedDigit()
                .contentTransition(.numericText())
        }.foregroundStyle(Theme.textPrimary).accessibilityLabel("Rest remaining \(seconds) seconds")
    }
    private var restControls: some View {
        HStack(spacing: 6) {
            restButton("−30") { recorder.adjustRest(by: -30) }.accessibilityLabel("Subtract 30 seconds")
            restButton("+30") { recorder.adjustRest(by: 30) }.accessibilityLabel("Add 30 seconds")
            restButton("Skip") { recorder.cancelRest() }
        }
    }
    private func restButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action).font(.subheadline.weight(.semibold))
            .frame(minWidth: 44, minHeight: 44).padding(.horizontal, 4)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 12))
            .foregroundStyle(Theme.textPrimary).buttonStyle(.plain)
    }

    private func focusedExercise(_ workout: ActiveWorkout) -> LoggedExercise? {
        if let id = recorder.selectedSetID, let exercise = workout.exercises.first(where: { $0.sets.contains { $0.id == id && !$0.completed } }) { return exercise }
        return workout.exercises.first { $0.sets.contains { !$0.completed } }
    }
    private func focusedSet(_ exercise: LoggedExercise) -> LoggedSet? {
        exercise.sets.first { $0.id == recorder.selectedSetID && !$0.completed } ?? exercise.sets.first { !$0.completed }
    }
    private func activeSetDock(_ exercise: LoggedExercise, set: LoggedSet) -> some View {
        let index = exercise.sets.firstIndex { $0.id == set.id } ?? 0
        let hint = exercise.hint(for: index)
        let weightText = (set.weightKg ?? hint?.weightKg).map { DetailFormat.decimal($0) } ?? "—"
        let count: Int? = exercise.tracking == .duration ? (set.seconds ?? hint?.seconds) : (set.reps ?? hint?.reps)
        let countText = count.map(String.init) ?? "—"
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Button { typeTarget = SetTypeTarget(id: set.id, exercise: exercise, set: set) } label: {
                        Label("Set \(index + 1) · \(set.kind.label)", systemImage: "chevron.up.chevron.down")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }.buttonStyle(.plain).accessibilityLabel("Change set type")
                }
                Spacer(minLength: 8)
                Button {
                    recorder.update { workout in
                        guard let i = workout.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
                        workout.exercises[i].sets.append(LoggedSet())
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: { Image(systemName: "plus").frame(width: 44, height: 44) }
                    .accessibilityLabel("Add set to \(exercise.name)")
            }
            HStack(spacing: 12) {
                if exercise.tracking == .weightReps {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Weight · kg").font(.caption).foregroundStyle(Theme.textSecondary)
                        Button { valueTarget = ValueTarget(exercise: exercise, set: set, weight: true) } label: {
                            Text(weightText)
                                .font(.title2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        }.buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                            .accessibilityLabel("Weight in kilograms")
                            .accessibilityValue(weightText)
                    }.frame(maxWidth: .infinity)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(exercise.tracking == .duration ? "Seconds" : "Reps").font(.caption).foregroundStyle(Theme.textSecondary)
                    Button { valueTarget = ValueTarget(exercise: exercise, set: set, weight: false) } label: {
                        Text(countText)
                            .font(.title2.weight(.semibold).monospacedDigit()).lineLimit(1).minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain).foregroundStyle(Theme.textPrimary)
                        .accessibilityLabel(exercise.tracking == .duration ? "Seconds" : "Repetitions")
                        .accessibilityValue(countText)
                }.frame(maxWidth: .infinity)
                Button { complete(exercise, set: set) } label: {
                    Image(systemName: "checkmark").font(.title3.weight(.bold)).frame(width: 56, height: 56)
                        .foregroundStyle(Theme.onAction).background(Theme.actionFill, in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain).accessibilityLabel("Complete set \(index + 1) of \(exercise.name)")
            }
        }
        .padding(16).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Theme.border, lineWidth: 0.5))
        .padding(.horizontal, 16)
    }

    private func complete(_ exercise: LoggedExercise, set: LoggedSet) {
        recorder.toggleSet(exercise: exercise.id, set: set.id)
        guard !set.completed, let updated = recorder.active?.exercises.first(where: { $0.id == exercise.id })?.sets.first(where: { $0.id == set.id }),
              isRecord(updated, best: WorkoutHistory.best(for: exercise.exerciseID, in: logs)),
              celebratedSets.insert(set.id).inserted else { return }
        recordNotice = String(localized: "Personal record · \(exercise.name)")
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            if scenePhase == .active { UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
            try? await Task.sleep(for: .seconds(3))
            recordNotice = nil
        }
    }

    // MARK: Helpers

    private func binding<T>(_ exercise: LoggedExercise, _ set: LoggedSet, _ keyPath: WritableKeyPath<LoggedSet, T>) -> Binding<T> {
        Binding(
            get: {
                recorder.active?.exercises.first { $0.id == exercise.id }?.sets.first { $0.id == set.id }?[keyPath: keyPath] ?? set[keyPath: keyPath]
            },
            set: { value in edit(exercise, set) { $0[keyPath: keyPath] = value } }
        )
    }

    private func edit(_ exercise: LoggedExercise, _ set: LoggedSet, _ change: (inout LoggedSet) -> Void) {
        recorder.update { w in
            guard let i = w.exercises.firstIndex(where: { $0.id == exercise.id }),
                  let j = w.exercises[i].sets.firstIndex(where: { $0.id == set.id }) else { return }
            change(&w.exercises[i].sets[j])
        }
    }

    /// Last session's number in a light grey.
    private func hintText(_ text: String) -> Text {
        Text(LocalizedStringKey(text)).foregroundStyle(Theme.textSecondary)
    }

    private func deleteSet(_ exercise: LoggedExercise, _ set: LoggedSet) {
        recorder.update { w in
            guard let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
            w.exercises[i].sets.removeAll { $0.id == set.id }
        }
    }

    private func move(_ exercise: LoggedExercise, by offset: Int) {
        recorder.update { w in
            guard let i = w.exercises.firstIndex(where: { $0.id == exercise.id }) else { return }
            let j = i + offset
            guard w.exercises.indices.contains(j) else { return }
            w.exercises.swapAt(i, j)
        }
    }

    private func isRecord(_ set: LoggedSet, best: WorkoutHistory.Best) -> Bool {
        guard set.completed, set.kind != .warmup, let e1rm = set.estimatedOneRepMax, let previous = best.oneRepMax else { return false }
        return e1rm > previous
    }

    private func previousText(_ set: LoggedSet, tracking: SetTracking) -> String {
        let rir = set.rir.map { " @\(RIRText.short($0))" } ?? ""
        switch tracking {
        case .weightReps: return "\(set.weightKg.map { DetailFormat.decimal($0) } ?? "–") × \(set.reps ?? 0)\(rir)"
        case .reps:       return "\(set.reps ?? 0) reps\(rir)"
        case .duration:   return "\(set.seconds ?? 0) s"
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.system(size: 20, weight: .semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
            Text(LocalizedStringKey(label)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View { Rectangle().fill(Theme.separator).frame(width: 1, height: 30) }

    private func clock(_ interval: TimeInterval) -> String {
        let total = max(Int(interval), 0)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }
}

// MARK: - Finish

struct FinishWorkoutSheet: View {
    let workout: ActiveWorkout
    var onSave: (String, String, [MuscleFeedback], Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var notes = ""
    @State private var feedback: [MuscleFeedback] = []
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    @AppStorage("workout.saveToHealth") private var saveToHealth = true

    private var incomplete: Int {
        workout.exercises.reduce(0) { $0 + $1.sets.filter { !$0.completed }.count }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Workout name", text: $name)
                    TextField("How did it go?", text: $notes, axis: .vertical)
                }
                ForEach(coachEnabled ? $feedback : .constant([])) { $item in
                    MuscleFeedbackSection(feedback: $item, showsHelp: item.id == feedback.first?.id)
                }
                Section {
                    Toggle("Save to Apple Health", isOn: $saveToHealth)
                } footer: {
                    Text("Adds a Strength Training workout with its time and estimated calories, so it counts toward your rings and training load. If your Watch recorded this session too, the app links to that one instead and doesn't save a duplicate.")
                }
                if incomplete > 0 {
                    Section {
                        Label("\(incomplete) set\(incomplete == 1 ? "" : "s") not ticked off will be left out.", systemImage: "exclamationmark.circle")
                            .foregroundStyle(Theme.warn)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Finish workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Keep going") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, notes, coachEnabled ? feedback : [], saveToHealth)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .onAppear {
                name = workout.name
                if feedback.isEmpty {
                    var seen = Set<String>()
                    feedback = workout.exercises
                        .filter { !$0.workingSets.isEmpty && $0.tracking != .duration }
                        .compactMap { seen.insert($0.primaryMuscle).inserted ? MuscleFeedback(muscle: $0.primaryMuscle) : nil }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Log detail / summary

struct WorkoutLogDetailView: View {
    let log: WorkoutLog
    var isSummary = false

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var heartRate: [TrendPoint] = []
    @State private var heartRateSamples: [(date: Date, bpm: Double)] = []
    @State private var confirmDelete = false
    @State private var editing = false

    var body: some View {
        let exercises = log.exercises
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if isSummary {
                    VStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Theme.good)
                            .symbolEffect(.bounce, value: isSummary)
                        Text("Workout complete").font(.title2.weight(.semibold))
                        Text(log.healthWorkoutID != nil ? "Linked with your Apple Watch workout"
                             : (log.savedToHealth ? "Saved here and to Apple Health" : "Saved"))
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }

                StatGrid(tiles: [
                    StatTile(label: String(localized: "Duration"), value: durationText(log.duration / 60), glyph: .training),
                    StatTile(label: String(localized: "Volume"), value: DetailFormat.whole(log.volume), unit: "kg", glyph: .trainingLoad),
                    StatTile(label: String(localized: "Avg heart rate"), value: log.averageHeartRate.map { DetailFormat.whole($0) } ?? "—", unit: "bpm",
                             caption: log.maxHeartRate.map { "Max \(DetailFormat.whole($0)) bpm" }, glyph: .heartRate),
                    StatTile(label: String(localized: "Calories"), value: log.calories.map { DetailFormat.whole($0) } ?? "—", unit: "kcal",
                             caption: String(localized: "Estimated"), glyph: .energy)
                ])

                let records = personalRecords(exercises)
                if !records.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("\(records.count) personal record\(records.count == 1 ? "" : "s")", systemImage: "trophy.fill")
                            .font(.headline).foregroundStyle(Theme.warn)
                        ForEach(records, id: \.self) { Text($0).font(.subheadline).foregroundStyle(Theme.textSecondary) }
                    }
                    .card()
                }

                if heartRate.count >= 2 {
                    ChartCard(title: String(localized: "Heart rate"), subtitle: String(localized: "From Apple Health during the session")) {
                        Chart(heartRate) { p in
                            AreaMark(x: .value("Time", p.date), y: .value("bpm", p.value))
                                .foregroundStyle(LinearGradient(colors: [Theme.bad.opacity(0.3), Theme.bad.opacity(0)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Time", p.date), y: .value("bpm", p.value))
                                .foregroundStyle(Theme.bad)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 150)
                    }
                }

                WorkoutEffortCard(log: log, samples: heartRateSamples, logs: logs)

                muscleSplit(exercises)

                ForEach(exercises) { exercise in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exercise.name).font(.headline).foregroundStyle(Theme.accentDeep)
                        ForEach(Array(exercise.sets.enumerated()), id: \.element.id) { i, set in
                            HStack {
                                Text(set.kind == .normal ? "\(i + 1)" : set.kind.short)
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 24)
                                    .foregroundStyle(set.kind == .warmup ? Theme.warn : Theme.textSecondary)
                                Text(setText(set, exercise.tracking)).font(.subheadline).monospacedDigit()
                                Spacer()
                                if let e1rm = set.estimatedOneRepMax, exercise.tracking == .weightReps {
                                    Text("1RM \(DetailFormat.decimal(e1rm))").font(.caption).foregroundStyle(Theme.textTertiary)
                                }
                            }
                        }
                    }
                    .card()
                }

                if !log.notes.isEmpty {
                    Text(log.notes).font(.subheadline).foregroundStyle(Theme.textSecondary).card()
                }

                if !isSummary {
                    Button("Delete workout", role: .destructive) { confirmDelete = true }
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(18)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(log.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) { WorkoutLogEditor(log: log) }
        .task {
            heartRateSamples = (try? await HealthKitManager.shared.heartRateSamples(from: log.start, to: log.end)) ?? []
            heartRate = heartRateSamples.map { TrendPoint(date: $0.date, value: $0.bpm) }
        }
        .confirmationDialog("Delete this workout?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                context.delete(log)
                dismiss()
            }
        } message: {
            Text(log.savedToHealth ? "It stays in Apple Health — remove it there too if you want." : "This can't be undone.")
        }
    }

    private func muscleSplit(_ exercises: [LoggedExercise]) -> some View {
        let sets = Dictionary(grouping: exercises, by: \.primaryMuscle)
            .map { (muscle: $0.key.capitalized, sets: $0.value.reduce(0) { $0 + $1.workingSets.count }) }
            .filter { $0.sets > 0 }
            .sorted { $0.sets > $1.sets }
        return Group {
            if !sets.isEmpty {
                ChartCard(title: String(localized: "Sets per muscle")) {
                    Chart(sets, id: \.muscle) { item in
                        BarMark(x: .value("Sets", item.sets), y: .value("Muscle", item.muscle))
                            .foregroundStyle(Theme.accent.gradient)
                            .cornerRadius(4)
                            .annotation(position: .trailing) {
                                Text("\(item.sets)").font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                            }
                    }
                    .chartXAxis(.hidden)
                    .frame(height: CGFloat(sets.count) * 30 + 10)
                }
            }
        }
    }

    private func personalRecords(_ exercises: [LoggedExercise]) -> [String] {
        exercises.compactMap { exercise in
            guard exercise.tracking == .weightReps, let now = exercise.bestOneRepMax else { return nil }
            let before = WorkoutHistory.best(for: exercise.exerciseID, in: logs.filter { $0.id != log.id }, before: log.start).oneRepMax
            guard let before, now > before else { return nil }
            return "\(exercise.name): est. 1RM \(DetailFormat.decimal(now)) kg (was \(DetailFormat.decimal(before)))"
        }
    }

    private func setText(_ set: LoggedSet, _ tracking: SetTracking) -> String {
        let rir = set.rir.map { " · \(RIRText.short($0)) RIR" } ?? ""
        switch tracking {
        case .weightReps: return "\(set.weightKg.map { DetailFormat.decimal($0) } ?? "–") kg × \(set.reps ?? 0)\(rir)"
        case .reps:       return "\(set.reps ?? 0) reps\(rir)"
        case .duration:   return "\(set.seconds ?? 0) s"
        }
    }
}
