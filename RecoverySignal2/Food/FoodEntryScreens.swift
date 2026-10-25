//
//  FoodEntryScreens.swift
//  RecoverySignal2
//
//  Two ways to log without searching: describe the meal in words and let
//  Gemini estimate it, or type the calories and macros in yourself (and keep
//  the food as a personal one for next time).
//

import SwiftUI
import SwiftData

// MARK: - Manual

struct ManualFoodScreen: View {
    let onAdd: (FoodItem, Double) -> Void

    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var amount: Double?
    @State private var inMl = false
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var saveAsPersonal = false
    @State private var addedName: String?

    private var canAdd: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && [kcal, protein, carbs, fat].contains { ($0 ?? 0) > 0 }
    }

    /// Calories from the macros, to catch typos (4 / 4 / 9 kcal per gram).
    private var macroKcal: Double { (protein ?? 0) * 4 + (carbs ?? 0) * 4 + (fat ?? 0) * 9 }

    var body: some View {
        Form {
            Section {
                TextField("Name, e.g. Mum's lasagne", text: $name)
            }

            Section {
                HStack {
                    Text("Amount")
                    Spacer()
                    LiveNumberField("optional", value: $amount)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(maxWidth: 90)
                    Picker("Unit", selection: $inMl) {
                        Text(verbatim: "g").tag(false)
                        Text(verbatim: "ml").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 90)
                }
                numberField("Calories", "kcal", $kcal)
                numberField("Protein", "g", $protein)
                numberField("Carbs", "g", $carbs)
                numberField("Fat", "g", $fat)
                if let kcal, kcal > 0, macroKcal > 0, abs(macroKcal - kcal) > max(40, kcal * 0.2) {
                    Label("The macros add up to about \(DetailFormat.safeInt(macroKcal)) kcal — worth a quick check.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            } header: {
                Text("What you ate")
            } footer: {
                Text("Enter the values for the portion you ate. The amount is optional — add it if you want to reuse this food by weight.")
            }

            Section {
                Toggle(isOn: $saveAsPersonal) {
                    HStack(spacing: 8) {
                        Text("Save to My foods")
                        PersonalBadge()
                    }
                }
                .tint(Theme.accent)
            } footer: {
                Text("Saved foods are marked Personal wherever they appear, so they're never confused with database values.")
            }

            Section {
                Button {
                    add()
                } label: {
                    Label("Add to meal", systemImage: "plus.circle.fill").fontWeight(.semibold)
                }
                .disabled(!canAdd)
                if let addedName {
                    Label("Added \(addedName)", systemImage: "checkmark.circle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.good)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Manual entry")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func numberField(_ label: LocalizedStringKey, _ unit: String, _ value: Binding<Double?>) -> some View {
        HStack {
            Text(label)
            Spacer()
            LiveNumberField("0", value: value)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(maxWidth: 110)
            Text(verbatim: unit).foregroundStyle(Theme.textTertiary).frame(width: 34, alignment: .leading)
        }
    }

    private func add() {
        // Values are for the portion eaten; store them per 100 like everything else.
        let portion = amount.flatMap { $0 > 0 ? $0 : nil } ?? 100
        let scale = 100 / portion
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let density: Double? = inMl ? 1 : nil

        var item = FoodItem(id: "manual-\(UUID().uuidString)", name: trimmed, brand: nil,
                            kcal: (kcal ?? 0) * scale, protein: (protein ?? 0) * scale,
                            carbs: (carbs ?? 0) * scale, fat: (fat ?? 0) * scale,
                            source: .custom, barcode: nil, servingGrams: portion, density: density)

        if saveAsPersonal {
            let food = UserFood(name: trimmed, isRecipe: false)
            food.kcal = item.kcal
            food.protein = item.protein
            food.carbs = item.carbs
            food.fat = item.fat
            food.servingGrams = portion
            food.density = density
            context.insert(food)
            try? context.save()
            item = food.item
        }

        onAdd(item, portion)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        addedName = trimmed
        name = ""; amount = nil; kcal = nil; protein = nil; carbs = nil; fat = nil; saveAsPersonal = false
    }
}
