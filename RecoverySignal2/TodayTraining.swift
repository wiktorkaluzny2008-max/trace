//
//  TodayTraining.swift
//  RecoverySignal2
//
//  The bodybuilding front page: today's session with one obvious Start
//  button and the week's session streak, weekly hard sets per muscle against
//  the 10–20 set growth range, and personal records. All derived from the
//  workouts logged in the app, so every card fills in as soon as you train.
//

import SwiftUI
import SwiftData

// MARK: - Settings

enum TrainingTargets {
    static let sessionsKey = "training.sessionsPerWeek"

    /// How many sessions a week you're aiming for (the week strip's goal).
    static var sessionsPerWeek: Int {
        get { max(1, min(UserDefaults.standard.object(forKey: sessionsKey) as? Int ?? 4, 7)) }
        set { UserDefaults.standard.set(newValue, forKey: sessionsKey) }
    }

    /// The usual weekly hard-set range for growth, per muscle.
    static let growthRange: ClosedRange<Double> = 10...20
}

// MARK: - Personal records

struct PersonalRecord: Identifiable, Hashable {
    enum Kind: Hashable {
        case oneRepMax, heaviest
        var label: String {
            switch self {
            case .oneRepMax: String(localized: "est. 1RM")
            case .heaviest:  String(localized: "heaviest set")
            }
        }
    }

    let id: String
    let exerciseID: String
    let exerciseName: String
    let kind: Kind
    let value: Double
    let previous: Double
    let date: Date

    var gain: Double { value - previous }
}

enum PersonalRecords {

    /// Every PR ever set, oldest first, by replaying the logs: a session counts
    /// when it beats the previous best for that exercise (the first time an
    /// exercise is done sets the baseline rather than a record).
    static func all(in logs: [WorkoutLog]) -> [PersonalRecord] {
        var best: [String: (oneRepMax: Double, heaviest: Double)] = [:]
        var records: [PersonalRecord] = []
        for log in logs.sorted(by: { $0.start < $1.start }) {
            for exercise in log.exercises {
                let sets = exercise.workingSets
                guard !sets.isEmpty else { continue }
                let sessionMax = sets.compactMap(\.estimatedOneRepMax).max() ?? 0
                let sessionHeaviest = sets.compactMap(\.weightKg).max() ?? 0
                guard sessionMax > 0 || sessionHeaviest > 0 else { continue }
                if let prior = best[exercise.exerciseID] {
                    if sessionHeaviest > prior.heaviest + 0.01 {
                        records.append(PersonalRecord(id: "\(log.id)-\(exercise.exerciseID)-w", exerciseID: exercise.exerciseID,
                                                      exerciseName: exercise.name, kind: .heaviest, value: sessionHeaviest,
                                                      previous: prior.heaviest, date: log.start))
                    } else if sessionMax > prior.oneRepMax + 0.01 {
                        records.append(PersonalRecord(id: "\(log.id)-\(exercise.exerciseID)-m", exerciseID: exercise.exerciseID,
                                                      exerciseName: exercise.name, kind: .oneRepMax, value: sessionMax,
                                                      previous: prior.oneRepMax, date: log.start))
                    }
                    best[exercise.exerciseID] = (max(prior.oneRepMax, sessionMax), max(prior.heaviest, sessionHeaviest))
                } else {
                    best[exercise.exerciseID] = (sessionMax, sessionHeaviest)
                }
            }
        }
        return records
    }

    /// PRs from the last `days` days, newest first.
    static func recent(in logs: [WorkoutLog], days: Int = 7) -> [PersonalRecord] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? .distantPast
        return all(in: logs).filter { $0.date >= cutoff }.sorted { $0.date > $1.date }
    }

    struct BestLift: Identifiable {
        var id: String { exerciseID }
        let exerciseID: String
        let name: String
        let oneRepMax: Double
        let weightKg: Double
        let reps: Int
    }

    /// Your strongest exercises by estimated one-rep max.
    static func bestLifts(in logs: [WorkoutLog], limit: Int = 3) -> [BestLift] {
        var best: [String: BestLift] = [:]
        for log in logs {
            for exercise in log.exercises {
                for set in exercise.workingSets {
                    guard let max = set.estimatedOneRepMax, let w = set.weightKg, let r = set.reps else { continue }
                    if max > (best[exercise.exerciseID]?.oneRepMax ?? 0) {
                        best[exercise.exerciseID] = BestLift(exerciseID: exercise.exerciseID, name: exercise.name,
                                                             oneRepMax: max, weightKg: w, reps: r)
                    }
                }
            }
        }
        return best.values.sorted { $0.oneRepMax > $1.oneRepMax }.prefix(limit).map { $0 }
    }
}

// MARK: - Formatting

private func kg(_ value: Double) -> String {
    value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
}

private func wholeNumber(_ value: Double) -> String {
    Int(value.rounded()).formatted()
}

// MARK: - Today's session

/// What to do today: the routine that's been waiting longest, with a Start
/// button, or the session already done, with its numbers. Underneath, the
/// week as seven dots against your sessions-a-week goal.
struct TrainingHeroCard: View {
    /// Daily rollups, for Watch workouts that weren't logged in the app.
    let days: [DailyMetrics]
    var onOpenTrain: () -> Void = {}

    @Query(sort: \WorkoutRoutine.createdAt, order: .forward) private var routines: [WorkoutRoutine]
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @State private var recorder = WorkoutRecorder.shared
    @AppStorage(TrainingTargets.sessionsKey) private var sessionsGoal = 4
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var calendar: Calendar { .current }
    private var todayLog: WorkoutLog? { logs.first { calendar.isDateInToday($0.start) } }

    /// The routine you haven't done for longest; never-done routines first,
    /// in the order you built them.
    private var nextRoutine: WorkoutRoutine? {
        routines.sorted {
            ($0.lastPerformed ?? .distantPast, $0.createdAt) < ($1.lastPerformed ?? .distantPast, $1.createdAt)
        }.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let done = todayLog {
                doneView(done)
            } else {
                nextUpView
            }

            weekStrip
        }
        .card(padding: 18)
    }

    // MARK: Next up

    @ViewBuilder
    private var nextUpView: some View {
        if let routine = nextRoutine {
            let exercises = routine.exercises
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(routine.lastPerformed.map { String(localized: "Next up · \($0.formatted(.relative(presentation: .named)))") }
                         ?? String(localized: "Next up · not done yet"))
                        .font(.eyebrow)
                        .tracking(0.9)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.accent)
                    Text(routine.name)
                        .font(.display(30))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                        .minimumScaleFactor(0.7)
                    Text(routineSummary(exercises))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(2)
                }

                // One button. Any other routine is a tap away on the Train tab,
                // which the section header opens.
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    recorder.start(name: routine.name, routine: routine, logs: logs)
                } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.primary)
                .disabled(recorder.isActive)
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("No routines yet")
                        .font(.display(26))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Build one for each session — Push, Pull, Legs — and it'll be waiting here on the right day.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    Button { onOpenTrain() } label: { Label("Build a routine", systemImage: "plus") }
                        .buttonStyle(.primary)
                    Button {
                        recorder.start(name: String(localized: "Workout"), routine: nil, logs: logs)
                    } label: {
                        Text("Empty")
                    }
                    .buttonStyle(.secondary)
                    .frame(maxWidth: 110)
                    .disabled(recorder.isActive)
                }
            }
        }
    }

    private func routineSummary(_ exercises: [PlannedExercise]) -> String {
        let sets = exercises.reduce(0) { $0 + $1.sets }
        var parts = [String(localized: "\(exercises.count) exercises"), String(localized: "\(sets) sets")]
        let muscles = mainMuscles(exercises)
        if !muscles.isEmpty { parts.append(muscles.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    /// The three muscles the routine works most, by weighted set count.
    private func mainMuscles(_ exercises: [PlannedExercise]) -> [String] {
        var totals: [Muscle: Double] = [:]
        for planned in exercises {
            guard let exercise = ExerciseLibrary.shared.exercise(id: planned.exerciseID) else { continue }
            for (muscle, weight) in LoggedMuscleVolume.weights(for: exercise) {
                totals[muscle, default: 0] += weight * Double(planned.sets)
            }
        }
        return totals.sorted { $0.value > $1.value }.prefix(3).map { $0.key.name }
    }

    // MARK: Done

    private func doneView(_ log: WorkoutLog) -> some View {
        let prs = PersonalRecords.all(in: logs).filter { calendar.isDate($0.date, inSameDayAs: log.start) }
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text(prs.isEmpty ? String(localized: "Done today") : String(localized: "Done today · \(prs.count) PR"))
                    .font(.eyebrow)
                    .tracking(0.9)
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.good)
                Text(log.name)
                    .font(.display(30))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                    .minimumScaleFactor(0.7)
            }
            HStack(spacing: 0) {
                stat(String(localized: "Sets"), "\(log.setCount)")
                divider
                stat(String(localized: "Volume"), wholeNumber(log.volume), unit: "kg")
                divider
                stat(String(localized: "Time"), durationText(log.duration / 60))
            }
            .padding(.vertical, 12)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))

            Button {
                onOpenTrain()
            } label: {
                Label("Train again", systemImage: "arrow.counterclockwise")
            }
            .buttonStyle(.secondary)
        }
    }

    private func stat(_ label: String, _ value: String, unit: String? = nil) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(verbatim: value).font(.display(22)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                if let unit { Text(verbatim: unit).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary) }
            }
            Text(LocalizedStringKey(label)).font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(width: 1, height: 28)
    }

    // MARK: Week strip

    private var weekStrip: some View {
        let week = currentWeekDays
        let trained = Set(week.filter { trainedOn($0) })
        let count = trained.count
        return VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.separator)
            HStack(alignment: .center, spacing: 12) {
                // Seven dots: filled on the days you trained, outlined for today.
                HStack(spacing: 6) {
                    ForEach(week, id: \.self) { day in
                        let did = trained.contains(day)
                        let isToday = calendar.isDateInToday(day)
                        VStack(spacing: 4) {
                            ZStack {
                                Circle().fill(did ? Theme.accent : Theme.track)
                                if isToday && !did {
                                    Circle().strokeBorder(Theme.accent, lineWidth: 1.5)
                                }
                            }
                            .frame(width: 16, height: 16)
                            Text(day.formatted(.dateTime.weekday(.narrow)))
                                .font(.system(size: 10, weight: isToday ? .bold : .medium))
                                .foregroundStyle(isToday ? Theme.textPrimary : Theme.textTertiary)
                        }
                        .frame(width: 22)
                    }
                }
                Spacer(minLength: 4)
                // "3 of 4 sessions" — tap to change the weekly goal.
                Menu {
                    Picker("Sessions a week", selection: $sessionsGoal) {
                        ForEach(2...7, id: \.self) { Text("\($0) a week").tag($0) }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(count) of \(sessionsGoal) sessions")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .foregroundStyle(count >= sessionsGoal ? Theme.good : Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                .fixedSize()
                .accessibilityLabel("\(count) of \(sessionsGoal) sessions this week. Sessions a week goal")
            }
        }
    }

    private var currentWeekDays: [Date] {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: Date()) else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    private func trainedOn(_ day: Date) -> Bool {
        if logs.contains(where: { calendar.isDate($0.start, inSameDayAs: day) }) { return true }
        return days.contains { calendar.isDate($0.date, inSameDayAs: day) && $0.hadWorkout }
    }
}

// MARK: - Weekly sets per muscle

/// This week's hard sets for the muscles that matter most, each against the
/// 10–20 set growth range (the band on the bar). Assisting muscles count half.
struct WeeklySetsCard: View {
    var onOpen: () -> Void = {}

    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]

    private static let shown: [Muscle] = [.chest, .lats, .upperBack, .sideDelts, .biceps, .triceps,
                                          .quads, .hamstrings, .glutes, .calves, .abs, .rearDelts]
    private static let scaleMax = 24.0

    var body: some View {
        let sets = LoggedMuscleVolume.weeklySets(logs: logs, sessions: sessions, weekContaining: Date())
        // The headline counts sets you actually did; the per-muscle bars
        // share assisting-muscle credit, so their sum would be higher.
        let week = Calendar.current.dateInterval(of: .weekOfYear, for: Date())
        let total = logs.filter { week?.contains($0.start) == true }.reduce(0) { $0 + $1.setCount }
            + sessions.filter { week?.contains($0.date) == true }.reduce(0) { $0 + $1.hardSets }
        let inRange = Self.shown.filter { TrainingTargets.growthRange.contains(sets[$0] ?? 0) }.count

        VStack(alignment: .leading, spacing: 16) {
            // The week in one line: the sets you did, and how many muscles sit
            // in the band the bars show.
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(verbatim: "\(total)")
                        .font(.display(26))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    Text("hard sets this week")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(total == 0 ? String(localized: "Nothing logged yet — the bars fill as you train")
                                : String(localized: "\(inRange) of \(Self.shown.count) muscles in the 10–20 set growth range"))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                      alignment: .leading, spacing: 12) {
                ForEach(Self.shown) { muscle in
                    row(muscle, sets: sets[muscle] ?? 0)
                }
            }
        }
        .card(padding: 18)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }

    private func row(_ muscle: Muscle, sets: Double) -> some View {
        let fraction = min(sets / Self.scaleMax, 1)
        let color: Color = sets == 0 ? Theme.textTertiary.opacity(0.5)
            : (sets < TrainingTargets.growthRange.lowerBound ? Theme.mint : Theme.accent)
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(muscle.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 4)
                Text(verbatim: kg(sets))
                    .font(.system(size: 13, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(sets == 0 ? Theme.textTertiary : Theme.textPrimary)
            }
            GeometryReader { geo in
                let lo = geo.size.width * TrainingTargets.growthRange.lowerBound / Self.scaleMax
                let hi = geo.size.width * TrainingTargets.growthRange.upperBound / Self.scaleMax
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Theme.accent.opacity(0.18))
                        .frame(width: hi - lo)
                        .offset(x: lo)
                    Capsule()
                        .fill(color)
                        .frame(width: max(geo.size.width * fraction, sets > 0 ? 5 : 0))
                }
            }
            .frame(height: 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(muscle.name): \(kg(sets)) sets this week")
    }
}

// MARK: - Personal records

/// New records this week, or — when there aren't any yet — your three
/// strongest lifts, so the card is never empty once you've trained.
struct RecordsCard: View {
    var onOpen: () -> Void = {}
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]

    var body: some View {
        let recent = PersonalRecords.recent(in: logs, days: 7)
        let best = recent.isEmpty ? PersonalRecords.bestLifts(in: logs) : []

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.isEmpty ? "Best lifts" : "New records")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(recent.isEmpty ? String(localized: "Estimated one-rep max, from your logged sets")
                                        : String(localized: "\(recent.count) this week"))
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                if !recent.isEmpty {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Theme.accent)
                }
            }

            if logs.isEmpty {
                Text("Records appear once you've logged the same exercise more than once.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if !recent.isEmpty {
                VStack(spacing: 0) {
                    ForEach(recent.prefix(4)) { record in
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.good)
                                .frame(width: 28, height: 28)
                                .background(Theme.good.opacity(0.12), in: Circle())
                            VStack(alignment: .leading, spacing: 1) {
                                Text(record.exerciseName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text("\(record.kind.label) · \(record.date.formatted(.dateTime.weekday(.abbreviated)))")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            Spacer(minLength: 4)
                            VStack(alignment: .trailing, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 2) {
                                    Text(verbatim: kg(record.value)).font(.display(20)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                                    Text(verbatim: "kg").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
                                }
                                Text(verbatim: "+\(kg(record.gain))")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(Theme.good)
                            }
                        }
                        .padding(.vertical, 8)
                        if record.id != recent.prefix(4).last?.id {
                            Divider().overlay(Theme.separator)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ForEach(best) { lift in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(lift.name)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textSecondary)
                                .lineLimit(2)
                                .minimumScaleFactor(0.8)
                                .frame(height: 30, alignment: .top)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text(verbatim: kg(lift.oneRepMax)).font(.display(24)).monospacedDigit().foregroundStyle(Theme.textPrimary)
                                Text(verbatim: "kg").font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textTertiary)
                            }
                            Text(verbatim: "\(kg(lift.weightKg)) × \(lift.reps)")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                }
            }
        }
        .card(padding: 18)
        .contentShape(Rectangle())
        .onTapGesture { onOpen() }
    }
}

// MARK: - Week summary (Train tab)

/// Four big numbers for the week: sessions, hard sets, volume and time.
struct TrainingWeekSummary: View {
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \DailyMetrics.date, order: .reverse) private var days: [DailyMetrics]
    @AppStorage(TrainingTargets.sessionsKey) private var sessionsGoal = 4

    var body: some View {
        let calendar = Calendar.current
        let week = calendar.dateInterval(of: .weekOfYear, for: Date())
        let thisWeek = logs.filter { week?.contains($0.start) == true }
        // Days trained, counted the same way as Today's week strip: a session
        // logged here or any workout the Watch recorded.
        let trainedDays = Set(thisWeek.map { calendar.startOfDay(for: $0.start) })
            .union(days.filter { week?.contains($0.date) == true && $0.hadWorkout }.map { calendar.startOfDay(for: $0.date) })
        let sets = thisWeek.reduce(0) { $0 + $1.setCount }
        let volume = thisWeek.reduce(0) { $0 + $1.volume }
        let minutes = thisWeek.reduce(0) { $0 + $1.duration / 60 }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("This week").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text(week.map { "\($0.start.formatted(.dateTime.day().month(.abbreviated))) – \($0.end.addingTimeInterval(-1).formatted(.dateTime.day().month(.abbreviated)))" } ?? "")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
            // Two by two, every tile the same height, so nothing truncates or
            // slides under its neighbour at larger text sizes.
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile(String(localized: "Sessions"), "\(trainedDays.count)", unit: String(localized: "of \(sessionsGoal)"), symbol: "figure.strengthtraining.traditional")
                tile(String(localized: "Hard sets"), "\(sets)", symbol: "square.stack.3d.up.fill")
                tile(String(localized: "Volume"), wholeNumber(volume), unit: "kg", symbol: "scalemass.fill")
                tile(String(localized: "Time"), durationText(minutes), symbol: "clock.fill")
            }
        }
        .card(padding: 16)
    }

    private func tile(_ label: String, _ value: String, unit: String? = nil, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text(LocalizedStringKey(label))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: value)
                    .font(.display(26))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(verbatim: unit)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
