//
//  WorkoutRecorder.swift
//  RecoverySignal2
//
//  The workout in progress: its exercises and sets, the clock, live heart
//  rate from Apple Health, and the rest timer. The draft is saved on every
//  change, so closing the app mid-session loses nothing.
//
//  Heart rate: the iPhone has no sensor, so readings come from whatever
//  writes heart rate to Health — normally your Apple Watch. The Watch samples
//  every few minutes on its own and every few seconds if you also start a
//  Strength workout on it.
//

import Foundation
import HealthKit
import SwiftData
import UIKit
import UserNotifications

struct ActiveWorkout: Codable {
    var id = UUID()
    var name: String
    var routineID: UUID?
    var start = Date()
    var exercises: [LoggedExercise]
}

@MainActor
@Observable
final class WorkoutRecorder {
    static let shared = WorkoutRecorder()

    // Presentation, owned here so any screen can open the tracker.
    var showsHome = false
    var showsActive = false

    var saveError: String?
    var selectedSetID: UUID? { didSet { persist() } }
    private var draftStore: WorkoutDraftStore?
    private var restoring = true
    private var batchingDraft = false
    private struct Snapshot: Codable {
        var active: ActiveWorkout?
        var restEndsAt: Date?
        var restDuration: Int
        var selectedSetID: UUID?
    }

    private(set) var active: ActiveWorkout? {
        didSet {
            persist()
            WorkoutLiveActivity.sync(active, restEndsAt: restEndsAt)
        }
    }

    // Live heart rate
    private(set) var heartRate: Double?
    private(set) var heartRateAt: Date?
    private(set) var heartRateSamples: [(date: Date, bpm: Double)] = []
    private var heartRateQuery: HKAnchoredObjectQuery?

    // Rest timer
    private(set) var restEndsAt: Date? {
        didSet {
            persist()
            WorkoutLiveActivity.sync(active, restEndsAt: restEndsAt)
        }
    }
    private(set) var restDuration: Int = 0

    private static let draftKey = "workout.activeDraft"
    private let store = HealthKitManager.shared.store

    private init() {
        defer { restoring = false }
        do {
            let url = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                 appropriateFor: nil, create: true)
                .appendingPathComponent("Trace/workout-draft.sqlite")
            draftStore = try WorkoutDraftStore(url: url)
            if let data = try draftStore?.read() {
                let snapshot = try JSONDecoder().decode(Snapshot.self, from: data)
                active = snapshot.active
                restEndsAt = snapshot.restEndsAt.flatMap { $0 > Date() ? $0 : nil }
                restDuration = snapshot.restDuration
                selectedSetID = snapshot.selectedSetID
            } else if let data = UserDefaults.standard.data(forKey: Self.draftKey) {
                // Leave the old draft intact as a migration backup.
                active = try JSONDecoder().decode(ActiveWorkout.self, from: data)
                restEndsAt = (UserDefaults.standard.object(forKey: "workout.restEndsAt") as? Date).flatMap { $0 > Date() ? $0 : nil }
                restDuration = restEndsAt.map { Int(ceil($0.timeIntervalSinceNow)) } ?? 0
                try draftStore?.write(JSONEncoder().encode(Snapshot(active: active, restEndsAt: restEndsAt,
                                                                    restDuration: restDuration, selectedSetID: nil)))
            }
            if let active { startHeartRate(from: active.start) }
        } catch {
            // Do not overwrite an unreadable draft. Surface the storage issue.
            draftStore = nil
            saveError = "Workout recovery is unavailable: \(error.localizedDescription)"
        }
    }

    var isActive: Bool { active != nil }

    var maxHeartRate: Double { HealthKitManager.shared.ageBasedMaxHeartRate() ?? 190 }

    // MARK: Lifecycle

    func start(name: String, routine: WorkoutRoutine?, logs: [WorkoutLog]) {
        cancelRest()
        let library = ExerciseLibrary.shared
        TrainingBlock.restartIfLongBreak(lastWorkout: logs.map(\.start).max())
        let block = TrainingBlock.load()
        let strained = ProgressionCoach.todayIsStrained()
        let coach = CoachSettings.isEnabled
        let planned = routine?.exercises ?? []
        // The coach always works out its targets, so switching it on later has
        // history to go on; when it's off they just aren't shown or used.
        let shares = VolumePlanner.allocate(planned.map { ($0.exerciseID, $0.name, library.exercise(id: $0.exerciseID)) },
                                            logs: logs, block: block)
        let exercises: [LoggedExercise] = planned.enumerated().map { index, planned in
            let exercise = library.exercise(id: planned.exerciseID)
            // Boxes start empty; the coach's targets (or last time) show as grey hints.
            let previous = WorkoutHistory.previousSets(for: planned.exerciseID, in: logs)
            let target = ProgressionCoach.recommend(exerciseID: planned.exerciseID, exercise: exercise,
                                                    plannedSets: planned.sets, repRange: planned.repRange,
                                                    logs: logs, block: block, strained: strained, share: shares[index])
            return LoggedExercise(exerciseID: planned.exerciseID, name: planned.name,
                                  primaryMuscle: exercise?.primaryMuscle ?? "other",
                                  tracking: exercise?.tracking ?? .weightReps,
                                  restSeconds: planned.restSeconds, notes: planned.notes,
                                  sets: coach ? Self.startingSets(previous: previous, working: target.sets)
                                              : Self.plainSets(previous: previous, count: planned.sets),
                                  previous: previous.isEmpty ? nil : previous, target: target, coachApplied: coach)
        }
        active = ActiveWorkout(name: name, routineID: routine?.id, exercises: coach ? Self.capAddedSets(exercises) : exercises)
        routine?.lastPerformed = Date()
        startHeartRate(from: Date())
        Task { _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) }
        UINotificationFeedbackGenerator().notificationOccurred(.success)

        // Let the home sheet finish closing before the full-screen tracker opens.
        showsHome = false
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            showsActive = true
        }
    }

    func discard() {
        stopHeartRate()
        cancelRest()
        active = nil
        showsActive = false
    }

    /// Saves the log (and optionally an Apple Health workout) and ends the session.
    func finish(name: String, notes: String, feedback: [MuscleFeedback] = [], saveToHealth: Bool, context: ModelContext) async -> WorkoutLog? {
        guard var workout = active else { return nil }
        saveError = nil
        let end = Date()

        // Keep only sets you actually ticked off.
        workout.exercises = workout.exercises
            .map { var e = $0; e.sets = e.sets.filter(\.completed); e.previous = nil; return e }
            .filter { !$0.sets.isEmpty }

        let samples = (try? await HealthKitManager.shared.heartRateSamples(from: workout.start, to: end)) ?? heartRateSamples
        let bpm = samples.map(\.bpm)
        let average = Stats.mean(bpm)
        let log = WorkoutLog(name: name.isEmpty ? workout.name : name, routineID: workout.routineID,
                             start: workout.start, end: end, exercises: workout.exercises)
        log.notes = notes
        log.feedback = feedback.filter { !$0.isEmpty }
        log.averageHeartRate = average
        log.maxHeartRate = bpm.max()
        log.calories = Self.estimateCalories(minutes: end.timeIntervalSince(workout.start) / 60, averageHR: average)

        // Record how ready you were going in: the labels a personal performance model learns from.
        let healthDays = (try? context.fetch(FetchDescriptor<DailyMetrics>())) ?? []
        let dayTags = (try? context.fetch(FetchDescriptor<DayTag>())) ?? []
        log.readiness = ReadinessSnapshot.capture(at: workout.start, days: healthDays, tags: dayTags)

        context.insert(log)
        do { try context.save() }
        catch {
            context.delete(log)
            saveError = "Your workout is still open. Saving failed: \(error.localizedDescription)"
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return nil
        }
        cancelRest()
        stopHeartRate()
        active = nil
        // If the Watch recorded this session too, link to it: use its calories
        // and don't write a second copy to Health.
        if let watch = await HealthWorkoutFeed.shared.overlapping(start: workout.start, end: end) {
            log.healthWorkoutID = watch.id
            log.calories = watch.calories ?? log.calories
            log.averageHeartRate = watch.averageHeartRate ?? log.averageHeartRate
            log.maxHeartRate = watch.maxHeartRate ?? log.maxHeartRate
        } else if saveToHealth {
            log.savedToHealth = await saveToAppleHealth(log)
        }

        do { try context.save() }
        catch { saveError = "Workout saved locally. Health link could not be saved: \(error.localizedDescription)" }
        // Let feedback tune the weekly set ranges.
        if !log.feedback.isEmpty {
            let all = (try? context.fetch(FetchDescriptor<WorkoutLog>())) ?? [log]
            VolumePlanner.learn(from: log, logs: all, block: TrainingBlock.load())
        }
        active = nil
        // Pull the new workout into Today's training numbers.
        try? await MetricsAggregator(context: context).refresh(days: 2)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return log
    }

    // MARK: Editing

    func update(_ transform: (inout ActiveWorkout) -> Void) {
        guard var workout = active else { return }
        transform(&workout)
        active = workout
    }

    func addExercises(_ exercises: [Exercise], logs: [WorkoutLog]) {
        let block = TrainingBlock.load()
        let strained = ProgressionCoach.todayIsStrained()
        let coach = CoachSettings.isEnabled
        let shares = VolumePlanner.allocate(exercises.map { ($0.id, $0.name, $0) }, logs: logs, block: block)
        update { workout in
            for (index, exercise) in exercises.enumerated() {
                workout.exercises.append(Self.logged(exercise, logs: logs, date: workout.start, block: block,
                                                     strained: strained, share: shares[index], coach: coach))
            }
        }
    }

    private static func logged(_ exercise: Exercise, logs: [WorkoutLog], date: Date, block: TrainingBlock,
                                strained: Bool, share: VolumePlanner.SessionShare?, coach: Bool) -> LoggedExercise {
        let previous = WorkoutHistory.previousSets(for: exercise.id, in: logs)
        let target = ProgressionCoach.recommend(exerciseID: exercise.id, exercise: exercise, plannedSets: nil,
                                                repRange: nil, logs: logs, date: date,
                                                block: block, strained: strained, share: share)
        return LoggedExercise(exerciseID: exercise.id, name: exercise.name,
                              primaryMuscle: exercise.primaryMuscle,
                              tracking: exercise.tracking,
                              sets: coach ? startingSets(previous: previous, working: target.sets)
                                          : plainSets(previous: previous, count: previous.isEmpty ? 3 : previous.count),
                              previous: previous.isEmpty ? nil : previous, target: target, coachApplied: coach)
    }

    /// Swaps an exercise that hasn't been started for another, with fresh targets.
    func swapExercise(_ id: UUID, to exercise: Exercise, logs: [WorkoutLog]) {
        let block = TrainingBlock.load()
        let strained = ProgressionCoach.todayIsStrained()
        update { workout in
            guard let i = workout.exercises.firstIndex(where: { $0.id == id }) else { return }
            let old = workout.exercises[i]
            let share = VolumePlanner.allocate([(exercise.id, exercise.name, exercise)], logs: logs, block: block).first ?? nil
            var replacement = Self.logged(exercise, logs: logs, date: workout.start, block: block, strained: strained,
                                          share: share, coach: CoachSettings.isEnabled)
            replacement.restSeconds = old.restSeconds
            workout.exercises[i] = replacement
        }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func setJointPain(_ pain: MuscleFeedback.JointPain?, exercise id: UUID) {
        update { workout in
            if let i = workout.exercises.firstIndex(where: { $0.id == id }) { workout.exercises[i].jointPain = pain }
        }
    }

    /// Without the coach: last session's set pattern, like before.
    private static func plainSets(previous: [LoggedSet], count: Int) -> [LoggedSet] {
        (0..<max(count, 1)).map { i in
            LoggedSet(kind: previous.indices.contains(i) && previous[i].kind == .warmup ? .warmup : .normal)
        }
    }

    /// Feedback is per muscle but targets are per exercise: without this, two
    /// shoulder exercises would each add two sets. Added sets per muscle are
    /// capped at the largest single suggestion, at most one per exercise when
    /// several train the same muscle.
    private static func capAddedSets(_ exercises: [LoggedExercise]) -> [LoggedExercise] {
        var budget: [String: Int] = [:]
        for e in exercises { if let change = e.target?.setChange, change > 0 { budget[e.primaryMuscle] = max(budget[e.primaryMuscle] ?? 0, change) } }
        return exercises.map { exercise in
            guard var target = exercise.target, target.setChange > 0, target.planMuscle == nil else { return exercise }
            let sharesMuscle = exercises.filter { $0.primaryMuscle == exercise.primaryMuscle }.count > 1
            let allowed = min(target.setChange, budget[exercise.primaryMuscle] ?? 0, sharesMuscle ? 1 : 2)
            budget[exercise.primaryMuscle, default: 0] -= allowed
            let removed = target.setChange - allowed
            guard removed > 0 else { return exercise }
            var e = exercise
            target.sets -= removed
            target.setChange = allowed
            if allowed == 0, target.action == .addSet { target.action = .hold }
            e.target = target
            for _ in 0..<removed { if let i = e.sets.lastIndex(where: { $0.kind != .warmup }), e.sets.filter({ $0.kind != .warmup }).count > 1 { e.sets.remove(at: i) } }
            return e
        }
    }

    /// Last session's warm-ups, then the coach's number of working sets.
    private static func startingSets(previous: [LoggedSet], working: Int) -> [LoggedSet] {
        let warmups = previous.prefix { $0.kind == .warmup }.count
        return (0..<warmups).map { _ in LoggedSet(kind: .warmup) } + (0..<max(working, 1)).map { _ in LoggedSet() }
    }

    /// Ticks a set on or off; ticking on starts the rest timer.
    func toggleSet(exercise exerciseID: UUID, set setID: UUID) {
        guard let exercise = active?.exercises.first(where: { $0.id == exerciseID }),
              let index = exercise.sets.firstIndex(where: { $0.id == setID }) else { return }
        if !exercise.sets[index].completed {
            let set = exercise.sets[index], hint = exercise.hint(for: index)
            let weight = set.weightKg ?? hint?.weightKg
            let reps = set.reps ?? hint?.reps
            let seconds = set.seconds ?? hint?.seconds
            let valid: Bool
            switch exercise.tracking {
            case .weightReps: valid = weight.map { $0.isFinite && $0 >= 0 } == true && (reps ?? 0) > 0
            case .reps: valid = (reps ?? 0) > 0
            case .duration: valid = (seconds ?? 0) > 0
            }
            guard valid else {
                saveError = "Enter a valid weight and reps, or duration, before completing this set."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
        }
        batchingDraft = true
        defer { batchingDraft = false; persist() }
        var restFor: Int?
        update { workout in
            guard let e = workout.exercises.firstIndex(where: { $0.id == exerciseID }),
                  let s = workout.exercises[e].sets.firstIndex(where: { $0.id == setID }) else { return }
            workout.exercises[e].sets[s].completed.toggle()
            let done = workout.exercises[e].sets[s].completed
            // Ticking an empty box accepts the grey hint, like Hevy.
            if done, let hint = workout.exercises[e].hint(for: s) {
                var set = workout.exercises[e].sets[s]
                if set.weightKg == nil { set.weightKg = hint.weightKg }
                if set.reps == nil { set.reps = hint.reps }
                if set.seconds == nil { set.seconds = hint.seconds }
                workout.exercises[e].sets[s] = set
            }
            // An unmarked set is taken as the planned effort; failure sets as 0.
            if done, workout.exercises[e].sets[s].rir == nil, workout.exercises[e].sets[s].kind != .warmup {
                if workout.exercises[e].sets[s].kind == .failure {
                    workout.exercises[e].sets[s].rir = 0
                } else if workout.exercises[e].coachApplied == true {
                    workout.exercises[e].sets[s].rir = workout.exercises[e].target?.rir
                }
            }
            workout.exercises[e].sets[s].completedAt = done ? Date() : nil
            if done { restFor = workout.exercises[e].restSeconds }
        }
        if let restFor {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            if restFor > 0 { startRest(seconds: restFor) }
        } else {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }

    /// IDs belong to the rendered button. Repeated/stale taps never advance another set.
    func setFromLockScreen(workoutID: UUID, exerciseID: UUID, setID: UUID, completed: Bool) {
        guard let workout = active, workout.id == workoutID,
              let exercise = workout.exercises.first(where: { $0.id == exerciseID }),
              let index = exercise.sets.firstIndex(where: { $0.id == setID }),
              exercise.sets[index].kind != .warmup,
              exercise.sets[index].completed != completed else { return }
        if completed {
            // Reject old buttons after exercise reordering or another device/app edit.
            guard let nextExercise = workout.exercises.first(where: { $0.sets.contains { !$0.completed && $0.kind != .warmup } }),
                  nextExercise.id == exerciseID,
                  nextExercise.sets.first(where: { !$0.completed && $0.kind != .warmup })?.id == setID else { return }
            let set = exercise.sets[index]
            let hint = exercise.hint(for: index)
            let weight = set.weightKg ?? hint?.weightKg
            let reps = set.reps ?? hint?.reps
            let seconds = set.seconds ?? hint?.seconds
            switch exercise.tracking {
            case .weightReps: guard let weight, weight.isFinite, weight >= 0, (reps ?? 0) > 0 else { return }
            case .reps: guard (reps ?? 0) > 0 else { return }
            case .duration: guard (seconds ?? 0) > 0 else { return }
            }
        } else {
            // Only undo the latest completion; a stale undo must not cancel a later rest.
            let latest = workout.exercises.flatMap(\.sets)
                .filter { $0.completed && $0.kind != .warmup && $0.completedAt != nil }
                .max { ($0.completedAt ?? .distantPast) < ($1.completedAt ?? .distantPast) }
            guard latest?.id == setID else { return }
        }
        toggleSet(exercise: exerciseID, set: setID)
        if !completed { cancelRest() }
    }

    // MARK: Rest timer

    func startRest(seconds: Int) {
        restDuration = seconds
        restEndsAt = Date().addingTimeInterval(TimeInterval(seconds))
        scheduleRestNotification()
    }

    func adjustRest(by seconds: Int) {
        guard let ends = restEndsAt else { return }
        let newEnd = ends.addingTimeInterval(TimeInterval(seconds))
        UIImpactFeedbackGenerator(style: seconds > 0 ? .medium : .light).impactOccurred()
        guard newEnd > Date() else { cancelRest(); return }
        restDuration = max(restDuration + seconds, 1)
        restEndsAt = newEnd
        scheduleRestNotification()
    }

    func cancelRest() {
        restEndsAt = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["workout.rest"])
    }

    /// Called by the timer view each tick; fires the end-of-rest haptic once.
    func checkRestFinished(now: Date) {
        guard let ends = restEndsAt, now >= ends else { return }
        restEndsAt = nil
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func scheduleRestNotification() {
        guard let ends = restEndsAt else { return }
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["workout.rest"])
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Rest over")
        content.body = String(localized: "Time for your next set.")
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(ends.timeIntervalSinceNow, 1), repeats: false)
        center.add(UNNotificationRequest(identifier: "workout.rest", content: content, trigger: trigger))
    }

    // MARK: Heart rate

    private func startHeartRate(from start: Date) {
        stopHeartRate()
        guard let type = HKObjectType.quantityType(forIdentifier: .heartRate) else { return }
        let predicate = HKQuery.predicateForSamples(withStart: start.addingTimeInterval(-120), end: nil, options: [])
        let unit = HKUnit.count().unitDivided(by: .minute())

        let handler: @Sendable ([HKSample]?) -> Void = { samples in
            let values = (samples as? [HKQuantitySample] ?? []).map { ($0.endDate, $0.quantity.doubleValue(for: unit)) }
            guard !values.isEmpty else { return }
            Task { @MainActor in
                let recorder = WorkoutRecorder.shared
                recorder.heartRateSamples.append(contentsOf: values.map { (date: $0.0, bpm: $0.1) })
                recorder.heartRateSamples.sort { $0.date < $1.date }
                if let latest = recorder.heartRateSamples.last {
                    recorder.heartRate = latest.bpm
                    recorder.heartRateAt = latest.date
                }
            }
        }

        let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: nil, limit: HKObjectQueryNoLimit) { _, samples, _, _, _ in
            handler(samples)
        }
        query.updateHandler = { _, samples, _, _, _ in handler(samples) }
        store.execute(query)
        heartRateQuery = query
    }

    private func stopHeartRate() {
        if let heartRateQuery { store.stop(heartRateQuery) }
        heartRateQuery = nil
        heartRate = nil
        heartRateAt = nil
        heartRateSamples = []
    }

    // MARK: Calories & Health

    /// Keytel et al. (2005) from average heart rate when age, sex and weight
    /// are known; otherwise 5 METs, typical of vigorous resistance training.
    static func estimateCalories(minutes: Double, averageHR: Double?) -> Double? {
        guard minutes > 0 else { return nil }
        let profile = BodyProfile.load()
        let weight = UserDefaults.standard.object(forKey: "workout.lastBodyMass") as? Double ?? 75
        if let hr = averageHR, let age = profile.ageYears {
            let perMinute = profile.isFemale == true
                ? (-20.4022 + 0.4472 * hr - 0.1263 * weight + 0.074 * Double(age)) / 4.184
                : (-55.0969 + 0.6309 * hr + 0.1988 * weight + 0.2017 * Double(age)) / 4.184
            if perMinute > 0 { return perMinute * minutes }
        }
        return 5.0 * weight * minutes / 60
    }

    private func saveToAppleHealth(_ log: WorkoutLog) async -> Bool {
        guard let energyType = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) else { return false }
        do {
            guard await HealthAccess.writable([HKObjectType.workoutType()]).isEmpty == false else { return false }
            let configuration = HKWorkoutConfiguration()
            configuration.activityType = .traditionalStrengthTraining
            configuration.locationType = .indoor
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: log.start)
            // Calories only if Health allows them — the workout still saves without.
            if let kcal = log.calories, kcal > 0, await !HealthAccess.writable([energyType]).isEmpty {
                let sample = HKQuantitySample(type: energyType, quantity: HKQuantity(unit: .kilocalorie(), doubleValue: kcal),
                                              start: log.start, end: log.end)
                try await builder.addSamples([sample])
            }
            try await builder.addMetadata([HKMetadataKeyWorkoutBrandName: log.name])
            try await builder.endCollection(at: log.end)
            _ = try await builder.finishWorkout()
            return true
        } catch {
            return false
        }
    }

    private func persist() {
        guard !restoring && !batchingDraft else { return }
        guard let draftStore else {
            saveError = "Workout changes could not be saved. Keep Trace open until storage is available."
            return
        }
        do {
            let snapshot = Snapshot(active: active, restEndsAt: restEndsAt,
                                    restDuration: restDuration, selectedSetID: selectedSetID)
            try draftStore.write(JSONEncoder().encode(snapshot))
        } catch {
            saveError = "Workout changes could not be saved: \(error.localizedDescription)"
        }
    }
}
