//
//  NarrativeService.swift
//  RecoverySignal
//
//  Turns a week of computed numbers + rule-engine flags into a plain-language
//  explanation via Google Gemini. Only aggregated stats go out over the
//  network — never raw HealthKit samples, and nothing that identifies you.
//  Requires a Gemini API key (aistudio.google.com), stored in Keychain.
//

import Foundation

struct NarrativeService {

    struct WeekSummaryInput {
        var days: [DailyMetrics]
        var insights: [Insight]
    }

    func generateWeeklyNarrative(_ input: WeekSummaryInput) async throws -> String {
        let statsBlock = Self.buildStatsBlock(input)

        let systemPrompt = """
        You are a calm, honest health-data interpreter inside a personal app called Trace.
        The user is not a clinician. Your job is to unpack what a week of biomarker and nutrition
        numbers actually means in plain language — not just repeat the numbers back.

        Rules:
        - Be concrete: reference the actual numbers you were given.
        - Be honest about uncertainty. A phone/watch cannot measure body composition, stress,
          or illness directly — say "consistent with" or "likely", never "you have gained muscle"
          as flat fact, unless the data genuinely leaves no other reasonable explanation.
        - Prioritize recovery (HRV, resting heart rate, sleep) and body composition/trend framing —
          that's what this user cares about most.
        - Keep it to 3-5 short paragraphs. No medical diagnosis, no alarming language.
        - End with 1-2 concrete, specific suggestions for the coming week, not generic advice.
        - Start every paragraph with exactly one topic tag, which the app replaces with an icon:
          [recovery] [sleep] [training] [nutrition] [body] or [suggestion] for the closing advice.
          Separate paragraphs with a blank line. Do not use emoji or markdown.
        """

        let userPrompt = """
        Here is this week's data. Write the weekly narrative.

        \(statsBlock)
        """

        // Private and free on Apple Intelligence iPhones; Gemini otherwise, or
        // if the on-device model declines or errors.
        if OnDeviceAI.isUsable,
           let text = try? await OnDeviceAI.respond(instructions: systemPrompt, prompt: userPrompt),
           !text.isEmpty {
            return text
        }
        return try await AIClient().send(system: systemPrompt, user: userPrompt, maxTokens: 1200)
    }

    /// Builds a compact, purely-numeric summary block — this is the only thing
    /// that leaves the device.
    private static func buildStatsBlock(_ input: NarrativeService.WeekSummaryInput) -> String {
        func avg(_ values: [Double?]) -> Double? {
            let vals = values.compactMap { $0 }
            guard !vals.isEmpty else { return nil }
            return vals.reduce(0, +) / Double(vals.count)
        }

        let days = input.days.sorted { $0.date < $1.date }
        var lines: [String] = []

        if let v = avg(days.map(\.hrvSDNN)) { lines.append("Avg HRV (SDNN): \(String(format: "%.0f", v)) ms") }
        if let v = avg(days.map(\.restingHeartRate)) { lines.append("Avg resting HR: \(String(format: "%.0f", v)) bpm") }
        if let v = avg(days.map(\.sleepAsleepHours)) { lines.append("Avg sleep (asleep): \(String(format: "%.1f", v)) h") }
        if let v = avg(days.map(\.steps)) { lines.append("Avg steps: \(String(format: "%.0f", v))") }
        if let v = avg(days.map(\.activeEnergyBurned)) { lines.append("Avg active energy: \(String(format: "%.0f", v)) kcal") }
        if let v = avg(days.map(\.dietaryEnergyKcal)) { lines.append("Avg dietary intake: \(String(format: "%.0f", v)) kcal") }
        if let v = avg(days.map(\.proteinGrams)) { lines.append("Avg protein: \(String(format: "%.0f", v)) g") }
        if let first = days.compactMap(\.bodyMassKg).first, let last = days.compactMap(\.bodyMassKg).last {
            lines.append("Body weight: \(String(format: "%.1f", first)) kg -> \(String(format: "%.1f", last)) kg across the week")
        }
        let sessions = days.reduce(0) { $0 + $1.workoutCount }
        let trainingMinutes = days.compactMap(\.workoutMinutes).reduce(0, +)
        let strengthMinutes = days.compactMap(\.strengthMinutes).reduce(0, +)
        let cardioMinutes = days.compactMap(\.cardioMinutes).reduce(0, +)
        lines.append("Training: \(sessions) sessions, \(Int(trainingMinutes)) min total (\(Int(strengthMinutes)) min strength, \(Int(cardioMinutes)) min cardio)")
        if let v = avg(days.map(\.workoutAvgHeartRate)) {
            lines.append("Avg workout heart rate: \(String(format: "%.0f", v)) bpm")
        }

        var block = "Weekly averages:\n" + lines.map { "- \($0)" }.joined(separator: "\n")

        if !input.insights.isEmpty {
            block += "\n\nRule-engine flags already raised this week:\n"
            block += input.insights.map { "- [\($0.severity.rawValue)] \($0.title): \($0.detail)" }.joined(separator: "\n")
        }

        return block
    }
}
