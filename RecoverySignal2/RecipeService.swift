//
//  RecipeService.swift
//  RecoverySignal2
//
//  Meal ideas sized to what's left of today's targets, for the current goal.
//  The model returns JSON; the macro numbers it gives are estimates,
//  so each recipe is sanity-checked (kcal ≈ 4P + 4C + 9F) before it's shown.
//

import Foundation
import SwiftData

nonisolated struct Recipe: Codable, Identifiable, Hashable {
    var id = UUID()
    let title: String
    let summary: String
    let minutes: Int
    let calories: Double
    let protein: Double
    let carbs: Double
    let fat: Double
    let ingredients: [String]
    let steps: [String]
    let whyItFits: String

    enum CodingKeys: String, CodingKey {
        case title, summary, minutes, calories, protein, carbs, fat, ingredients, steps
        case whyItFits = "why_it_fits"
    }

    /// Lenient: open models sometimes send numbers as strings ("20", "350 kcal").
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func number(_ key: CodingKeys) throws -> Double {
            if let value = try? c.decode(Double.self, forKey: key) { return value }
            let text = try c.decode(String.self, forKey: key)
            let digits = text.prefix { $0.isNumber || $0 == "." }
            guard let value = Double(digits) else {
                throw DecodingError.dataCorruptedError(forKey: key, in: c, debugDescription: "Not a number: \(text)")
            }
            return value
        }
        title = try c.decode(String.self, forKey: .title)
        summary = (try? c.decode(String.self, forKey: .summary)) ?? ""
        minutes = Int((try? number(.minutes)) ?? 0)
        calories = try number(.calories)
        protein = try number(.protein)
        carbs = try number(.carbs)
        fat = try number(.fat)
        ingredients = try c.decode([String].self, forKey: .ingredients)
        steps = try c.decode([String].self, forKey: .steps)
        whyItFits = (try? c.decode(String.self, forKey: .whyItFits)) ?? ""
    }

    /// Calories implied by the macros. Large gaps mean the estimate is shaky.
    var macroCalories: Double { protein * 4 + carbs * 4 + fat * 9 }
    var macrosConsistent: Bool {
        guard calories > 0 else { return false }
        return abs(macroCalories - calories) / calories <= 0.15
    }
}

@Model
final class SavedRecipe {
    var id: UUID
    var savedAt: Date
    var payload: Data

    init(recipe: Recipe) {
        id = recipe.id
        savedAt = Date()
        payload = (try? JSONEncoder().encode(recipe)) ?? Data()
    }

    var recipe: Recipe? { try? JSONDecoder().decode(Recipe.self, from: payload) }
}

enum MealSlot: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
    var label: String {
        switch self {
        case .breakfast: String(localized: "Breakfast")
        case .lunch:     String(localized: "Lunch")
        case .dinner:    String(localized: "Dinner")
        case .snack:     String(localized: "Snack")
        }
    }

    static func forNow(_ date: Date = Date()) -> MealSlot {
        switch Calendar.current.component(.hour, from: date) {
        case 4..<11:  .breakfast
        case 11..<15: .lunch
        case 15..<17: .snack
        default:      .dinner
        }
    }
}

struct RecipeRequest: Identifiable {
    let id = UUID()
    var slot: MealSlot
    let goal: GoalSettings
    let remainingCalories: Double?
    let remainingProtein: Double?
    let remainingCarbs: Double?
    let remainingFat: Double?
}

struct RecipeService {

    func suggest(_ request: RecipeRequest) async throws -> [Recipe] {
        let system = """
        You are a practical sports nutritionist writing recipes inside a personal health app.
        Suggest meals that a normal person can cook at home with supermarket ingredients.

        - Size each recipe to fit the remaining macros for the meal slot, not the whole day's remainder
          unless it is dinner late in the day. Prioritise hitting protein; carbs and fat are flexible.
        - Match the user's goal: cutting favours high-volume, high-protein, lower-calorie meals;
          building muscle favours calorie-dense meals that are still easy to eat.
        - Respect every dietary note exactly. If a note is ambiguous, choose the safer interpretation.
        - Macros are per serving. Keep calories consistent with 4 kcal/g protein and carbs, 9 kcal/g fat.
        - Ingredients include quantities in grams or common units. Steps are short and ordered.
        - why_it_fits is one sentence linking the recipe to the user's remaining targets and goal.

        \(Self.shapeInstructions)
        """

        let user = """
        Meal slot: \(request.slot.label)
        Goal: \(request.goal.phase.label)\(request.goal.phase == .maintain ? "" : " at \(request.goal.rateKgPerWeek) kg/week")
        Remaining today: \(describe(request))
        Dietary notes: \(request.goal.dietaryNotes.isEmpty ? "none" : request.goal.dietaryNotes)

        Suggest 3 different recipes.
        """

        let text = try await AIClient().send(system: system, user: user, maxTokens: 3000, json: true,
                                             accepts: { (try? JSONDecoder().decode(Envelope.self, from: Data($0.utf8)))?.recipes.isEmpty == false })
        do {
            let recipes = try JSONDecoder().decode(Envelope.self, from: Data(text.utf8)).recipes
            guard !recipes.isEmpty else { throw AIClient.AIError.emptyResponse }
            return recipes
        } catch let error as AIClient.AIError {
            throw error
        } catch {
            throw AIClient.AIError.requestFailed("The AI's recipes came back in an unexpected format. Try again.")
        }
    }

    private func describe(_ r: RecipeRequest) -> String {
        func part(_ label: String, _ value: Double?, _ unit: String) -> String? {
            value.map { "\(label) \(Int(max(0, $0).rounded())) \(unit)" }
        }
        let parts = [
            part("calories", r.remainingCalories, "kcal"),
            part("protein", r.remainingProtein, "g"),
            part("carbs", r.remainingCarbs, "g"),
            part("fat", r.remainingFat, "g")
        ].compactMap { $0 }
        return parts.isEmpty ? "unknown — no targets yet, suggest a balanced high-protein meal" : parts.joined(separator: ", ")
    }

    private struct Envelope: Decodable { let recipes: [Recipe] }

    /// JSON output mode guarantees valid JSON, not this shape — so it's spelled out.
    private static let shapeInstructions = """
    Respond with JSON only, in exactly this shape:
    {"recipes": [{"title": string, "summary": string, "minutes": integer, "calories": number,
    "protein": number, "carbs": number, "fat": number, "ingredients": [string], "steps": [string],
    "why_it_fits": string}]}
    Numbers are plain numbers without units.
    """
}
