//
//  CoachViews.swift
//  RecoverySignal2
//
//  The progression coach on screen: the suggestion under each exercise, the
//  per-muscle questions after a workout, the training-block card and its
//  explainer, and the rep-range picker in the routine editor.
//

import SwiftUI
import SwiftData

nonisolated enum RIRText {
    static func short(_ rir: Int) -> String { rir >= 5 ? "5+" : "\(rir)" }

    static func option(_ rir: Int) -> String {
        switch rir {
        case 0: String(localized: "0 · failure")
        case 1: String(localized: "1 · one more rep")
        case 5: String(localized: "5+ · easy")
        default: String(localized: "\(rir) more reps")
        }
    }
}

// MARK: - Suggestion under an exercise

struct CoachRow: View {
    let target: ExerciseTarget
    let tracking: SetTracking
    var onSwap: ((Exercise) -> Void)? = nil
    @State private var expanded = false

    private var swaps: [Exercise] {
        (target.alternatives ?? []).compactMap { ExerciseLibrary.shared.exercise(id: $0) }
    }

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: target.symbol)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(target.color)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(target.title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(verbatim: plan)
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(target.color)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                    }
                    if !target.reason.isEmpty {
                        Text(target.reason)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(expanded ? nil : 2)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let onSwap, !swaps.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(swaps) { swap in
                                    Button { onSwap(swap) } label: {
                                        Label(swap.name, systemImage: "arrow.triangle.2.circlepath")
                                            .font(.system(size: 11, weight: .semibold))
                                            .lineLimit(1)
                                            .padding(.horizontal, 9)
                                            .padding(.vertical, 5)
                                            .foregroundStyle(target.color)
                                            .background(Theme.surface, in: Capsule())
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }
                        .padding(.top, 3)
                    }
                }
            }
            .padding(10)
            .background(target.color.opacity(0.09), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
    }

    private var plan: String {
        var parts: [String] = []
        switch tracking {
        case .weightReps:
            let reps = target.reps.map { "\($0)" } ?? "\(target.repLow)–\(target.repHigh)"
            parts.append(target.weightKg.map { "\(ProgressionCoach.fmt($0)) kg × \(reps)" } ?? String(localized: "\(reps) reps"))
        case .reps:
            parts.append(String(localized: "\(target.reps ?? target.repLow) reps"))
        case .duration:
            if let s = target.seconds { parts.append("\(s) s") }
        }
        if tracking != .duration { parts.append("@\(RIRText.short(target.rir))") }
        let change = target.setChange > 0 ? " (+\(target.setChange))" : (target.setChange < 0 ? " (\(target.setChange))" : "")
        parts.append((target.sets == 1 ? String(localized: "1 set") : String(localized: "\(target.sets) sets")) + change)
        return parts.joined(separator: " · ")
    }
}

// MARK: - After the workout

struct MuscleFeedbackSection: View {
    @Binding var feedback: MuscleFeedback
    var showsHelp = false

    var body: some View {
        Section {
            question("Pump", selection: $feedback.pump, options: MuscleFeedback.Pump.allCases, label: \.label)
            question("Soreness since last time", selection: $feedback.soreness, options: MuscleFeedback.Soreness.allCases, label: \.label)
            question("Workload", selection: $feedback.workload, options: MuscleFeedback.Workload.allCases, label: \.label)
        } header: {
            Text(LocalizedStringKey(feedback.muscle.capitalized))
        } footer: {
            if showsHelp {
                Text("Optional. Next time the coach adds a set when a muscle was barely challenged and takes one away when it's still sore or overworked. Your answers also tune each muscle's weekly set range. Rate joint pain on each exercise with the bandage button.")
            }
        }
    }

    private func question<T: Hashable>(_ title: LocalizedStringKey, selection: Binding<T?>, options: [T], label: KeyPath<T, String>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline)
            HStack(spacing: 6) {
                ForEach(options, id: \.self) { option in
                    let selected = selection.wrappedValue == option
                    Button {
                        selection.wrappedValue = selected ? nil : option
                    } label: {
                        Text(option[keyPath: label])
                            .font(.system(size: 12, weight: selected ? .semibold : .regular))
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .foregroundStyle(selected ? .white : Theme.textPrimary)
                            .background(selected ? Theme.accent : Theme.track, in: Capsule())
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .padding(.vertical, 2)
        .sensoryFeedback(.selection, trigger: selection.wrappedValue)
    }
}

// MARK: - Training block card

struct TrainingBlockCard: View {
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    @State private var block = TrainingBlock.load()
    @State private var showsExplainer = false

    var body: some View {
        let phase = block.phase()
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("TRAINING BLOCK")
                        .font(.eyebrow).tracking(0.8)
                        .foregroundStyle(Theme.textTertiary)
                    Text(title(phase))
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(subtitle(phase))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Menu {
                    Picker("Build weeks", selection: Binding(get: { block.buildWeeks }, set: { weeks in
                        var updated = block
                        updated.buildWeeks = weeks
                        updated.save()
                        block = updated
                    })) {
                        ForEach(3...6, id: \.self) { Text("\($0) weeks + deload").tag($0) }
                    }
                    Button("Start deload now", systemImage: "battery.25percent") {
                        TrainingBlock.startDeloadNow()
                        block = TrainingBlock.load()
                    }
                    .disabled(phase == .deload)
                    Button("Start a new block", systemImage: "arrow.counterclockwise") {
                        TrainingBlock.restart()
                        block = TrainingBlock.load()
                    }
                    Button("Reset learned set ranges", systemImage: "slider.horizontal.3") { VolumePlanner.resetPersonal() }
                    Button("How the coach works", systemImage: "info.circle") { showsExplainer = true }
                    Divider()
                    Button("Turn coach off", systemImage: "power") { coachEnabled = false }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(width: 32, height: 32)
                        .background(Theme.track, in: Circle())
                }
            }

            HStack(spacing: 5) {
                ForEach(0...block.buildWeeks, id: \.self) { i in
                    let isDeload = i == block.buildWeeks
                    let current = currentIndex(phase) == i
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(fill(index: i, phase: phase, isDeload: isDeload))
                            .frame(height: current ? 8 : 6)
                        Text(isDeload ? String(localized: "DL") : "\(RIRText.short(rirFor(week: i)))")
                            .font(.system(size: 10, weight: current ? .bold : .medium).monospacedDigit())
                            .foregroundStyle(current ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Text("Numbers are reps in reserve for isolation lifts; compound lifts stop at 1.")
                .font(.caption2)
                .foregroundStyle(Theme.textTertiary)
        }
        .card(padding: 16)
        .onAppear { block = TrainingBlock.load() }
        .sheet(isPresented: $showsExplainer) { CoachExplainer() }
    }

    private func currentIndex(_ phase: TrainingBlock.Phase) -> Int {
        switch phase {
        case .build(let week, _): week - 1
        case .deload: block.buildWeeks
        }
    }

    private func rirFor(week index: Int) -> Int {
        let total = block.buildWeeks
        let fraction = total > 1 ? Double(index) / Double(total - 1) : 1
        return Int((3 * (1 - fraction)).rounded())
    }

    private func fill(index: Int, phase: TrainingBlock.Phase, isDeload: Bool) -> Color {
        let current = currentIndex(phase)
        if index > current { return Theme.track }
        if isDeload { return Theme.warn }
        return index == current ? Theme.accent : Theme.accent.opacity(0.45)
    }

    private func title(_ phase: TrainingBlock.Phase) -> String {
        switch phase {
        case .build(let week, let total): String(localized: "Week \(week) of \(total)")
        case .deload: String(localized: "Deload week")
        }
    }

    private func subtitle(_ phase: TrainingBlock.Phase) -> String {
        switch phase {
        case .build(let week, let total):
            let rir = block.targetRIR(compound: false)
            if week == total { return String(localized: "Last hard week: push isolation lifts to failure, compounds to 1 rep short. Deload next.") }
            return String(localized: "Stop sets about \(rir) reps short of failure. Effort rises each week.")
        case .deload:
            return String(localized: "Half the sets, ~10% lighter, easy effort. A new block starts after this week.")
        }
    }
}

// MARK: - Explainer

struct CoachExplainer: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    block("Reps in reserve (RIR)", "arrow.down.to.line",
                          "After each set, tap the RIR box and pick how many more clean reps you could have done. 0 means you couldn't do another. If you skip it, the set counts as the planned effort.")
                    block("Training blocks", "calendar",
                          "Train in blocks of 3–6 weeks. Week one stops about 3 reps short of failure; each week gets closer, and the last hard week goes to failure on isolation lifts (1 rep short on compounds). Then a deload week — half the sets, about 10% lighter — lets fatigue clear so you come back stronger.")
                    block("Weight and reps", "scalemass",
                          "Your strength each session is estimated from weight, reps and the reps you had left. Next time aims a little above it. If the next weight up keeps you inside your rep range, the coach adds weight; if that jump is too big, it adds reps instead; if your reps fell below the range, it lightens the load.")
                    block("Sets", "square.stack.3d.up",
                          "After a workout you can rate each muscle's pump, soreness since last time, workload and joint pain. Barely sore, low pump and easy → one more set next time. Still sore, too much or painful joints → one set fewer. Sets never go up while your performance is dropping, or on a strained recovery day.")
                    block("Weekly sets per muscle", "chart.bar",
                          "Each muscle has a weekly range: the fewest sets that still grow it and the most you can recover from. A block starts near the bottom and climbs toward the top, and each workout gets its share of what's left this week. The ranges start from published guidelines and learn from your answers: \"too much\" or \"still sore\" lowers the top; easy and barely sore near the top raises it.")
                    block("Joint pain", "bandage",
                          "Tap the bandage on an exercise if it bothered your joints. Pain a lot → one set fewer next time. Pain two sessions running → the coach suggests swaps for the same muscle, ranked by what hasn't hurt you, your pump, and similar equipment.")
                    block("Stalls", "chart.line.flattrend.xyaxis",
                          "If a lift hasn't improved for three sessions, the coach adds a set early in a block, or suggests deloading if you're near the end of one. Two drops in a row means fatigue is winning: one set fewer. Six sessions without progress: try a variation of the exercise.")
                    Text("These rules follow the hypertrophy-periodisation approach: rising effort across a block, volume guided by how the muscle responds, and planned deloads. They're guidance, not a prescription — if something hurts, stop.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(20)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("How the coach works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func block(_ title: LocalizedStringKey, _ symbol: String, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Rep range in the routine editor

struct RepRangeMenu: View {
    @Binding var planned: PlannedExercise

    private static let presets: [ClosedRange<Int>] = [5...8, 6...10, 8...12, 10...15, 12...20, 15...30]

    var body: some View {
        let exercise = ExerciseLibrary.shared.exercise(id: planned.exerciseID)
        let range = planned.repRange ?? ProgressionCoach.defaultRepRange(for: exercise)
        Menu {
            Button {
                planned.repLow = nil
                planned.repHigh = nil
            } label: {
                if planned.repRange == nil { Label("Automatic", systemImage: "checkmark") } else { Text("Automatic") }
            }
            ForEach(Self.presets, id: \.self) { preset in
                Button {
                    planned.repLow = preset.lowerBound
                    planned.repHigh = preset.upperBound
                } label: {
                    let text = String(localized: "\(preset.lowerBound)–\(preset.upperBound) reps")
                    if planned.repRange == preset { Label(text, systemImage: "checkmark") } else { Text(text) }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(verbatim: "\(range.lowerBound)–\(range.upperBound)")
                    .monospacedDigit()
                Text("reps")
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold))
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(planned.repRange == nil ? Theme.textTertiary : Theme.accent)
        }
        .buttonStyle(.borderless)
    }
}

// MARK: - Weekly sets

struct WeeklyVolumeCard: View {
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]

    var body: some View {
        let block = TrainingBlock.load()
        let week = VolumePlanner.week(containing: Date(), block: block)
        let done = VolumePlanner.sets(in: week, logs: logs)
        let muscles = VolumePlanner.trainedMuscles(logs: logs)

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("WEEKLY SETS")
                    .font(.eyebrow).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                Text(muscles.isEmpty ? String(localized: "Plans appear once you've trained")
                                     : String(localized: "\(week.start.formatted(.dateTime.day().month(.abbreviated))) – \(week.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))"))
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            if muscles.isEmpty {
                Text("Log a few workouts and each muscle you train gets a weekly set target that grows through the block.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 10) {
                    ForEach(muscles) { muscle in
                        row(muscle, done: done[muscle] ?? 0,
                            target: VolumePlanner.weeklyTarget(for: muscle, block: block),
                            marks: VolumePlanner.landmarks(for: muscle))
                    }
                }
                Text("Hard sets this block week (assisting muscles count half). Grey numbers are each muscle's range — they adjust to your feedback.")
                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .card(padding: 16)
    }

    private func row(_ muscle: Muscle, done: Double, target: Int, marks: VolumeLandmarks) -> some View {
        let fraction = target > 0 ? min(done / Double(target), 1) : 0
        let complete = done >= Double(target) - 0.25
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(muscle.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary)
                if VolumePlanner.isPersonalised(muscle) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.accent)
                        .accessibilityLabel("Range learned from your feedback")
                }
                Spacer()
                Text(verbatim: "\(format(done)) / \(target)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(complete ? Theme.good : Theme.textPrimary)
                Text(verbatim: "\(Int(marks.mev))–\(Int(marks.mrv))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textTertiary)
                    .frame(width: 38, alignment: .trailing)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(complete ? Theme.good : Theme.accent)
                        .frame(width: max(geo.size.width * fraction, fraction > 0 ? 6 : 0))
                }
            }
            .frame(height: 6)
        }
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }
}

// MARK: - Coach off

struct CoachOffCard: View {
    @AppStorage(CoachSettings.key) private var coachEnabled = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text("Progression coach").font(.subheadline.weight(.semibold))
                Text("Off. Your RIR and progress are still tracked, so suggestions are ready the moment you turn it on.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            Toggle("Progression coach", isOn: $coachEnabled)
                .labelsHidden()
                .tint(Theme.accent)
        }
        .card(padding: 14)
    }
}

// MARK: - Swap

struct SwapExerciseSheet: View {
    let exercise: Exercise
    let excluding: Set<String>
    let onPick: (Exercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var options: [Exercise]?

    var body: some View {
        NavigationStack {
            List {
                let joints = ExerciseRanking.joints(for: exercise.id, logs: logs)
                if joints.hurtTimes > 0 {
                    Section {
                        Label("Hurt your joints \(joints.hurtTimes) of the last \(joints.rated) times rated.", systemImage: "bandage")
                            .font(.footnote).foregroundStyle(Theme.warn)
                    }
                }
                Section {
                    if let options {
                        if options.isEmpty {
                            Text("No similar exercises found.").foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(options) { option in
                            Button {
                                onPick(option)
                                dismiss()
                            } label: {
                                HStack(spacing: 12) {
                                    ExerciseDemo(exercise: option, animated: false, cornerRadius: 8)
                                        .frame(width: 44, height: 44)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(option.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                        Text(caption(option)).font(.caption).foregroundStyle(Theme.textTertiary)
                                    }
                                    Spacer()
                                }
                            }
                        }
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                } header: {
                    Text("Same muscle, kindest on your joints first")
                }
            }
            .navigationTitle("Swap \(exercise.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                await ExerciseLibrary.shared.loadIfNeeded()
                options = ExerciseRanking.alternatives(to: exercise, logs: logs, excluding: excluding, limit: 8)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func caption(_ option: Exercise) -> String {
        let joints = ExerciseRanking.joints(for: option.id, logs: logs)
        var parts = [option.equipmentLabel]
        if joints.rated > 0 {
            parts.append(joints.hurtTimes == 0 ? String(localized: "no joint pain so far") : String(localized: "hurt \(joints.hurtTimes)×"))
        }
        return parts.joined(separator: " · ")
    }
}

/// Small orange marker for exercises that keep hurting.
struct JointWarningBadge: View {
    let history: ExerciseRanking.JointHistory

    var body: some View {
        Label("Hurt \(history.hurtTimes)× recently", systemImage: "bandage.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.warn)
            .labelStyle(.titleAndIcon)
    }
}
