//
//  FoodSourceScreens.swift
//  RecoverySignal2
//
//  The ways to find a food: search, barcode, photo, and your own foods and
//  recipes — plus the editors for creating them.
//

import SwiftUI
import SwiftData
import PhotosUI
import VisionKit
import Vision

// MARK: - Search

struct FoodSearchScreen: View {
    var initialQuery: String
    let onPick: (FoodItem) -> Void

    /// Recent entries only — "recents" needs the last 20 distinct foods, not
    /// every entry ever logged.
    @Query private var history: [FoodEntry]

    init(initialQuery: String, onPick: @escaping (FoodItem) -> Void) {
        self.initialQuery = initialQuery
        self.onPick = onPick
        let cutoff = Calendar.current.date(byAdding: .day, value: -60, to: Date()) ?? .distantPast
        _history = Query(filter: #Predicate<FoodEntry> { $0.date >= cutoff }, sort: \FoodEntry.date, order: .reverse)
    }
    @Query(sort: \UserFood.createdAt, order: .reverse) private var userFoods: [UserFood]
    @State private var query = ""
    @State private var products: [FoodItem] = []
    @State private var loadingProducts = false
    @State private var productError: String?
    @State private var started = false
    @State private var scope: SearchScope = .all
    @State private var retryCount = 0
    @State private var activeRequest = UUID()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private enum SearchScope: String, CaseIterable, Identifiable {
        case all, foods, products, mine
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .all: "All"
            case .foods: "Foods"
            case .products: "Products"
            case .mine: "Mine"
            }
        }
    }

    private struct SearchRequest: Hashable {
        let query: String
        let scope: SearchScope
        let retry: Int
    }

    private var searchTerm: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var showsMine: Bool { scope == .all || scope == .mine }
    private var showsFoods: Bool { scope == .all || scope == .foods }
    private var showsProducts: Bool { scope == .all || scope == .products }

    /// A plain loop, not a lazy chain: `.lazy.filter` is allowed to invoke its
    /// predicate more than once per element, and this predicate mutates a
    /// captured `seen` set — with a big enough history that combination once
    /// corrupted the sequence's own count bookkeeping badly enough to crash
    /// outright (`Range requires lowerBound <= upperBound`) rather than just
    /// mis-dedupe. A single-pass loop can't have that problem.
    private var recents: [FoodItem] {
        var seen: Set<String> = []
        var result: [FoodItem] = []
        for entry in history {
            guard let item = entry.item, seen.insert(item.id).inserted else { continue }
            result.append(item)
            if result.count >= 20 { break }
        }
        return result
    }

    /// Local matches for the current query, refreshed once per keystroke
    /// (after a short pause) rather than on every redraw of the list.
    @State private var local: [FoodItem] = []

    private var mine: [FoodItem] {
        let documents = userFoods.map { SmartSearch.Document(id: $0.id, name: $0.name, extra: [$0.brand ?? ""]) }
        let byID = Dictionary(userFoods.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return SmartSearch.rank(query: query, in: documents, limit: 30).compactMap { byID[$0.id]?.item }
    }

    var body: some View {
        List {
            Section {
                if dynamicTypeSize.isAccessibilitySize {
                    sourcePicker.pickerStyle(.menu)
                } else {
                    sourcePicker.pickerStyle(.segmented)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            if searchTerm.isEmpty {
                if showsMine && !userFoods.isEmpty {
                    Section("My foods & recipes") {
                        ForEach(userFoods.prefix(scope == .mine ? userFoods.count : 8).map(\.item)) { row($0) }
                    }
                }
                if scope == .all || scope == .foods {
                    Section("Recent") {
                        let recentFoods = recents.filter { scope != .foods || $0.source != .product }
                        if recentFoods.isEmpty {
                            Text("Foods you log show up here for quick re-adding.")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(recentFoods) { row($0) }
                    }
                } else if scope == .products {
                    Text("Search by brand or product name. Packaged foods need an internet connection.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                } else if userFoods.isEmpty {
                    Text("Your saved personal foods and recipes will appear here.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } else {
                if showsMine && (!mine.isEmpty || scope == .mine) {
                    Section("My foods & recipes") {
                        if mine.isEmpty {
                            Text("No personal foods match this search.")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(mine) { row($0) }
                    }
                }
                if showsFoods {
                    Section {
                        if local.isEmpty {
                            Text("No generic food matches. Try English or German, e.g. “Poulet” or “chicken”.")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(local) { row($0) }
                    } header: {
                        HStack {
                            Text("Food database")
                            Spacer()
                            Label("Available offline", systemImage: "checkmark.circle")
                                .textCase(nil)
                        }
                        .font(.caption.weight(.semibold))
                    }
                }
                if showsProducts {
                    Section("Products") {
                        if loadingProducts {
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Searching products…").font(.footnote).foregroundStyle(Theme.textSecondary)
                            }
                        } else if productError != nil {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Product search is unavailable. You can still use the offline food database.")
                                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                                Button("Try again", systemImage: "arrow.clockwise") { retryCount += 1 }
                                    .font(.subheadline.weight(.medium))
                            }
                        } else if searchTerm.count < 3 {
                            Text("Type at least 3 characters to search products.")
                                .font(.footnote).foregroundStyle(Theme.textSecondary)
                        } else if products.isEmpty {
                            Text("No products found.").font(.footnote).foregroundStyle(Theme.textSecondary)
                        }
                        ForEach(products) { row($0) }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(16)
        .contentMargins(.top, 12, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Food, brand or product")
        .scrollDismissesKeyboard(.interactively)
        .autocorrectionDisabled()
        .sensoryFeedback(.selection, trigger: scope)
        .onAppear {
            guard !started else { return }
            started = true
            query = initialQuery
            #if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-previewFoodQuery"), index + 1 < args.count {
                query = args[index + 1]
            }
            #endif
        }
        .task(id: searchTerm) {
            let term = searchTerm
            guard !term.isEmpty else { local = []; return }
            // Let the keystroke land before searching, so typing never waits on it.
            try? await Task.sleep(for: .milliseconds(90))
            guard !Task.isCancelled else { return }
            local = SwissFoodDatabase.search(term, limit: 30)
        }
        .task(id: SearchRequest(query: searchTerm, scope: scope, retry: retryCount)) { await searchProducts() }
    }

    private var sourcePicker: some View {
        Picker("Food source", selection: $scope) {
            ForEach(SearchScope.allCases) { Text($0.label).tag($0) }
        }
    }

    private func row(_ item: FoodItem) -> some View {
        Button { onPick(item) } label: { FoodItemRow(item: item) }
            .buttonStyle(.plain)
    }

    private func searchProducts() async {
        let request = UUID()
        activeRequest = request
        let q = searchTerm
        products = PolishProductDatabase.search(q)
        productError = nil
        loadingProducts = false
        guard showsProducts, q.count >= 3 else { return }
        loadingProducts = true
        // A cancelled request must not clear a newer request's loading state.
        defer { if activeRequest == request { loadingProducts = false } }
        do {
            try await Task.sleep(for: .milliseconds(700))
            try Task.checkCancellation()
            let found = try await OpenFoodFacts().search(q)
            guard !Task.isCancelled, activeRequest == request else { return }
            let liveIDs = Set(found.map(\.id))
            products = PolishProductDatabase.search(q).filter { !liveIDs.contains($0.id) } + found
        } catch {
            guard !Task.isCancelled, activeRequest == request else { return }
            productError = error.localizedDescription
        }
    }

}

struct FoodItemRow: View {
    let item: FoodItem

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(verbatim: item.name)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    if item.isVerified { VerifiedTick() }
                }
                if item.isPersonal { PersonalBadge() }
                Text(verbatim: [item.brand, item.sourceLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                if let medium = item.portions.first(where: { $0.size == .medium }) {
                    Text("1 \(medium.name) ≈ \(DetailFormat.safeInt(item.amount(medium.grams).kcal)) kcal")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(DetailFormat.safeInt(item.kcal * (item.density ?? 1))) kcal")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.textPrimary)
                Text(item.isLiquid ? "per 100 ml" : "per 100 g").font(.caption2).foregroundStyle(Theme.textTertiary)
            }
        }
        .contentShape(Rectangle())
    }
}

// MARK: - Barcode

struct BarcodeFoodScreen: View {
    @Binding var path: [FoodRoute]

    @Query private var userFoods: [UserFood]
    @State private var code: String?
    @State private var looking = false
    @State private var notFound = false
    @State private var error: String?
    @State private var manualCode = ""
    @State private var scannerKey = UUID()

    private var canScan: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }

    var body: some View {
        List {
            Section {
                ZStack {
                    if canScan {
                        BarcodeScanner { found in
                            guard code == nil else { return }
                            Task { await lookUp(found) }
                        }
                        .id(scannerKey)
                    } else {
                        ContentUnavailableView("Camera unavailable", systemImage: "barcode.viewfinder",
                                               description: Text("Type the number under the barcode instead."))
                    }
                    if looking {
                        ProgressView().controlSize(.large).padding(20).background(.thinMaterial, in: Circle())
                    }
                }
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            } footer: {
                Text("Point the camera at the barcode. Works best with packaged foods sold in Switzerland.")
            }

            if notFound, let code {
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Not in the database yet").font(.headline)
                        Text("Barcode \(code). Add it once from the nutrition label and it'll be found next time.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                    Button("Add from the nutrition label", systemImage: "text.viewfinder") {
                        path.append(.newFood(barcode: code))
                    }
                    Button("Scan another", systemImage: "arrow.clockwise") { reset() }
                }
            }

            if let error {
                Section {
                    Text(error).font(.footnote).foregroundStyle(Theme.bad)
                    Button("Try again", systemImage: "arrow.clockwise") { reset() }
                }
            }

            Section("Type the barcode") {
                HStack {
                    TextField("e.g. 7610900126941", text: $manualCode)
                        .keyboardType(.numberPad)
                    Button("Look up") { Task { await lookUp(manualCode) } }
                        .disabled(manualCode.count < 8 || looking)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Scan barcode")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Coming back from the amount screen: ready for the next pack.
            if code != nil && !notFound && error == nil { reset() }
        }
    }

    private func reset() {
        code = nil
        notFound = false
        error = nil
        scannerKey = UUID()
    }

    private func lookUp(_ raw: String) async {
        let barcode = raw.filter(\.isNumber)
        guard !barcode.isEmpty, !looking else { return }
        code = barcode
        notFound = false
        error = nil
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        if let mine = userFoods.first(where: { $0.barcode == barcode }) {
            path.append(.amount(mine.item))
            return
        }
        looking = true
        defer { looking = false }
        do {
            if let item = try await OpenFoodFacts().product(barcode: barcode) {
                path.append(.amount(item))
            } else {
                notFound = true
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// The system live barcode scanner.
struct BarcodeScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isHighlightingEnabled: true)
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ scanner: DataScannerViewController, context: Context) {
        context.coordinator.onCode = onCode
        if !scanner.isScanning { try? scanner.startScanning() }
    }

    static func dismantleUIViewController(_ scanner: DataScannerViewController, coordinator: Coordinator) {
        scanner.stopScanning()
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onCode: (String) -> Void
        private var fired = false

        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !fired else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let value = barcode.payloadStringValue {
                    fired = true
                    onCode(value)
                    return
                }
            }
        }
    }
}

// MARK: - Photo

struct PhotoFoodScreen: View {
    let slot: MealSlot
    @Binding var path: [FoodRoute]

    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var guesses: [FoodRecognizer.Guess] = []
    @State private var recognising = false
    @State private var showCamera = false
    @State private var geminiRequest: RecipeRequest?

    var body: some View {
        List {
            Section {
                VStack(spacing: 12) {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(height: 200)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    HStack(spacing: 10) {
                        Button { showCamera = true } label: {
                            Label("Camera", systemImage: "camera.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            Label("Library", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .controlSize(.large)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } footer: {
                Text(FoodRecognizer.usesCustomModel
                     ? "Recognised on your phone by your own trained model — the photo isn't uploaded."
                     : "Recognised on your phone — the photo isn't uploaded. Pick the closest match, then set the amount.")
            }

            if recognising {
                Section { HStack { ProgressView(); Text("Recognising…").foregroundStyle(Theme.textSecondary) } }
            } else if image != nil {
                if guesses.isEmpty {
                    Section {
                        Text("Couldn't recognise a food. Try a closer photo, search, or analyse it in detail.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }
                ForEach(guesses) { guess in
                    Section {
                        ForEach(guess.matches) { item in
                            Button { path.append(.amount(item)) } label: { FoodItemRow(item: item) }
                                .buttonStyle(.plain)
                        }
                        Button("Search for “\(guess.label)”", systemImage: "magnifyingglass") {
                            path.append(.search(guess.label))
                        }
                        .font(.subheadline)
                    } header: {
                        Text(verbatim: "\(guess.label.capitalized) · \(DetailFormat.safeInt(guess.confidence * 100))%")
                    }
                }
            }

            Section {
                Button {
                    let goal = GoalSettings.load()
                    geminiRequest = RecipeRequest(slot: slot, goal: goal, remainingCalories: nil,
                                                  remainingProtein: nil, remainingCarbs: nil, remainingFat: nil)
                } label: {
                    HStack(spacing: 12) {
                        GeminiMark(size: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Analyse in detail").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Text("For mixed plates: describe the meal and Gemini estimates each part.")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Theme.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Photo")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let picked = UIImage(data: data) else { return }
                await recognise(picked)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured in
                showCamera = false
                if let captured { Task { await recognise(captured) } }
            }
            .ignoresSafeArea()
        }
        .sheet(item: $geminiRequest) { MealScanView(remaining: $0) }
    }

    private func recognise(_ picked: UIImage) async {
        image = picked
        guesses = []
        recognising = true
        guesses = await FoodRecognizer.recognise(picked)
        recognising = false
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

// MARK: - My foods

struct MyFoodsScreen: View {
    @Binding var path: [FoodRoute]

    @Environment(\.modelContext) private var context
    @Query(sort: \UserFood.name) private var foods: [UserFood]

    var body: some View {
        List {
            Section {
                Button("New recipe", systemImage: "book.closed") { path.append(.recipe(nil)) }
                Button("New food from a label", systemImage: "text.viewfinder") { path.append(.newFood(barcode: nil)) }
            }
            section("Recipes", foods.filter(\.isRecipe))
            section("My foods", foods.filter { !$0.isRecipe })
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My recipes")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func section(_ title: LocalizedStringKey, _ list: [UserFood]) -> some View {
        if !list.isEmpty {
            Section(title) {
                ForEach(list) { food in
                    FoodItemRow(item: food.item)
                        .contentShape(Rectangle())
                        .onTapGesture { path.append(.amount(food.item)) }
                        .swipeActions {
                            Button(role: .destructive) { context.delete(food) } label: { Label("Delete", systemImage: "trash") }
                            Button { edit(food) } label: { Label("Edit", systemImage: "pencil") }.tint(Theme.accent)
                        }
                        .contextMenu {
                            Button("Edit", systemImage: "pencil") { edit(food) }
                            Button("Delete", systemImage: "trash", role: .destructive) { context.delete(food) }
                        }
                }
            }
        }
    }

    private func edit(_ food: UserFood) {
        path.append(food.isRecipe ? .recipe(food) : .editFood(food))
    }
}

// MARK: - Custom food (from a label)

struct CustomFoodEditor: View {
    let existing: UserFood?
    let barcode: String?
    let onSaved: (FoodItem) -> Void

    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var brand = ""
    @State private var kcal: Double?
    @State private var protein: Double?
    @State private var carbs: Double?
    @State private var fat: Double?
    @State private var serving: Double?
    @State private var loaded = false
    @State private var showCamera = false
    @State private var photoItem: PhotosPickerItem?
    @State private var reading = false
    @State private var labelMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
                TextField("Brand (optional)", text: $brand)
                if let barcode {
                    LabeledContent("Barcode") { Text(verbatim: barcode).monospacedDigit() }
                }
            }

            Section {
                HStack(spacing: 10) {
                    Button { showCamera = true } label: {
                        Label("Photograph label", systemImage: "camera.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.on.rectangle").padding(.horizontal, 6)
                    }
                    .buttonStyle(.bordered)
                }
                .controlSize(.large)
                if reading {
                    HStack { ProgressView(); Text("Reading the label…").font(.footnote).foregroundStyle(Theme.textSecondary) }
                }
                if let labelMessage {
                    Text(labelMessage).font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            } footer: {
                Text("Read on your phone. Always check the numbers against the pack.")
            }

            Section {
                numberField("Calories", "kcal", $kcal)
                numberField("Protein", "g", $protein)
                numberField("Carbs", "g", $carbs)
                numberField("Fat", "g", $fat)
            } header: {
                Text("Per 100 g")
            }

            Section {
                numberField("Serving size", "g", $serving)
            } footer: {
                Text("Optional — adds a one-tap serving button when you log it.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(existing == nil ? "New food" : "Edit food")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || kcal == nil)
            }
        }
        .onAppear(perform: load)
        .onChange(of: photoItem) { _, item in
            Task {
                guard let data = try? await item?.loadTransferable(type: Data.self), let picked = UIImage(data: data) else { return }
                await readLabel(picked)
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { captured in
                showCamera = false
                if let captured { Task { await readLabel(captured) } }
            }
            .ignoresSafeArea()
        }
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

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name
        brand = existing.brand ?? ""
        kcal = existing.kcal
        protein = existing.protein
        carbs = existing.carbs
        fat = existing.fat
        serving = existing.servingGrams
    }

    private func readLabel(_ image: UIImage) async {
        reading = true
        labelMessage = nil
        let values = await NutritionLabelReader.read(image)
        reading = false
        guard values.foundAnything else {
            labelMessage = String(localized: "Couldn't read the table. Try a straight, well-lit photo of just the nutrition table.")
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            return
        }
        withAnimation {
            if let v = values.kcal { kcal = v }
            if let v = values.protein { protein = v }
            if let v = values.carbs { carbs = v }
            if let v = values.fat { fat = v }
        }
        let missing = [values.kcal == nil ? String(localized: "calories") : nil,
                       values.protein == nil ? String(localized: "protein") : nil,
                       values.carbs == nil ? String(localized: "carbs") : nil,
                       values.fat == nil ? String(localized: "fat") : nil].compactMap { $0 }
        labelMessage = missing.isEmpty
            ? String(localized: "Filled in from the label — check them against the pack.")
            : String(localized: "Couldn't find \(missing.joined(separator: ", ")) — type those in.")
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    private func save() {
        let food = existing ?? UserFood(name: name, isRecipe: false)
        food.name = name.trimmingCharacters(in: .whitespaces)
        food.brand = brand.trimmingCharacters(in: .whitespaces).isEmpty ? nil : brand.trimmingCharacters(in: .whitespaces)
        food.barcode = barcode
        food.kcal = kcal ?? 0
        food.protein = protein ?? 0
        food.carbs = carbs ?? 0
        food.fat = fat ?? 0
        food.servingGrams = serving.flatMap { $0 > 0 ? $0 : nil }
        if existing == nil { context.insert(food) }
        try? context.save()
        onSaved(food.item)
    }
}

// MARK: - Recipes

struct RecipeEditorView: View {
    let existing: UserFood?
    let onSaved: (FoodItem) -> Void

    @Environment(\.modelContext) private var context
    @State private var name = ""
    @State private var ingredients: [RecipeIngredient] = []
    @State private var cookedWeight: Double?
    @State private var serving: Double?
    @State private var description = ""
    @State private var calculating = false
    @State private var aiError: String?
    @State private var pickingIngredient = false
    @State private var loaded = false

    private var rawWeight: Double { ingredients.reduce(0) { $0 + $1.grams } }
    private var finalWeight: Double { cookedWeight.flatMap { $0 > 0 ? $0 : nil } ?? rawWeight }

    private var per100: FoodItem.Amount {
        let totals = ingredients.map { $0.food.amount($0.grams) }
        let scale = finalWeight > 0 ? 100 / finalWeight : 0
        return FoodItem.Amount(kcal: totals.reduce(0) { $0 + $1.kcal } * scale,
                               protein: totals.reduce(0) { $0 + $1.protein } * scale,
                               carbs: totals.reduce(0) { $0 + $1.carbs } * scale,
                               fat: totals.reduce(0) { $0 + $1.fat } * scale)
    }

    var body: some View {
        Form {
            Section {
                TextField("Recipe name", text: $name)
            }

            Section {
                TextField("e.g. 200 g oats, 500 ml milk, 2 bananas, 30 g honey", text: $description, axis: .vertical)
                    .lineLimit(3...8)
                Button {
                    Task { await calculate() }
                } label: {
                    HStack(spacing: 8) {
                        if calculating { ProgressView() } else { GeminiMark(size: 16) }
                        Text("Calculate ingredients")
                    }
                }
                .disabled(description.trimmingCharacters(in: .whitespaces).isEmpty || calculating)
                if let aiError { Text(aiError).font(.footnote).foregroundStyle(Theme.bad) }
            } header: {
                Text("Describe it")
            } footer: {
                Text("Gemini turns your description into ingredients with amounts. You can adjust them below.")
            }

            Section {
                ForEach($ingredients) { $ingredient in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: ingredient.food.name).font(.subheadline).lineLimit(2)
                            Text("\(DetailFormat.safeInt(ingredient.food.amount(ingredient.grams).kcal)) kcal")
                                .font(.caption).foregroundStyle(Theme.textTertiary).monospacedDigit()
                        }
                        Spacer()
                        LiveNumberField("0", value: $ingredient.grams)
                            .multilineTextAlignment(.trailing)
                            .monospacedDigit()
                            .frame(width: 70)
                        Text(verbatim: "g").foregroundStyle(Theme.textTertiary)
                    }
                }
                .onDelete { ingredients.remove(atOffsets: $0) }
                Button("Add ingredient", systemImage: "plus.circle.fill") { pickingIngredient = true }
            } header: {
                Text("Ingredients")
            }

            Section {
                LabeledContent("Raw weight") { Text(verbatim: "\(DetailFormat.decimal(rawWeight)) g").monospacedDigit() }
                HStack {
                    Text("Cooked weight")
                    Spacer()
                    LiveNumberField("optional", value: $cookedWeight, fractionDigits: 0)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 100)
                    Text(verbatim: "g").foregroundStyle(Theme.textTertiary)
                }
                HStack {
                    Text("Serving size")
                    Spacer()
                    LiveNumberField("optional", value: $serving, fractionDigits: 0)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 100)
                    Text(verbatim: "g").foregroundStyle(Theme.textTertiary)
                }
            } header: {
                Text("Weight")
            } footer: {
                Text("Weigh the finished dish if you can — cooking loses water, so each 100 g ends up denser than the raw ingredients.")
            }

            Section {
                HStack(spacing: 0) {
                    per100Tile("kcal", per100.kcal, Theme.accent)
                    per100Tile("Protein", per100.protein, Theme.protein)
                    per100Tile("Carbs", per100.carbs, Theme.carbs)
                    per100Tile("Fat", per100.fat, Theme.fat)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Per 100 g")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(existing == nil ? "New recipe" : "Edit recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty || finalWeight <= 0)
            }
        }
        .sheet(isPresented: $pickingIngredient) {
            IngredientPicker { food, grams in
                ingredients.append(RecipeIngredient(food: food, grams: grams))
            }
        }
        .onAppear(perform: load)
    }

    private func per100Tile(_ label: LocalizedStringKey, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text("\(DetailFormat.safeInt(value))")
                .font(.system(size: 20, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let existing else { return }
        name = existing.name
        ingredients = existing.ingredients
        cookedWeight = existing.totalGrams
        serving = existing.servingGrams
        description = existing.notes
    }

    private func calculate() async {
        calculating = true
        aiError = nil
        defer { calculating = false }
        do {
            let result = try await RecipeCalculator.calculate(name: name, description: description)
            withAnimation {
                if name.trimmingCharacters(in: .whitespaces).isEmpty { name = result.name }
                ingredients = result.ingredients
                if let cooked = result.cookedWeight { cookedWeight = cooked }
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            aiError = error.localizedDescription
        }
    }

    private func save() {
        let food = existing ?? UserFood(name: name, isRecipe: true)
        let p = per100
        food.name = name.trimmingCharacters(in: .whitespaces)
        food.ingredients = ingredients
        food.totalGrams = cookedWeight.flatMap { $0 > 0 ? $0 : nil }
        food.servingGrams = serving.flatMap { $0 > 0 ? $0 : nil }
        food.notes = description
        food.kcal = p.kcal
        food.protein = p.protein
        food.carbs = p.carbs
        food.fat = p.fat
        if existing == nil { context.insert(food) }
        try? context.save()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onSaved(food.item)
    }
}

/// Search for an ingredient, then say how much of it goes in.
private struct IngredientPicker: View {
    let onAdd: (FoodItem, Double) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var picked: FoodItem?
    @State private var grams: Double = 100

    var body: some View {
        NavigationStack {
            FoodSearchScreen(initialQuery: "") { picked = $0 }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                }
                .navigationDestination(item: $picked) { item in
                    Form {
                        Section { FoodItemRow(item: item) }
                        Section("Amount in the recipe") {
                            HStack {
                                LiveNumberField("Grams", value: $grams)
                                    .font(.title2.weight(.semibold))
                                Text(verbatim: "g").foregroundStyle(Theme.textTertiary)
                            }
                        }
                        Section {
                            Button("Add ingredient") {
                                onAdd(item, grams)
                                dismiss()
                            }
                            .fontWeight(.semibold)
                            .disabled(grams <= 0)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.background.ignoresSafeArea())
                    .navigationTitle("Ingredient")
                    .navigationBarTitleDisplayMode(.inline)
                }
        }
        .tint(Theme.accent)
    }
}

enum RecipeCalculator {
    struct Result {
        let name: String
        let ingredients: [RecipeIngredient]
        let cookedWeight: Double?
    }

    private struct Envelope: Decodable {
        let name: String?
        let items: [MealEstimate.Item]
        let cookedWeight: Double?

        enum CodingKeys: String, CodingKey { case name, items = "ingredients", cookedWeight = "cooked_weight_grams" }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try? c.decode(String.self, forKey: .name)
            items = (try? c.decode([MealEstimate.Item].self, forKey: .items)) ?? []
            cookedWeight = try? c.decode(Double.self, forKey: .cookedWeight)
        }
    }

    static func calculate(name: String, description: String) async throws -> Result {
        let system = """
        You are a nutritionist turning a home recipe into a precise ingredient list for a food log.
        For each ingredient give its raw weight in grams (convert units, pieces and millilitres to grams using
        typical Swiss supermarket products) and the calories, protein, carbs and fat for that amount.
        Keep calories consistent with 4 kcal/g protein and carbs and 9 kcal/g fat.
        Include cooking oil or butter only if mentioned. If the finished cooked weight is given, return it.

        Respond with JSON only, in exactly this shape:
        {"name": string, "ingredients": [{"name": string, "grams": number, "calories": number,
        "protein": number, "carbs": number, "fat": number}], "cooked_weight_grams": number | null}
        """
        let user = "Recipe: \(name.isEmpty ? "untitled" : name)\n\(description)"
        let text = try await AIClient().send(system: system, user: user, maxTokens: 2500, temperature: 0.2, json: true,
                                             accepts: { (try? JSONDecoder().decode(Envelope.self, from: Data($0.utf8)))?.items.isEmpty == false })
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: Data(text.utf8)), !envelope.items.isEmpty else {
            throw AIClient.AIError.requestFailed(String(localized: "Couldn't turn that into ingredients. Try listing each one with an amount."))
        }
        let ingredients = envelope.items.filter { $0.grams > 0 }.map { item in
            let scale = 100 / item.grams
            let food = FoodItem(id: "ai-\(UUID().uuidString)", name: item.name, brand: nil,
                                kcal: item.calories * scale, protein: item.protein * scale,
                                carbs: item.carbs * scale, fat: item.fat * scale,
                                source: .estimate, barcode: nil, servingGrams: nil)
            return RecipeIngredient(food: food, grams: item.grams)
        }
        return Result(name: envelope.name ?? name, ingredients: ingredients, cookedWeight: envelope.cookedWeight)
    }
}
