//
//  LiveNumberField.swift
//  RecoverySignal2
//
//  A number field whose value updates on every keystroke. SwiftUI's
//  `TextField(value:format:)` only commits when editing ends, so Save buttons
//  and live totals kept seeing the old number until you tapped Done.
//  Accepts "12.5" and "12,5" alike.
//

import SwiftUI

struct LiveNumberField: View {
    private let placeholder: LocalizedStringKey
    private let prompt: Text?
    @Binding private var value: Double?
    private let fractionDigits: Int

    @State private var text = ""
    @FocusState private var focused: Bool

    init(_ placeholder: LocalizedStringKey = "", value: Binding<Double?>, fractionDigits: Int = 1, prompt: Text? = nil) {
        self.placeholder = placeholder
        self._value = value
        self.fractionDigits = fractionDigits
        self.prompt = prompt
    }

    /// For values that are never empty: an empty field reads as 0.
    init(_ placeholder: LocalizedStringKey = "", value: Binding<Double>, fractionDigits: Int = 1, prompt: Text? = nil) {
        self.init(placeholder, value: Binding<Double?>(get: { Optional(value.wrappedValue) }, set: { value.wrappedValue = $0 ?? 0 }),
                  fractionDigits: fractionDigits, prompt: prompt)
    }

    /// Whole numbers (reps, seconds).
    init(_ placeholder: LocalizedStringKey = "", value: Binding<Int?>, prompt: Text? = nil) {
        self.init(placeholder, value: Binding<Double?>(get: { value.wrappedValue.map(Double.init) },
                                              set: { value.wrappedValue = $0.map { Int($0.rounded()) } }),
                  fractionDigits: 0, prompt: prompt)
    }

    var body: some View {
        TextField(placeholder, text: $text, prompt: prompt)
            .keyboardType(fractionDigits > 0 ? .decimalPad : .numberPad)
            .focused($focused)
            .onAppear { text = format(value) }
            .onChange(of: text) { _, new in
                let parsed = parse(new)
                if parsed != value { value = parsed }
            }
            .onChange(of: value) { _, new in
                // Changed from outside (a chip, a portion button): show it —
                // unless it's just what's being typed.
                let clearedWhileTyping = focused && text.isEmpty && (new ?? 0) == 0
                if parse(text) != new && !clearedWhileTyping { text = format(new) }
            }
            .onChange(of: focused) { _, isFocused in
                if !isFocused { text = format(value) }
            }
    }

    private func parse(_ string: String) -> Double? {
        let cleaned = string.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, let number = Double(cleaned), number.isFinite else { return nil }
        return number
    }

    private func format(_ number: Double?) -> String {
        guard let number else { return "" }
        return number.formatted(.number.precision(.fractionLength(0...fractionDigits)).grouping(.never))
    }
}
