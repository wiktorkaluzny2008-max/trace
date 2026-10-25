//
//  FoodVision.swift
//  RecoverySignal2
//
//  On-device image understanding for the food log — nothing leaves the phone.
//
//  • FoodRecognizer guesses what's in a photo and matches each guess to the
//    Swiss food database. If a Core ML model named FoodClassifier (for example
//    one trained with Create ML on your own meal photos) is added to the
//    project, it's used instead of the system classifier.
//  • NutritionLabelReader reads a nutrition table from a photo of the pack and
//    pulls out kcal, protein, carbs and fat per 100 g.
//

import UIKit
import Vision
import CoreML

enum FoodRecognizer {
    struct Guess: Identifiable {
        let id = UUID()
        let label: String
        let confidence: Double
        let matches: [FoodItem]
    }

    /// Labels too broad to be useful as a food.
    private static let generic: Set<String> = [
        "food", "dish", "meal", "plate", "bowl", "tableware", "table", "cutlery", "fork", "knife", "spoon",
        "dessert", "snack", "cuisine", "ingredient", "produce", "baked goods", "drink", "beverage", "container",
        "cup", "glass", "people", "adult", "hand", "indoor", "structure", "wood", "cloth", "textile", "napkin"
    ]

    /// Classifier labels that the database names differently.
    private static let aliases: [String: String] = [
        "spaghetti": "pasta", "noodle": "pasta", "noodles": "pasta", "macaroni": "pasta", "lasagna": "lasagne",
        "fries": "french fries", "burger": "hamburger", "steak": "beef steak", "oatmeal": "oat flakes",
        "porridge": "oat", "yoghurt": "yogurt", "cereal": "muesli", "omelet": "omelette", "scrambled eggs": "egg",
        "sausage": "sausage", "doughnut": "berliner", "donut": "berliner", "cookie": "biscuit", "cheesecake": "cake",
        "prawn": "shrimp", "shellfish": "shrimp", "citrus fruit": "orange"
    ]

    static var usesCustomModel: Bool { customModelURL != nil }

    private static var customModelURL: URL? {
        Bundle.main.url(forResource: "FoodClassifier", withExtension: "mlmodelc")
    }

    static func recognise(_ image: UIImage) async -> [Guess] {
        guard let cgImage = image.normalisedCGImage() else { return [] }
        let observations = await classify(cgImage)
        var seen: Set<String> = []
        var guesses: [Guess] = []
        for observation in observations.sorted(by: { $0.confidence > $1.confidence }) {
            let label = observation.identifier.replacingOccurrences(of: "_", with: " ")
            guard observation.confidence >= 0.08, !generic.contains(label), seen.insert(label).inserted else { continue }
            var matches = SwissFoodDatabase.search(aliases[label] ?? label, limit: 6)
            if matches.isEmpty, let last = label.split(separator: " ").last, last != Substring(label) {
                matches = SwissFoodDatabase.search(String(last), limit: 6)
            }
            guesses.append(Guess(label: label, confidence: Double(observation.confidence), matches: matches))
            if guesses.count == 5 { break }
        }
        // Guesses that match a known food first, most confident first within each group.
        return guesses.sorted { ($0.matches.isEmpty ? 1 : 0, -$0.confidence) < ($1.matches.isEmpty ? 1 : 0, -$1.confidence) }
    }

    private static func classify(_ cgImage: CGImage) async -> [ClassificationObservation] {
        if let url = customModelURL,
           let model = try? MLModel(contentsOf: url),
           let container = try? CoreMLModelContainer(model: model) {
            let request = CoreMLRequest(model: container)
            if let results = try? await request.perform(on: cgImage) {
                return results.compactMap { $0 as? ClassificationObservation }
            }
        }
        let request = ClassifyImageRequest()
        return (try? await request.perform(on: cgImage)) ?? []
    }
}

// MARK: - Nutrition label

struct LabelValues {
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?

    var foundAnything: Bool { kcal != nil || protein != nil || carbs != nil || fat != nil }
}

enum NutritionLabelReader {
    private static let proteinWords = ["protein", "eiweiss", "eiweiß", "proteine", "protéines", "białko", "proteina"]
    private static let carbWords = ["kohlenhydrate", "carbohydrate", "glucides", "carboidrati", "węglowodany", "hidratos"]
    private static let fatWords = ["fett", "fat", "matières grasses", "lipides", "grassi", "tłuszcz", "grasas"]
    /// Lines that mention a keyword but aren't the total.
    private static let subLines = ["davon", "of which", "dont", "di cui", "w tym", "gesättigt", "saturated", "saturés",
                                   "fettsäuren", "zucker", "sugar", "sucres", "zuccheri", "cukry"]

    static func read(_ image: UIImage) async -> LabelValues {
        guard let cgImage = image.normalisedCGImage() else { return LabelValues() }
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        guard let observations = try? await request.perform(on: cgImage) else { return LabelValues() }

        let lines: [(text: String, box: CGRect)] = observations.compactMap { obs in
            guard let text = obs.topCandidates(1).first?.string else { return nil }
            return (text, obs.boundingBox.cgRect)
        }

        var values = LabelValues()
        values.kcal = kcal(in: lines)
        values.protein = value(for: proteinWords, in: lines)
        values.carbs = value(for: carbWords, in: lines)
        values.fat = value(for: fatWords, in: lines)
        return values
    }

    /// "1520 kJ / 363 kcal" — the number right before kcal.
    private static func kcal(in lines: [(text: String, box: CGRect)]) -> Double? {
        let pattern = /(\d+(?:[.,]\d+)?)\s*kcal/.ignoresCase()
        for line in lines {
            if let match = line.text.firstMatch(of: pattern), let v = number(String(match.1)) { return v }
        }
        // Table layout: kcal is its own row label, the value sits to the right.
        if let label = lines.first(where: { $0.text.lowercased().contains("kcal") }) {
            return neighbourNumber(of: label, in: lines)
        }
        return nil
    }

    private static func value(for words: [String], in lines: [(text: String, box: CGRect)]) -> Double? {
        let candidates = lines.filter { line in
            let t = line.text.lowercased()
            return words.contains(where: t.contains) && !subLines.contains(where: t.contains)
        }
        for line in candidates {
            let t = line.text.lowercased()
            // Value on the same text line: "Fett 12,5 g".
            if let match = t.firstMatch(of: /(\d+(?:[.,]\d+)?)\s*g\b/), let v = number(String(match.1)) { return v }
            if let v = neighbourNumber(of: line, in: lines) { return v }
        }
        return nil
    }

    /// The nearest number to the right on the same row — the per-100 g column
    /// comes first on EU labels.
    private static func neighbourNumber(of label: (text: String, box: CGRect), in lines: [(text: String, box: CGRect)]) -> Double? {
        let row = lines
            .filter { abs($0.box.midY - label.box.midY) < max(label.box.height, 0.012) && $0.box.minX > label.box.midX }
            .sorted { $0.box.minX < $1.box.minX }
        for cell in row {
            if let match = cell.text.firstMatch(of: /(\d+(?:[.,]\d+)?)/), let v = number(String(match.1)) { return v }
        }
        return nil
    }

    private static func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: "."))
    }
}

extension UIImage {
    /// Vision reads raw pixels, so bake the photo's orientation in first.
    func normalisedCGImage() -> CGImage? {
        if imageOrientation == .up, let cgImage { return cgImage }
        let maxEdge: CGFloat = 1600
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }.cgImage
    }
}
