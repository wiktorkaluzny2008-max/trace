import Foundation

/// Offline Polish-market labels from Open Food Facts (ODbL), not official Polish tables.
enum PolishProductDatabase {
    struct Row: Decodable {
        let code: String
        let name: String
        let english: String?
        let brand: String?
        let kcal: Double
        let protein: Double
        let carbs: Double
        let fat: Double
        let servingGrams: Double?
    }
    private static let rows: [Row] = Bundle.main.url(forResource: "PolishProducts", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([Row].self, from: $0) } ?? []

    /// Loads the table ahead of the first search (see SwissFoodDatabase.warmUp).
    static func warmUp() { _ = rows.count }

    /// Prepared once for typo-tolerant search over name, English name and brand.
    private static let documents: [SmartSearch.Document<String>] = rows.map { row in
        SmartSearch.Document(id: row.code, name: row.name, extra: [row.english ?? "", row.brand ?? ""])
    }
    private static let rowsByCode: [String: Row] = Dictionary(rows.map { ($0.code, $0) }, uniquingKeysWith: { a, _ in a })

    static func search(_ query: String) -> [FoodItem] {
        guard !SmartSearch.tokens(query).isEmpty else { return [] }
        return SmartSearch.rank(query: query, in: documents, limit: 40).compactMap { hit in
            guard let row = rowsByCode[hit.id] else { return nil }
            return FoodItem(id: "off-\(row.code)", name: AppLanguage.current == .polish ? row.name : (row.english ?? row.name),
                            brand: row.brand, kcal: row.kcal, protein: row.protein, carbs: row.carbs, fat: row.fat,
                            source: .product, barcode: row.code, servingGrams: row.servingGrams)
        }
    }

    static func portions(for item: FoodItem) -> [FoodPortion] {
        guard rows.contains(where: { "off-\($0.code)" == item.id }), let grams = item.servingGrams else { return [] }
        return [FoodPortion(size: .medium, unit: String(localized: "Label serving"), grams: grams, custom: true)]
    }
}
