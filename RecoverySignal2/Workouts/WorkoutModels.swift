//
//  WorkoutModels.swift
//  RecoverySignal2
//
//  Routines you build and workouts you log. The exercise and set lists are
//  stored as JSON inside each record — simple, and robust to adding fields.
//

import Foundation
import SwiftData

struct PlannedExercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var exerciseID: String
    var name: String
    var sets: Int = 3
    var reps: Int = 10
    var restSeconds: Int = 90
    var notes: String = ""
    /// Rep range the coach keeps you in; nil means a default for the exercise.
    var repLow: Int? = nil
    var repHigh: Int? = nil

    var repRange: ClosedRange<Int>? {
        guard let repLow, let repHigh, repLow <= repHigh else { return nil }
        return repLow...repHigh
    }
}

/// Decoded JSON payloads, remembered per model object so a routine's or a
/// log's exercises are parsed once rather than on every read. Entries are
/// keyed by the object and checked against the current bytes, so an edit is
/// never served stale; the cache is bounded and purged under memory pressure.
enum PayloadCache {
    private final class Box {
        let payload: Data
        let value: Any
        init(payload: Data, value: Any) { self.payload = payload; self.value = value }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 6000
        return cache
    }()

    static func decode<T: Decodable>(_ type: T.Type, from payload: Data, owner: AnyObject, slot: String, fallback: T) -> T {
        guard !payload.isEmpty else { return fallback }
        let key = "\(ObjectIdentifier(owner).hashValue)-\(slot)" as NSString
        if let box = cache.object(forKey: key), box.payload == payload, let value = box.value as? T { return value }
        let decoded = (try? JSONDecoder().decode(T.self, from: payload)) ?? fallback
        cache.setObject(Box(payload: payload, value: decoded), forKey: key)
        return decoded
    }

    /// Optional variant: nil when the payload is empty or doesn't parse (failures aren't cached).
    static func decode<T: Decodable>(_ type: T.Type, from payload: Data, owner: AnyObject, slot: String) -> T? {
        guard !payload.isEmpty else { return nil }
        let key = "\(ObjectIdentifier(owner).hashValue)-\(slot)" as NSString
        if let box = cache.object(forKey: key), box.payload == payload, let value = box.value as? T { return value }
        guard let decoded = try? JSONDecoder().decode(T.self, from: payload) else { return nil }
        cache.setObject(Box(payload: payload, value: decoded), forKey: key)
        return decoded
    }
}

enum SetKind: String, Codable, CaseIterable {
    case warmup, normal, drop, failure

    var short: String {
        switch self {
        case .warmup:  String(localized: "W")
        case .normal:  ""
        case .drop:    String(localized: "D")
        case .failure: String(localized: "F")
        }
    }

    var label: String {
        switch self {
        case .warmup:  String(localized: "Warm-up")
        case .normal:  String(localized: "Normal")
        case .drop:    String(localized: "Drop set")
        case .failure: String(localized: "Failure")
        }
    }
}

struct LoggedSet: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: SetKind = .normal
    var weightKg: Double?
    var reps: Int?
    var seconds: Int?
    /// Reps in reserve: how many more you could have done. 0 = failure.
    var rir: Int? = nil
    var completed = false
    var completedAt: Date?

    /// Epley estimated one-rep max.
    var estimatedOneRepMax: Double? {
        guard let w = weightKg, let r = reps, w > 0, r > 0 else { return nil }
        return r == 1 ? w : w * (1 + Double(r) / 30)
    }

    var volume: Double { (weightKg ?? 0) * Double(reps ?? 0) }
}

struct LoggedExercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var exerciseID: String
    var name: String
    var primaryMuscle: String
    var tracking: SetTracking
    var restSeconds: Int = 90
    var notes: String = ""
    var sets: [LoggedSet] = []
    /// What you did last time, shown as grey hints in the empty boxes.
    var previous: [LoggedSet]? = nil
    /// What the coach suggested for this session.
    var target: ExerciseTarget? = nil
    /// Whether the coach was on when this exercise was set up: its targets
    /// fill the grey hints and set count only then.
    var coachApplied: Bool? = nil
    /// Joint pain during this exercise, if rated.
    var jointPain: MuscleFeedback.JointPain? = nil

    /// The hint for a set: the coach's target, else the same set last session,
    /// else the set above it.
    func hint(for index: Int) -> LoggedSet? {
        if coachApplied == true, let target, sets.indices.contains(index), sets[index].kind != .warmup,
           target.weightKg != nil || target.reps != nil || target.seconds != nil {
            var set = LoggedSet()
            set.weightKg = target.weightKg
            set.reps = target.reps
            set.seconds = target.seconds
            // Blank weight (first time) falls back to what's above.
            if set.weightKg == nil, tracking == .weightReps { set.weightKg = previousHint(for: index)?.weightKg }
            return set
        }
        return previousHint(for: index)
    }

    private func previousHint(for index: Int) -> LoggedSet? {
        if let previous, previous.indices.contains(index) { return previous[index] }
        if let previous, let last = previous.last, index >= previous.count { return last }
        return index > 0 ? sets[index - 1] : nil
    }

    var completedSets: [LoggedSet] { sets.filter(\.completed) }
    /// Completed sets that count: warm-ups are excluded.
    var workingSets: [LoggedSet] { completedSets.filter { $0.kind != .warmup } }
    var volume: Double { completedSets.filter { $0.kind != .warmup }.reduce(0) { $0 + $1.volume } }
    var bestOneRepMax: Double? { completedSets.compactMap(\.estimatedOneRepMax).max() }
}

@Model
final class WorkoutRoutine {
    var id: UUID = UUID()
    var name: String = ""
    var notes: String = ""
    var createdAt: Date = Date()
    var lastPerformed: Date?
    var payload: Data = Data()

    init(name: String, exercises: [PlannedExercise] = []) {
        self.name = name
        self.exercises = exercises
    }

    var exercises: [PlannedExercise] {
        get { PayloadCache.decode([PlannedExercise].self, from: payload, owner: self, slot: "exercises", fallback: []) }
        set { payload = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

@Model
final class WorkoutLog {
    var id: UUID = UUID()
    var name: String = ""
    var routineID: UUID?
    var start: Date = Date()
    var end: Date = Date()
    var averageHeartRate: Double?
    var maxHeartRate: Double?
    var calories: Double?
    var savedToHealth: Bool = false
    /// The Apple Watch workout recorded at the same time, if any.
    var healthWorkoutID: UUID?
    var notes: String = ""
    var payload: Data = Data()
    /// Per-muscle pump / soreness / workload / joint pain, as JSON.
    var feedbackPayload: Data = Data()
    /// How your body looked when the session started (see PerformanceModel).
    var readinessPayload: Data = Data()

    init(name: String, routineID: UUID?, start: Date, end: Date, exercises: [LoggedExercise]) {
        self.name = name
        self.routineID = routineID
        self.start = start
        self.end = end
        self.exercises = exercises
    }

    var exercises: [LoggedExercise] {
        get { PayloadCache.decode([LoggedExercise].self, from: payload, owner: self, slot: "exercises", fallback: []) }
        set { payload = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var feedback: [MuscleFeedback] {
        get { PayloadCache.decode([MuscleFeedback].self, from: feedbackPayload, owner: self, slot: "feedback", fallback: []) }
        set { feedbackPayload = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var volume: Double { exercises.reduce(0) { $0 + $1.volume } }
    /// Working sets only — warm-ups don't count.
    var setCount: Int { exercises.reduce(0) { $0 + $1.workingSets.count } }
}

enum WorkoutHistory {
    /// The most recent completed sets for an exercise, for the "previous" column.
    static func previousSets(for exerciseID: String, in logs: [WorkoutLog], before date: Date = .distantFuture) -> [LoggedSet] {
        for log in logs.sorted(by: { $0.start > $1.start }) where log.start < date {
            if let match = log.exercises.first(where: { $0.exerciseID == exerciseID }), !match.completedSets.isEmpty {
                return match.completedSets
            }
        }
        return []
    }

    struct Best {
        let oneRepMax: Double?
        let heaviest: Double?
        let mostReps: Int?
        let bestVolumeSet: Double?
    }

    static func best(for exerciseID: String, in logs: [WorkoutLog], before date: Date = .distantFuture) -> Best {
        let sets = logs.filter { $0.start < date }
            .flatMap { $0.exercises.filter { $0.exerciseID == exerciseID }.flatMap(\.completedSets) }
            .filter { $0.kind != .warmup }
        return Best(oneRepMax: sets.compactMap(\.estimatedOneRepMax).max(),
                    heaviest: sets.compactMap(\.weightKg).max(),
                    mostReps: sets.compactMap(\.reps).max(),
                    bestVolumeSet: sets.map(\.volume).max())
    }

    /// Estimated 1RM per session, for the progress chart.
    static func oneRepMaxHistory(for exerciseID: String, in logs: [WorkoutLog]) -> [TrendPoint] {
        logs.sorted { $0.start < $1.start }.compactMap { log in
            log.exercises.first { $0.exerciseID == exerciseID }?.bestOneRepMax.map { TrendPoint(date: log.start, value: $0) }
        }
    }
}
