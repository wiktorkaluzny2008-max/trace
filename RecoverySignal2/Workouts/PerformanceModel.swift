//
//  PerformanceModel.swift
//  RecoverySignal2
//
//  Learns, from one person's history, how sleep, HRV, resting heart rate and
//  training load relate to how well they lift, and (once there's enough data
//  and it demonstrably beats a plain guess) forecasts today's session.
//
//  Three pieces:
//   • ReadinessSnapshot — what your body looked like when a session started.
//     Saved with every workout from now on, and rebuilt from Health history for
//     sessions logged before this existed.
//   • PerformanceIndex — how a session went: each exercise's best estimated
//     one-rep max against its own recent average, as a percentage.
//   • PerformanceModel — pairs the two, and decides what can honestly be said:
//     nothing yet, which factors go with your good sessions, or a forecast.
//
//  Nothing here is sent anywhere. Gemini, if used, is only handed the finished
//  numbers to put into words.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Readiness snapshot

/// The state of your body going into a session. Only things known before the
/// first set: this morning's readings, and yesterday's load and food.
struct ReadinessSnapshot: nonisolated Codable, nonisolated Equatable {
    var capturedAt: Date
    var recoveryScore: Int?
    var sleepHours: Double?
    /// Hours asleep as a fraction of that night's estimated need (1 = met it).
    var sleepVsNeed: Double?
    var hrv: Double?
    /// HRV / resting heart rate in standard deviations from your own 4-week normal.
    var hrvZ: Double?
    var restingHR: Double?
    var restingHRZ: Double?
    var yesterdayStrain: Double?
    var trainingLoadRatio: Double?
    var yesterdayProtein: Double?
    var yesterdayKcal: Double?
    var deloadWeek: Bool?
    var hourOfDay: Int
    var alcoholYesterday: Bool

    /// The features the model sees, in a fixed order (see `featureNames`).
    var features: [Double?] {
        [sleepHours, sleepVsNeed, hrvZ, restingHRZ, yesterdayStrain, trainingLoadRatio, yesterdayProtein,
         deloadWeek.map { $0 ? 1.0 : 0.0 }, alcoholYesterday ? 1.0 : 0.0]
    }

    static let featureNames: [String] = [
        String(localized: "Sleep length"), String(localized: "Sleep vs need"), String(localized: "HRV vs your normal"),
        String(localized: "Resting heart rate vs your normal"), String(localized: "Yesterday's strain"),
        String(localized: "Training load ratio"), String(localized: "Yesterday's protein"),
        String(localized: "Deload week"), String(localized: "Alcohol the day before")
    ]

    /// Builds a snapshot from Health history. Uses only readings up to the morning of `start`,
    /// so it never sees the session it describes. HRV and resting HR are day averages, so a
    /// reading taken later that day can leak in slightly; that's noted, not fixed.
    static func capture(at start: Date, days: [DailyMetrics], tags: [DayTag] = []) -> ReadinessSnapshot? {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: start)
        let sorted = days.sorted { $0.date < $1.date }.filter { $0.date <= dayStart }
        guard let today = sorted.last, calendar.isDate(today.date, inSameDayAs: start) else { return nil }
        let excluded = DayTagStore.excludedDates(tags)
        let history = sorted.dropLast().filter { !excluded.contains($0.date) }.suffix(28)

        func z(_ value: Double?, _ keyPath: KeyPath<DailyMetrics, Double?>) -> Double? {
            guard let value else { return nil }
            let values = history.compactMap { $0[keyPath: keyPath] }
            guard values.count >= 7, let mean = Stats.mean(values), let sd = Stats.standardDeviation(values), sd > 0 else { return nil }
            return (value - mean) / sd
        }

        let window = Array(sorted.suffix(RecoveryScore.baselineDays + 1))
        let score = RecoveryScore.compute(from: window, excluded: excluded)
        let yesterday = sorted.dropLast().last { calendar.isDate($0.date, inSameDayAs: calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart) }

        let block = TrainingBlock.load()
        let deload: Bool? = start >= block.start ? { if case .deload = block.phase(on: start) { true } else { false } }() : nil

        return ReadinessSnapshot(
            capturedAt: start,
            recoveryScore: score?.value,
            sleepHours: today.sleepAsleepHours,
            sleepVsNeed: score?.sleepPerformance,
            hrv: today.hrvSDNN,
            hrvZ: z(today.hrvSDNN, \.hrvSDNN),
            restingHR: today.restingHeartRate,
            restingHRZ: z(today.restingHeartRate, \.restingHeartRate),
            yesterdayStrain: yesterday?.strain,
            trainingLoadRatio: TrainingLoadModel.compute(from: sorted.filter { $0.date < dayStart })?.ratio,
            yesterdayProtein: yesterday?.proteinGrams,
            yesterdayKcal: yesterday?.dietaryEnergyKcal,
            deloadWeek: deload,
            hourOfDay: calendar.component(.hour, from: start),
            alcoholYesterday: DayTagStore.dates(tags, with: .alcohol).contains(calendar.date(byAdding: .day, value: -1, to: dayStart) ?? dayStart)
        )
    }
}

// MARK: - Performance index

enum PerformanceIndex {
    /// Each exercise needs this many earlier sessions before its result counts.
    static let minPriorSessions = 3

    /// Best working-set estimated 1RM in one logged exercise, counting reps left in reserve.
    static func bestOneRepMax(_ exercise: LoggedExercise) -> Double? {
        guard exercise.tracking == .weightReps else { return nil }
        return exercise.workingSets.compactMap { set -> Double? in
            guard let w = set.weightKg, let r = set.reps, w > 0, r > 0 else { return nil }
            return w * (1 + Double(r + (set.rir ?? 2)) / 30)
        }.max()
    }

    /// How this session went, as a percentage against your own recent form: the median,
    /// across the exercises with enough history, of best 1RM ÷ the average of the last
    /// four sessions of that exercise − 1. Clamped to ±25% so one typo can't dominate.
    static func value(for log: WorkoutLog, in logs: [WorkoutLog]) -> Double? {
        let earlier = logs.filter { $0.start < log.start }.sorted { $0.start > $1.start }
        var ratios: [Double] = []
        for exercise in log.exercises {
            guard let best = bestOneRepMax(exercise) else { continue }
            let prior = earlier.compactMap { session in
                session.exercises.first { $0.exerciseID == exercise.exerciseID }.flatMap { bestOneRepMax($0) }
            }.prefix(4)
            guard prior.count >= minPriorSessions, let baseline = Stats.mean(Array(prior)), baseline > 0 else { continue }
            ratios.append(min(max((best / baseline - 1) * 100, -25), 25))
        }
        guard !ratios.isEmpty else { return nil }
        let sorted = ratios.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }
}

extension WorkoutLog {
    /// What your body looked like when the session started, if it was captured.
    var readiness: ReadinessSnapshot? {
        get { PayloadCache.decode(ReadinessSnapshot.self, from: readinessPayload, owner: self, slot: "readiness") }
        set { readinessPayload = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }
}

// MARK: - The model

enum PerformanceModel {

    static let needForDrivers = 20
    static let needForForecast = 50
    /// A forecast must beat the better plain guess by at least this much.
    static let requiredImprovement = 0.10
    static let lambda = 5.0

    struct Driver: Identifiable {
        let id = UUID()
        let name: String
        let r: Double
        let n: Int
        var goesWithBetter: Bool { r > 0 }
    }

    struct Contribution: Identifiable {
        let id = UUID()
        let name: String
        /// Effect on today's session, in percentage points.
        let points: Double
    }

    struct Forecast {
        let percent: Double
        /// A typical miss of the model, in percentage points.
        let typicalMiss: Double
        let contributions: [Contribution]
        let sessions: Int
        let improvement: Double
        /// What today's readings were, for the explanation to refer to.
        let today: ReadinessSnapshot
    }

    enum Status {
        case collecting(have: Int, need: Int)
        case drivers(sessions: Int, [Driver], forecastWithheld: Bool)
        case forecast(Forecast, drivers: [Driver])
    }

    struct Labelled {
        let date: Date
        let y: Double
        let features: [Double?]
    }

    /// Every session that has both a result and a snapshot, oldest first.
    static func labelled(logs: [WorkoutLog], days: [DailyMetrics], tags: [DayTag]) -> [Labelled] {
        logs.sorted { $0.start < $1.start }.compactMap { log in
            guard let y = PerformanceIndex.value(for: log, in: logs),
                  let snapshot = log.readiness ?? ReadinessSnapshot.capture(at: log.start, days: days, tags: tags) else { return nil }
            return Labelled(date: log.start, y: y, features: snapshot.features)
        }
    }

    static func status(logs: [WorkoutLog], days: [DailyMetrics], tags: [DayTag], now: Date = Date()) -> Status {
        let data = labelled(logs: logs, days: days, tags: tags)
        guard data.count >= needForDrivers else { return .collecting(have: data.count, need: needForDrivers) }

        let ys = data.map(\.y)
        let names = ReadinessSnapshot.featureNames
        let drivers: [Driver] = names.indices.compactMap { j in
            guard let c = PerformanceCore.correlation(data.map { $0.features[j] }, ys), abs(c.r) >= 0.2 else { return nil }
            return Driver(name: names[j], r: c.r, n: c.n)
        }.sorted { abs($0.r) > abs($1.r) }

        guard data.count >= needForForecast else { return .drivers(sessions: data.count, drivers, forecastWithheld: false) }

        let rows = data.map(\.features)
        guard let evaluation = PerformanceCore.evaluate(rows, ys, lambda: lambda),
              evaluation.improvement >= requiredImprovement,
              let fit = PerformanceCore.fit(rows, ys, lambda: lambda),
              let snapshot = ReadinessSnapshot.capture(at: now, days: days, tags: tags) else {
            return .drivers(sessions: data.count, drivers, forecastWithheld: true)
        }

        let today = snapshot.features
        let z = PerformanceCore.standardised(fit, today)
        let contributions = names.indices.compactMap { j -> Contribution? in
            let points = fit.beta[j] * z[j]
            return abs(points) >= 0.3 ? Contribution(name: names[j], points: points) : nil
        }.sorted { abs($0.points) > abs($1.points) }

        return .forecast(Forecast(percent: PerformanceCore.predict(fit, today), typicalMiss: evaluation.residualSD,
                                  contributions: Array(contributions.prefix(3)), sessions: data.count,
                                  improvement: evaluation.improvement, today: snapshot), drivers: drivers)
    }
}

// MARK: - Explanation (Gemini)

/// Puts the model's finished numbers into words. The model does the maths; the
/// language model only gets the results and is told not to add any of its own.
enum PerformanceNarrator {

    private static let cacheKey = "performance.explanation"

    private struct Cached: Codable { var day: Date; var fingerprint: String; var text: String }

    /// Today's saved explanation for these exact numbers, if there is one.
    static func cached(for status: PerformanceModel.Status) -> String? {
        guard let data = UserDefaults.standard.data(forKey: cacheKey),
              let cached = try? JSONDecoder().decode(Cached.self, from: data),
              Calendar.current.isDateInToday(cached.day), cached.fingerprint == fingerprint(status) else { return nil }
        return cached.text
    }

    static func explain(_ status: PerformanceModel.Status) async throws -> String {
        let facts = factsBlock(status)
        let system = """
        You explain one person's training-readiness numbers inside a strength-training app.
        A statistical model has already done the calculation. You only put its results into
        plain language for someone who has never heard of these terms.

        Rules:
        - Use only the numbers you are given. Never invent, adjust or add numbers.
        - The forecast is a percentage against the person's own recent form on their lifts:
          negative means expected to lift a little below their usual, positive a little above.
        - Always mention how uncertain it is, using the typical miss you were given.
        - Describe links as "goes with" or "tends to", never as a cause. No medical claims,
          no diagnosis, no alarming language.
        - Write 3 to 4 short sentences in plain text: no lists, no markdown, no emoji.
        - End with at most one optional, practical suggestion about effort or warm-up. It must
          not tell the person to skip training or to lift more than planned.
        """
        let user = "Here are the results. Explain them.\n\n\(facts)"

        // Private on Apple Intelligence iPhones; Gemini otherwise, or if that declines.
        var text: String?
        if OnDeviceAI.isUsable, let local = try? await OnDeviceAI.respond(instructions: system, prompt: user), !local.isEmpty {
            text = local
        }
        if text == nil {
            text = try await AIClient().send(system: system, user: user, maxTokens: 400, temperature: 0.4)
        }
        let trimmed = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if let data = try? JSONEncoder().encode(Cached(day: Date(), fingerprint: fingerprint(status), text: trimmed)) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
        return trimmed
    }

    private static func fingerprint(_ status: PerformanceModel.Status) -> String {
        switch status {
        case .collecting(let have, _): "collecting-\(have)"
        case .drivers(let n, let drivers, _): "drivers-\(n)-" + drivers.map { "\($0.name)\(Int($0.r * 100))" }.joined(separator: ",")
        case .forecast(let f, _): "forecast-\(Int(f.percent.rounded()))-\(Int(f.typicalMiss.rounded()))-" + f.contributions.map(\.name).joined(separator: ",")
        }
    }

    private static func factsBlock(_ status: PerformanceModel.Status) -> String {
        func signed(_ v: Double, _ digits: Int = 0) -> String { (v >= 0 ? "+" : "-") + String(format: "%.\(digits)f", abs(v)) }
        func driverLines(_ drivers: [PerformanceModel.Driver]) -> [String] {
            drivers.prefix(4).map { "- \($0.name): higher goes with \($0.goesWithBetter ? "better" : "worse") sessions (correlation \(String(format: "%.2f", $0.r)) over \($0.n) sessions)" }
        }
        switch status {
        case .collecting(let have, let need):
            return "Not enough sessions yet: \(have) of \(need). No results to explain."
        case .drivers(let sessions, let drivers, let withheld):
            var lines = ["Sessions analysed: \(sessions)", "No forecast today" + (withheld ? " because the model was not reliably better than assuming the usual." : ".")]
            lines.append(drivers.isEmpty ? "No factor stands out." : "Factors that go with better or worse sessions:")
            return (lines + driverLines(drivers)).joined(separator: "\n")
        case .forecast(let f, let drivers):
            var lines = [
                "Sessions the model learned from: \(f.sessions)",
                "Expected performance today: \(signed(f.percent))% versus their recent form",
                "Typical miss of this forecast: about \(String(format: "%.0f", f.typicalMiss)) percentage points",
                "Model accuracy: about \(Int((f.improvement * 100).rounded()))% better than assuming their usual"
            ]
            let t = f.today
            if let v = t.sleepHours { lines.append("Sleep last night: \(String(format: "%.1f", v)) hours") }
            if let v = t.hrvZ { lines.append("HRV versus their own normal: \(signed(v, 1)) standard deviations") }
            if let v = t.restingHRZ { lines.append("Resting heart rate versus their own normal: \(signed(v, 1)) standard deviations") }
            if let v = t.yesterdayStrain { lines.append("Yesterday's strain: \(String(format: "%.1f", v)) of 21") }
            if !f.contributions.isEmpty {
                lines.append("What moves today's forecast, in percentage points:")
                lines += f.contributions.map { "- \($0.name): \(signed($0.points, 1))" }
            }
            if !drivers.isEmpty { lines.append("Across all sessions:"); lines += driverLines(drivers) }
            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Card

/// On the Workouts page: learning progress, then drivers, then (earned) a forecast.
struct PerformanceCard: View {
    @Query(sort: \WorkoutLog.start, order: .reverse) private var logs: [WorkoutLog]
    @Query(sort: \DailyMetrics.date, order: .forward) private var days: [DailyMetrics]
    @Query private var tags: [DayTag]
    @State private var explanation: String?
    @State private var explaining = false
    @State private var explainError: String?

    var body: some View {
        let status = PerformanceModel.status(logs: logs, days: days, tags: tags)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.accent)
                Text("Your training readiness").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Spacer()
            }
            switch status {
            case .collecting(let have, let need):
                ProgressView(value: Double(min(have, need)), total: Double(need)).tint(Theme.accent)
                Text("Learning how your body affects your lifting: \(have) of \(need) sessions so far.")
                    .font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                note("Each session you log is matched with how you slept, your HRV and resting heart rate, and your recent load. After \(need) sessions it shows what your good days have in common. Around \(PerformanceModel.needForForecast), it can forecast a session, but only if the forecast proves more accurate than a simple guess.")

            case .drivers(let sessions, let drivers, let withheld):
                driverList(drivers, sessions: sessions)
                if withheld {
                    note("No forecast yet: with \(sessions) sessions it isn't reliably better than just assuming your usual, so it stays off rather than guess.")
                } else {
                    note("A forecast unlocks at \(PerformanceModel.needForForecast) sessions, if it proves more accurate than a plain guess.")
                }

            case .forecast(let forecast, let drivers):
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(verbatim: forecast.percent >= 0 ? "+\(String(format: "%.0f", forecast.percent))%" : "−\(String(format: "%.0f", abs(forecast.percent)))%")
                        .font(.system(size: 34, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(forecast.percent >= 0 ? Theme.good : Theme.warn)
                    Text("vs your recent form, ±\(String(format: "%.0f", forecast.typicalMiss))")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                if !forecast.contributions.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(forecast.contributions) { c in
                            HStack {
                                Text(c.name).font(.footnote).foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(verbatim: "\(c.points >= 0 ? "+" : "−")\(String(format: "%.1f", abs(c.points)))")
                                    .font(.footnote.weight(.semibold)).monospacedDigit()
                                    .foregroundStyle(c.points >= 0 ? Theme.good : Theme.warn)
                            }
                        }
                    }
                }
                note("Built from your \(forecast.sessions) sessions, and about \(Int((forecast.improvement * 100).rounded()))% more accurate than assuming your usual. A guide for how hard to push, not a rule.")
                if !drivers.isEmpty { Divider().overlay(Theme.separator); driverList(drivers, sessions: forecast.sessions) }
            }

            if case .collecting = status {} else {
                explainSection(status)
            }
        }
        .card()
    }

    private func explainSection(_ status: PerformanceModel.Status) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(Theme.separator)
            if let text = explanation ?? PerformanceNarrator.cached(for: status) {
                HStack(alignment: .top, spacing: 10) {
                    GeminiMark(size: 16).padding(.top, 2)
                    Text(text).font(.footnote).foregroundStyle(Theme.textPrimary).lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Button {
                    Task {
                        explaining = true
                        explainError = nil
                        do { explanation = try await PerformanceNarrator.explain(status) }
                        catch { explainError = error.localizedDescription }
                        explaining = false
                    }
                } label: {
                    HStack(spacing: 8) {
                        if explaining { ProgressView() } else { GeminiMark(size: 16) }
                        Text("Explain this in plain English").font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(Theme.accentDeep)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(explaining)
                if let explainError {
                    Text(explainError).font(.caption).foregroundStyle(Theme.bad).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func driverList(_ drivers: [PerformanceModel.Driver], sessions: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What goes with your better sessions").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            if drivers.isEmpty {
                note("Nothing stands out yet across \(sessions) sessions. That can mean your lifting isn't strongly tied to any of these, which is a result too.")
            } else {
                ForEach(drivers.prefix(4)) { d in
                    HStack(spacing: 8) {
                        Image(systemName: d.goesWithBetter ? "arrow.up.right" : "arrow.down.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(d.goesWithBetter ? Theme.good : Theme.warn)
                        Text(d.name).font(.footnote).foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text(d.goesWithBetter ? "higher = better sessions" : "higher = worse sessions")
                            .font(.caption).foregroundStyle(Theme.textTertiary)
                    }
                }
                note("Patterns across \(sessions) sessions, not proof of cause.")
            }
        }
    }

    private func note(_ text: LocalizedStringKey) -> some View {
        Text(text).font(.caption).foregroundStyle(Theme.textTertiary).fixedSize(horizontal: false, vertical: true)
    }
}
