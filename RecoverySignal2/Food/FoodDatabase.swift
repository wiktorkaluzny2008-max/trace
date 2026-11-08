//
//  FoodDatabase.swift
//  RecoverySignal2
//
//  Where foods come from, and how a logged food reaches Apple Health.
//
//  • The Swiss Food Composition Database (Federal Food Safety and Veterinary
//    Office, V 7.1) ships inside the app: ~1,250 generic foods, searchable
//    offline in English and German.
//  • USDA FoodData Central (SR Legacy, public domain) ships alongside it:
//    ~6,600 more generic foods with laboratory-derived values.
//  • Packaged products come from Open Food Facts, the open barcode database,
//    looked up by barcode or searched by name (Swiss products first).
//

import Foundation
import os
import SwiftData
import HealthKit

// MARK: - Swiss database (bundled)

/// Nonisolated so searches can run off the main thread while you type.
nonisolated enum SwissFoodDatabase {
    private struct Row: Decodable {
        let id: Int
        let en: String
        let de: String?
        let syn: String
        let kcal: Double
        let p: Double
        let c: Double
        let f: Double
        let d: Double?
        /// App-defined typical servings; nutrition remains the published FSVO value.
        let s: [PortionPair]?
    }

    private struct UsdaRow: Decodable {
        let id: Int
        let n: String
        let k: Double
        let p: Double
        let c: Double
        let f: Double
        /// Published portions: [name, grams for one], at most three.
        let dataset: String?
        let s: [PortionPair]?
    }

    private struct PortionPair: Decodable {
        let name: String
        let grams: Double

        init(from decoder: Decoder) throws {
            var c = try decoder.unkeyedContainer()
            name = try c.decode(String.self)
            grams = try c.decode(Double.self)
        }
    }

    private static let usdaRows: [UsdaRow] = Bundle.main.url(forResource: "UsdaFoods", withExtension: "json")
        .flatMap { try? Data(contentsOf: $0) }
        .flatMap { try? JSONDecoder().decode([UsdaRow].self, from: $0) } ?? []

    private static let usdaPortionsByID: [String: [PortionPair]] = {
        var map: [String: [PortionPair]] = [:]
        for row in usdaRows { if let s = row.s, !s.isEmpty { map["usda-\(row.id)"] = s } }
        return map
    }()

    private static let surveyIDs = Set(usdaRows.filter { $0.dataset != nil }.map { "usda-\($0.id)" })

    /// Named USDA portions; survey records default to the source's first portion.
    /// One portion is filed as "medium", two as small + medium, so the default
    /// selection always exists.
    @MainActor
    static func usdaPortions(for item: FoodItem) -> [FoodPortion] {
        guard let pairs = usdaPortionsByID[item.id] else { return [] }
        let sizes: [FoodPortion.Size]
        if surveyIDs.contains(item.id) {
            sizes = [.medium, .small, .large]
        } else {
            sizes = pairs.count == 1 ? [.medium] : pairs.count == 2 ? [.small, .medium] : [.small, .medium, .large]
        }
        return zip(sizes, pairs).map { size, pair in
            FoodPortion(size: size, unit: pair.name, grams: pair.grams, custom: true)
        }
    }

    private struct Indexed {
        let item: FoodItem
        let name: String
        let key: String
        /// The key as bytes: substring checks on bytes are many times faster
        /// than String.contains, and the key is already folded to ASCII-ish.
        let keyBytes: [UInt8]

        init(item: FoodItem, name: String, key: String) {
            self.item = item
            self.name = name
            self.key = key
            self.keyBytes = Array(key.utf8)
        }
    }

    /// Plain byte search, used on the folded keys.
    private static func contains(_ hay: [UInt8], _ needle: [UInt8]) -> Bool {
        let n = needle.count, h = hay.count
        guard n > 0, n <= h else { return n == 0 }
        let first = needle[0]
        var i = 0
        let last = h - n
        while i <= last {
            if hay[i] == first {
                var j = 1
                while j < n, hay[i + j] == needle[j] { j += 1 }
                if j == n { return true }
            }
            i += 1
        }
        return false
    }

    /// The last query and its results, so a screen that redraws several times
    /// per keystroke doesn't repeat the search.
    private struct LastSearch { var query = ""; var limit = 0; var results: [FoodItem] = [] }
    private static let last = OSAllocatedUnfairLock(initialState: LastSearch())

    /// Curated sources first when a name matches equally well.
    private static func priority(_ source: FoodItem.Source) -> Int {
        switch source {
        case .common: 0
        case .swiss:  1
        default:      2
        }
    }

    private static let swissRows: [Row] = Bundle.main.url(forResource: "SwissFoods", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([Row].self, from: $0) } ?? []

    private static let swissServings: [String: [PortionPair]] = {
        Dictionary(uniqueKeysWithValues: swissRows.compactMap { row in
            row.s.map { ("swiss-\(row.id)", $0) }
        })
    }()

    @MainActor
    static func swissPortions(for item: FoodItem) -> [FoodPortion] {
        guard let pairs = swissServings[item.id] else { return [] }
        let sizes: [FoodPortion.Size] = pairs.count == 1 ? [.medium] : pairs.count == 2 ? [.small, .medium] : [.small, .medium, .large]
        return zip(sizes, pairs).map { size, pair in
            FoodPortion(size: size, unit: String(localized: String.LocalizationValue(pair.name)), grams: pair.grams, custom: true)
        }
    }

    private static let index: [Indexed] = {
        let swiss = swissRows.map { row in
            let item = FoodItem(id: "swiss-\(row.id)", name: row.en, brand: nil, kcal: row.kcal, protein: row.p,
                                carbs: row.c, fat: row.f, source: .swiss, barcode: nil, servingGrams: nil, density: row.d)
            let key = fold([row.en, row.de ?? "", row.syn].joined(separator: " "))
            return Indexed(item: item, name: fold(row.en), key: key)
        }
        // Everyday foods the Swiss database doesn't list (CommonFoods.swift).
        let common = zip(CommonFoods.entries, CommonFoods.items).map { entry, item in
            Indexed(item: item, name: fold(item.name), key: fold(entry.name + " " + (entry.polishName ?? "") + " " + entry.aliases))
        }
        let usda = usdaRows.map { row in
            let item = FoodItem(id: "usda-\(row.id)", name: row.n, brand: nil, kcal: row.k, protein: row.p,
                                carbs: row.c, fat: row.f, source: .usda, barcode: nil, servingGrams: nil, density: nil)
            return Indexed(item: item, name: fold(row.n), key: fold(row.n))
        }
        return common + swiss + usda
    }()

    /// Builds the search index (a 2 MB USDA table plus the Swiss one) ahead of
    /// the first search, so typing in the food screen doesn't start with the
    /// decode. Called once shortly after launch.
    static func warmUp() {
        _ = index.count
        _ = documents.count
        _ = usdaPortionsByID.count
        _ = surveyIDs.count
        _ = swissServings.count
    }

    /// The index prepared for typo-tolerant search (built once).
    private static let documents: [SmartSearch.Document<String>] = index.map { entry in
        SmartSearch.Document(id: entry.item.id, name: entry.item.name, extra: [entry.key],
                             boost: priority(entry.item.source) == 0 ? 0.3 : (priority(entry.item.source) == 1 ? 0.15 : 0))
    }
    private static let itemsByID: [String: FoodItem] = Dictionary(index.map { ($0.item.id, $0.item) }, uniquingKeysWith: { a, _ in a })

    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ł", with: "l")
    }

    private static func rank(_ name: String, _ q: String) -> Int {
        if name.hasPrefix(q) { return 0 }
        if name.contains(" " + q) || name.contains("," + q) { return 1 }
        return name.contains(q) ? 2 : 3
    }

    /// Every word of the query must appear; names that start with it rank
    /// first. When that strict pass finds little — a typo, a plural, a word in
    /// another form — the smart search (SmartSearch.swift) fills the list with
    /// close matches, so "brocoli" and "chiken brest" still find their foods.
    static func search(_ query: String, limit: Int = 60) -> [FoodItem] {
        let q = fold(query.trimmingCharacters(in: .whitespaces))
        if let cached = last.withLock({ $0.query == q && $0.limit == limit ? $0.results : nil }) { return cached }
        let words = q.split(whereSeparator: { $0 == " " || $0 == "," }).map { Array($0.utf8) }
        guard !words.isEmpty else { return [] }
        let hits: [Indexed] = index.filter { entry in words.allSatisfy { contains(entry.keyBytes, $0) } }
        let ranked: [(item: FoodItem, rank: Int, length: Int)] = hits.map { ($0.item, rank($0.name, q), $0.name.count) }
        let sorted = ranked.sorted { a, b in
            if a.rank != b.rank { return a.rank < b.rank }
            let (pa, pb) = (priority(a.item.source), priority(b.item.source))
            return pa != pb ? pa < pb : a.length < b.length
        }
        var results = Array(sorted.prefix(limit).map(\.item))
        // Typos and odd word forms: only when the strict pass came up short,
        // and only once the query is long enough to be fuzzy-matched sensibly.
        if results.count < 8, q.count >= 4 {
            var seen = Set(results.map(\.id))
            for hit in SmartSearch.rank(query: query, in: documents, limit: limit) where !seen.contains(hit.id) {
                guard let item = itemsByID[hit.id] else { continue }
                results.append(item)
                seen.insert(item.id)
                if results.count >= limit { break }
            }
        }
        let final = results
        last.withLock { $0 = LastSearch(query: q, limit: limit, results: final) }
        return final
    }
}

// MARK: - Open Food Facts (online)

struct OpenFoodFacts {
    enum LookupError: LocalizedError {
        case offline
        var errorDescription: String? { String(localized: "Couldn't reach the product database. Check your connection.") }
    }

    private static let fields = "code,product_name,product_name_en,product_name_pl,product_name_de,brands,quantity,serving_size,serving_quantity,nutriments"

    func product(barcode: String) async throws -> FoodItem? {
        let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=\(Self.fields)")!
        let data = try await get(url)
        struct Envelope: Decodable { let status: Int?; let product: Product? }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        return envelope.product?.item(barcode: barcode)
    }

    /// Worldwide products, with ones sold in Switzerland listed first. Uses the
    /// fast search service, and the older search page if that's down — one
    /// mirror failing never ends the search.
    func search(_ query: String) async throws -> [FoodItem] {
        if let items = try? await fastSearch(query), !items.isEmpty { return items }
        return try await classicSearch(query, host: "world.openfoodfacts.org")
    }

    private func fastSearch(_ query: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://search.openfoodfacts.org/search")!
        components.queryItems = [
            .init(name: "q", value: query), .init(name: "page_size", value: "20"),
            .init(name: "fields", value: "code,product_name,product_name_en,product_name_pl,product_name_de,brands,countries_tags,quantity,serving_size,serving_quantity,nutriments")
        ]
        let data = try await get(components.url!)
        struct Envelope: Decodable { let hits: [Product] }
        let hits = try JSONDecoder().decode(Envelope.self, from: data).hits
        let swiss = hits.filter(\.soldInSwitzerland)
        let rest = hits.filter { !$0.soldInSwitzerland }
        return (swiss + rest).compactMap { $0.item(barcode: nil) }
    }

    private func classicSearch(_ query: String, host: String) async throws -> [FoodItem] {
        var components = URLComponents(string: "https://\(host)/cgi/search.pl")!
        components.queryItems = [
            .init(name: "search_terms", value: query), .init(name: "search_simple", value: "1"),
            .init(name: "json", value: "1"), .init(name: "page_size", value: "30"),
            .init(name: "fields", value: Self.fields)
        ]
        let data = try await get(components.url!)
        struct Envelope: Decodable { let products: [Product]? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else { throw LookupError.offline }
        return (envelope.products ?? []).compactMap { $0.item(barcode: nil) }
    }

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 15)
        // The database asks apps to identify themselves.
        request.setValue("Trace/1.0 (iOS personal app)", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { throw LookupError.offline }
            return data
        } catch {
            throw LookupError.offline
        }
    }

    private struct Product: Decodable {
        let code: String?
        let product_name: String?
        let product_name_en: String?
        let product_name_pl: String?
        let product_name_de: String?
        let brands: Strings?
        let countries_tags: [String]?
        let quantity: String?
        let serving_size: String?
        let serving_quantity: Flexible?
        let nutriments: [String: Flexible]?

        var soldInSwitzerland: Bool { countries_tags?.contains("en:switzerland") == true }

        var isDrink: Bool {
            [quantity, serving_size].compactMap { $0?.lowercased() }
                .contains { $0.firstMatch(of: /\d\s*(ml|cl|l)\b/) != nil }
        }

        func item(barcode: String?) -> FoodItem? {
            let candidates = AppLanguage.current == .polish ? [product_name_pl, product_name, product_name_en, product_name_de] : [product_name_en, product_name, product_name_pl, product_name_de]
            let names = candidates.compactMap { $0?.trimmingCharacters(in: .whitespaces) }
            guard let name = names.first(where: { !$0.isEmpty }), let n = nutriments else { return nil }
            let kcal = n["energy-kcal_100g"]?.value ?? n["energy_100g"]?.value.map { $0 / 4.184 }
            guard let kcal else { return nil }
            let brand = brands?.first
            let code = barcode ?? code
            return FoodItem(id: "off-\(code ?? name)", name: name, brand: brand, kcal: kcal,
                            protein: n["proteins_100g"]?.value ?? 0, carbs: n["carbohydrates_100g"]?.value ?? 0,
                            fat: n["fat_100g"]?.value ?? 0, source: .product, barcode: code,
                            servingGrams: serving_quantity?.value.flatMap { $0 > 0 ? $0 : nil },
                            // Drinks are labelled per 100 ml, so 1 ml counts as 1 g of the label.
                            density: isDrink ? 1 : nil)
        }
    }

    /// Brands arrive as "A, B" from one service and ["A", "B"] from the other.
    private struct Strings: Decodable {
        let values: [String]
        var first: String? { values.first.map { $0.trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } }
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let list = try? c.decode([String].self) { values = list }
            else if let text = try? c.decode(String.self) { values = text.split(separator: ",").map(String.init) }
            else { values = [] }
        }
    }

    /// Numbers arrive as 12, "12" or occasionally junk.
    private struct Flexible: Decodable {
        let value: Double?
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let d = try? c.decode(Double.self) { value = d }
            else if let s = try? c.decode(String.self) { value = Double(s.replacingOccurrences(of: ",", with: ".")) }
            else { value = nil }
        }
    }
}

// MARK: - Apple Health

/// Writes food to Apple Health as one food entry (calories, protein, carbs,
/// fat), so it counts toward the rings like any other nutrition app's log.
enum FoodHealthWriter {
    private static var types: [(HKQuantityTypeIdentifier, HKUnit)] {
        [(.dietaryEnergyConsumed, .kilocalorie()), (.dietaryProtein, .gram()),
         (.dietaryCarbohydrates, .gram()), (.dietaryFatTotal, .gram())]
    }

    struct Saved {
        let food: HKCorrelation
        /// Macros that weren't written because Health access for them is off.
        let skipped: [String]
    }

    /// Writes whichever of calories, protein, carbs and fat Health allows —
    /// never asks again once the user has answered.
    static func save(name: String, kcal: Double, protein: Double, carbs: Double, fat: Double,
                     at date: Date) async throws -> Saved {
        let store = HealthKitManager.shared.store
        let allowed = Set(await HealthAccess.writable(HealthAccess.nutritionTypes))

        let metadata: [String: Any] = [HKMetadataKeyFoodType: name]
        let labels = [String(localized: "calories"), String(localized: "protein"), String(localized: "carbs"), String(localized: "fat")]
        var skipped: [String] = []
        var samples = Set<HKSample>()
        for (i, (pair, value)) in zip(types, [kcal, protein, carbs, fat]).enumerated() {
            guard value > 0, let type = HKObjectType.quantityType(forIdentifier: pair.0) else { continue }
            guard allowed.contains(type) else { skipped.append(labels[i]); continue }
            samples.insert(HKQuantitySample(type: type, quantity: HKQuantity(unit: pair.1, doubleValue: value),
                                            start: date, end: date, metadata: metadata))
        }
        guard let foodType = HKObjectType.correlationType(forIdentifier: .food) else { throw FoodLogger.LogError.healthDenied }
        guard !samples.isEmpty else {
            throw [kcal, protein, carbs, fat].contains(where: { $0 > 0 }) ? FoodLogger.LogError.healthDenied : FoodLogger.LogError.nothingToSave
        }
        let food = HKCorrelation(type: foodType, start: date, end: date, objects: samples, metadata: metadata)
        try await store.save(food)
        return Saved(food: food, skipped: skipped)
    }

    static func delete(_ food: HKCorrelation) async throws {
        try await HealthKitManager.shared.store.delete(Array(food.objects) + [food])
    }

    static func delete(id: UUID) async {
        guard let foodType = HKObjectType.correlationType(forIdentifier: .food) else { return }
        let store = HealthKitManager.shared.store
        let food: HKCorrelation? = await withCheckedContinuation { continuation in
            let query = HKCorrelationQuery(type: foodType, predicate: HKQuery.predicateForObject(with: id),
                                           samplePredicates: nil) { _, results, _ in
                continuation.resume(returning: results?.first)
            }
            store.execute(query)
        }
        if let food { try? await delete(food) }
    }
}

// MARK: - Logging

enum FoodLogger {
    enum LogError: LocalizedError {
        case nothingToSave
        case healthDenied

        var errorDescription: String? {
            switch self {
            case .nothingToSave: String(localized: "Enter an amount first.")
            case .healthDenied:  String(localized: "Couldn't save to Apple Health — allow Trace to write nutrition in Settings → Health → Data Access & Devices.")
            }
        }
    }

    @discardableResult
    static func log(_ item: FoodItem, grams: Double, slot: MealSlot, at date: Date,
                    context: ModelContext) async throws -> FoodEntry {
        let a = item.amount(grams)
        guard grams > 0, a.kcal > 0 || a.protein > 0 || a.carbs > 0 || a.fat > 0 else { throw LogError.nothingToSave }
        let label = [item.brand, item.name].compactMap { $0 }.joined(separator: " ")
        let saved: FoodHealthWriter.Saved
        do {
            saved = try await FoodHealthWriter.save(name: label, kcal: a.kcal, protein: a.protein, carbs: a.carbs,
                                                    fat: a.fat, at: date)
        } catch let error as LogError {
            throw error
        } catch {
            throw LogError.healthDenied
        }
        lastSkipped = saved.skipped
        let entry = FoodEntry(item: item, grams: grams, slot: slot, date: date, healthID: saved.food.uuid)
        context.insert(entry)
        adjustDay(of: date, kcal: a.kcal, protein: a.protein, carbs: a.carbs, fat: a.fat, context: context)
        return entry
    }

    /// Macros skipped on the last save because their Health access is off.
    static var lastSkipped: [String] = []

    static func delete(_ entry: FoodEntry, context: ModelContext) async {
        if let id = entry.healthID.flatMap(UUID.init(uuidString:)) { await FoodHealthWriter.delete(id: id) }
        adjustDay(of: entry.date, kcal: -entry.kcal, protein: -entry.protein, carbs: -entry.carbs, fat: -entry.fat, context: context)
        context.delete(entry)
        try? context.save()
    }

    /// Show the change straight away — rings, widget and Live Activity — then
    /// confirm against Health a moment later, once its totals have caught up.
    static func adjustDay(of date: Date, kcal: Double, protein: Double, carbs: Double, fat: Double, context: ModelContext) {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<DailyMetrics>(predicate: #Predicate { $0.date == day })
        if let metrics = try? context.fetch(descriptor).first {
            func add(_ value: Double?, _ delta: Double) -> Double? { max((value ?? 0) + delta, 0) }
            metrics.dietaryEnergyKcal = add(metrics.dietaryEnergyKcal, kcal)
            metrics.proteinGrams = add(metrics.proteinGrams, protein)
            metrics.carbsGrams = add(metrics.carbsGrams, carbs)
            metrics.fatGrams = add(metrics.fatGrams, fat)
        }
        try? context.save()
        BriefingService.update(with: (try? context.fetch(FetchDescriptor<DailyMetrics>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
        HealthSync.shared.refreshSoon(after: .seconds(4))
    }

    /// Record an entry already written to Health elsewhere (the Gemini meal scan).
    static func record(_ item: FoodItem, grams: Double, healthID: UUID, at date: Date = Date(), slot: MealSlot? = nil, context: ModelContext) -> FoodEntry {
        let entry = FoodEntry(item: item, grams: grams, slot: slot ?? .forNow(), date: date, healthID: healthID)
        context.insert(entry)
        try? context.save()
        return entry
    }

    static func refresh(_ context: ModelContext) async {
        await HealthSync.shared.refreshNow()
    }
}
