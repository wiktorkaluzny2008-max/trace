//
//  SetEffort.swift
//  RecoverySignal2
//
//  Lines the heart rate recorded during a workout up with every set you
//  logged, and reads from it only what the research supports:
//
//  • Heart rate during lifting tracks cardiovascular load — reps, time under
//    tension, muscle mass and rest length — not how many reps you had left.
//    Light 15RM sets raise heart rate more than heavy 4RM sets even though
//    lifters rate the heavy sets harder (Gjøvaag 2016; Day 2004). So RIR is
//    estimated from load and reps against your own estimated 1RM, and heart
//    rate is shown beside it as a separate "cardio cost" reading.
//  • Heart rate peaks at the end of a set or within ~20 s after it, and stays
//    close to that for the first minute (Lässing 2023), so the peak window is
//    set end → +20 s and recovery is read at 60 s.
//  • Heart rate drifts upward across a session and recovers more slowly as
//    sets accumulate, more so with short rests (<90 s) (JSCR 2016; Int J
//    Exerc Sci 2018). Between-set recovery is therefore read as fatigue.
//  • Lower-body compound lifts produce bigger heart-rate responses and slower
//    recovery than upper-body or isolation work (J Hum Kinet 2014), so sets
//    are classified and only compared within their class.
//  • Session cardiac load uses Edwards' zone TRIMP — the standard heart-rate
//    load measure, valid for the cardiovascular side of a session only.
//  • Apple Watch heart rate during lifting reads within ~2 bpm of a chest
//    strap on average (Bioengineering 2026), so wrist readings are trusted
//    when the signal is continuous; sets with gaps are left out.
//

import Foundation
import SwiftUI
import SwiftData
import Charts

// MARK: - Classification

/// Heart rate responds very differently to a squat and a curl, so sets are
/// only ever compared within their class.
enum ExerciseClass: String {
    case lowerCompound, upperCompound, isolation

    var label: String {
        switch self {
        case .lowerCompound: String(localized: "lower-body compound")
        case .upperCompound: String(localized: "upper-body compound")
        case .isolation:     String(localized: "isolation")
        }
    }

    private static let lower: Set<String> = ["quadriceps", "hamstrings", "glutes", "lower back", "adductors", "abductors", "calves"]

    static func of(_ exercise: LoggedExercise) -> ExerciseClass {
        let library = ExerciseLibrary.shared.exercise(id: exercise.exerciseID)
        let primary = library?.primaryMuscles.first ?? exercise.primaryMuscle
        let compound = (library?.mechanic ?? "compound") == "compound"
        if !compound { return .isolation }
        return lower.contains(primary.lowercased()) ? .lowerCompound : .upperCompound
    }
}

// MARK: - Per-set heart-rate response

struct SetHeartRateResponse: Hashable {
    /// Mean heart rate in the rest before the set (its lowest stretch).
    let baseline: Double
    /// Highest reading from set end to 20 s after.
    let peak: Double
    /// Reading about 60 s after the set, when the rest was long enough.
    let after60: Double?

    var rise: Double { peak - baseline }
    var recovery60: Double? { after60.map { peak - $0 } }
}

enum SetHeartRate {

    /// Minimum samples around a set for its response to count.
    static let minimumSamples = 4

    /// Matches each completed working set to the heart-rate stream.
    /// `samples` are the session's readings, oldest first.
    static func responses(for log: WorkoutLog, samples: [(date: Date, bpm: Double)]) -> [UUID: SetHeartRateResponse] {
        guard samples.count >= minimumSamples else { return [:] }
        let sets = log.exercises.flatMap { exercise in
            exercise.sets.filter { $0.completed && $0.kind != .warmup }.compactMap { set in set.completedAt.map { (set.id, $0) } }
        }.sorted { $0.1 < $1.1 }

        var result: [UUID: SetHeartRateResponse] = [:]
        for (index, (id, end)) in sets.enumerated() {
            let previousEnd = index > 0 ? sets[index - 1].1 : log.start
            let nextEnd = index + 1 < sets.count ? sets[index + 1].1 : log.end

            // The signal has to be continuous around the set: wrist sensors
            // drop out when you grip hard, and a gap would fake a peak.
            let around = samples.filter { $0.date >= end.addingTimeInterval(-45) && $0.date <= end.addingTimeInterval(20) }
            guard around.count >= minimumSamples else { continue }

            // Peak: set end → +20 s (the post-set rebound once breathing resumes).
            guard let peak = samples.filter({ $0.date >= end.addingTimeInterval(-10) && $0.date <= end.addingTimeInterval(20) })
                .map(\.bpm).max() else { continue }

            // Baseline: the calmest 20 s of the rest before the set, after the
            // previous set's own rebound has passed. Short rests fall back to
            // the lowest reading in between.
            let restStart = previousEnd.addingTimeInterval(index > 0 ? 30 : 0)
            let restEnd = end.addingTimeInterval(-35)
            let rest = samples.filter { $0.date >= restStart && $0.date <= restEnd }.map(\.bpm)
            let baseline: Double
            if rest.count >= 3 {
                let lowest = rest.sorted().prefix(max(3, rest.count / 3))
                baseline = lowest.reduce(0, +) / Double(lowest.count)
            } else if let low = samples.filter({ $0.date >= previousEnd && $0.date <= end.addingTimeInterval(-15) }).map(\.bpm).min() {
                baseline = low
            } else {
                continue
            }

            // Recovery at 60 s, only when the next set hadn't started yet.
            var after60: Double?
            if nextEnd.timeIntervalSince(end) > 75 {
                let target = end.addingTimeInterval(60)
                after60 = samples
                    .filter { abs($0.date.timeIntervalSince(target)) <= 12 }
                    .min { abs($0.date.timeIntervalSince(target)) < abs($1.date.timeIntervalSince(target)) }?.bpm
            }
            result[id] = SetHeartRateResponse(baseline: baseline, peak: max(peak, baseline), after60: after60)
        }
        return result
    }

    /// Your maximum heart rate: the highest reading ever recorded in a
    /// workout, or 220 − age until a session has shown something higher.
    static func maxHeartRate(logs: [WorkoutLog], profile: BodyProfile = BodyProfile.load()) -> Double {
        let observed = logs.compactMap(\.maxHeartRate).max() ?? 0
        let formula = Double(220 - (profile.ageYears ?? 30))
        return max(observed, formula)
    }

    /// Edwards' summated-zone TRIMP for a session: minutes in each 10 % band
    /// of max heart rate from 50 % up, weighted 1–5.
    static func edwardsTRIMP(samples: [(date: Date, bpm: Double)], maxHeartRate: Double) -> Double {
        guard samples.count >= 2, maxHeartRate > 0 else { return 0 }
        var load = 0.0
        for (a, b) in zip(samples, samples.dropFirst()) {
            let minutes = min(b.date.timeIntervalSince(a.date), 120) / 60
            let fraction = a.bpm / maxHeartRate
            let zone: Double = fraction >= 0.9 ? 5 : fraction >= 0.8 ? 4 : fraction >= 0.7 ? 3 : fraction >= 0.6 ? 2 : fraction >= 0.5 ? 1 : 0
            load += minutes * zone
        }
        return load
    }
}

// MARK: - Load-implied effort

enum LoadEffort {

    /// Reps in reserve implied by the load: how many reps your estimated 1RM
    /// says you could do at this weight (Epley, inverted), minus the reps you
    /// did. The 1RM is the RIR-adjusted best from the previous 60 days — a set
    /// stopped two reps short counts as two reps more, the same adjustment the
    /// performance model uses — so a session that sets a PR doesn't read as
    /// "zero left" by construction. Epley is only trusted up to about 12 reps;
    /// beyond that the estimate is marked rough.
    struct Estimate: Hashable {
        let rir: Int
        let repsPossible: Double
        let oneRepMax: Double
        let rough: Bool
    }

    /// Epley with reps in reserve added back (2 when the set wasn't rated).
    nonisolated static func adjustedOneRepMax(_ set: LoggedSet) -> Double? {
        guard let w = set.weightKg, let r = set.reps, w > 0, r > 0 else { return nil }
        return w * (1 + Double(r + (set.rir ?? 2)) / 30)
    }

    static func estimate(set: LoggedSet, exercise: LoggedExercise, log: WorkoutLog, logs: [WorkoutLog]) -> Estimate? {
        guard exercise.tracking == .weightReps, let w = set.weightKg, let r = set.reps, w > 0, r > 0 else { return nil }
        let since = Calendar.current.date(byAdding: .day, value: -60, to: log.start) ?? .distantPast
        let history = logs.filter { $0.start >= since && $0.start < log.start && $0.id != log.id }
        var best = history
            .flatMap { $0.exercises.filter { $0.exerciseID == exercise.exerciseID }.flatMap(\.workingSets) }
            .compactMap(adjustedOneRepMax)
            .max()
        if best == nil {
            // First time: the session's own other sets are all there is.
            best = exercise.workingSets.filter { $0.id != set.id }.compactMap(adjustedOneRepMax).max()
        }
        guard let oneRepMax = best, oneRepMax > 0 else { return nil }
        let possible = w >= oneRepMax ? 1 : 30 * (oneRepMax / w - 1)
        let rir = max(0, min(10, Int((possible - Double(r)).rounded())))
        return Estimate(rir: rir, repsPossible: possible, oneRepMax: oneRepMax, rough: r > 12 || possible > 15)
    }
}

// MARK: - Session reading

struct SetEffortRow: Identifiable, Hashable {
    let id: UUID
    let exerciseName: String
    let exerciseClass: ExerciseClass
    let index: Int
    let set: LoggedSet
    let tracking: SetTracking
    let heart: SetHeartRateResponse?
    let load: LoadEffort.Estimate?
    /// Seconds since the previous completed set (any exercise).
    let restBefore: TimeInterval?
    let completedAt: Date
}

struct SessionEffort {
    let rows: [SetEffortRow]
    let maxHeartRate: Double
    let trimp: Double
    /// Linear trend of 60-s recovery across the session, bpm per set; negative = recovery slowing.
    let recoveryTrend: Double?
    let shortRests: Int
    let ratedSets: Int

    var withHeart: [SetEffortRow] { rows.filter { $0.heart != nil } }

    static func build(log: WorkoutLog, logs: [WorkoutLog], samples: [(date: Date, bpm: Double)]) -> SessionEffort {
        let responses = SetHeartRate.responses(for: log, samples: samples)
        let maxHR = SetHeartRate.maxHeartRate(logs: logs)
        var rows: [SetEffortRow] = []
        var previous: Date? = nil
        let ordered = log.exercises.flatMap { exercise in
            exercise.sets.enumerated().compactMap { i, set -> (LoggedExercise, Int, LoggedSet, Date)? in
                guard set.completed, set.kind != .warmup, let at = set.completedAt else { return nil }
                return (exercise, i, set, at)
            }
        }.sorted { $0.3 < $1.3 }
        for (exercise, i, set, at) in ordered {
            rows.append(SetEffortRow(id: set.id, exerciseName: exercise.name, exerciseClass: ExerciseClass.of(exercise), index: i + 1,
                                     set: set, tracking: exercise.tracking, heart: responses[set.id],
                                     load: LoadEffort.estimate(set: set, exercise: exercise, log: log, logs: logs),
                                     restBefore: previous.map { at.timeIntervalSince($0) }, completedAt: at))
            previous = at
        }
        let recoveries = rows.compactMap { $0.heart?.recovery60 }
        return SessionEffort(rows: rows, maxHeartRate: maxHR,
                             trimp: SetHeartRate.edwardsTRIMP(samples: samples, maxHeartRate: maxHR),
                             recoveryTrend: recoveries.count >= 4 ? Stats.slope(recoveries) : nil,
                             shortRests: rows.filter { ($0.restBefore ?? 999) < 90 }.count,
                             ratedSets: rows.filter { $0.set.rir != nil }.count)
    }
}

// MARK: - Matched sets over time

/// The same exercise at the same weight and reps in earlier sessions: a lower
/// heart-rate rise for the same work means better conditioning or a fresher
/// day; a higher one, the opposite.
struct MatchedSetComparison: Identifiable {
    var id: String { exerciseName }
    let exerciseName: String
    let weightKg: Double
    let reps: Int
    let riseNow: Double
    let riseBefore: Double
    let sessionsBefore: Int
}

enum MatchedSets {
    static func compare(effort: SessionEffort, log: WorkoutLog, logs: [WorkoutLog],
                        history: [UUID: [(date: Date, bpm: Double)]]) -> [MatchedSetComparison] {
        var out: [MatchedSetComparison] = []
        let byExercise = Dictionary(grouping: effort.withHeart, by: \.exerciseName)
        for (name, rows) in byExercise {
            guard let best = rows.max(by: { ($0.set.volume) < ($1.set.volume) }),
                  let heart = best.heart, let w = best.set.weightKg, let r = best.set.reps else { continue }
            var rises: [Double] = []
            var sessions = 0
            for prior in logs where prior.id != log.id && prior.start < log.start {
                guard let samples = history[prior.id], let exercise = prior.exercises.first(where: { $0.name == name }) else { continue }
                let responses = SetHeartRate.responses(for: prior, samples: samples)
                let matches = exercise.sets.filter { $0.completed && $0.kind != .warmup && abs(($0.weightKg ?? -1) - w) < 0.01 && $0.reps == r }
                let matched = matches.compactMap { responses[$0.id]?.rise }
                if let m = matched.max() { rises.append(m); sessions += 1 }
            }
            guard sessions >= 2, let mean = Stats.mean(rises) else { continue }
            out.append(MatchedSetComparison(exerciseName: name, weightKg: w, reps: r, riseNow: heart.rise, riseBefore: mean, sessionsBefore: sessions))
        }
        return out.sorted { $0.exerciseName < $1.exerciseName }
    }
}

// MARK: - Card

/// Effort and heart rate, set by set, on a finished workout.
struct WorkoutEffortCard: View {
    let log: WorkoutLog
    let samples: [(date: Date, bpm: Double)]
    let logs: [WorkoutLog]

    @State private var comparisons: [MatchedSetComparison] = []
    @State private var showsAll = false

    var body: some View {
        let effort = SessionEffort.build(log: log, logs: logs, samples: samples)
        let heartRows = effort.withHeart
        let rows = showsAll ? effort.rows : Array(effort.rows.prefix(8))

        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Effort & heart rate")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(heartRows.isEmpty
                     ? String(localized: "Load-implied RIR per set. Wear your Watch for the heart-rate columns.")
                     : String(localized: "\(heartRows.count) of \(effort.rows.count) sets matched to a continuous heart-rate signal"))
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }

            if !heartRows.isEmpty {
                HStack(spacing: 10) {
                    tile(String(localized: "Cardiac load"), DetailFormat.whole(effort.trimp), detail: String(localized: "Edwards TRIMP"))
                    tile(String(localized: "Peak"), "\(DetailFormat.whole(100 * (heartRows.map { $0.heart!.peak }.max() ?? 0) / effort.maxHeartRate))%",
                         detail: String(localized: "of \(DetailFormat.whole(effort.maxHeartRate)) bpm max"))
                    tile(String(localized: "Short rests"), "\(effort.shortRests)", detail: String(localized: "under 90 s"))
                }
            }

            // Set table: the exercise column takes whatever the four fixed
            // number columns leave, so names get the most room.
            VStack(spacing: 0) {
                HStack(spacing: 4) {
                    Text("Set").frame(maxWidth: .infinity, alignment: .leading)
                    Text("RIR you").frame(width: Self.column)
                    Text("RIR load").frame(width: Self.column)
                    Text("HR rise").frame(width: Self.column)
                    Text("Rec. 60 s").frame(width: Self.column)
                }
                .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                .foregroundStyle(Theme.textTertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .padding(.bottom, 6)
                ForEach(rows) { row in
                    setRow(row, effort: effort)
                    if row.id != rows.last?.id { Divider().overlay(Theme.separator) }
                }
                if effort.rows.count > 8 {
                    Button(showsAll ? "Show fewer" : "Show all \(effort.rows.count) sets") { withAnimation(.snappy) { showsAll.toggle() } }
                        .font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                        .padding(.top, 8)
                }
            }

            if heartRows.count >= 2 {
                recoveryChart(heartRows)
            }

            ForEach(findings(effort), id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "waveform.path.ecg").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.accent).frame(width: 16)
                    Text(line).font(.footnote).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(comparisons) { c in
                let diff = c.riseNow - c.riseBefore
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: diff <= -4 ? "arrow.down.right.circle.fill" : (diff >= 4 ? "arrow.up.right.circle.fill" : "equal.circle.fill"))
                        .font(.system(size: 13)).foregroundStyle(diff <= -4 ? Theme.good : (diff >= 4 ? Theme.warn : Theme.textTertiary)).frame(width: 16)
                    Text(comparisonText(c, diff: diff))
                        .font(.footnote).foregroundStyle(Theme.textPrimary).fixedSize(horizontal: false, vertical: true)
                }
            }

            Text("Heart rate reflects cardiovascular load — reps, time under tension, muscle mass and rest — not how many reps you had left, so RIR here comes from your load against your estimated 1RM. Heart-rate readings are least telling for isolation and upper-body work.")
                .font(.caption2).foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 16)
        .task(id: log.id) { await loadComparisons(effort) }
    }

    // MARK: Rows

    private static let column: CGFloat = 50

    private func setRow(_ row: SetEffortRow, effort: SessionEffort) -> some View {
        let disagree = row.set.rir.flatMap { logged in row.load.map { abs($0.rir - logged) >= 2 && !$0.rough } } ?? false
        return HStack(spacing: 4) {
            VStack(alignment: .leading, spacing: 1) {
                Text(row.exerciseName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(setLabel(row)).font(.system(size: 10)).monospacedDigit().foregroundStyle(Theme.textTertiary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            cell(row.set.rir.map { RIRText.short($0) } ?? "—", color: Theme.textPrimary)
            cell(row.load.map { ($0.rough ? "~" : "") + "\($0.rir)" } ?? "—", color: disagree ? Theme.warn : Theme.textPrimary)
            cell(row.heart.map { "+\(DetailFormat.whole($0.rise))" } ?? "—",
                 color: row.heart.map { heartColor($0, max: effort.maxHeartRate) } ?? Theme.textTertiary)
            cell(row.heart?.recovery60.map { "−\(DetailFormat.whole($0))" } ?? "—", color: Theme.textPrimary)
        }
        .padding(.vertical, 7)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ text: String, color: Color) -> some View {
        Text(verbatim: text)
            .font(.system(size: 13, weight: .semibold)).monospacedDigit()
            .foregroundStyle(text == "—" ? Theme.textTertiary : color)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: Self.column)
    }

    /// "130 × 6 · 2:30 rest" — whole kilos stay whole.
    private func setLabel(_ row: SetEffortRow) -> String {
        var parts: [String] = []
        switch row.tracking {
        case .weightReps: parts.append("\(kilos(row.set.weightKg ?? 0)) × \(row.set.reps ?? 0)")
        case .reps:       parts.append("\(row.set.reps ?? 0) reps")
        case .duration:   parts.append("\(row.set.seconds ?? 0) s")
        }
        if let rest = row.restBefore, rest < 900 {
            let total = Int(rest.rounded())
            parts.append(String(format: "%d:%02d", total / 60, total % 60))
        }
        return parts.joined(separator: " · ")
    }

    private func kilos(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }

    private func heartColor(_ heart: SetHeartRateResponse, max: Double) -> Color {
        heart.peak / max >= 0.85 ? Theme.bad : (heart.peak / max >= 0.7 ? Theme.accent : Theme.textPrimary)
    }

    private func tile(_ label: String, _ value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value).font(.display(22)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(label)).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Text(verbatim: detail).font(.system(size: 10)).foregroundStyle(Theme.textTertiary).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    // MARK: Recovery chart

    private func recoveryChart(_ rows: [SetEffortRow]) -> some View {
        let points = rows.enumerated().map { (i: $0.offset + 1, peak: $0.element.heart!.peak, base: $0.element.heart!.baseline) }
        return VStack(alignment: .leading, spacing: 6) {
            Text("Heart rate per set — baseline before, peak after")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.textSecondary)
            Chart {
                ForEach(points, id: \.i) { p in
                    BarMark(x: .value("Set", p.i), yStart: .value("Base", p.base), yEnd: .value("Peak", p.peak), width: .ratio(0.55))
                        .foregroundStyle(Theme.accent.gradient)
                        .cornerRadius(3)
                }
            }
            .chartYScale(domain: .automatic(includesZero: false))
            .chartXAxis { AxisMarks(values: .automatic(desiredCount: min(points.count, 8))) }
            .frame(height: 120)
        }
    }

    // MARK: Findings

    private func findings(_ effort: SessionEffort) -> [String] {
        var lines: [String] = []
        let heart = effort.withHeart
        if let trend = effort.recoveryTrend, heart.count >= 4 {
            if trend <= -1 {
                lines.append(String(localized: "Your 60-second recovery slowed by about \(DetailFormat.whole(-trend)) bpm per set through the session — fatigue accumulating, which is normal; if it's steep, rest a little longer late in the session."))
            } else if trend >= 1 {
                lines.append(String(localized: "Recovery between sets got faster as the session went on — you warmed into it."))
            }
        }
        if effort.shortRests >= 3 {
            lines.append(String(localized: "\(effort.shortRests) sets came after less than 90 s of rest. Short rests raise heart rate on the next set regardless of how hard it was, so its HR rise reads high."))
        }
        let lower = heart.filter { $0.exerciseClass == .lowerCompound }
        let upper = heart.filter { $0.exerciseClass != .lowerCompound }
        if lower.count >= 2, upper.count >= 2,
           let l = Stats.mean(lower.map { $0.heart!.rise }), let u = Stats.mean(upper.map { $0.heart!.rise }) {
            lines.append(String(localized: "Lower-body compound sets raised heart rate +\(DetailFormat.whole(l)) bpm on average versus +\(DetailFormat.whole(u)) for the rest — expected, bigger muscles mean a bigger cardio response, not harder sets."))
        }
        let disagreements = effort.rows.filter { row in
            guard let logged = row.set.rir, let load = row.load, !load.rough else { return false }
            return load.rir - logged >= 2
        }
        if disagreements.count >= 2 {
            lines.append(String(localized: "\(disagreements.count) sets were logged closer to failure than your estimated 1RM suggests — either the 1RM is stale or those sets were harder than the numbers show. Both are worth knowing."))
        }
        if effort.ratedSets < effort.rows.count / 2 && effort.rows.count >= 4 {
            lines.append(String(localized: "Rate RIR on more sets: your own rating is the most reliable effort signal there is, and it's what the coach plans from."))
        }
        return lines
    }

    private func comparisonText(_ c: MatchedSetComparison, diff: Double) -> String {
        let work = "\(c.exerciseName) \(DetailFormat.decimal(c.weightKg)) kg × \(c.reps)"
        if diff <= -4 {
            return String(localized: "\(work): heart rate rose +\(DetailFormat.whole(c.riseNow)) bpm today vs +\(DetailFormat.whole(c.riseBefore)) across \(c.sessionsBefore) earlier sessions — the same work costs less, a sign of better conditioning or a fresher day.")
        } else if diff >= 4 {
            return String(localized: "\(work): heart rate rose +\(DetailFormat.whole(c.riseNow)) bpm today vs +\(DetailFormat.whole(c.riseBefore)) before — the same work cost more; check sleep, caffeine, rest length or a short night.")
        }
        return String(localized: "\(work): heart-rate response in line with your \(c.sessionsBefore) earlier sessions.")
    }

    private func loadComparisons(_ effort: SessionEffort) async {
        guard !effort.withHeart.isEmpty else { return }
        let names = Set(effort.withHeart.map(\.exerciseName))
        let since = Calendar.current.date(byAdding: .day, value: -90, to: log.start) ?? .distantPast
        let candidates = logs.filter { $0.id != log.id && $0.start < log.start && $0.start >= since
            && $0.exercises.contains { names.contains($0.name) } }.prefix(8)
        var history: [UUID: [(date: Date, bpm: Double)]] = [:]
        for prior in candidates {
            if let s = try? await HealthKitManager.shared.heartRateSamples(from: prior.start, to: prior.end), s.count >= SetHeartRate.minimumSamples {
                history[prior.id] = s
            }
        }
        comparisons = MatchedSets.compare(effort: effort, log: log, logs: logs, history: history)
    }
}
