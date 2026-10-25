//
//  HealthWidgets.swift
//  HealthWidgets (widget extension)
//
//  The widget bundle and the Live Activity designs (Lock Screen and Dynamic
//  Island). Home and Lock Screen widgets live in HomeWidgets.swift for the Lock Screen and
//  Dynamic Island. The app writes the numbers; this only draws them.
//

import WidgetKit
import SwiftUI
import ActivityKit

@main
struct HealthWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        BedtimeWidget()
        MacroLiveActivityWidget()
        WorkoutLiveActivityWidget()
    }
}

// MARK: - Palette
// Quiet and premium: graphite ground, white type, one muted tint per macro.

private enum Palette {
    static let ground = Color(red: 0.07, green: 0.075, blue: 0.085)
    static let groundTop = Color(red: 0.12, green: 0.125, blue: 0.14)
    static let track = Color.white.opacity(0.1)
    static let secondary = Color.white.opacity(0.55)
    static let tertiary = Color.white.opacity(0.38)
    static let accent = Color(red: 0x4C / 255, green: 0x8D / 255, blue: 0xFF / 255)
    static let accentDeep = Color(red: 0x0F / 255, green: 0x4F / 255, blue: 0xD6 / 255)
    static let mint = Color(red: 0x5A / 255, green: 0xA9 / 255, blue: 0xFF / 255)
    static let protein = Color(red: 0.85, green: 0.50, blue: 0.48)
    static let carbs = Color(red: 0.37, green: 0.61, blue: 0.80)
    static let fat = Color(red: 0.83, green: 0.68, blue: 0.34)
    static let good = Color(red: 0.36, green: 0.80, blue: 0.55)
    static let warn = Color(red: 0.98, green: 0.74, blue: 0.35)
    static let bad = Color(red: 0.98, green: 0.45, blue: 0.42)

    static func band(_ score: Int?) -> Color {
        guard let score else { return tertiary }
        return score >= 67 ? good : (score >= 34 ? warn : bad)
    }
}

// MARK: - Workout Live Activity

struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            WorkoutLockScreenView(attributes: context.attributes, state: context.state)
                .padding(12)
                .activityBackgroundTint(Palette.ground.opacity(0.92))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(context.attributes.start, style: .timer).monospacedDigit()
                    } icon: {
                        Image(systemName: "figure.strengthtraining.traditional")
                    }
                    .font(.headline)
                    .foregroundStyle(Palette.good)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(state.setsDone)/\(state.setsTotal) sets")
                        .font(.headline)
                        .monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(state.exerciseName).font(.subheadline).lineLimit(1)
                                if let description = state.setDescription, state.setID != nil {
                                    Text(description).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                                }
                            }
                            Spacer()
                            if let rest = state.restEndsAt, rest > .now {
                                Text(timerInterval: Date.now...rest, countsDown: true)
                                    .monospacedDigit().foregroundStyle(Palette.warn)
                                    .frame(width: 55)
                            }
                        }
                        WorkoutSetControls(state: state)
                    }
                }
            } compactLeading: {
                Image(systemName: state.restEndsAt.map { $0 > .now } == true ? "timer" : "figure.strengthtraining.traditional")
                    .foregroundStyle(state.restEndsAt.map { $0 > .now } == true ? Palette.warn : Palette.good)
            } compactTrailing: {
                if let rest = state.restEndsAt, rest > .now {
                    Text(timerInterval: Date.now...rest, countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                        .foregroundStyle(Palette.warn)
                } else {
                    Text(context.attributes.start, style: .timer)
                        .monospacedDigit()
                        .frame(maxWidth: 52)
                        .foregroundStyle(Palette.good)
                }
            } minimal: {
                Image(systemName: "figure.strengthtraining.traditional").foregroundStyle(Palette.good)
            }
            .keylineTint(Palette.good)
        }
    }
}

private struct WorkoutLockScreenView: View {
    let attributes: WorkoutActivityAttributes
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(attributes.workoutName).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1)
                Spacer(minLength: 0)
                Text(attributes.start, style: .timer).font(.subheadline.weight(.semibold)).monospacedDigit()
                    .fixedSize()
                Text("\(state.setsDone)/\(state.setsTotal) sets").font(.caption.weight(.semibold)).monospacedDigit()
            }
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(state.exerciseName).font(.subheadline.weight(.medium)).lineLimit(1)
                        if let number = state.setNumber {
                            Text("Set \(number)").font(.caption).foregroundStyle(Palette.secondary).fixedSize()
                        }
                    }
                    if let description = state.setDescription, state.setID != nil {
                        Text(description).font(.caption).foregroundStyle(Palette.secondary).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                Spacer(minLength: 4)
                if let rest = state.restEndsAt, rest > .now {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Rest").font(.caption2)
                        Text(timerInterval: Date.now...rest, countsDown: true).font(.headline).monospacedDigit().frame(width: 58)
                    }.foregroundStyle(Palette.warn)
                }
            }
            WorkoutSetControls(state: state)
        }
        .foregroundStyle(.white)
    }
}

private struct WorkoutSetControls: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if let workoutID = state.workoutID {
            HStack(spacing: 10) {
                if let exerciseID = state.exerciseID, let setID = state.setID {
                    Button(intent: UpdateWorkoutSetIntent(workoutID: workoutID, exerciseID: exerciseID, setID: setID, completed: true)) {
                        Label("Complete set", systemImage: "checkmark")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Palette.good.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Palette.good)
                    .disabled(state.canComplete != true)
                    .accessibilityHint("Logs the displayed weight and reps and starts rest.")
                } else {
                    Text("Finish your workout in Trace").font(.caption).foregroundStyle(Palette.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let exerciseID = state.undoExerciseID, let setID = state.undoSetID {
                    Button(intent: UpdateWorkoutSetIntent(workoutID: workoutID, exerciseID: exerciseID, setID: setID, completed: false)) {
                        Label("Undo", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.medium))
                            .frame(minHeight: 44)
                            .padding(.horizontal, 10)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white)
                    .accessibilityHint("Unchecks the most recently completed working set.")
                }
            }
        }
    }
}

// MARK: - Macro Live Activity
// Calm by design: system material behind it (so it follows the Lock Screen's
// light or dark look as the wallpaper darkens), soft tints, numbers eaten.

private enum SoftTint {
    static let protein = Color(red: 0.75, green: 0.38, blue: 0.35)
    static let carbs = Color(red: 0.25, green: 0.48, blue: 0.67)
    static let fat = Color(red: 0.72, green: 0.57, blue: 0.23)
    static let calories = Color(red: 0.36, green: 0.58, blue: 0.95)
}

struct MacroLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MacroActivityAttributes.self) { context in
            MacroLockScreenView(state: context.state)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let s = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(s.caloriesEaten.formatted())")
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text("kcal eaten").font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let bed = s.bedtime {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text(bed, style: .time)
                                .font(.system(size: 22, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("bed by").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 4)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    MacroBars(state: s).padding(.top, 6)
                }
            } compactLeading: {
                Image(systemName: "fork.knife").foregroundStyle(SoftTint.calories)
            } compactTrailing: {
                Text("\(s.caloriesEaten)")
                    .monospacedDigit()
                    .foregroundStyle(SoftTint.calories)
            } minimal: {
                Image(systemName: "fork.knife").foregroundStyle(SoftTint.calories)
            }
            .keylineTint(SoftTint.calories)
        }
    }
}

private struct MacroLockScreenView: View {
    let state: MacroActivityAttributes.ContentState

    private var fraction: Double {
        guard state.caloriesTarget > 0 else { return 0 }
        return min(Double(state.caloriesEaten) / Double(state.caloriesTarget), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle().stroke(SoftTint.calories.opacity(0.2), lineWidth: 5)
                    Circle()
                        .trim(from: 0, to: max(fraction, state.caloriesEaten > 0 ? 0.02 : 0))
                        .stroke(SoftTint.calories, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    if state.caloriesTarget > 0 {
                        Text(verbatim: "\(Int((fraction * 100).rounded()))%")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    } else {
                        Image(systemName: "fork.knife").font(.system(size: 13))
                    }
                }
                .frame(width: 50, height: 50)

                VStack(alignment: .leading, spacing: 1) {
                    Text("EATEN TODAY")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(state.caloriesEaten.formatted())")
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(state.caloriesTarget > 0 ? "/ \(state.caloriesTarget.formatted()) kcal" : "kcal")
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if let bed = state.bedtime {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("BED BY")
                            .font(.system(size: 10, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 4) {
                            Image(systemName: "moon.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                            Text(bed, style: .time)
                                .font(.system(size: 18, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                        }
                    }
                }
            }
            MacroBars(state: state)
        }
    }
}

private struct MacroBars: View {
    let state: MacroActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            macro("Protein", state.proteinEaten, state.proteinTarget, SoftTint.protein)
            macro("Carbs", state.carbsEaten, state.carbsTarget, SoftTint.carbs)
            macro("Fat", state.fatEaten, state.fatTarget, SoftTint.fat)
        }
    }

    private func macro(_ label: LocalizedStringKey, _ eaten: Int, _ target: Int, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                Text(verbatim: "\(eaten) g")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.2))
                    Capsule().fill(color)
                        .frame(width: max(geo.size.width * min(Double(eaten) / Double(max(target, 1)), 1), eaten > 0 ? 3 : 0))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity)
    }
}
