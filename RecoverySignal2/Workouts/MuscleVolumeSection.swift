//
//  MuscleVolumeSection.swift
//  RecoverySignal2
//
//  Weekly hard sets per muscle from the workouts you log: a radar with every
//  muscle around the circle (further out = more sets) and a front/back body
//  map that darkens with volume. Shoulders are split into front, side and rear
//  delts by exercise name; anything else uses the exercise library's muscles.
//

import SwiftUI
import SwiftData

enum LoggedMuscleVolume {

    /// Library muscle names → the radar's muscle groups. Generic "shoulders"
    /// becomes front delts (most shoulder moves in the library are presses).
    private static func muscles(forLibraryName name: String) -> [Muscle] {
        switch name {
        case "chest":        [.chest]
        case "shoulders":    [.frontDelts]
        case "biceps":       [.biceps]
        case "triceps":      [.triceps]
        case "forearms":     [.forearms]
        case "lats":         [.lats]
        case "middle back":  [.upperBack]
        case "lower back":   [.lowerBack]
        case "traps", "neck": [.traps]
        case "abdominals":   [.abs]
        case "quadriceps":   [.quads]
        case "hamstrings":   [.hamstrings]
        case "glutes", "abductors": [.glutes]
        case "adductors":    [.adductors]
        case "calves":       [.calves]
        default:             []
        }
    }

    /// Sets per muscle for one hard set of a library exercise: the researched
    /// rules in MuscleMapping first, otherwise primary 1 and secondary 0.5.
    static func weights(for exercise: Exercise) -> [Muscle: Double] {
        if let named = MuscleMapping.weights(for: exercise.name) { return named }
        var weights: [Muscle: Double] = [:]
        exercise.secondaryMuscles.flatMap { muscles(forLibraryName: $0) }.forEach { weights[$0] = 0.5 }
        exercise.primaryMuscles.flatMap { muscles(forLibraryName: $0) }.forEach { weights[$0] = 1 }
        return weights
    }

    /// Primary muscles count a full set, secondary muscles half.
    static func weights(for exercise: LoggedExercise) -> [Muscle: Double] {
        if let named = MuscleMapping.weights(for: exercise.name) { return named }
        var weights: [Muscle: Double] = [:]
        if let libraryExercise = ExerciseLibrary.shared.exercise(id: exercise.exerciseID) {
            libraryExercise.secondaryMuscles.flatMap { muscles(forLibraryName: $0) }.forEach { weights[$0] = 0.5 }
            libraryExercise.primaryMuscles.flatMap { muscles(forLibraryName: $0) }.forEach { weights[$0] = 1 }
        } else {
            muscles(forLibraryName: exercise.primaryMuscle).forEach { weights[$0] = 1 }
        }
        return weights
    }

    static func weeklySets(logs: [WorkoutLog], sessions: [StrengthSession], weekContaining date: Date,
                           calendar: Calendar = .current) -> [Muscle: Double] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [:] }
        var totals = MuscleVolume.weeklySets(sessions: sessions, weekContaining: date, calendar: calendar)
        for log in logs where week.contains(log.start) {
            for exercise in log.exercises {
                let hardSets = Double(exercise.completedSets.filter { $0.kind != .warmup }.count)
                guard hardSets > 0 else { continue }
                for (muscle, weight) in weights(for: exercise) {
                    totals[muscle, default: 0] += hardSets * weight
                }
            }
        }
        return totals
    }
}

struct MuscleVolumeSection: View {
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]
    @State private var weekOffset = 0
    @State private var view: Style = .radar

    enum Style: String, CaseIterable { case radar = "Radar", body = "Body" }

    private var calendar: Calendar { .current }

    private var weekStart: Date {
        let base = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: base) ?? base
    }

    var body: some View {
        let sets = LoggedMuscleVolume.weeklySets(logs: logs, sessions: sessions, weekContaining: weekStart)
        let weekLogs = logs.filter { calendar.dateInterval(of: .weekOfYear, for: weekStart)?.contains($0.start) == true }
        let totalSets = sets.values.reduce(0, +)

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Muscles trained", icon: .training)

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Button { withAnimation(.snappy) { weekOffset -= 1 } } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30)
                    }
                    Spacer()
                    VStack(spacing: 1) {
                        Text(LocalizedStringKey(weekTitle)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                        Text("\(weekLogs.count) workout\(weekLogs.count == 1 ? "" : "s") · \(Int(totalSets.rounded())) weighted sets")
                            .font(.caption).monospacedDigit().foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Button { withAnimation(.snappy) { weekOffset += 1 } } label: {
                        Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold)).frame(width: 30, height: 30)
                    }
                    .disabled(weekOffset >= 0)
                }
                .tint(Theme.accent)

                Picker("View", selection: $view) {
                    ForEach(Style.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if totalSets == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: "figure.strengthtraining.traditional")
                            .font(.system(size: 30))
                            .foregroundStyle(Theme.textTertiary)
                        Text("No sets logged this week")
                            .font(.subheadline.weight(.semibold))
                        Text("Finish a workout here and every ticked set fills in the radar and body map.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else if view == .radar {
                    MuscleRadar(sets: sets)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity)
                } else {
                    VStack(spacing: 10) {
                        BodyMap(sets: sets)
                            .frame(height: 300)
                        BodyMapLegend()
                    }
                    .transition(.opacity)
                }

                if totalSets > 0 {
                    focusRow(sets)
                }

                Text("Hard sets per muscle — warm-ups don't count; the main target gets a full set, assisting muscles half. About 10–20 sets a week per muscle is the usual range for growth.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .card(padding: 16)
        }
        .sensoryFeedback(.selection, trigger: weekOffset)
        .sensoryFeedback(.selection, trigger: view)
    }

    /// Most trained and most neglected muscles at a glance.
    private func focusRow(_ sets: [Muscle: Double]) -> some View {
        let sorted = Muscle.allCases.map { ($0, sets[$0] ?? 0) }.sorted { $0.1 > $1.1 }
        let top = sorted.prefix(3).filter { $0.1 > 0 }
        let under = sorted.reversed().prefix(3)
        return HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("MOST").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.good)
                ForEach(Array(top), id: \.0) { muscle, value in
                    Text("\(muscle.name) · \(format(value))").font(.caption).foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text("LEAST").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.warn)
                ForEach(Array(under), id: \.0) { muscle, value in
                    Text("\(muscle.name) · \(format(value))").font(.caption).foregroundStyle(Theme.textPrimary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private func format(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }

    private var weekTitle: String {
        switch weekOffset {
        case 0:  return "This week"
        case -1: return "Last week"
        default:
            let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }
}
