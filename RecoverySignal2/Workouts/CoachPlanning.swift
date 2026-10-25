//
//  CoachPlanning.swift
//  RecoverySignal2
//
//  Two more pieces of the progression coach:
//
//  WEEKLY VOLUME. Each muscle has a range of hard sets per week: MEV (the
//  least that still grows it) and MRV (the most you can recover from). The
//  starting ranges are the published hypertrophy-periodisation guidelines —
//  rules of thumb, not measurements. A block starts each muscle near MEV and
//  climbs to MRV − 2 by the last build week; the deload halves week one.
//  Sets are counted the same fractional way as the Muscles-trained card
//  (target muscle 1, assisting muscles ½), in block weeks.
//
//  Each workout gets its share: what's left of the week's target, divided by
//  the sessions likely left this week (from how often you trained the muscle
//  over the last 14 days), split across the session's exercises for it in
//  order, subtracting what each exercise also gives other muscles.
//
//  The ranges learn. "Too much" or "still sore" pulls that muscle's MRV down
//  toward the volume that caused it; "easy" and barely sore near the top of
//  the range nudges it up; a low pump and no soreness near MEV lifts MEV.
//  At most one change per muscle per week.
//
//  JOINT RANKING. Joint pain is rated per exercise. Each exercise's pain rate
//  weights recent sessions most (0.8ⁿ). Alternatives for a swap share the
//  muscle and are ranked: no pain history first, then a good pump, the same
//  main muscle, similar equipment and mechanics.
//

import Foundation

enum CoachSettings {
    static let key = "coach.enabled"
    /// On by default. Off hides the coach; calculations keep running.
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

// MARK: - Weekly volume

struct VolumeLandmarks: Codable, Hashable {
    var mev: Double
    var mrv: Double
}

enum VolumePlanner {

    static let defaults: [Muscle: VolumeLandmarks] = [
        .chest: .init(mev: 8, mrv: 22),
        .frontDelts: .init(mev: 0, mrv: 12),
        .sideDelts: .init(mev: 8, mrv: 26),
        .rearDelts: .init(mev: 6, mrv: 24),
        .traps: .init(mev: 0, mrv: 26),
        .upperBack: .init(mev: 6, mrv: 20),
        .lats: .init(mev: 6, mrv: 20),
        .lowerBack: .init(mev: 0, mrv: 10),
        .biceps: .init(mev: 8, mrv: 24),
        .triceps: .init(mev: 6, mrv: 18),
        .forearms: .init(mev: 0, mrv: 20),
        .abs: .init(mev: 0, mrv: 20),
        .obliques: .init(mev: 0, mrv: 16),
        .glutes: .init(mev: 0, mrv: 16),
        .quads: .init(mev: 8, mrv: 20),
        .hamstrings: .init(mev: 4, mrv: 20),
        .adductors: .init(mev: 0, mrv: 16),
        .calves: .init(mev: 8, mrv: 20),
    ]

    private static let personalKey = "volume.landmarks"
    private static let learnedKey = "volume.learnedWeek"

    static func landmarks(for muscle: Muscle) -> VolumeLandmarks {
        personal()[muscle.rawValue] ?? defaults[muscle] ?? .init(mev: 4, mrv: 16)
    }

    static func isPersonalised(_ muscle: Muscle) -> Bool { personal()[muscle.rawValue] != nil }

    private static func personal() -> [String: VolumeLandmarks] {
        guard let data = UserDefaults.standard.data(forKey: personalKey) else { return [:] }
        return (try? JSONDecoder().decode([String: VolumeLandmarks].self, from: data)) ?? [:]
    }

    private static func setPersonal(_ value: VolumeLandmarks, for muscle: Muscle) {
        var all = personal()
        all[muscle.rawValue] = value
        if let data = try? JSONEncoder().encode(all) { UserDefaults.standard.set(data, forKey: personalKey) }
    }

    static func resetPersonal() { UserDefaults.standard.removeObject(forKey: personalKey) }

    // MARK: Weeks

    /// The block week containing `date`: build weeks run from the block start
    /// in sevens; an early deload is its own week.
    static func week(containing date: Date, block: TrainingBlock) -> DateInterval {
        let calendar = Calendar.current
        if let deload = block.deloadStart, date >= deload {
            return DateInterval(start: deload, duration: 7 * 86_400)
        }
        let days = max(calendar.dateComponents([.day], from: block.start, to: calendar.startOfDay(for: date)).day ?? 0, 0)
        let start = calendar.date(byAdding: .day, value: (days / 7) * 7, to: block.start) ?? block.start
        return DateInterval(start: start, duration: 7 * 86_400)
    }

    // MARK: Targets

    /// Hard sets planned for this muscle this block week.
    static func weeklyTarget(for muscle: Muscle, block: TrainingBlock, on date: Date = Date()) -> Int {
        let marks = landmarks(for: muscle)
        let low = max(marks.mev, min(4, marks.mrv))
        let high = max(marks.mrv - 2, low)
        switch block.phase(on: date) {
        case .deload:
            return max(Int((low / 2).rounded()), 1)
        case .build(let week, let total):
            let fraction = total > 1 ? Double(week - 1) / Double(total - 1) : 1
            return Int((low + (high - low) * fraction).rounded())
        }
    }

    /// Weighted hard sets done for each muscle in an interval.
    static func sets(in interval: DateInterval, logs: [WorkoutLog]) -> [Muscle: Double] {
        var totals: [Muscle: Double] = [:]
        for log in logs where interval.contains(log.start) {
            for exercise in log.exercises {
                let hard = Double(exercise.workingSets.count)
                guard hard > 0 else { continue }
                for (muscle, weight) in LoggedMuscleVolume.weights(for: exercise) {
                    totals[muscle, default: 0] += hard * weight
                }
            }
        }
        return totals
    }

    /// Sessions a week that train the muscle as a main target, over the last 14 days.
    static func frequency(of muscle: Muscle, logs: [WorkoutLog], now: Date = Date()) -> Double {
        let since = now.addingTimeInterval(-14 * 86_400)
        let sessions = logs.filter { $0.start >= since && $0.start < now }.filter { log in
            log.exercises.contains { !$0.workingSets.isEmpty && (LoggedMuscleVolume.weights(for: $0)[muscle] ?? 0) >= 0.75 }
        }.count
        return Double(sessions) / 2
    }

    /// Muscles worth planning: trained as a main target in the last 3 weeks.
    static func trainedMuscles(logs: [WorkoutLog], now: Date = Date()) -> [Muscle] {
        let since = now.addingTimeInterval(-21 * 86_400)
        var found = Set<Muscle>()
        for log in logs where log.start >= since {
            for exercise in log.exercises where !exercise.workingSets.isEmpty {
                for (muscle, weight) in LoggedMuscleVolume.weights(for: exercise) where weight >= 0.75 { found.insert(muscle) }
            }
        }
        return Muscle.allCases.filter(found.contains)
    }

    /// The exercise's main muscle — the one it counts most toward.
    static func mainMuscle(of weights: [Muscle: Double]) -> Muscle? {
        weights.max { a, b in a.value == b.value ? a.key.rawValue > b.key.rawValue : a.value < b.value }?.key
    }

    struct SessionShare {
        let sets: Int
        let muscle: Muscle
        let weeklyTarget: Int
        let doneThisWeek: Double
    }

    /// Working sets for each exercise of a session, from the weekly plan.
    /// Nil where the exercise doesn't map to a muscle.
    static func allocate(_ exercises: [(id: String, name: String, library: Exercise?)], logs: [WorkoutLog],
                         block: TrainingBlock, now: Date = Date()) -> [SessionShare?] {
        let week = week(containing: now, block: block)
        let done = sets(in: week, logs: logs)
        let daysLeft = max(week.end.timeIntervalSince(now) / 86_400, 1)

        let weights: [[Muscle: Double]] = exercises.map { item in
            if let library = item.library { return LoggedMuscleVolume.weights(for: library) }
            return MuscleMapping.weights(for: item.name) ?? [:]
        }

        var need: [Muscle: Double] = [:]
        var targets: [Muscle: Int] = [:]
        for muscle in Set(weights.compactMap { mainMuscle(of: $0) }) {
            let target = weeklyTarget(for: muscle, block: block, on: now)
            let remaining = max(Double(target) - (done[muscle] ?? 0), 0)
            // No recent history: assume twice a week, the common split.
            let seen = frequency(of: muscle, logs: logs, now: now)
            let perWeek = seen > 0 ? max(seen, 1) : 2
            let sessionsLeft = max((perWeek * daysLeft / 7).rounded(.up), 1)
            // Don't cram a whole week into one late session.
            need[muscle] = min(remaining / sessionsLeft, Double(target) / perWeek + 2)
            targets[muscle] = target
        }

        return exercises.indices.map { i in
            guard let main = mainMuscle(of: weights[i]), let target = targets[main] else { return nil }
            let sharing = (i..<exercises.count).filter { mainMuscle(of: weights[$0]) == main }.count
            let weight = max(weights[i][main] ?? 1, 0.25)
            let raw = (need[main] ?? 0) / Double(sharing) / weight
            let sets = min(max(Int(raw.rounded()), 1), 6)
            for (muscle, w) in weights[i] { need[muscle, default: 0] -= Double(sets) * w }
            return SessionShare(sets: sets, muscle: main, weeklyTarget: target, doneThisWeek: done[main] ?? 0)
        }
    }

    // MARK: Learning

    /// Adjusts personal ranges from a finished workout's feedback.
    static func learn(from log: WorkoutLog, logs: [WorkoutLog], block: TrainingBlock) {
        let week = week(containing: log.start, block: block)
        let done = sets(in: week, logs: logs.contains { $0.id == log.id } ? logs : logs + [log])
        var learned = (UserDefaults.standard.dictionary(forKey: learnedKey) as? [String: Double]) ?? [:]

        for feedback in log.feedback {
            let muscles = Set(log.exercises
                .filter { $0.primaryMuscle == feedback.muscle && !$0.workingSets.isEmpty }
                .compactMap { mainMuscle(of: LoggedMuscleVolume.weights(for: $0)) })
            for muscle in muscles {
                guard learned[muscle.rawValue] != week.start.timeIntervalSince1970 else { continue }
                var marks = landmarks(for: muscle)
                let volume = done[muscle] ?? 0
                let target = Double(weeklyTarget(for: muscle, block: block, on: log.start))
                let original = marks

                if feedback.workload == .tooMuch || feedback.soreness == .stillSore {
                    marks.mrv = max(marks.mev + 4, min(marks.mrv - 1, volume.rounded()))
                } else if feedback.workload == .easy, feedback.soreness == MuscleFeedback.Soreness.none || feedback.soreness == .healedEarly,
                          volume >= target - 1, volume >= marks.mrv - 4 {
                    marks.mrv = min(marks.mrv + 1, 40)
                } else if feedback.pump == .low, feedback.soreness == MuscleFeedback.Soreness.none, volume <= marks.mev + 2 {
                    marks.mev = min(marks.mev + 1, marks.mrv - 4)
                }

                if marks != original {
                    setPersonal(marks, for: muscle)
                    learned[muscle.rawValue] = week.start.timeIntervalSince1970
                }
            }
        }
        UserDefaults.standard.set(learned, forKey: learnedKey)
    }
}

// MARK: - Joint ranking

enum ExerciseRanking {

    struct JointHistory {
        /// 0 (never hurt) … 1 (always hurt a lot), recent sessions weighted most.
        let painRate: Double
        let rated: Int
        let hurtTimes: Int
        let lastTwoHurt: Bool
        let lastWasBad: Bool

        var flagged: Bool { lastTwoHurt || (rated >= 2 && painRate >= 0.34) }
    }

    static func joints(for exerciseID: String, logs: [WorkoutLog], before date: Date = .distantFuture) -> JointHistory {
        let ratings = logs.filter { $0.start < date }
            .sorted { $0.start > $1.start }
            .compactMap { log in log.exercises.first { $0.exerciseID == exerciseID }?.jointPain }
            .prefix(8)
        return history(Array(ratings))
    }

    private static func value(_ pain: MuscleFeedback.JointPain) -> Double {
        switch pain {
        case .none: 0
        case .some: 0.5
        case .alot: 1
        }
    }

    /// Joint history for every rated exercise in one pass, for lists.
    static func jointHistories(logs: [WorkoutLog]) -> [String: JointHistory] {
        var ratings: [String: [MuscleFeedback.JointPain]] = [:]
        for log in logs.sorted(by: { $0.start > $1.start }) {
            for exercise in log.exercises {
                if let pain = exercise.jointPain, ratings[exercise.exerciseID, default: []].count < 8 {
                    ratings[exercise.exerciseID, default: []].append(pain)
                }
            }
        }
        return ratings.mapValues { history($0) }
    }

    private static func history(_ ratings: [MuscleFeedback.JointPain]) -> JointHistory {
        var weighted = 0.0, total = 0.0
        for (i, pain) in ratings.enumerated() {
            let w = pow(0.8, Double(i))
            weighted += w * value(pain)
            total += w
        }
        let recent = Array(ratings.prefix(2))
        return JointHistory(painRate: total > 0 ? weighted / total : 0,
                            rated: ratings.count,
                            hurtTimes: ratings.filter { $0 != .none }.count,
                            lastTwoHurt: recent.count == 2 && recent.allSatisfy { $0 != .none },
                            lastWasBad: recent.first == .alot)
    }

    /// Average pump for sessions that included the exercise (0 low … 1 great).
    static func pump(for exerciseID: String, logs: [WorkoutLog]) -> Double? {
        let values: [Double] = logs.sorted { $0.start > $1.start }.prefix(40).compactMap { log in
            guard let exercise = log.exercises.first(where: { $0.exerciseID == exerciseID }),
                  let pump = log.feedback.first(where: { $0.muscle == exercise.primaryMuscle })?.pump else { return nil }
            switch pump {
            case .low: return 0
            case .moderate: return 0.5
            case .great: return 1
            }
        }
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Up to `limit` swaps for the same muscle, kindest on joints first.
    static func alternatives(to exercise: Exercise, logs: [WorkoutLog], excluding: Set<String> = [], limit: Int = 3) -> [Exercise] {
        let main = VolumePlanner.mainMuscle(of: LoggedMuscleVolume.weights(for: exercise))
        let done = Set(logs.flatMap { $0.exercises.map(\.exerciseID) })
        let candidates = ExerciseLibrary.shared.all.filter {
            $0.id != exercise.id && !excluding.contains($0.id)
                && $0.primaryMuscle == exercise.primaryMuscle
                && $0.tracking == exercise.tracking
                && ($0.category == nil || $0.category == "strength" || $0.category == "powerlifting")
        }
        let scored = candidates.map { candidate -> (Exercise, Double) in
            var score = 0.0
            let joints = joints(for: candidate.id, logs: logs)
            if joints.rated > 0 { score -= 3 * joints.painRate }
            if done.contains(candidate.id) && joints.rated > 0 && joints.painRate == 0 { score += 0.6 }
            if let pump = pump(for: candidate.id, logs: logs) { score += pump }
            if let main, VolumePlanner.mainMuscle(of: LoggedMuscleVolume.weights(for: candidate)) == main { score += 1.5 }
            if candidate.equipment == exercise.equipment { score += 0.5 }
            if candidate.mechanic == exercise.mechanic { score += 0.4 }
            if candidate.level != "expert" { score += 0.1 }
            if !candidate.images.isEmpty || candidate.isCustom { score += 0.1 }
            return (candidate, score)
        }
        return scored.sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }.prefix(limit).map(\.0)
    }
}
