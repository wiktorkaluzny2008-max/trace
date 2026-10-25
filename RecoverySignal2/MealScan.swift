//
//  MealScan.swift
//  RecoverySignal2
//
//  "Snap a meal": photograph a plate and Gemini estimates what's on it and its
//  macros, shown against what's left of today's targets.
//
//  These are visual estimates — portion size from a photo is genuinely hard, so
//  the model reports its confidence and the UI says so. A scanned meal is
//  saved to Apple Health and appears in the food log like any other entry.
//

import SwiftUI
import SwiftData
import PhotosUI
import UIKit
import HealthKit

// MARK: - Model

struct MealEstimate: Decodable {
    struct Item: Decodable, Identifiable {
        let id = UUID()
        let name: String
        let grams: Double
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double

        enum CodingKeys: String, CodingKey { case name, grams, calories, protein, carbs, fat }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            grams = c.flexibleNumber(.grams) ?? 0
            calories = c.flexibleNumber(.calories) ?? 0
            protein = c.flexibleNumber(.protein) ?? 0
            carbs = c.flexibleNumber(.carbs) ?? 0
            fat = c.flexibleNumber(.fat) ?? 0
        }
    }

    let mealName: String
    let items: [Item]
    let confidence: String
    let notes: String

    enum CodingKeys: String, CodingKey {
        case mealName = "meal_name", items, confidence, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mealName = (try? c.decode(String.self, forKey: .mealName)) ?? String(localized: "Your meal")
        items = (try? c.decode([Item].self, forKey: .items)) ?? []
        confidence = ((try? c.decode(String.self, forKey: .confidence)) ?? "low").lowercased()
        notes = (try? c.decode(String.self, forKey: .notes)) ?? ""
    }

    /// The whole meal as one food, for the food log.
    var loggedGrams: Double {
        let grams = items.reduce(0) { $0 + $1.grams }
        return grams > 0 ? grams : 100
    }

    var foodItem: FoodItem {
        let scale = 100 / loggedGrams
        return FoodItem(id: "scan-\(UUID().uuidString)", name: mealName, brand: nil, kcal: calories * scale,
                        protein: protein * scale, carbs: carbs * scale, fat: fat * scale,
                        source: .estimate, barcode: nil, servingGrams: nil)
    }

    var calories: Double { items.reduce(0) { $0 + $1.calories } }
    var protein: Double { items.reduce(0) { $0 + $1.protein } }
    var carbs: Double { items.reduce(0) { $0 + $1.carbs } }
    var fat: Double { items.reduce(0) { $0 + $1.fat } }
}

private extension KeyedDecodingContainer {
    /// Accepts 120, "120" or "120 g".
    func flexibleNumber(_ key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) { return value }
        guard let text = try? decode(String.self, forKey: key) else { return nil }
        return Double(text.prefix { $0.isNumber || $0 == "." })
    }
}

enum MealScanService {

    /// Estimates from a photo, a written description, or both. When both are
    /// given, the description wins on anything a photo can't show — exact
    /// quantities, ingredients, cooking fat, brands.
    static func analyse(_ image: UIImage?, description: String = "", dietaryNotes: String) async throws -> MealEstimate {
        var images: [Data] = []
        if let image {
            guard let jpeg = image.preparedForUpload() else {
                throw AIClient.AIError.requestFailed("Couldn't read that photo. Try another one.")
            }
            images = [jpeg]
        }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !images.isEmpty || !description.isEmpty else {
            throw AIClient.AIError.requestFailed("Add a photo or describe the meal first.")
        }

        let system = """
        You are a sports nutritionist estimating the nutrition of a meal from a photo and/or the eater's own description.
        When the eater describes the meal, treat their quantities, weights, ingredients, brands and cooking method as
        facts that override what you'd guess from the photo; use the photo for anything they didn't mention.
        Without a photo, estimate from the description alone using typical portions for anything unspecified.
        Identify each distinct food, estimate its cooked portion weight in grams from visual cues
        (plate size, cutlery, typical servings), and estimate calories, protein, carbs and fat for that portion.
        Keep each item's calories consistent with 4 kcal/g protein and carbs and 9 kcal/g fat.
        Include hidden energy you'd reasonably expect (cooking oil, sauces, dressing) as its own item.
        If there is no food in the photo or description, return an empty items list and explain in notes.

        Respond with JSON only, in exactly this shape:
        {"meal_name": string, "items": [{"name": string, "grams": number, "calories": number,
        "protein": number, "carbs": number, "fat": number}], "confidence": "low" | "medium" | "high",
        "notes": string}
        notes is one short sentence on what most affects accuracy (e.g. unseen oil, portion depth).
        """

        var user = images.isEmpty ? "Estimate this meal from my description." : "Estimate this meal."
        if !description.isEmpty { user += "\nMy description of it: \(description)" }
        if !dietaryNotes.isEmpty { user += "\nContext about how I eat: \(dietaryNotes)" }

        let text = try await AIClient().send(system: system, user: user, maxTokens: 2000,
                                             temperature: 0.2, json: true, images: images,
                                             onDeviceContext: { await OnDeviceAI.foodContext(images) },
                                             accepts: { (try? JSONDecoder().decode(MealEstimate.self, from: Data($0.utf8))) != nil })
        do {
            return try JSONDecoder().decode(MealEstimate.self, from: Data(text.utf8))
        } catch {
            throw AIClient.AIError.requestFailed("The meal estimate came back in an unexpected format. Try again.")
        }
    }
}

extension UIImage {
    /// Downscales to at most 1280 px on the long edge and compresses — plenty
    /// for recognising food, and far faster to upload than a full photo.
    func preparedForUpload() -> Data? {
        let maxEdge: CGFloat = 1280
        let scale = min(1, maxEdge / max(size.width, size.height))
        let target = CGSize(width: size.width * scale, height: size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: 0.72)
    }
}

// MARK: - Screen

struct MealScanView: View {
    @Environment(\.foodLoggingDate) private var loggingDate
    @Environment(\.foodLoggingSlot) private var loggingSlot
    let remaining: RecipeRequest

    @Environment(\.dismiss) private var dismiss
    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var estimate: MealEstimate?
    @State private var isAnalysing = false
    @State private var errorMessage: String?
    @State private var showCamera = false
    @State private var mealDescription = ""
    @FocusState private var descriptionFocused: Bool
    @Environment(\.modelContext) private var context
    @State private var savedMeal: HKCorrelation?
    @State private var loggedEntry: FoodEntry?
    @State private var healthMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    photoCard
                    descriptionCard

                    if isAnalysing {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking at your plate…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: 20)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.bad)
                            .card()
                    }

                    if let estimate {
                        if estimate.items.isEmpty {
                            Text(estimate.notes.isEmpty ? String(localized: "No food found in that photo.") : estimate.notes)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .card()
                        } else {
                            healthCard
                            totalsCard(estimate)
                            itemsCard(estimate)
                            fitCard(estimate)
                        }
                    }

                    Text("Estimates, not measurements — the more exact your description, the better. Scanned meals are added to Apple Health automatically, so don't also log the same meal in Yazio or it will count twice.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Snap a meal")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        GeminiMark(size: 16)
                        Text("Snap a meal").font(.headline)
                    }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: photoItem) { _, item in
                Task {
                    guard let data = try? await item?.loadTransferable(type: Data.self),
                          let picked = UIImage(data: data) else { return }
                    photoChosen(picked)
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPicker { captured in
                    showCamera = false
                    if let captured { photoChosen(captured) }
                }
                .ignoresSafeArea()
            }
        }
        .tint(Theme.accent)
    }

    private var photoCard: some View {
        VStack(spacing: 14) {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            } else {
                VStack(spacing: 10) {
                    GlyphView(.nutrition, size: 44)
                    Text("Photograph your plate from above for the best estimate.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 22)
            }

            HStack(spacing: 10) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        showCamera = true
                    } label: {
                        Label("Camera", systemImage: "camera.fill")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(.white)
                            .background(LinearGradient(colors: [Theme.accentDeep, Theme.accent],
                                                       startPoint: .leading, endPoint: .trailing),
                                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Photos", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .foregroundStyle(Theme.accentDeep)
                        .background(Theme.accent.opacity(0.12),
                                    in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .disabled(isAnalysing)
        }
        .card(padding: 14)
    }

    /// Optional words that make the estimate far more accurate.
    private var descriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                Text("Describe it")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("optional · much more accurate")
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
            }

            TextField("e.g. 200 g chicken breast, 150 g cooked basmati rice, 1 tbsp olive oil, half an avocado",
                      text: $mealDescription, axis: .vertical)
                .lineLimit(2...6)
                .font(.subheadline)
                .focused($descriptionFocused)
                .padding(12)
                .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(["Quantities in grams", "Cooked in oil", "Homemade", "Restaurant portion", "Sauce on the side"], id: \.self) { hint in
                        Button {
                            mealDescription += (mealDescription.isEmpty || mealDescription.hasSuffix(" ") ? "" : ", ") + hint.lowercased()
                            descriptionFocused = true
                        } label: {
                            Text("+ \(hint)")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Theme.accentDeep)
                                .padding(.horizontal, 9)
                                .padding(.vertical, 5)
                                .background(Theme.accent.opacity(0.1), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !hasDescription {
                Label(image == nil ? String(localized: "Describe your meal to scan it") : String(localized: "Photo ready — describe it to start the scan"),
                      systemImage: "text.cursor")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(image == nil ? Theme.textTertiary : Theme.warn)
            }

            Button {
                descriptionFocused = false
                Task { await analyse(image) }
            } label: {
                HStack(spacing: 8) {
                    GeminiMark(size: 16)
                    Text(image == nil ? String(localized: "Scan description") : (estimate == nil ? String(localized: "Scan photo + description") : String(localized: "Re-scan")))
                }
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(Theme.accentDeep, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isAnalysing || !hasDescription)
            .opacity(isAnalysing || !hasDescription ? 0.45 : 1)
        }
        .card(padding: 14)
    }

    private func totalsCard(_ e: MealEstimate) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(e.mealName)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                confidenceTag(e.confidence)
            }
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text("\(Int(e.calories.rounded()))")
                    .font(.system(size: 34, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text("kcal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            HStack(spacing: 0) {
                macro("Protein", e.protein, .protein, Theme.protein)
                macro("Carbs", e.carbs, .carbs, Theme.carbs)
                macro("Fat", e.fat, .fat, Theme.fat)
            }
            if !e.notes.isEmpty {
                Text(e.notes)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .card(padding: 18)
    }

    private func itemsCard(_ e: MealEstimate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: String(localized: "What's on the plate"), icon: .nutrition)
            VStack(spacing: 0) {
                ForEach(Array(e.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(LocalizedStringKey(item.name))
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.textPrimary)
                            Text("~\(Int(item.grams.rounded())) g · \(Int(item.protein.rounded()))P \(Int(item.carbs.rounded()))C \(Int(item.fat.rounded()))F")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.textTertiary)
                        }
                        Spacer()
                        Text("\(Int(item.calories.rounded())) kcal")
                            .font(.system(size: 14, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 10)
                }
            }
            .card(padding: 14)
        }
    }

    /// How the meal lands against what was left of today's targets.
    @ViewBuilder
    private func fitCard(_ e: MealEstimate) -> some View {
        if let kcalLeft = remaining.remainingCalories {
            let after = kcalLeft - e.calories
            let proteinAfter = (remaining.remainingProtein ?? 0) - e.protein
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: String(localized: "How it fits today"), icon: .target)
                VStack(alignment: .leading, spacing: 6) {
                    Text(after >= 0
                         ? String(localized: "Leaves about \(Int(after.rounded())) kcal for the rest of today.")
                         : String(localized: "Puts you about \(Int((-after).rounded())) kcal over today's target."))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(after >= 0 ? Theme.textPrimary : Theme.warn)
                    Text(proteinAfter > 0
                         ? String(localized: "You'd still need around \(Int(proteinAfter.rounded())) g of protein.")
                         : String(localized: "Covers the rest of today's protein target."))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
                .card()
            }
        }
    }

    private func macro(_ label: String, _ grams: Double, _ glyph: Glyph, _ color: Color) -> some View {
        HStack(spacing: 6) {
            GlyphView(glyph, size: 16, palette: .mono(color, soft: 0.22))
            VStack(alignment: .leading, spacing: 0) {
                Text("\(Int(grams.rounded())) g")
                    .font(.system(size: 15, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(label))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func confidenceTag(_ confidence: String) -> some View {
        let color: Color = confidence == "high" ? Theme.good : (confidence == "medium" ? Theme.warn : Theme.bad)
        return Text("\(confidence.capitalized) confidence")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }

    private var hasDescription: Bool {
        !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A photo alone doesn't scan — it waits for your description.
    private func photoChosen(_ picked: UIImage) {
        image = picked
        estimate = nil
        errorMessage = nil
        if hasDescription {
            Task { await analyse(picked) }
        } else {
            descriptionFocused = true
        }
    }

    @ViewBuilder
    private var healthCard: some View {
        HStack(spacing: 12) {
            Image(systemName: savedMeal != nil ? "heart.text.square.fill" : "heart.slash")
                .font(.system(size: 22))
                .foregroundStyle(savedMeal != nil ? Theme.bad : Theme.textTertiary)
            VStack(alignment: .leading, spacing: 2) {
                Text(savedMeal != nil ? String(localized: "Added to Apple Health") : (healthMessage ?? String(localized: "Saving to Apple Health…")))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(savedMeal != nil ? String(localized: "Calories and macros now count toward today's rings.") : "")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if savedMeal != nil {
                Button("Undo") { Task { await undoHealthSave() } }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.bad)
            }
        }
        .card()
    }

    private func saveToHealth(_ estimate: MealEstimate) async {
        healthMessage = nil
        do {
            let date = loggingDate ?? Date()
            let meal = try await MealHealthWriter.save(estimate, at: date)
            savedMeal = meal
            loggedEntry = FoodLogger.record(estimate.foodItem, grams: estimate.loggedGrams, healthID: meal.uuid, at: date, slot: loggingSlot, context: context)
            FoodLogger.adjustDay(of: date, kcal: estimate.calories, protein: estimate.protein,
                                 carbs: estimate.carbs, fat: estimate.fat, context: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            healthMessage = "Couldn't save to Apple Health — allow Trace to write nutrition in Health settings."
        }
    }

    private func undoHealthSave() async {
        guard let meal = savedMeal else { return }
        try? await MealHealthWriter.delete(meal)
        savedMeal = nil
        removeLoggedEntry()
        healthMessage = "Removed from Apple Health"
        if let estimate {
            FoodLogger.adjustDay(of: meal.startDate, kcal: -estimate.calories, protein: -estimate.protein,
                                 carbs: -estimate.carbs, fat: -estimate.fat, context: context)
        }
    }

    private func removeLoggedEntry() {
        guard let loggedEntry else { return }
        context.delete(loggedEntry)
        try? context.save()
        self.loggedEntry = nil
    }

    private func analyse(_ picked: UIImage?) async {
        guard hasDescription else {
            descriptionFocused = true
            return
        }
        // Re-scanning replaces the previous entry rather than adding a second meal.
        if let meal = savedMeal {
            try? await MealHealthWriter.delete(meal)
            savedMeal = nil
            removeLoggedEntry()
        }
        image = picked
        estimate = nil
        errorMessage = nil
        isAnalysing = true
        defer { isAnalysing = false }
        do {
            let result = try await MealScanService.analyse(picked, description: mealDescription,
                                                           dietaryNotes: remaining.goal.dietaryNotes)
            estimate = result
            if !result.items.isEmpty {
                Task { await saveToHealth(result) }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The system camera, for taking the meal photo in-app.
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}

// MARK: - Apple Health

/// Writes a scanned meal to Apple Health as one food entry (calories, protein,
/// carbs, fat), so it flows into the rings like a Yazio log would.
enum MealHealthWriter {
    private static var types: [(HKQuantityTypeIdentifier, HKUnit)] {
        [(.dietaryEnergyConsumed, .kilocalorie()), (.dietaryProtein, .gram()),
         (.dietaryCarbohydrates, .gram()), (.dietaryFatTotal, .gram())]
    }

    static func save(_ estimate: MealEstimate, at date: Date = Date()) async throws -> HKCorrelation {
        try await FoodHealthWriter.save(name: estimate.mealName, kcal: estimate.calories, protein: estimate.protein,
                                        carbs: estimate.carbs, fat: estimate.fat, at: date).food
    }

    static func delete(_ food: HKCorrelation) async throws {
        let store = HealthKitManager.shared.store
        try await store.delete(Array(food.objects) + [food])
    }
}
