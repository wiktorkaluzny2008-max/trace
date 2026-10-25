//
//  NarrativeFormat.swift
//  RecoverySignal2
//
//  Splits the AI narrative into paragraphs and pulls out each one's topic.
//  The model opens every paragraph with a tag like "[sleep]", which the UI
//  swaps for that topic's glyph. Narratives saved before tags existed opened
//  with an emoji instead, so those are recognised too.
//

import Foundation

nonisolated enum NarrativeFormat {

    struct Paragraph: Sendable {
        let glyph: Glyph?
        let body: String
    }

    private static let legacyEmoji: [Character: Glyph] = [
        "💓": .recovery, "😴": .sleep, "🏋️": .training, "🥗": .nutrition, "⚖️": .body, "🎯": .target
    ]

    static func paragraphs(_ text: String) -> [Paragraph] {
        text.split(whereSeparator: \.isNewline).compactMap { rawLine in
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { return nil }
            var glyph: Glyph?

            if line.hasPrefix("["), let close = line.firstIndex(of: "]") {
                let tag = String(line[line.index(after: line.startIndex)..<close])
                glyph = .topic(tag)
                line = String(line[line.index(after: close)...]).trimmingCharacters(in: .whitespaces)
            } else if let first = line.first, let legacy = legacyEmoji[first] {
                glyph = legacy
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            return line.isEmpty ? nil : Paragraph(glyph: glyph, body: line)
        }
    }
}
