//
//  FoodModels.swift
//  RecoverySignal2
//
//  What the food log is made of. A `FoodItem` is nutrition per 100 g from any
//  source (Swiss database, a scanned product, your own recipe). A `FoodEntry`
//  is one thing you ate, stored locally and mirrored to Apple Health, which
//  is what the rings, maintenance and trends read.
//

import Foundation
import SwiftData

nonisolated struct FoodItem: Identifiable, Hashable, Codable {
    enum Source: String, Codable {
        case swiss, common, usda, product, recipe, custom, estimate
    }

    var id: String
    var name: String
    var brand: String?
    /// Per 100 g (or 100 ml for drinks).
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var source: Source
    var barcode: String?
    var servingGrams: Double?
    /// Grams per millilitre for drinks and other pourables; nil for solids.
    var density: Double? = nil

    var isLiquid: Bool { density != nil }
    var isPersonal: Bool { source == .custom || source == .recipe }

    struct Amount {
        let kcal: Double, protein: Double, carbs: Double, fat: Double
    }

    func amount(_ grams: Double) -> Amount {
        let f = grams / 100
        return Amount(kcal: kcal * f, protein: protein * f, carbs: carbs * f, fat: fat * f)
    }

    /// A short warning if this food's numbers look implausible, else nil.
    /// Scale-invariant — it checks the per-100 g figures, so it applies
    /// however much of it you actually log.
    var plausibilityWarning: String? {
        let macroKcal = protein * 4 + carbs * 4 + fat * 9
        if kcal > 900 {
            return String(localized: "\(DetailFormat.safeInt(kcal)) kcal per 100 g is unusually high — worth double-checking this entry.")
        }
        if kcal > 0, macroKcal > 0, abs(macroKcal - kcal) > max(40, kcal * 0.2) {
            return String(localized: "The macros add up to about \(DetailFormat.safeInt(macroKcal)) kcal per 100 g, not \(DetailFormat.safeInt(kcal)) — worth a quick check.")
        }
        return nil
    }

    var sourceLabel: String {
        switch source {
        case .swiss:    String(localized: "Swiss food database")
        case .common:   String(localized: "Common foods")
        case .usda:     String(localized: "USDA FoodData Central")
        case .product:  String(localized: "Open Food Facts · product data")
        case .recipe:   String(localized: "My recipe")
        case .custom:   String(localized: "My food")
        case .estimate: String(localized: "Estimate")
        }
    }
}

@Model
final class FoodEntry {
    var id: UUID
    var date: Date
    var slotRaw: String
    var name: String
    var brand: String?
    var grams: Double
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    /// The per-100 g item, so it can be logged again from Recent.
    var itemData: Data
    /// The Apple Health food entry this mirrors.
    var healthID: String?

    init(item: FoodItem, grams: Double, slot: MealSlot, date: Date, healthID: UUID?) {
        let a = item.amount(grams)
        id = UUID()
        self.date = date
        slotRaw = slot.rawValue
        name = item.name
        brand = item.brand
        self.grams = grams
        kcal = a.kcal
        protein = a.protein
        carbs = a.carbs
        fat = a.fat
        itemData = (try? JSONEncoder().encode(item)) ?? Data()
        self.healthID = healthID?.uuidString
    }

    var slot: MealSlot { MealSlot(rawValue: slotRaw) ?? .snack }
    /// Parsed once per entry (see PayloadCache): the food log reads this for
    /// the name, macros, density and badges of every row on every redraw.
    var item: FoodItem? { PayloadCache.decode(FoodItem.self, from: itemData, owner: self, slot: "item") }
}

/// Your own foods: recipes built from ingredients (or calculated by AI), and
/// products you entered from a nutrition label.
@Model
final class UserFood {
    var id: UUID
    var createdAt: Date
    var name: String
    var brand: String?
    var barcode: String?
    var isRecipe: Bool
    var kcal: Double
    var protein: Double
    var carbs: Double
    var fat: Double
    var servingGrams: Double?
    var totalGrams: Double?
    /// Set for drinks, so they can be logged in ml.
    var density: Double?
    var ingredientsData: Data
    var notes: String

    init(name: String, isRecipe: Bool) {
        id = UUID()
        createdAt = Date()
        self.name = name
        self.isRecipe = isRecipe
        kcal = 0; protein = 0; carbs = 0; fat = 0
        ingredientsData = Data()
        notes = ""
    }

    var ingredients: [RecipeIngredient] {
        get { (try? JSONDecoder().decode([RecipeIngredient].self, from: ingredientsData)) ?? [] }
        set { ingredientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var item: FoodItem {
        FoodItem(id: "user-\(id.uuidString)", name: name, brand: brand, kcal: kcal, protein: protein, carbs: carbs, fat: fat,
                 source: isRecipe ? .recipe : .custom, barcode: barcode, servingGrams: servingGrams, density: density)
    }
}

nonisolated struct RecipeIngredient: Identifiable, Hashable, Codable {
    var id = UUID()
    var food: FoodItem
    var grams: Double
}

/// A named group of foods you log together often — a usual breakfast, a
/// post-workout shake — logged into any meal slot in one tap. Distinct from
/// "copy yesterday's X": this isn't tied to a date, and you name it yourself.
@Model
final class SavedMeal {
    var id: UUID = UUID()
    var name: String = ""
    var createdAt: Date = Date()
    var itemsData: Data = Data()

    init(name: String, items: [RecipeIngredient]) {
        self.id = UUID()
        self.name = name
        self.createdAt = Date()
        self.items = items
    }

    var items: [RecipeIngredient] {
        get { (try? JSONDecoder().decode([RecipeIngredient].self, from: itemsData)) ?? [] }
        set { itemsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var totalKcal: Double { items.reduce(0) { $0 + $1.food.amount($1.grams).kcal } }
}
