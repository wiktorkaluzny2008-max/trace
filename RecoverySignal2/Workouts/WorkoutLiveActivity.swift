//
//  WorkoutLiveActivity.swift
//  RecoverySignal2
//
//  The running workout on the Lock Screen and in the Dynamic Island (the
//  timer next to the camera): elapsed time, the exercise you're on, sets done
//  and a rest countdown. Also shows rest-over notifications while the app is
//  open. `WorkoutActivityAttributes` must match the widget extension's copy.
//

import Foundation
import ActivityKit
import UserNotifications

nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var exerciseName: String
        var setsDone: Int
        var setsTotal: Int
        var restEndsAt: Date?
        // Optional for compatibility with activities created by an older app build.
        var workoutID: UUID?
        var exerciseID: UUID?
        var setID: UUID?
        var setNumber: Int?
        var setDescription: String?
        var canComplete: Bool?
        var undoExerciseID: UUID?
        var undoSetID: UUID?
    }

    var workoutName: String
    var start: Date
}

@MainActor
enum WorkoutLiveActivity {

    private static var updateTask: Task<Void, Never>?

    static func sync(_ workout: ActiveWorkout?, restEndsAt: Date?) {
        // Serialize ActivityKit updates so rapid edits cannot publish older state last.
        let previous = updateTask
        updateTask = Task {
            await previous?.value
            await publish(workout, restEndsAt: restEndsAt)
        }
    }

    static func flush() async { await updateTask?.value }

    private static func publish(_ workout: ActiveWorkout?, restEndsAt: Date?) async {
        guard let workout else {
            for activity in Activity<WorkoutActivityAttributes>.activities {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        let working = workout.exercises.flatMap(\.sets).filter { $0.kind != .warmup }
        let current = workout.exercises.first { $0.sets.contains { !$0.completed && $0.kind != .warmup } }
        let index = current?.sets.firstIndex { !$0.completed && $0.kind != .warmup }
        let set = index.flatMap { current?.sets[$0] }
        let hint = index.flatMap { current?.hint(for: $0) }
        let weight = set?.weightKg ?? hint?.weightKg
        let reps = set?.reps ?? hint?.reps
        let seconds = set?.seconds ?? hint?.seconds
        let ready: Bool
        let description: String
        switch current?.tracking {
        case .weightReps:
            ready = weight.map { $0.isFinite && $0 >= 0 } == true && (reps ?? 0) > 0
            description = ready ? "\(weight!.formatted(.number.precision(.fractionLength(0...2)))) kg × \(reps!)" : String(localized: "Enter weight and reps in Trace")
        case .reps:
            ready = (reps ?? 0) > 0
            description = ready ? String(localized: "\(reps!) reps") : String(localized: "Enter reps in Trace")
        case .duration:
            ready = (seconds ?? 0) > 0
            description = ready ? String(localized: "\(seconds!) sec") : String(localized: "Enter duration in Trace")
        case nil:
            ready = false
            description = String(localized: "All working sets logged")
        }
        let latest = workout.exercises.flatMap { exercise in
            exercise.sets.filter { $0.completed && $0.kind != .warmup && $0.completedAt != nil }
                .map { (exercise.id, $0) }
        }.max { ($0.1.completedAt ?? .distantPast) < ($1.1.completedAt ?? .distantPast) }
        let state = WorkoutActivityAttributes.ContentState(
            exerciseName: current?.name ?? String(localized: "All working sets logged"),
            setsDone: working.filter(\.completed).count, setsTotal: working.count,
            restEndsAt: restEndsAt.flatMap { $0 > Date() ? $0 : nil },
            workoutID: workout.id, exerciseID: current?.id, setID: set?.id,
            setNumber: index.map { i in current!.sets[...i].filter { $0.kind != .warmup }.count },
            setDescription: description, canComplete: ready,
            undoExerciseID: latest?.0, undoSetID: latest?.1.id)
        let content = ActivityContent(state: state, staleDate: nil)
        if let activity = Activity<WorkoutActivityAttributes>.activities.first(where: { $0.attributes.start == workout.start }) {
            await activity.update(content)
        } else {
            for stale in Activity<WorkoutActivityAttributes>.activities {
                await stale.end(nil, dismissalPolicy: .immediate)
            }
            _ = try? Activity.request(attributes: WorkoutActivityAttributes(workoutName: workout.name, start: workout.start),
                                      content: content, pushType: nil)
        }
    }
}

/// Lets notifications (like "Rest over") appear as banners even while the
/// app is on screen.
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
