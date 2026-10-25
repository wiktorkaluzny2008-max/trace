//
//  ProgressionCoach.swift
//  RecoverySignal2
//
//  Tells you what to lift next time, the way hypertrophy periodisation does it:
//
//  1. Training blocks. A block is 4–6 weeks of building, then a deload week.
//     Effort rises through the block: reps in reserve (RIR — how many more
//     reps you could have done) start at 3 and fall to 0–1 by the last week
//     (compound lifts stop at 1). The deload halves the sets, takes ~10% off
//     the weight and stops 4+ reps short, so fatigue clears and the next block
//     starts stronger.
//
//  2. Load and reps. Each session's strength is read as an estimated 1RM
//     that counts the reps you left in the tank:
//         e1RM = weight × (1 + (reps + RIR) ÷ 30)          (Epley)
//     Next time aims ~1% above that. The coach first tries the next weight
//     step up; if that would push reps below your rep range, it keeps the
//     weight and adds reps instead (small dumbbell jumps are big percentages).
//     If you fell below the range, the weight comes down.
//
//  3. Sets from how the muscle felt. After a workout you rate, per muscle,
//     the pump, how sore you got from last time, the workload and joint pain.
//     Barely sore + low pump + easy → add a set. Still sore, too much, or
//     joint pain → take one away. Sets never go up while performance drops.
//
//  4. Stalls. If the estimated 1RM hasn't beaten the session three back by
//     more than 1%, the lift has stalled: add a set early in a block, deload
//     late in one, and after a long stall try a variation. Two drops in a
//     row mean fatigue is outrunning recovery: remove a set, and deload if it
//     keeps happening.
//
//  5. A strained recovery score today adds a rep in reserve and holds sets.
//

import Foundation
import SwiftUI

// MARK: - Training block

struct TrainingBlock: Codable, Equatable {
    var start: Date
    var buildWeeks: Int = 4
    /// Set when a deload is started early; the block restarts a week later.
    var deloadStart: Date?

    enum Phase: Equatable {
        case build(week: Int, of: Int)   // week is 1-based
        case deload
    }

    private static let key = "training.block"

    static func load(now: Date = Date()) -> TrainingBlock {
        guard let data = UserDefaults.standard.data(forKey: key),
              var block = try? JSONDecoder().decode(TrainingBlock.self, from: data) else {
            return TrainingBlock(start: Calendar.current.startOfDay(for: now))
        }
        if block.normalise(now: now) { block.save() }
        return block
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { UserDefaults.standard.set(data, forKey: Self.key) }
    }

    /// Rolls an early deload into a fresh block once its week is over.
    @discardableResult
    mutating func normalise(now: Date) -> Bool {
        guard let deloadStart, now >= deloadStart.addingTimeInterval(7 * 86_400) else { return false }
        start = Calendar.current.startOfDay(for: deloadStart.addingTimeInterval(7 * 86_400))
        self.deloadStart = nil
        return true
    }

    func phase(on date: Date = Date()) -> Phase {
        if let deloadStart, date >= deloadStart { return .deload }
        let days = max(Calendar.current.dateComponents([.day], from: start, to: Calendar.current.startOfDay(for: date)).day ?? 0, 0)
        let index = (days / 7) % (buildWeeks + 1)
        return index == buildWeeks ? .deload : .build(week: index + 1, of: buildWeeks)
    }

    /// 3 RIR in week one falling to 0 in the last build week; compounds stop at 1.
    func targetRIR(on date: Date = Date(), compound: Bool) -> Int {
        switch phase(on: date) {
        case .deload: return 4
        case .build(let week, let total):
            let fraction = total > 1 ? Double(week - 1) / Double(total - 1) : 1
            let rir = Int((3 * (1 - fraction)).rounded())
            return compound ? max(rir, 1) : rir
        }
    }

    static func restart(buildWeeks: Int? = nil, now: Date = Date()) {
        var block = load(now: now)
        block.start = Calendar.current.startOfDay(for: now)
        block.deloadStart = nil
        if let buildWeeks { block.buildWeeks = buildWeeks }
        block.save()
    }

    static func startDeloadNow(now: Date = Date()) {
        var block = load(now: now)
        block.deloadStart = Calendar.current.startOfDay(for: now)
        block.save()
    }

    /// After two weeks off, carrying on mid-block makes no sense: start over.
    static func restartIfLongBreak(lastWorkout: Date?, now: Date = Date()) {
        guard let lastWorkout, now.timeIntervalSince(lastWorkout) > 14 * 86_400 else { return }
        let block = load(now: now)
        if block.start < lastWorkout || block.start < now.addingTimeInterval(-14 * 86_400) { restart(now: now) }
    }
}

// MARK: - Muscle feedback

struct MuscleFeedback: Codable, Hashable, Identifiable {
    var muscle: String
    var pump: Pump?
    var soreness: Soreness?
    var workload: Workload?
    var jointPain: JointPain?

    var id: String { muscle }
    var isEmpty: Bool { pump == nil && soreness == nil && workload == nil && jointPain == nil }

    enum Pump: String, Codable, CaseIterable { case low, moderate, great }
    enum Soreness: String, Codable, CaseIterable { case none, healedEarly, onTime, stillSore }
    enum Workload: String, Codable, CaseIterable { case easy, justRight, pushing, tooMuch }
    enum JointPain: String, Codable, CaseIterable { case none, some, alot }

    /// −1, 0, +1 or +2 sets next time.
    var setChange: Int {
        var score = 0
        switch soreness {
        case .none?: score += 1
        case .healedEarly?: score += 1
        case .stillSore?: score -= 2
        default: break
        }
        if pump == .low { score += 1 }
        switch workload {
        case .easy?: score += 1
        case .tooMuch?: score -= 2
        default: break
        }
        if jointPain == .alot { score -= 2 }
        let hasBrake = soreness == .stillSore || workload == .tooMuch || jointPain != nil && jointPain != JointPain.none
        if score <= -1 { return -1 }
        if hasBrake { return 0 }
        return score >= 3 ? 2 : (score >= 2 ? 1 : 0)
    }
}

extension MuscleFeedback.Pump {
    var label: String {
        switch self {
        case .low: String(localized: "Low")
        case .moderate: String(localized: "Decent")
        case .great: String(localized: "Great")
        }
    }
}

extension MuscleFeedback.Soreness {
    var label: String {
        switch self {
        case .none: String(localized: "Not sore")
        case .healedEarly: String(localized: "Healed early")
        case .onTime: String(localized: "Just in time")
        case .stillSore: String(localized: "Still sore")
        }
    }
}

extension MuscleFeedback.Workload {
    var label: String {
        switch self {
        case .easy: String(localized: "Easy")
        case .justRight: String(localized: "Just right")
        case .pushing: String(localized: "Pushed me")
        case .tooMuch: String(localized: "Too much")
        }
    }
}

extension MuscleFeedback.JointPain {
    var label: String {
        switch self {
        case .none: String(localized: "None")
        case .some: String(localized: "A little")
        case .alot: String(localized: "A lot")
        }
    }
}

// MARK: - Recommendation

struct ExerciseTarget: Codable, Hashable {
    enum Action: String, Codable {
        case start, addWeight, addReps, hold, reduceWeight, deload, addSet, removeSet, swap
    }

    var action: Action
    var weightKg: Double?
    var reps: Int?
    var seconds: Int?
    var rir: Int
    var repLow: Int
    var repHigh: Int
    var sets: Int
    var setChange: Int = 0
    var reason: String
    var stalled: Bool = false
    var regressing: Bool = false
    /// The weekly plan behind the set count, when there is one.
    var planMuscle: String? = nil
    var weeklyTarget: Int? = nil
    var doneThisWeek: Double? = nil
    /// Library ids of suggested swaps, kindest on joints first.
    var alternatives: [String]? = nil

    var title: String {
        switch action {
        case .start:        String(localized: "Find your weight")
        case .addWeight:    String(localized: "Add weight")
        case .addReps:      String(localized: "Add reps")
        case .hold:         String(localized: "Match last time")
        case .reduceWeight: String(localized: "Lighten the load")
        case .deload:       String(localized: "Deload")
        case .addSet:       String(localized: "Add a set")
        case .removeSet:    String(localized: "Remove a set")
        case .swap:         String(localized: "Try a variation")
        }
    }

    var symbol: String {
        switch action {
        case .start:        "scope"
        case .addWeight:    "arrow.up.circle.fill"
        case .addReps:      "plus.circle.fill"
        case .hold:         "equal.circle.fill"
        case .reduceWeight: "arrow.down.circle.fill"
        case .deload:       "battery.25percent"
        case .addSet:       "square.stack.3d.up.fill"
        case .removeSet:    "minus.circle.fill"
        case .swap:         "arrow.triangle.2.circlepath"
        }
    }

    var color: Color {
        switch action {
        case .addWeight, .addReps, .addSet: Theme.good
        case .start, .hold:                 Theme.accent
        case .deload, .removeSet, .reduceWeight: Theme.warn
        case .swap:                         Theme.fat
        }
    }
}

enum ProgressionCoach {

    /// One past session of an exercise, reduced to what the coach needs.
    struct Session {
        let date: Date
        let sets: [LoggedSet]
        let targetRIR: Int?

        var topWeight: Double? { sets.compactMap(\.weightKg).filter { $0 > 0 }.max() }
        /// Reps on the first working set at the top weight — the freshest effort.
        var topReps: Int? {
            guard let top = topWeight else { return sets.compactMap(\.reps).max() }
            return sets.first { $0.weightKg == top }?.reps
        }

        func assumedRIR(_ set: LoggedSet) -> Int {
            if set.kind == .failure { return 0 }
            return set.rir ?? targetRIR ?? 2
        }

        /// Best estimated 1RM, counting reps left in reserve.
        var capacity: Double? {
            sets.compactMap { set -> Double? in
                guard let w = set.weightKg, w > 0, let r = set.reps, r > 0 else { return nil }
                return w * (1 + Double(r + assumedRIR(set)) / 30)
            }.max()
        }

        /// For bodyweight lifts: reps to failure on the best set.
        var repCapacity: Int? { sets.compactMap { s in s.reps.map { $0 + assumedRIR(s) } }.max() }
        var bestSeconds: Int? { sets.compactMap(\.seconds).max() }
        var averageRIR: Double? {
            let values = sets.compactMap(\.rir)
            return values.isEmpty ? nil : Double(values.reduce(0, +)) / Double(values.count)
        }
    }

    static func sessions(for exerciseID: String, in logs: [WorkoutLog], before date: Date) -> [Session] {
        logs.filter { $0.start < date }
            .sorted { $0.start > $1.start }
            .compactMap { log in
                guard let match = log.exercises.first(where: { $0.exerciseID == exerciseID }) else { return nil }
                let working = match.workingSets
                return working.isEmpty ? nil : Session(date: log.start, sets: working, targetRIR: match.target?.rir)
            }
    }

    /// Feedback from the last session that trained this muscle (within three
    /// weeks). Only that one: its set change is already baked into later sessions.
    static func feedback(for muscle: String, in logs: [WorkoutLog], before date: Date) -> MuscleFeedback? {
        guard let log = logs.filter({ $0.start < date })
            .sorted(by: { $0.start > $1.start })
            .first(where: { $0.exercises.contains { $0.primaryMuscle == muscle && !$0.workingSets.isEmpty } }),
              date.timeIntervalSince(log.start) < 21 * 86_400 else { return nil }
        return log.feedback.first { $0.muscle == muscle && !$0.isEmpty }
    }

    static func defaultRepRange(for exercise: Exercise?) -> ClosedRange<Int> {
        guard let exercise else { return 8...12 }
        if exercise.tracking == .reps { return 8...20 }
        if exercise.mechanic == "isolation" { return 10...15 }
        return exercise.equipment == "barbell" ? 6...10 : 8...12
    }

    /// The smallest sensible jump for the equipment.
    static func weightStep(for equipment: String?, weight: Double) -> Double {
        switch equipment {
        case "dumbbell": weight < 10 ? 1 : 2
        case "kettlebells": 4
        case "machine", "cable": weight < 20 ? 1.25 : 2.5
        default: 2.5
        }
    }

    static func todayIsStrained() -> Bool {
        guard let snapshot = WidgetSnapshot.load(), Calendar.current.isDateInToday(snapshot.updatedAt),
              let score = snapshot.score else { return false }
        return score <= 33
    }

    // MARK: The recommendation

    static func recommend(exerciseID: String, exercise: Exercise?, plannedSets: Int?, repRange: ClosedRange<Int>?,
                          logs: [WorkoutLog], date: Date = Date(),
                          block: TrainingBlock = .load(), strained: Bool = ProgressionCoach.todayIsStrained(),
                          share: VolumePlanner.SessionShare? = nil) -> ExerciseTarget {
        var target = recommendCore(exerciseID: exerciseID, exercise: exercise, plannedSets: plannedSets, repRange: repRange,
                                   logs: logs, date: date, block: block, strained: strained, share: share)
        if let share {
            target.planMuscle = share.muscle.rawValue
            target.weeklyTarget = share.weeklyTarget
            target.doneThisWeek = share.doneThisWeek
            let done = Int(share.doneThisWeek.rounded())
            let note = String(localized: "Weekly plan: \(share.muscle.name.lowercased()) \(share.weeklyTarget) sets this week, \(done) done so far.")
            target.reason = target.reason.isEmpty ? note : target.reason + " " + note
        }
        if target.action == .swap, let exercise {
            target.alternatives = ExerciseRanking.alternatives(to: exercise, logs: logs).map(\.id)
        }
        return target
    }

    private static func recommendCore(exerciseID: String, exercise: Exercise?, plannedSets: Int?, repRange: ClosedRange<Int>?,
                                      logs: [WorkoutLog], date: Date, block: TrainingBlock, strained: Bool,
                                      share: VolumePlanner.SessionShare?) -> ExerciseTarget {
        let tracking = exercise?.tracking ?? .weightReps
        let compound = exercise?.mechanic != "isolation"
        let range = repRange ?? defaultRepRange(for: exercise)
        let phase = block.phase(on: date)
        var rir = block.targetRIR(on: date, compound: compound)
        if strained && phase != .deload { rir += 1 }

        let history = sessions(for: exerciseID, in: logs, before: date)
        let muscle = exercise?.primaryMuscle ?? "other"
        let feedback = feedback(for: muscle, in: logs, before: date)

        let joints = ExerciseRanking.joints(for: exerciseID, logs: logs, before: date)

        guard let last = history.first else {
            let sets = share?.sets ?? plannedSets ?? 3
            let reps = (range.lowerBound + range.upperBound) / 2
            let reason = tracking == .weightReps
                ? String(localized: "No history yet. Pick a weight you can lift for \(reps) reps with about \(rir) more in the tank, and mark the RIR on each set.")
                : String(localized: "No history yet. Stop each set with about \(rir) reps in reserve and mark it.")
            return ExerciseTarget(action: .start, weightKg: nil, reps: tracking == .duration ? nil : reps, seconds: nil,
                                  rir: rir, repLow: range.lowerBound, repHigh: range.upperBound, sets: sets, reason: reason)
        }

        let lastSets = last.sets.count
        // The weekly plan decides the baseline when there is one.
        // Ramp toward it: at most two more sets than last time on one exercise.
        let baseSets = share.map { min($0.sets, lastSets + 2) } ?? max(plannedSets.map { max($0, lastSets) } ?? lastSets, 1)

        // Stall and regression, from RIR-adjusted strength over recent sessions.
        let capacities: [Double] = history.prefix(6).compactMap { tracking == .weightReps ? $0.capacity : $0.repCapacity.map(Double.init) }
        let regressing = capacities.count >= 3 && capacities[0] < capacities[1] * 0.97 && capacities[1] < capacities[2] * 0.99
        let stalled = !regressing && capacities.count >= 3 && max(capacities[0], capacities[1]) <= capacities[2] * 1.01
        let longStall = stalled && capacities.count >= 6 && capacities.prefix(5).max()! <= capacities[5] * 1.01

        var notes: [String] = []
        if strained && phase != .deload { notes.append(String(localized: "Recovery is strained today, so stop one rep earlier and don't add sets.")) }

        // Deload week.
        if phase == .deload {
            let sets = share?.sets ?? max(lastSets / 2, 1)
            var target = ExerciseTarget(action: .deload, weightKg: nil, reps: last.topReps, seconds: last.bestSeconds,
                                        rir: 4, repLow: range.lowerBound, repHigh: range.upperBound, sets: sets,
                                        setChange: sets - lastSets,
                                        reason: String(localized: "Deload week: half the sets, about 10% lighter, and stop well short of failure. Fatigue drops, strength shows up next block."))
            if let top = last.topWeight {
                let step = weightStep(for: exercise?.equipment, weight: top)
                target.weightKg = max((top * 0.9 / step).rounded() * step, step)
            }
            return target
        }

        // Sets: muscle feedback, stalls and regressions.
        var setChange = feedback?.setChange ?? 0
        if let feedback, setChange > 0 {
            notes.append(String(localized: "Last time \(muscleName(muscle)) felt \(feedbackSummary(feedback)) — room for more sets."))
        } else if let feedback, setChange < 0 {
            notes.append(String(localized: "Last time \(muscleName(muscle)) felt \(feedbackSummary(feedback)) — one set fewer so it can recover."))
        }
        // With a weekly plan, feedback only fine-tunes (the ranges learn from it too).
        if share != nil { setChange = min(max(setChange, -1), 1) }
        if joints.lastWasBad {
            setChange = min(setChange, -1)
            notes.append(String(localized: "Your joints hurt a lot last time — one set fewer."))
        }
        if regressing { setChange = min(setChange, -1) }
        if strained { setChange = min(setChange, 0) }
        setChange = min(setChange, 2)
        // Falling performance: one fewer than last time, whatever the plan says.
        let sets = regressing ? max(min(baseSets, lastSets) - 1, 1) : min(max(baseSets + setChange, 1), 8)

        var target = ExerciseTarget(action: .hold, weightKg: last.topWeight, reps: last.topReps, seconds: last.bestSeconds,
                                    rir: rir, repLow: range.lowerBound, repHigh: range.upperBound,
                                    sets: sets, setChange: sets - lastSets, reason: "",
                                    stalled: stalled, regressing: regressing)

        switch tracking {
        case .weightReps:
            progressLoad(&target, last: last, equipment: exercise?.equipment, notes: &notes)
        case .reps:
            if let capacity = last.repCapacity, let lastReps = last.topReps {
                let reps = max(Int((Double(capacity) * 1.03).rounded(.down)) - rir, 1)
                target.reps = reps
                target.action = reps > lastReps ? .addReps : .hold
                notes.insert(reps > lastReps
                             ? String(localized: "Aim for \(reps) reps — one or two more than last time.")
                             : String(localized: "Match last time's \(lastReps) reps, leaving \(rir) in reserve."), at: 0)
            }
        case .duration:
            if let seconds = last.bestSeconds {
                target.seconds = seconds + 5
                target.action = .addReps
                notes.insert(String(localized: "Hold 5 seconds longer than last time."), at: 0)
            }
        }

        // Joint pain, stalls and regressions override the headline.
        if joints.lastTwoHurt {
            target.action = .swap
            notes.insert(String(localized: "This hurt your joints the last two times. Try one of the swaps below — same muscle, easier on the joints."), at: 0)
        } else if regressing {
            target.action = .removeSet
            target.weightKg = last.topWeight
            target.reps = last.topReps
            notes.insert(String(localized: "Performance has dropped two sessions in a row — fatigue is outrunning recovery. Same weight, one set fewer. If it keeps dropping, start a deload."), at: 0)
        } else if longStall {
            target.action = .swap
            notes.insert(String(localized: "No real progress in six sessions. Swap to a similar exercise for the next block — a new variation often gets things moving again."), at: 0)
        } else if stalled {
            if case .build(let week, let total) = block.phase(on: date), week >= total - 1 {
                target.action = .deload
                notes.insert(String(localized: "Stalled for three sessions this late in the block — that's accumulated fatigue. Consider starting your deload now."), at: 0)
            } else if target.setChange <= 0 && !strained && feedback?.setChange ?? 0 >= 0 {
                target.sets = min(target.sets + 1, 8)
                target.setChange = target.sets - lastSets
                target.action = .addSet
                notes.insert(String(localized: "No progress in weight or reps for three sessions. Add a set: more volume is the next lever."), at: 0)
            }
        } else if target.setChange > 0 && target.action == .hold {
            target.action = .addSet
        } else if target.setChange < 0 && target.action == .hold {
            target.action = .removeSet
        }

        if joints.rated == 0 && feedback?.jointPain == .alot {
            notes.append(String(localized: "Joints hurt a lot last time — if it happens again, swap this exercise."))
        }

        target.reason = notes.joined(separator: " ")
        return target
    }

    private static func progressLoad(_ target: inout ExerciseTarget, last: Session, equipment: String?, notes: inout [String]) {
        guard let weight = last.topWeight, let lastReps = last.topReps, let capacity = last.capacity else { return }
        let rir = target.rir
        let low = target.repLow, high = target.repHigh
        // Aim a little above last time.
        let goal = capacity * 1.01
        func reps(at w: Double) -> Int { Int((30 * (goal / w - 1)).rounded(.down)) - rir }

        let step = weightStep(for: equipment, weight: weight)
        let heavier = weight + step
        let repsHeavier = reps(at: heavier)
        let repsSame = reps(at: weight)
        let felt = last.averageRIR
        let intended = last.targetRIR ?? rir

        if lastReps >= high || repsHeavier >= low {
            // Top of the range, or strong enough to move up and stay in it.
            let r = min(max(repsHeavier, low), high)
            target.action = .addWeight
            target.weightKg = heavier
            target.reps = r
            if let felt, felt > Double(intended) + 0.5 {
                notes.insert(String(localized: "Last time felt easier than planned. Go up to \(fmt(heavier)) kg for \(r) reps."), at: 0)
            } else {
                notes.insert(String(localized: "You earned it: \(fmt(heavier)) kg for \(r) reps, stopping \(rir) short of failure."), at: 0)
            }
        } else if repsSame < low - 1 {
            // Can't stay in the range at this effort: lighten so the reps land inside it.
            let raw = goal / (1 + Double(low + rir) / 30)
            let lighter = max(min((raw / step).rounded(.down) * step, weight - step), step)
            target.action = .reduceWeight
            target.weightKg = lighter
            target.reps = low
            notes.insert(lastReps < low
                         ? String(localized: "Last time's reps fell below your \(low)–\(high) range. Drop to \(fmt(lighter)) kg and get back in it.")
                         : String(localized: "Stopping \(rir) reps short at \(fmt(weight)) kg would leave you under \(low) reps. Use \(fmt(lighter)) kg for \(low)."), at: 0)
        } else if repsSame > lastReps {
            let r = min(max(repsSame, lastReps + 1), high)
            target.action = .addReps
            target.weightKg = weight
            target.reps = r
            notes.insert(String(localized: "The next weight up is too big a jump. Stay at \(fmt(weight)) kg and go for \(r) reps."), at: 0)
        } else {
            let r = max(repsSame, low)
            target.action = .hold
            target.weightKg = weight
            target.reps = r
            if let felt, felt < Double(intended) - 0.5 {
                notes.insert(String(localized: "You went closer to failure than planned. Stay at \(fmt(weight)) kg × \(r), but stop \(rir) reps short this time."), at: 0)
            } else {
                notes.insert(String(localized: "Match \(fmt(weight)) kg × \(r) with \(rir) in reserve — beating it cleanly next time moves you up."), at: 0)
            }
        }
    }

    static func muscleName(_ muscle: String) -> String {
        String(localized: String.LocalizationValue(muscle.capitalized)).lowercased()
    }

    private static func feedbackSummary(_ f: MuscleFeedback) -> String {
        var parts: [String] = []
        if let s = f.soreness { parts.append(s.label.lowercased()) }
        if let p = f.pump { parts.append(String(localized: "\(p.label.lowercased()) pump")) }
        if let w = f.workload { parts.append(w.label.lowercased()) }
        return parts.joined(separator: ", ")
    }

    static func fmt(_ kg: Double) -> String {
        kg.formatted(.number.precision(.fractionLength(0...2)))
    }
}
