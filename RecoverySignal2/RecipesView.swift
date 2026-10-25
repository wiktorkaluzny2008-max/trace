//
//  RecipesView.swift
//  RecoverySignal2
//

import SwiftUI
import SwiftData

struct RecipesView: View {
    @State var request: RecipeRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \SavedRecipe.savedAt, order: .reverse) private var saved: [SavedRecipe]

    @State private var recipes: [Recipe] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("Meal", selection: $request.slot) {
                        ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)

                    remainingStrip

                    if isLoading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Cooking up ideas…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: 22)
                    } else if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.bad)
                            .card()
                    }

                    ForEach(recipes) { recipe in
                        NavigationLink(value: recipe) {
                            RecipeRow(recipe: recipe, isSaved: isSaved(recipe))
                        }
                        .buttonStyle(.plain)
                    }

                    if !recipes.isEmpty {
                        Button {
                            Task { await load() }
                        } label: {
                            Label("Different ideas", systemImage: "arrow.clockwise")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .tint(Theme.accent)
                        .disabled(isLoading)
                    }

                    let savedRecipes = saved.compactMap(\.recipe)
                    if !savedRecipes.isEmpty {
                        SectionLabel(text: "Saved", icon: .recipe)
                        ForEach(savedRecipes) { recipe in
                            NavigationLink(value: recipe) {
                                RecipeRow(recipe: recipe, isSaved: true)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("Nutrition figures are AI estimates, not measurements. Log what you actually eat in Yazio so your rings stay accurate.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .padding(.horizontal, 4)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Meal ideas")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 6) {
                        GeminiMark(size: 16)
                        Text("Meal ideas").font(.headline)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Recipe.self) { recipe in
                RecipeDetailView(recipe: recipe, isSaved: isSaved(recipe)) { toggleSave(recipe) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: request.slot) { await load() }
        }
        .tint(Theme.accent)
    }

    private var remainingStrip: some View {
        HStack(spacing: 0) {
            remaining("kcal", request.remainingCalories, .energy, Theme.accent)
            remaining("protein", request.remainingProtein, .protein, Theme.protein)
            remaining("carbs", request.remainingCarbs, .carbs, Theme.carbs)
            remaining("fat", request.remainingFat, .fat, Theme.fat)
        }
        .card(padding: 12)
    }

    private func remaining(_ label: String, _ value: Double?, _ glyph: Glyph, _ color: Color) -> some View {
        VStack(spacing: 4) {
            GlyphView(glyph, size: 18, palette: .mono(color, soft: 0.22))
            Text(value.map { "\(Int(max(0, $0).rounded()))" } ?? "—")
                .font(.system(size: 15, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text("\(label) left")
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            recipes = try await RecipeService().suggest(request)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func isSaved(_ recipe: Recipe) -> Bool {
        saved.contains { $0.recipe?.title == recipe.title }
    }

    private func toggleSave(_ recipe: Recipe) {
        if let existing = saved.first(where: { $0.recipe?.title == recipe.title }) {
            context.delete(existing)
        } else {
            context.insert(SavedRecipe(recipe: recipe))
        }
        try? context.save()
    }
}

// MARK: - Components

private struct MacroPills: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 6) {
            pill(String(localized: "\(Int(recipe.calories.rounded())) kcal"), Theme.accent)
            pill(String(localized: "\(Int(recipe.protein.rounded()))g P"), Theme.protein)
            pill(String(localized: "\(Int(recipe.carbs.rounded()))g C"), Theme.carbs)
            pill(String(localized: "\(Int(recipe.fat.rounded()))g F"), Theme.fat)
        }
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
    }
}

private struct RecipeRow: View {
    let recipe: Recipe
    let isSaved: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(recipe.title)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 6)
                if isSaved {
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.accent)
                }
                Text("\(recipe.minutes) min")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textTertiary)
            }
            Text(recipe.summary)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.leading)
            MacroPills(recipe: recipe)
        }
        .card()
    }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @State var isSaved: Bool
    let onToggleSave: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(recipe.summary)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    MacroPills(recipe: recipe)
                    HStack(alignment: .top, spacing: 10) {
                        GlyphView(.target, size: 20)
                        Text(recipe.whyItFits)
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if !recipe.macrosConsistent {
                        Text("Heads up: these macros add up to about \(Int(recipe.macroCalories.rounded())) kcal, not \(Int(recipe.calories.rounded())) — treat the numbers as rough.")
                            .font(.caption)
                            .foregroundStyle(Theme.warn)
                    }
                }
                .card(padding: 18)

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Ingredients", icon: .nutrition)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(recipe.ingredients, id: \.self) { item in
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(Theme.mint).frame(width: 6, height: 6).padding(.top, 6)
                                Text(item).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel(text: "Method", icon: .recipe)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(Theme.accentDeep)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.accent.opacity(0.13), in: Circle())
                                Text(step).font(.subheadline).foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                    .card()
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 32)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(recipe.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    onToggleSave()
                    isSaved.toggle()
                } label: {
                    Image(systemName: isSaved ? "bookmark.fill" : "bookmark")
                }
            }
        }
    }
}
