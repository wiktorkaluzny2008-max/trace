//
//  PasteMacros.swift
//  RecoverySignal2
//
//  Logging macros that another app worked out, mainly ChatGPT. There's no way to
//  connect to ChatGPT itself, so the text comes in by paste (the Paste button in
//  the food log) or by Shortcuts ("Log Macros in Trace", which can sit in the
//  share sheet). The text is read on the phone; a confirm sheet shows what was
//  found so nothing is logged unchecked. Messy text can be handed to the AI.
//

import SwiftUI
import SwiftData
import AppIntents

// MARK: - Reading the numbers

nonisolated struct ParsedMacros: Equatable {
    var name: String = ""
    var kcal: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var grams: Double?

    var foundAnything: Bool { kcal != nil || protein != nil || carbs != nil || fat != nil }
    var isComplete: Bool { kcal != nil && protein != nil && carbs != nil && fat != nil }
}

nonisolated enum MacroTextParser {

    /// Pulls calories, protein, carbs and fat out of free text such as a ChatGPT
    /// reply. When the text has a "Total" line (a meal broken into items), the
    /// numbers after the last one win; otherwise the last mention of each.
    static func parse(_ raw: String) -> ParsedMacros {
        let cleaned = raw
            .replacingOccurrences(of: "*", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: " ")
        var result = ParsedMacros(name: name(in: cleaned))

        let lowered = cleaned.lowercased()
            // Sub-types that would otherwise read as the main macro.
            .replacingOccurrences(of: "saturated fat", with: "satfat")
            .replacingOccurrences(of: "trans fat", with: "transfat")
            .replacingOccurrences(of: "net carbs", with: "netcarbs")

        let lines = lowered.components(separatedBy: .newlines)
        var focus = lowered
        if let last = lines.lastIndex(where: { $0.contains("total") }) {
            focus = lines[last...].joined(separator: "\n")
        }

        func find(_ patterns: [String]) -> Double? {
            let fromTotals = patterns.compactMap { first(match: $0, in: focus) }.first
            if focus != lowered, let fromTotals { return fromTotals }
            return patterns.compactMap { last(match: $0, in: lowered) }.first
        }

        let num = #"(\d+(?:[.,]\d+)?)(?:\s*(?:-|–|to)\s*(\d+(?:[.,]\d+)?))?"#
        // Between a label and its number: punctuation, a table bar, "(approx.)" or "about" —
        // never a comma or another word, so "protein, 60 g carbs" isn't read as 60 g protein.
        let gap = #"\s*(?:\([^)\d]*\))?[\s:=|\-–—~≈]*(?:about|approx\.?|approximately|roughly|around|ca\.?)?[\s~≈]*"#
        result.kcal = find([#"(?:calories|energy)"# + gap + num,
                            num + #"\s*(?:kcal|calories|cal)\b"#])
        result.protein = find([#"protein"# + gap + num,
                               num + #"\s*g(?:rams)?\s*(?:of\s+)?protein"#,
                               #"\bp\s*[:=]?\s*"# + num + #"\s*g\b"#])
        result.carbs = find([#"carb(?:s|ohydrates?)?"# + gap + num,
                             num + #"\s*g(?:rams)?\s*(?:of\s+)?carb"#,
                             #"\bc\s*[:=]?\s*"# + num + #"\s*g\b"#])
        result.fat = find([#"\bfats?\b"# + gap + num,
                           num + #"\s*g(?:rams)?\s*(?:of\s+)?fat\b"#,
                           #"\bf\s*[:=]?\s*"# + num + #"\s*g\b"#])
        result.grams = find([#"(?:weight|portion|serving size)"# + gap + num + #"\s*g\b"#])

        // Calories are easy to leave out; the macros give them.
        if result.kcal == nil, let p = result.protein, let c = result.carbs, let f = result.fat {
            result.kcal = (p * 4 + c * 4 + f * 9).rounded()
        }
        return result
    }

    /// The first short, plain line, as a name for the entry.
    private static func name(in text: String) -> String {
        let fillers = ["here", "sure", "okay", "ok", "great", "absolutely", "certainly", "estimated", "estimate"]
        for line in text.components(separatedBy: .newlines) {
            var trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ":-–•")))
            for prefix in ["meal:", "food:", "dish:", "name:"] where trimmed.lowercased().hasPrefix(prefix) {
                trimmed = String(trimmed.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            guard !trimmed.isEmpty, trimmed.count <= 60,
                  trimmed.rangeOfCharacter(from: .decimalDigits) == nil,
                  !fillers.contains(where: { trimmed.lowercased().hasPrefix($0) }) else { continue }
            return trimmed
        }
        return ""
    }

    private static func value(_ match: NSTextCheckingResult, in text: String) -> Double? {
        func number(_ i: Int) -> Double? {
            guard i < match.numberOfRanges, let r = Range(match.range(at: i), in: text) else { return nil }
            return Double(text[r].replacingOccurrences(of: ",", with: "."))
        }
        guard let low = number(1) else { return nil }
        if let high = number(2) { return ((low + high) / 2).rounded() }
        return low
    }

    private static func matches(_ pattern: String, in text: String) -> [NSTextCheckingResult] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    private static func first(match pattern: String, in text: String) -> Double? {
        matches(pattern, in: text).lazy.compactMap { value($0, in: text) }.first
    }

    private static func last(match pattern: String, in text: String) -> Double? {
        matches(pattern, in: text).reversed().lazy.compactMap { value($0, in: text) }.first
    }
}

// MARK: - Handing text over from Shortcuts

struct PastedText: Identifiable {
    let id = UUID()
    let text: String
}

/// Text that arrived through Shortcuts, waiting for the confirm sheet.
@MainActor
@Observable
final class MacroPasteInbox {
    static let shared = MacroPasteInbox()
    var pending: PastedText?
    private init() {}
}

struct LogMacrosIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Macros in Trace"
    static let description = IntentDescription(
        "Opens Trace with the calories and macros from some text, such as a ChatGPT reply, ready to check and log.")
    static let openAppWhenRun = true

    @Parameter(title: "Text", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult {
        MacroPasteInbox.shared.pending = PastedText(text: text)
        return .result()
    }
}

struct TraceShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogMacrosIntent(),
                    phrases: ["Log macros in \(.applicationName)"],
                    shortTitle: "Log Macros",
                    systemImageName: "fork.knife")
    }
}

// MARK: - Confirm sheet

struct PasteMacrosSheet: View {
    @Environment(\.foodLoggingDate) private var loggingDate
    let text: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var slot: MealSlot
    @State private var name = ""
    @State private var kcal = ""
    @State private var protein = ""
    @State private var carbs = ""
    @State private var fat = ""
    @State private var grams = ""
    @State private var reading = false
    @State private var logging = false
    @State private var errorMessage: String?
    @State private var showsSource = false
    @FocusState private var focused: Bool

    init(text: String, slot: MealSlot = .forNow()) {
        self.text = text
        _slot = State(initialValue: slot)
    }

    private func number(_ s: String) -> Double? {
        Double(s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces))
    }
    private var kcalValue: Double? { number(kcal) }
    private var macroKcal: Double { (number(protein) ?? 0) * 4 + (number(carbs) ?? 0) * 4 + (number(fat) ?? 0) * 9 }
    private var canLog: Bool { (kcalValue ?? 0) > 0 || macroKcal > 0 }
    private var looksOff: Bool {
        guard let k = kcalValue, k > 0, macroKcal > 0 else { return false }
        return abs(macroKcal - k) > max(40, k * 0.15)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    sourceCard

                    VStack(alignment: .leading, spacing: 12) {
                        TextField("Name, e.g. Chicken rice bowl", text: $name)
                            .font(.headline)
                            .focused($focused)
                        Picker("Meal", selection: $slot) {
                            ForEach([MealSlot.breakfast, .lunch, .snack, .dinner]) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .card(padding: 16)

                    VStack(spacing: 0) {
                        field("Calories", unit: "kcal", text: $kcal, tint: Theme.textPrimary)
                        Divider().overlay(Theme.separator)
                        field("Protein", unit: "g", text: $protein, tint: Theme.protein)
                        Divider().overlay(Theme.separator)
                        field("Carbs", unit: "g", text: $carbs, tint: Theme.carbs)
                        Divider().overlay(Theme.separator)
                        field("Fat", unit: "g", text: $fat, tint: Theme.fat)
                        Divider().overlay(Theme.separator)
                        field("Weight (optional)", unit: "g", text: $grams, tint: Theme.textSecondary)
                    }
                    .card(padding: 4)

                    if looksOff {
                        Label("The macros add up to about \(Int(macroKcal)) kcal, not \(Int(kcalValue ?? 0)). Worth a quick check.",
                              systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.warn)
                    }
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(Theme.bad)
                    }

                    Button {
                        Task { await readWithAI() }
                    } label: {
                        HStack(spacing: 8) {
                            if reading { ProgressView() } else { Image(systemName: "sparkles") }
                            Text(reading ? "Reading…" : "Read it with AI instead")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(reading)

                    Text("Numbers are read on your iPhone. Check them before logging; the entry is saved to Apple Health like any other food.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                .padding(18)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Pasted macros")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(logging ? "Logging…" : "Log") { Task { await log() } }
                        .fontWeight(.semibold)
                        .disabled(!canLog || logging)
                }
            }
            .onAppear { apply(MacroTextParser.parse(text)) }
        }
    }

    private var sourceCard: some View {
        let parsed = MacroTextParser.parse(text)
        return VStack(alignment: .leading, spacing: 8) {
            Label(parsed.isComplete ? "Found calories and all three macros"
                  : (parsed.foundAnything ? "Found some of the numbers — fill in the rest" : "Couldn't find the numbers — try the AI below"),
                  systemImage: parsed.isComplete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(parsed.isComplete ? Theme.good : Theme.warn)
            Button {
                withAnimation(.snappy) { showsSource.toggle() }
            } label: {
                Text(verbatim: text)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(showsSource ? nil : 3)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
        }
        .card(padding: 16)
    }

    private func field(_ title: LocalizedStringKey, unit: String, text: Binding<String>, tint: Color) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            Spacer()
            TextField("0", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.body.monospacedDigit())
                .frame(maxWidth: 110)
                .focused($focused)
            Text(verbatim: unit).font(.footnote).foregroundStyle(Theme.textTertiary).frame(width: 34, alignment: .leading)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func apply(_ parsed: ParsedMacros) {
        func format(_ v: Double?) -> String {
            guard let v else { return "" }
            return v == v.rounded() ? String(Int(v)) : DetailFormat.decimal(v)
        }
        if !parsed.name.isEmpty { name = parsed.name }
        if parsed.kcal != nil { kcal = format(parsed.kcal) }
        if parsed.protein != nil { protein = format(parsed.protein) }
        if parsed.carbs != nil { carbs = format(parsed.carbs) }
        if parsed.fat != nil { fat = format(parsed.fat) }
        if parsed.grams != nil { grams = format(parsed.grams) }
    }

    private func readWithAI() async {
        reading = true
        errorMessage = nil
        defer { reading = false }
        struct Reply: Decodable {
            let name: String?
            let calories: Double?
            let protein: Double?
            let carbs: Double?
            let fat: Double?
            let grams: Double?
        }
        let system = """
        You extract nutrition totals from text someone pasted, often a reply from another AI about a meal.
        If the text lists several foods, return the totals for the whole meal. Do not estimate anything the
        text doesn't state, except calories from macros (4 kcal/g protein and carbs, 9 kcal/g fat).
        Respond with JSON only: {"name": string, "calories": number|null, "protein": number|null,
        "carbs": number|null, "fat": number|null, "grams": number|null}. name is a short name for the meal.
        """
        do {
            let reply = try await AIClient().send(system: system, user: text, maxTokens: 400, temperature: 0.1, json: true,
                                                  accepts: { (try? JSONDecoder().decode(Reply.self, from: Data($0.utf8))) != nil })
            let r = try JSONDecoder().decode(Reply.self, from: Data(reply.utf8))
            apply(ParsedMacros(name: r.name ?? "", kcal: r.calories, protein: r.protein, carbs: r.carbs, fat: r.fat, grams: r.grams))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func log() async {
        logging = true
        defer { logging = false }
        let weight = number(grams).flatMap { $0 > 0 ? $0 : nil } ?? 100
        let scale = 100 / weight
        let totalKcal = kcalValue ?? macroKcal
        let title = name.trimmingCharacters(in: .whitespaces)
        let item = FoodItem(id: "paste-\(UUID().uuidString)", name: title.isEmpty ? String(localized: "Pasted meal") : title,
                            brand: nil, kcal: totalKcal * scale, protein: (number(protein) ?? 0) * scale,
                            carbs: (number(carbs) ?? 0) * scale, fat: (number(fat) ?? 0) * scale,
                            source: .estimate, barcode: nil, servingGrams: weight)
        do {
            try await FoodLogger.log(item, grams: weight, slot: slot, at: loggingDate ?? Date(), context: context)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}
