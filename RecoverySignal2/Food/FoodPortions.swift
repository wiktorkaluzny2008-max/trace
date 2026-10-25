//
//  FoodPortions.swift
//  RecoverySignal2
//
//  Foods you count rather than weigh — an egg, an apple, a bread roll — get a
//  small, medium and large portion alongside per-100 g values. Weights are
//  the edible part (no shell, peel or core), from typical Swiss supermarket
//  sizes.
//

import Foundation

struct FoodPortion: Identifiable, Hashable {
    enum Size: Int, CaseIterable, Identifiable {
        case small, medium, large
        var id: Int { rawValue }

        var label: String {
            switch self {
            case .small:  String(localized: "Small")
            case .medium: String(localized: "Medium")
            case .large:  String(localized: "Large")
            }
        }
    }

    let size: Size
    /// What one of it is called: "egg", "apple", "slice", "can".
    let unit: String
    let grams: Double
    /// Volume, for drinks.
    var ml: Double? = nil
    /// A measure with its own name ("cup, sliced", "oz") rather than a small/medium/large "one of it".
    var custom = false

    var id: Int { size.rawValue }

    /// "medium egg", or "can · 330 ml" for drinks (the size word adds nothing there).
    var name: String {
        if custom { return unit }
        if let ml { return "\(unit) · \(Int(ml)) ml" }
        if AppLanguage.current == .polish { return "\(unit) · \(size.label)" }
        return "\(size.label.lowercased()) \(unit)"
    }
    /// "52 g" or "330 ml".
    var amountLabel: String { ml.map { "\(Int($0)) ml" } ?? "\(Int(grams)) g" }
}

enum FoodPortions {
    private struct Rule {
        /// Matches the part of the food's name before the first comma.
        let heads: [String]
        let unit: String
        let grams: (Double, Double, Double)
    }

    /// Anything processed enough that "one of it" stops making sense.
    private static let excluded = ["dried", "juice", "canned", "stewed", "pie", "nectar", "peel", "syrup", "sauce",
                                   "jam", "pickled", "chips", "powder", "liqueur", "paste", "soup", "quiche",
                                   "salad", "mashed", "flakes", "starch", "gratin", "dough", "curd", "sweetener"]

    private static var rules: [Rule] {
        [
            Rule(heads: ["egg", "chicken egg"], unit: String(localized: "egg"), grams: (45, 52, 60)),
            Rule(heads: ["apple"], unit: String(localized: "apple"), grams: (130, 180, 230)),
            Rule(heads: ["banana"], unit: String(localized: "banana"), grams: (90, 120, 150)),
            Rule(heads: ["orange"], unit: String(localized: "orange"), grams: (110, 150, 190)),
            Rule(heads: ["pear"], unit: String(localized: "pear"), grams: (140, 180, 230)),
            Rule(heads: ["kiwi fruit"], unit: String(localized: "kiwi"), grams: (60, 75, 95)),
            Rule(heads: ["peach", "nectarine"], unit: String(localized: "piece"), grams: (110, 150, 190)),
            Rule(heads: ["avocado"], unit: String(localized: "avocado"), grams: (100, 140, 180)),
            Rule(heads: ["mandarin"], unit: String(localized: "mandarin"), grams: (50, 70, 90)),
            Rule(heads: ["plum", "prune plum", "apricot"], unit: String(localized: "piece"), grams: (30, 42, 55)),
            Rule(heads: ["mango"], unit: String(localized: "mango"), grams: (200, 280, 360)),
            Rule(heads: ["grapefruit (white or red)"], unit: String(localized: "grapefruit"), grams: (200, 260, 320)),
            Rule(heads: ["lemon"], unit: String(localized: "lemon"), grams: (45, 60, 80)),
            Rule(heads: ["fig"], unit: String(localized: "fig"), grams: (35, 50, 65)),
            Rule(heads: ["pineapple"], unit: String(localized: "slice"), grams: (60, 90, 120)),
            Rule(heads: ["watermelon"], unit: String(localized: "slice"), grams: (200, 300, 400)),
            Rule(heads: ["tomato"], unit: String(localized: "tomato"), grams: (70, 120, 180)),
            Rule(heads: ["carrot"], unit: String(localized: "carrot"), grams: (50, 75, 110)),
            Rule(heads: ["onion"], unit: String(localized: "onion"), grams: (70, 110, 160)),
            Rule(heads: ["bell pepper"], unit: String(localized: "pepper"), grams: (120, 160, 220)),
            Rule(heads: ["cucumber"], unit: String(localized: "cucumber"), grams: (200, 300, 400)),
            Rule(heads: ["zucchini"], unit: String(localized: "zucchini"), grams: (150, 220, 300)),
            Rule(heads: ["potato", "potatoe", "sweet potato"], unit: String(localized: "potato"), grams: (90, 150, 220)),
            Rule(heads: ["bread roll", "lye roll"], unit: String(localized: "roll"), grams: (45, 65, 90)),
            Rule(heads: ["butter croissant", "croissant (average)"], unit: String(localized: "croissant"), grams: (40, 55, 70)),
            Rule(heads: ["bread (average)", "bread for toasting", "braided"], unit: String(localized: "slice"), grams: (25, 40, 55)),
            Rule(heads: ["yogurt natural", "yogurt bifidus", "yogurt flavored"], unit: String(localized: "pot"), grams: (120, 150, 180)),
            Rule(heads: ["berliner pastry", "donut"], unit: String(localized: "piece"), grams: (50, 70, 90)),
            Rule(heads: ["burger patty"], unit: String(localized: "patty"), grams: (100, 130, 180)),
            Rule(heads: ["pizza margherita", "pizza hawaii", "pizza with", "pizza calzone"], unit: String(localized: "pizza"), grams: (250, 350, 450))
        ]
    }

    /// Glass, can, bottle — or spoons for oils and cream, a shot for spirits.
    static func drinkPortions(for item: FoodItem) -> [FoodPortion] {
        guard let density = item.density else { return [] }
        let name = item.name.lowercased()
        let sizes: [(String, Double)]
        if name.contains("oil") {
            sizes = [(String(localized: "teaspoon"), 5), (String(localized: "tablespoon"), 10), (String(localized: "tablespoon"), 15)]
        } else if name.contains("cream") || name.contains("syrup undiluted") {
            sizes = [(String(localized: "teaspoon"), 5), (String(localized: "tablespoon"), 15), (String(localized: "splash"), 50)]
        } else if name.contains("espresso") || name.contains("ristretto") {
            sizes = [(String(localized: "shot"), 25), (String(localized: "double"), 50), (String(localized: "cup"), 100)]
        } else if name.contains("coffee") || name.contains("cappuccino") || name.contains("latte") || name.contains("flat white") || name.contains("tea") {
            sizes = [(String(localized: "cup"), 150), (String(localized: "mug"), 250), (String(localized: "large cup"), 350)]
        } else if name.hasPrefix("spirits") || name.contains("vol%") && (name.contains("pastis") || name.contains("amaro") || name.contains("suze") || name.contains("liqueur")) {
            sizes = [(String(localized: "shot"), 20), (String(localized: "shot"), 40), (String(localized: "double"), 60)]
        } else if name.hasPrefix("wine") || name.contains("sparkling wine") || name.hasPrefix("port") || name.contains("sherry") || name.contains("vermouth") {
            sizes = [(String(localized: "small glass"), 100), (String(localized: "glass"), 150), (String(localized: "bottle"), 750)]
        } else if name.hasPrefix("beer") || name.hasPrefix("cider") {
            sizes = [(String(localized: "glass"), 300), (String(localized: "bottle"), 330), (String(localized: "large"), 500)]
        } else if name.contains("soup") {
            sizes = [(String(localized: "cup"), 200), (String(localized: "bowl"), 300), (String(localized: "large bowl"), 450)]
        } else if name.contains("cola") || name.contains("soft drink") || name.contains("energy drink") || name.contains("ice tea") {
            sizes = [(String(localized: "glass"), 250), (String(localized: "can"), 330), (String(localized: "bottle"), 500)]
        } else {
            sizes = [(String(localized: "small glass"), 150), (String(localized: "glass"), 250), (String(localized: "bottle"), 500)]
        }
        return zip(FoodPortion.Size.allCases, sizes).map { size, s in
            FoodPortion(size: size, unit: s.0, grams: s.1 * density, ml: s.1)
        }
    }

    static func portions(for item: FoodItem) -> [FoodPortion] {
        if item.source == .product {
            let polish = PolishProductDatabase.portions(for: item)
            if !polish.isEmpty { return polish }
        }
        if item.source == .common { return CommonFoods.portions(for: item) }
        if item.source == .usda { return SwissFoodDatabase.usdaPortions(for: item) }
        if item.isLiquid, item.source == .swiss || item.source == .product || item.isPersonal {
            return drinkPortions(for: item)
        }
        guard item.source == .swiss else { return [] }
        let named = SwissFoodDatabase.swissPortions(for: item)
        if !named.isEmpty { return named }
        let name = item.name.lowercased()
        guard !excluded.contains(where: name.contains) else { return [] }
        let head = name.split(separator: ",").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? name
        guard let rule = rules.first(where: { rule in
            rule.heads.contains { head == $0 || head.hasPrefix($0 + " ") }
        }) else { return [] }
        let (s, m, l) = rule.grams
        return [FoodPortion(size: .small, unit: rule.unit, grams: s),
                FoodPortion(size: .medium, unit: rule.unit, grams: m),
                FoodPortion(size: .large, unit: rule.unit, grams: l)]
    }
}

extension FoodItem {
    var portions: [FoodPortion] { FoodPortions.portions(for: self) }
}
