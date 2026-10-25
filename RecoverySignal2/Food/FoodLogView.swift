//
//  FoodLogView.swift
//  RecoverySignal2
//
//  The food page you reach from the fork button on Today. It's a logging tool:
//  add food by search, barcode, photo or your own recipes, and fix what you
//  logged today. A compact daily total stays visible below the log.
//

import SwiftUI
import SwiftData

struct FoodLogView: View {
    @Environment(\.modelContext) private var context
    /// Only recent entries: the diary shows one day at a time and "copy
    /// yesterday's…" looks back a few days, so loading the whole history on
    /// every change made the screen slower with every month of logging.
    @Query private var entries: [FoodEntry]
    @Query(sort: \DailyMetrics.date, order: .reverse) private var days: [DailyMetrics]
    @Query(sort: \SavedMeal.createdAt, order: .reverse) private var savedMeals: [SavedMeal]
    @State private var selectedDay = Date()

    init() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -FoodLogView.historyDays, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        _entries = Query(filter: #Predicate<FoodEntry> { $0.date >= cutoff }, sort: \FoodEntry.date, order: .reverse)
    }

    /// How far back the diary can page and copy meals from.
    static let historyDays = 120
    private var selectedTimestamp: Date { FoodLogDate.timestamp(on: selectedDay) }
    @State private var adding: FoodAddStart?
    @State private var loggingSavedMeal: SavedMeal?
    @State private var deletingSavedMeal: SavedMeal?
    @State private var copying: MealSlot?
    @State private var mealActionMessage: String?
    private var batchBusy: Bool { copying != nil || loggingSavedMeal != nil }
    /// Which meal the person is about to log; the log methods only appear once one is picked.
    @State private var pickedSlot: MealSlot?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var recipeRequest: RecipeRequest?
    /// Text pasted in (e.g. a ChatGPT reply) and the meal it goes into.
    @State private var pasted: (text: PastedText, slot: MealSlot)?

    private var today: [FoodEntry] { entries.filter { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) } }

    /// Meal sections in the order that's actually useful right now: whichever
    /// slot fits the time of day leads, followed by the rest of today's still
    /// -unlogged slots in day order, with anything already logged pushed to
    /// the bottom — you've already handled those.
    private var orderedSlots: [MealSlot] {
        let chronological: [MealSlot] = [.breakfast, .lunch, .snack, .dinner]
        guard Calendar.current.isDateInToday(selectedDay) else { return chronological }
        let currentIndex = chronological.firstIndex(of: .forNow()) ?? 0
        let rotated = Array(chronological[currentIndex...] + chronological[..<currentIndex])
        let isLogged = Set(today.map(\.slot))
        return rotated.filter { !isLogged.contains($0) } + rotated.filter { isLogged.contains($0) }
    }

    /// The most recent earlier day this slot was logged, if any.
    private func lastLogged(for slot: MealSlot) -> (date: Date, entries: [FoodEntry])? {
        let startOfToday = Calendar.current.startOfDay(for: selectedDay)
        let past = entries.filter { $0.slot == slot && $0.date < startOfToday }
        guard let mostRecentDay = past.map({ Calendar.current.startOfDay(for: $0.date) }).max() else { return nil }
        let dayEntries = past.filter { Calendar.current.isDate($0.date, inSameDayAs: mostRecentDay) }
        return dayEntries.isEmpty ? nil : (mostRecentDay, dayEntries)
    }

    private func copyLabel(_ slot: MealSlot, date: Date) -> String {
        Calendar.current.isDateInYesterday(date)
            ? String(localized: "Copy yesterday's \(slot.label.lowercased())")
            : String(localized: "Copy \(date.formatted(.dateTime.weekday(.wide)))'s \(slot.label.lowercased())")
    }

    private func copyMeal(_ slot: MealSlot, _ source: [FoodEntry]) async {
        guard !batchBusy else { return }
        let logDate = selectedTimestamp
        copying = slot
        defer { copying = nil }
        var saved = 0
        var issue: String?
        var skipped = Set<String>()
        for entry in source {
            guard let item = entry.item else {
                issue = String(localized: "A food's original values could not be read.")
                continue
            }
            do {
                try await FoodLogger.log(item, grams: entry.grams, slot: slot, at: logDate, context: context)
                saved += 1
                skipped.formUnion(FoodLogger.lastSkipped)
            } catch { issue = error.localizedDescription }
        }
        reportMealSave(saved: saved, total: source.count, skipped: skipped, issue: issue)
    }

    private func reportMealSave(saved: Int, total: Int, skipped: Set<String>, issue: String?) {
        if saved != total || total == 0 {
            let summary = String(localized: "Logged \(saved) of \(total) foods. Check the meal below before adding the missing foods again.")
            mealActionMessage = [summary, issue].compactMap { $0 }.joined(separator: "\n\n")
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        } else if !skipped.isEmpty {
            mealActionMessage = String(localized: "Food saved. Apple Health access is off for: \(skipped.sorted().joined(separator: ", ")).")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        List {
            Section {
                slotPicker
                    .id("logTop")
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                if let slot = pickedSlot {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Add to \(slot.label.lowercased()) with…")
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer()
                            Button { pickedSlot = nil } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textTertiary)
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Close logging options")
                        }
                        actionRow(slot)
                        Divider().overlay(Theme.separator).padding(.top, 4)
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Macros from ChatGPT?").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text("Copy its reply, then paste").font(.caption).foregroundStyle(Theme.textTertiary)
                            }
                            Spacer()
                            PasteButton(payloadType: String.self) { strings in
                                guard let text = strings.first, !text.isEmpty else { return }
                                Task { @MainActor in
                                    pasted = (PastedText(text: text), slot)
                                    pickedSlot = nil
                                }
                            }
                            .buttonBorderShape(.capsule)
                            .labelStyle(.titleAndIcon)
                            .tint(Theme.accent)
                        }
                    }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                if Calendar.current.isDateInToday(selectedDay) {
                HydrationQuickAddRow(days: days)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: 4, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                }
            }

            if today.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Your meals, all in one place").font(.headline)
                        Text("Choose a meal above to search, scan or describe what you ate.")
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.vertical, 6)
                }
            }

            ForEach(orderedSlots) { slot in
                let logged = today.filter { $0.slot == slot }.sorted { $0.date < $1.date }
                let last = logged.isEmpty ? lastLogged(for: slot) : nil
                if !logged.isEmpty || last != nil {
                Section {
                    ForEach(logged) { entry in
                        row(entry)
                            .contentShape(Rectangle())
                            .onTapGesture { adding = FoodAddStart(mode: .edit(entry), slot: slot) }
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) { delete(entry) } label: { Label("Delete", systemImage: "trash") }
                            }
                            .contextMenu {
                                Button("Delete", systemImage: "trash", role: .destructive) { delete(entry) }
                            }
                    }
                    if !logged.isEmpty {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            withAnimation(.snappy) { pickedSlot = slot }
                        } label: {
                            Label("Add more", systemImage: "plus.circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    if let last {
                        Button {
                            Task { await copyMeal(slot, last.entries) }
                        } label: {
                            if copying == slot {
                                HStack(spacing: 6) { ProgressView(); Text("Copying…") }
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textSecondary)
                            } else {
                                Label(copyLabel(slot, date: last.date), systemImage: "arrow.uturn.backward.circle.fill")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                        .disabled(batchBusy)
                    }
                } header: {
                    HStack(alignment: .firstTextBaseline) {
                        Text(slot.label)
                        Spacer()
                        if !logged.isEmpty {
                            Text("\(DetailFormat.safeInt(logged.reduce(0) { $0 + $1.kcal })) kcal")
                                .monospacedDigit().textCase(nil)
                        }
                    }
                }
                }
            }

            Section {
                mealIdeasRow
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }

            if !savedMeals.isEmpty {
                Section {
                    savedMealsRow
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                } header: {
                    Text("Saved meals")
                }
            }

            Section {
                DisclosureGroup("Health sync & food sources") {
                    Text("Logged food is saved to Apple Health and counts toward the selected day's totals. If you also log the same meal in another app, it counts twice. Generic foods: Swiss Food Composition Database (FSVO), plus common foods with typical values (mostly USDA FoodData Central). Products: Open Food Facts.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 4)
                }
                .font(.footnote.weight(.medium))
                .tint(Theme.textSecondary)
            } footer: {
                Text("Log each meal in one app to avoid counting it twice.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Food")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .top, spacing: 0) { dayNavigator }
        .safeAreaInset(edge: .bottom) {
            FoodDayTotalsBar(days: days, date: selectedDay, loggedEntries: today)
                .padding(.horizontal, 14)
                .padding(.bottom, 4)
        }
        .alert("Meal logging", isPresented: Binding(get: { mealActionMessage != nil }, set: { if !$0 { mealActionMessage = nil } })) {
            Button("OK", role: .cancel) { mealActionMessage = nil }
        } message: {
            Text(mealActionMessage ?? "")
        }
        .sheet(item: $adding) { start in
            FoodAddSheet(start: start)
                .environment(\.foodLoggingDate, selectedTimestamp)
                .environment(\.foodLoggingSlot, start.slot)
        }
        .sheet(item: $recipeRequest) { request in
            RecipesView(request: request)
                .environment(\.foodLoggingDate, selectedTimestamp)
        }
        .sheet(item: Binding(get: { pasted?.text }, set: { if $0 == nil { pasted = nil } })) { item in
            PasteMacrosSheet(text: item.text, slot: pasted?.slot ?? .forNow())
                .environment(\.foodLoggingDate, selectedTimestamp)
        }
        #if DEBUG
        .task {
            let args = ProcessInfo.processInfo.arguments
            if args.contains("-previewFoodMethods") { pickedSlot = .forNow() }
            if args.contains("-previewFoodChat") { adding = FoodAddStart(mode: .describe, slot: .forNow()) }
            if args.contains("-previewFoodSearch") { adding = FoodAddStart(mode: .search, slot: .forNow()) }
        }
        #endif
        .onChange(of: pickedSlot) { _, slot in
            if slot != nil { withAnimation(.snappy) { proxy.scrollTo("logTop", anchor: .top) } }
        }
        }
    }

    private var dayTitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(selectedDay) { return String(localized: "Today") }
        if calendar.isDateInYesterday(selectedDay) { return String(localized: "Yesterday") }
        if calendar.isDateInTomorrow(selectedDay) { return String(localized: "Tomorrow") }
        return selectedDay.formatted(.dateTime.weekday(.wide))
    }

    private func changeDay(_ offset: Int) {
        guard !batchBusy else { return }
        selectedDay = FoodLogDate.shifted(selectedDay, by: offset)
        pickedSlot = nil
        UISelectionFeedbackGenerator().selectionChanged()
    }

    private var dayNavigator: some View {
        VStack(spacing: 2) {
            HStack {
                Button { changeDay(-1) } label: {
                    Image(systemName: "chevron.left").frame(width: 44, height: 44)
                }.accessibilityLabel("Previous day")
                Spacer()
                VStack(spacing: 2) {
                    Text(dayTitle).font(.headline)
                    Text(selectedDay.formatted(.dateTime.day().month(.wide).year()))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .accessibilityElement(children: .combine)
                Spacer()
                Button { changeDay(1) } label: {
                    Image(systemName: "chevron.right").frame(width: 44, height: 44)
                }.accessibilityLabel("Next day")
            }
            HStack(spacing: 12) {
                Text("Swipe this bar to change day").font(.caption2).foregroundStyle(Theme.textTertiary)
                if !Calendar.current.isDateInToday(selectedDay) {
                    Button("Today") { selectedDay = Date(); pickedSlot = nil }
                        .font(.caption.weight(.semibold)).padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 16).padding(.bottom, 6)
        .background(Theme.background)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            guard abs(value.translation.width) > 60,
                  abs(value.translation.width) > abs(value.translation.height) * 1.5 else { return }
            changeDay(value.translation.width < 0 ? 1 : -1)
        })
        .disabled(batchBusy)
    }

    /// Recipe ideas sized to what's left of today's calories and macros.
    private var mealIdeasRow: some View {
        let goal = GoalSettings.load()
        let slot = pickedSlot ?? MealSlot.forNow()
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            let metrics = days.first { Calendar.current.isDate($0.date, inSameDayAs: selectedDay) }
            let targets = EnergyModel.maintenance(from: days, profile: BodyProfile.load())
                .map { EnergyModel.targets(from: days, maintenance: $0) }
            recipeRequest = RecipeRequest(
                slot: slot, goal: goal,
                remainingCalories: targets.map { $0.calories - (metrics?.dietaryEnergyKcal ?? today.reduce(0) { $0 + $1.kcal }) },
                remainingProtein: targets.map { $0.proteinGrams - (metrics?.proteinGrams ?? today.reduce(0) { $0 + $1.protein }) },
                remainingCarbs: targets.map { $0.carbsGrams - (metrics?.carbsGrams ?? today.reduce(0) { $0 + $1.carbs }) },
                remainingFat: targets.map { $0.fatGrams - (metrics?.fatGrams ?? today.reduce(0) { $0 + $1.fat }) })
        } label: {
            HStack(spacing: 13) {
                GlyphTile(glyph: .recipe)
                    .overlay(alignment: .topTrailing) {
                        GeminiMark(size: 13)
                            .padding(2)
                            .background(Circle().fill(Theme.surface))
                            .offset(x: 5, y: -5)
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Meal ideas for \(slot.label.lowercased())")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Recipes sized to what's left on this day, for your \(goal.phase.label.lowercased()) goal.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
            .card()
        }
        .buttonStyle(.plain)
    }

    /// One tap logs the whole saved meal into whichever slot fits now.
    private var savedMealsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(savedMeals) { meal in
                    Button {
                        Task { await logSavedMeal(meal) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 5) {
                                if loggingSavedMeal?.id == meal.id { ProgressView().controlSize(.mini) }
                                Text(meal.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            }
                            Text("\(DetailFormat.safeInt(meal.totalKcal)) kcal · \(meal.items.count) foods")
                                .font(.system(size: 11)).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .foregroundStyle(Theme.textPrimary)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(batchBusy)
                    .contextMenu {
                        ForEach(MealSlot.allCases) { slot in
                            Button(slot.label) { Task { await logSavedMeal(meal, slot: slot) } }
                        }
                        Button("Delete", systemImage: "trash", role: .destructive) { deletingSavedMeal = meal }
                    }
                }
            }
            .padding(.horizontal, 2)
        }
        .confirmationDialog("Delete this saved meal?", isPresented: Binding(get: { deletingSavedMeal != nil }, set: { if !$0 { deletingSavedMeal = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let meal = deletingSavedMeal { context.delete(meal) }
                deletingSavedMeal = nil
            }
        }
    }

    private func logSavedMeal(_ meal: SavedMeal, slot: MealSlot? = nil) async {
        guard !batchBusy else { return }
        let slot = slot ?? pickedSlot ?? MealSlot.forNow()
        let logDate = selectedTimestamp
        loggingSavedMeal = meal
        defer { loggingSavedMeal = nil }
        var saved = 0
        var issue: String?
        var skipped = Set<String>()
        let lines = meal.items
        for line in lines {
            do {
                try await FoodLogger.log(line.food, grams: line.grams, slot: slot, at: logDate, context: context)
                saved += 1
                skipped.formUnion(FoodLogger.lastSkipped)
            } catch { issue = error.localizedDescription }
        }
        reportMealSave(saved: saved, total: lines.count, skipped: skipped, issue: issue)
    }

    /// Four meal chips in the order that fits the time of day. Tapping one
    /// reveals the ways to log into it; tapping it again hides them.
    private var slotPicker: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                count: dynamicTypeSize.isAccessibilitySize ? 1 : 2), spacing: 8) {
            ForEach(orderedSlots) { slot in
                let kcal = today.filter { $0.slot == slot }.reduce(0) { $0 + $1.kcal }
                let isPicked = pickedSlot == slot
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.snappy) { pickedSlot = isPicked ? nil : slot }
                } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 6) {
                        Text(slot.label)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                        Text(kcal > 0 ? "\(DetailFormat.safeInt(kcal)) kcal" : String(localized: "Add"))
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isPicked ? "minus.circle" : "plus.circle")
                            .font(.title3).foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity, minHeight: 58)
                    .padding(.vertical, 14)
                    .foregroundStyle(Theme.textPrimary)
                    .background(isPicked ? Theme.surfaceRaised : Theme.surface,
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(isPicked ? Theme.accent.opacity(0.35) : Theme.border, lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isPicked ? .isSelected : [])
            }
        }
    }

    /// All the ways to log into the picked meal, as one compact row.
    private func actionRow(_ slot: MealSlot) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6),
                                 count: dynamicTypeSize.isAccessibilitySize ? 2 : 3), spacing: 16) {
            action("Search", "magnifyingglass", .search, slot)
            action("Scan", "barcode.viewfinder", .barcode, slot)
            action("Describe", "text.bubble", .describe, slot, ai: true)
            action("Manual", "square.and.pencil", .manual, slot)
            action("Photo", "camera.viewfinder", .photo, slot, ai: true)
            action("Recipes", "book.closed", .myFoods, slot)
        }
    }

    private func action(_ title: LocalizedStringKey, _ icon: String, _ mode: FoodAddStart.Mode, _ slot: MealSlot, ai: Bool = false) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            adding = FoodAddStart(mode: mode, slot: slot)
            pickedSlot = nil
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 48, height: 48)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        if ai {
                            GeminiMark(size: 12)
                                .padding(2)
                                .background(Theme.surface, in: Circle())
                                .offset(x: 2, y: -2)
                        }
                    }
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func row(_ entry: FoodEntry) -> some View {
        let item = entry.item
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: entry.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if item?.isVerified == true { VerifiedTick() }
                }
                Text(verbatim: [entry.brand, entryAmount(entry),
                                entry.date.formatted(date: .omitted, time: .shortened)].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(DetailFormat.safeInt(entry.kcal)) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                MacroLine(protein: entry.protein, carbs: entry.carbs, fat: entry.fat)
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func entryAmount(_ entry: FoodEntry) -> String {
        if let density = entry.item?.density {
            return "\(DetailFormat.decimal(entry.grams / density)) ml"
        }
        return "\(DetailFormat.decimal(entry.grams)) g"
    }

    private func delete(_ entry: FoodEntry) {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        Task { await FoodLogger.delete(entry, context: context) }
    }
}

/// "P 24 · C 40 · F 9" in the macro colours.
struct MacroLine: View {
    let protein: Double
    let carbs: Double
    let fat: Double

    var body: some View {
        HStack(spacing: 6) {
            part("P", protein, Theme.protein)
            part("C", carbs, Theme.carbs)
            part("F", fat, Theme.fat)
        }
        .font(.caption2.weight(.medium))
        .monospacedDigit()
    }

    private func part(_ letter: String, _ value: Double, _ color: Color) -> some View {
        Text(verbatim: "\(letter) \(DetailFormat.safeInt(value))").foregroundStyle(color)
    }
}

// MARK: - Add sheet

struct FoodAddStart: Identifiable {
    enum Mode {
        case search, barcode, photo, myFoods, describe, manual
        case edit(FoodEntry)
    }

    let id = UUID()
    let mode: Mode
    let slot: MealSlot
}

enum FoodRoute: Hashable {
    case amount(FoodItem)
    case search(String)
    case newFood(barcode: String?)
    case editFood(UserFood)
    case recipe(UserFood?)
}

struct FoodAddSheet: View {
    @Environment(\.foodLoggingDate) private var loggingDate
    let start: FoodAddStart

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var path: [FoodRoute] = []
    @State private var slot: MealSlot
    /// Foods collected so far, logged together.
    @State private var meal: [MealLine] = []
    @State private var showsMeal = false
    @State private var logging = false
    @State private var logError: String?
    @State private var skippedNote: String?
    @State private var saveAsMeal = false
    @State private var savedMealName = ""
    @State private var confirmsDiscard = false
    @State private var savedMealRecorded = false

    struct MealLine: Identifiable {
        let id = UUID()
        let item: FoodItem
        var grams: Double
        var date: Date
    }

    init(start: FoodAddStart) {
        self.start = start
        _slot = State(initialValue: start.slot)
    }

    private var isChat: Bool { if case .describe = start.mode { true } else { false } }
    private var isEditing: Bool { if case .edit = start.mode { true } else { false } }
    private var onAmountScreen: Bool { if case .amount = path.last { true } else { false } }
    private var mealKcal: Double { meal.reduce(0) { $0 + $1.item.amount($1.grams).kcal } }

    var body: some View {
        NavigationStack(path: $path) {
            root
                .safeAreaInset(edge: .top, spacing: 0) { loggingDateBanner }
                .disabled(logging)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") {
                            if meal.isEmpty { dismiss() } else { confirmsDiscard = true }
                        }
                        .disabled(logging)
                    }
                }
                .navigationDestination(for: FoodRoute.self) { route in
                    Group {
                    switch route {
                    case .amount(let item):
                        FoodAmountView(item: item, slot: $slot, onAddToMeal: addToMeal, onDone: finish)
                    case .search(let query):
                        FoodSearchScreen(initialQuery: query) { path.append(.amount($0)) }
                    case .newFood(let barcode):
                        CustomFoodEditor(existing: nil, barcode: barcode) { path = [.amount($0)] }
                    case .editFood(let food):
                        CustomFoodEditor(existing: food, barcode: food.barcode) { _ in path.removeLast() }
                    case .recipe(let food):
                        RecipeEditorView(existing: food) { item in
                            if food == nil { path = [.amount(item)] } else { path.removeLast() }
                        }
                    }
                    }
                    .safeAreaInset(edge: .top, spacing: 0) { loggingDateBanner }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if !meal.isEmpty && !onAmountScreen && !isEditing {
                mealBar
            }
        }
        .interactiveDismissDisabled(logging || !meal.isEmpty)
        .confirmationDialog("Discard this meal?", isPresented: $confirmsDiscard, titleVisibility: .visible) {
            Button("Discard meal", role: .destructive) { dismiss() }
            Button("Keep logging", role: .cancel) {}
        } message: {
            Text("The foods in this basket have not been logged yet.")
        }
        .sheet(isPresented: $showsMeal) {
            mealReview
                .interactiveDismissDisabled(logging)
                .presentationDetents([.medium, .large])
        }
        .alert("Logged", isPresented: Binding(get: { skippedNote != nil }, set: { if !$0 { skippedNote = nil; dismiss() } })) {
            Button("OK") {}
        } message: {
            Text(skippedNote ?? "")
        }
        .tint(Theme.accent)
    }

    // Keep the date inside each page's safe area, below the navigation bar.
    // An inset around NavigationStack itself displaces/clips the sheet header.
    @ViewBuilder
    private var loggingDateBanner: some View {
        if let loggingDate, !isEditing, !isChat {
            Text("Logging for \(loggingDate.formatted(date: .abbreviated, time: .omitted))")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Theme.background)
        }
    }

    @ViewBuilder
    private var root: some View {
        switch start.mode {
        case .search:
            FoodSearchScreen(initialQuery: "") { path.append(.amount($0)) }
        case .barcode:
            BarcodeFoodScreen(path: $path)
        case .photo:
            PhotoFoodScreen(slot: slot, path: $path)
        case .myFoods:
            MyFoodsScreen(path: $path)
        case .describe:
            FoodChatView()
        case .manual:
            ManualFoodScreen { item, grams in addToMeal(item, grams, loggingDate ?? Date()) }
        case .edit(let entry):
            if let item = entry.item {
                FoodAmountView(item: item, slot: $slot, replacing: entry, onDone: finish)
            } else {
                ContentUnavailableView("This entry can't be edited", systemImage: "exclamationmark.triangle")
            }
        }
    }

    private func addToMeal(_ item: FoodItem, _ grams: Double, _ date: Date) {
        withAnimation(.snappy) { meal.append(MealLine(item: item, grams: grams, date: date)) }
        // Back to the list or scanner, ready for the next food.
        if onAmountScreen { path.removeLast() }
    }

    // MARK: Meal being built

    private var mealBar: some View {
        HStack(spacing: 12) {
            Button { showsMeal = true } label: {
                HStack(spacing: 10) {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "fork.knife")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.white.opacity(0.18), in: Circle())
                        Text(verbatim: "\(meal.count)")
                            .font(.system(size: 11, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(Theme.onAction)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(.white, in: Circle())
                            .offset(x: 4, y: -4)
                    }
                    VStack(alignment: .leading, spacing: 0) {
                        Text(meal.count == 1 ? "1 food" : "\(meal.count) foods").font(.subheadline.weight(.semibold))
                        Text("\(DetailFormat.safeInt(mealKcal)) kcal · tap to review").font(.caption).opacity(0.85)
                    }
                }
            }
            .buttonStyle(.plain)
            Spacer(minLength: 8)
            Button {
                Task { await logMeal() }
            } label: {
                Group {
                    if logging { ProgressView().tint(Theme.accent) } else { Text("Log \(slot.label.lowercased())").font(.subheadline.weight(.bold)) }
                }
                .foregroundStyle(Theme.onAction)
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
                .background(Theme.actionFill, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(logging)
        }
        .foregroundStyle(Theme.textPrimary)
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private var mealReview: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Meal", selection: $slot) {
                        ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    ForEach($meal) { $line in
                        HStack(spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text(verbatim: line.item.name).font(.subheadline).lineLimit(2)
                                    if line.item.isPersonal { PersonalBadge() }
                                }
                                let a = line.item.amount(line.grams)
                                MacroLine(protein: a.protein, carbs: a.carbs, fat: a.fat)
                                if let warning = line.item.plausibilityWarning {
                                    Label(warning, systemImage: "exclamationmark.triangle")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.warn)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                HStack(spacing: 2) {
                                    LiveNumberField("0", value: Binding(
                                        get: { line.item.isLiquid ? line.grams / (line.item.density ?? 1) : line.grams },
                                        set: { line.grams = line.item.isLiquid ? $0 * (line.item.density ?? 1) : $0 }))
                                        .multilineTextAlignment(.trailing)
                                        .monospacedDigit()
                                        .frame(width: 60)
                                    Text(verbatim: line.item.isLiquid ? "ml" : "g").foregroundStyle(Theme.textTertiary)
                                }
                                Text("\(DetailFormat.safeInt(line.item.amount(line.grams).kcal)) kcal")
                                    .font(.caption.weight(.semibold)).monospacedDigit()
                            }
                        }
                    }
                    .onDelete { meal.remove(atOffsets: $0) }
                } header: {
                    Text("\(DetailFormat.safeInt(mealKcal)) kcal")
                } footer: {
                    Text("Swipe to remove. Everything is logged together when you tap Log.")
                }
                Section {
                    Toggle(isOn: $saveAsMeal) {
                        Text("Save as a meal I can log again")
                    }
                    .tint(Theme.accent)
                    if saveAsMeal {
                        TextField("Name, e.g. Usual breakfast", text: $savedMealName)
                    }
                } footer: {
                    if saveAsMeal {
                        Text("Saved separately from today's log, so you can add it again in one tap another day.")
                    }
                }
                if let logError {
                    Section { Text(logError).font(.footnote).foregroundStyle(Theme.bad) }
                }
            }
            .disabled(logging)
            .navigationTitle("This meal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Add more") { showsMeal = false }.disabled(logging)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { Task { await logMeal() } }
                        .fontWeight(.semibold)
                        .disabled(meal.isEmpty || logging || (saveAsMeal && savedMealName.trimmingCharacters(in: .whitespaces).isEmpty))
                }
            }
        }
        .tint(Theme.accent)
    }

    private func logMeal() async {
        guard !meal.isEmpty, !logging else { return }
        logging = true
        logError = nil
        defer { logging = false }
        if saveAsMeal && !savedMealRecorded {
            let trimmed = savedMealName.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty {
                let items = meal.map { RecipeIngredient(food: $0.item, grams: $0.grams) }
                let savedMeal = SavedMeal(name: trimmed, items: items)
                context.insert(savedMeal)
                do {
                    try context.save()
                    savedMealRecorded = true
                } catch {
                    context.delete(savedMeal)
                    logError = error.localizedDescription
                    showsMeal = true
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    return
                }
            }
        }
        var skipped = Set<String>()
        while let line = meal.first {
            do {
                try await FoodLogger.log(line.item, grams: line.grams, slot: slot, at: line.date, context: context)
                skipped.formUnion(FoodLogger.lastSkipped)
                meal.removeFirst()
            } catch {
                logError = error.localizedDescription
                showsMeal = true
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
        }
        showsMeal = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        if skipped.isEmpty {
            dismiss()
        } else {
            skippedNote = String(localized: "Saved, but Apple Health isn't allowed to store \(skipped.sorted().joined(separator: ", ")). Turn it on in Settings → Health → Data Access & Devices → Trace.")
        }
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        dismiss()
    }
}

// MARK: - Amount

struct FoodAmountView: View {
    @Environment(\.foodLoggingDate) private var loggingDate
    let item: FoodItem
    @Binding var slot: MealSlot
    var replacing: FoodEntry? = nil
    /// When set (adding, not editing), the button collects the food into the
    /// meal being built instead of logging it on its own.
    var onAddToMeal: ((FoodItem, Double, Date) -> Void)? = nil
    let onDone: () -> Void

    @Environment(\.modelContext) private var context
    @State private var grams: Double = 100
    @State private var date = Date()
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var amountFocused: Bool
    @State private var byPortion = false
    @State private var portionSize: FoodPortion.Size = .medium
    @State private var count = 1
    @State private var inMl = false

    private var amount: FoodItem.Amount { item.amount(grams) }
    private var portions: [FoodPortion] { item.portions }
    private var selectedPortion: FoodPortion? { portions.first { $0.size == portionSize } }
    private var density: Double { item.density ?? 1 }

    /// The typed amount, in whichever unit is showing.
    private var shownAmount: Binding<Double> {
        Binding(get: { inMl ? grams / density : grams },
                set: { grams = inMl ? $0 * density : $0 })
    }

    private func amountText(_ g: Double) -> String {
        inMl || (byPortion && item.isLiquid) ? "\(DetailFormat.decimal(g / density)) ml" : "\(DetailFormat.decimal(g)) g"
    }

    private func applyPortion() {
        guard byPortion, let p = selectedPortion else { return }
        withAnimation(.snappy) { grams = p.grams * Double(count) }
    }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        if let brand = item.brand {
                            Text(verbatim: brand).font(.caption.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                        }
                        if item.isPersonal { PersonalBadge() }
                    }
                    Text(verbatim: item.name).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                    if item.isLiquid {
                        Text("Per 100 ml: \(DetailFormat.safeInt(item.kcal * density)) kcal · per 100 g: \(DetailFormat.safeInt(item.kcal)) kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    } else {
                        Text("Per 100 g: \(DetailFormat.safeInt(item.kcal)) kcal · \(item.sourceLabel)")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    if let medium = portions.first(where: { $0.size == .medium }) {
                        Text("1 \(medium.name): \(DetailFormat.safeInt(item.amount(medium.grams).kcal)) kcal")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
                .padding(.vertical, 4)
            }

            if !portions.isEmpty {
                Section {
                    Picker("Measure", selection: $byPortion) {
                        Text("Servings").tag(true)
                        Text(item.isLiquid ? "Amount" : "Grams").tag(false)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: byPortion) { _, _ in applyPortion() }
                }
            }

            if byPortion, !portions.isEmpty {
                Section {
                    let portionLayout = portions.contains(where: { $0.custom })
                        ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                    portionLayout {
                        ForEach(portions) { portion in
                            portionButton(portion)
                        }
                    }
                    .padding(.vertical, 2)
                    Stepper(value: $count, in: 1...20) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(verbatim: "\(count) × \(selectedPortion?.unit ?? "")")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(3)
                            Text(verbatim: "= \(amountText(grams))")
                                .font(.caption).monospacedDigit()
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    .onChange(of: count) { _, _ in applyPortion() }
                } header: {
                    Text("Portion")
                } footer: {
                    Text(item.isLiquid ? "Typical serving sizes. Switch to Amount to enter ml or grams."
                                       : "Typical edible weights. Switch to grams if you weighed it.")
                }
            } else {
                Section {
                    HStack(alignment: .firstTextBaseline) {
                        LiveNumberField("Amount", value: shownAmount)
                            .focused($amountFocused)
                            .font(.system(size: 40, weight: .semibold))
                            .monospacedDigit()
                        if item.isLiquid {
                            Picker("Unit", selection: $inMl) {
                                Text(verbatim: "ml").tag(true)
                                Text(verbatim: "g").tag(false)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 100)
                        } else {
                            Text(verbatim: "g").font(.title3.weight(.medium)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            if let serving = item.servingGrams {
                                chip(String(localized: "1 serving · \(amountText(serving))"), serving)
                                if serving * 2 <= 1000 { chip(String(localized: "2 servings"), serving * 2) }
                            }
                            if inMl {
                                ForEach([100.0, 150, 200, 250, 330, 500], id: \.self) { chip("\(Int($0)) ml", $0 * density) }
                            } else {
                                ForEach([50.0, 100, 150, 200, 250, 300], id: \.self) { chip("\(Int($0)) g", $0) }
                            }
                        }
                    }
                } header: {
                    Text("Amount")
                } footer: {
                    if item.isLiquid {
                        Text("Nutrition data is per 100 g; ml is converted using this drink's density (\(density.formatted(.number.precision(.fractionLength(0...2)))) g per ml).")
                    }
                }
            }

            Section {
                HStack(spacing: 0) {
                    macroTile("kcal", amount.kcal, Theme.accent)
                    macroTile("Protein", amount.protein, Theme.protein)
                    macroTile("Carbs", amount.carbs, Theme.carbs)
                    macroTile("Fat", amount.fat, Theme.fat)
                }
                .padding(.vertical, 4)
                if let warning = item.plausibilityWarning {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }

            Section {
                Picker("Meal", selection: $slot) {
                    ForEach(MealSlot.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                DatePicker("Time", selection: $date)
            }

            if let error {
                Section { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
            }
        }
        .navigationTitle(replacing == nil ? "Add food" : "Edit entry")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            Button {
                if let onAddToMeal, replacing == nil {
                    amountFocused = false
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    onAddToMeal(item, grams, date)
                } else {
                    Task { await save() }
                }
            } label: {
                HStack {
                    if saving { ProgressView().tint(.white) }
                    if replacing != nil {
                        Text("Save changes").font(.headline)
                    } else if onAddToMeal != nil {
                        Label("Add to meal", systemImage: "plus").font(.headline)
                    } else {
                        Text("Add to \(slot.label.lowercased())").font(.headline)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(saving || grams <= 0)
            .opacity(grams <= 0 ? 0.5 : 1)
            .padding(.horizontal, 18)
            .padding(.bottom, 8)
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { amountFocused = false }
            }
        }
        .sensoryFeedback(.selection, trigger: slot)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            inMl = item.isLiquid
            date = loggingDate ?? Date()
            if let replacing {
                grams = replacing.grams
                date = replacing.date
                // Reopen in pieces when the amount is a whole number of one portion size.
                for portion in portions {
                    let n = replacing.grams / portion.grams
                    if abs(n - n.rounded()) < 0.01, n >= 1 {
                        byPortion = true; portionSize = portion.size; count = max(DetailFormat.safeInt(n), 1)
                        break
                    }
                }
            } else if !portions.isEmpty {
                byPortion = true
                applyPortion()
            } else {
                grams = item.servingGrams ?? 100
            }
        }
    }

    private func portionButton(_ portion: FoodPortion) -> some View {
        let selected = portion.size == portionSize
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            portionSize = portion.size
            applyPortion()
        } label: {
            Group {
                if portion.custom {
                    HStack(spacing: 12) {
                        Text(verbatim: portion.unit)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 4)
                        VStack(alignment: .trailing, spacing: 3) {
                            Text(verbatim: portion.amountLabel).font(.subheadline).monospacedDigit()
                            Text("\(DetailFormat.safeInt(item.amount(portion.grams).kcal)) kcal")
                                .font(.caption).monospacedDigit().opacity(0.8)
                        }
                        .fixedSize()
                    }
                    .padding(.horizontal, 12)
                } else {
                    VStack(spacing: 3) {
                        Text(verbatim: portion.ml == nil ? portion.size.label : portion.unit)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(verbatim: portion.amountLabel).font(.caption2).monospacedDigit().opacity(0.8)
                        Text("\(DetailFormat.safeInt(item.amount(portion.grams).kcal)) kcal")
                            .font(.caption2.weight(.medium)).monospacedDigit()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? .white : Theme.textPrimary)
            .background(selected ? Theme.accent : Theme.track, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.borderless)
    }

    private func chip(_ label: String, _ value: Double) -> some View {
        let selected = abs(grams - value) < 0.01
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.snappy) { grams = value }
        } label: {
            Text(verbatim: label)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .foregroundStyle(selected ? .white : Theme.textPrimary)
                .background(selected ? Theme.accent : Theme.track, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private func macroTile(_ label: LocalizedStringKey, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(DetailFormat.safeInt(value))")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText(value: value))
                .animation(.snappy, value: value)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func save() async {
        amountFocused = false
        saving = true
        error = nil
        defer { saving = false }
        do {
            try await FoodLogger.log(item, grams: grams, slot: slot, at: date, context: context)
            if let replacing { await FoodLogger.delete(replacing, context: context) }
            onDone()
        } catch {
            self.error = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

/// Marks foods you created yourself, so they're never mistaken for database values.
struct PersonalBadge: View {
    var body: some View {
        Label("Personal", systemImage: "person.fill")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.fat)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.fat.opacity(0.12), in: Capsule())
            .labelStyle(.titleAndIcon)
    }
}

/// Today's calories and macros, floating at the bottom of the food page.
struct FoodDayTotalsBar: View {
    let days: [DailyMetrics]
    var date: Date = Date()
    var loggedEntries: [FoodEntry] = []
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var today: DailyMetrics? { days.first { Calendar.current.isDate($0.date, inSameDayAs: date) } }
    private var targets: NutritionTargets? {
        EnergyModel.maintenance(from: days).map { EnergyModel.targets(from: days, maintenance: $0) }
    }

    var body: some View {
        let kcal = today?.dietaryEnergyKcal ?? loggedEntries.reduce(0) { $0 + $1.kcal }
        let t = targets
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    calorieSummary(kcal, target: t?.calories)
                    macroTotals(t)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        calorieSummary(kcal, target: t?.calories)
                        macroTotals(t).frame(minWidth: 180)
                    }
                    VStack(alignment: .leading, spacing: 12) {
                        calorieSummary(kcal, target: t?.calories)
                        macroTotals(t)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        .animation(reduceMotion ? nil : .snappy, value: kcal)
    }

    private func calorieSummary(_ kcal: Double, target: Double?) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().stroke(Theme.accent.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: max(min(kcal / max(target ?? 2500, 1), 1), 0))
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: "flame.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .frame(width: 32, height: 32)
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(DetailFormat.safeInt(kcal).formatted()) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                Text(Calendar.current.isDateInToday(date) ? "Eaten today" : "Logged for this day")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .combine)
    }

    private func macroTotals(_ targets: NutritionTargets?) -> some View {
        HStack(spacing: 12) {
            macro("P", name: "Protein", today?.proteinGrams ?? loggedEntries.reduce(0) { $0 + $1.protein }, targets?.proteinGrams, Theme.protein)
            macro("C", name: "Carbs", today?.carbsGrams ?? loggedEntries.reduce(0) { $0 + $1.carbs }, targets?.carbsGrams, Theme.carbs)
            macro("F", name: "Fat", today?.fatGrams ?? loggedEntries.reduce(0) { $0 + $1.fat }, targets?.fatGrams, Theme.fat)
        }
    }

    private func macro(_ letter: String, name: LocalizedStringKey, _ grams: Double, _ target: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(verbatim: letter).font(.caption2.weight(.bold)).foregroundStyle(color)
                Text("\(DetailFormat.safeInt(grams)) g")
                    .font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                    .contentTransition(.numericText())
            }
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(color.opacity(0.18))
                    Capsule().fill(color)
                        .frame(width: max(0, geo.size.width * min(max(grams, 0) / max(target ?? 150, 1), 1)))
                }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(name))
        .accessibilityValue(Text("\(DetailFormat.safeInt(grams)) g"))
    }
}
