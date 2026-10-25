//
//  SmartSearch.swift
//  RecoverySignal2
//
//  Typo-tolerant, word-order-independent search shared by the exercise picker,
//  workout history and the food databases. A query is split into words; each
//  word has to match some word of a candidate — exactly, as a prefix, inside a
//  longer word, or within a small edit distance (one typo for short words, two
//  for long ones). Words are reduced to a canonical form first, so "tricep",
//  "triceps" and "tris" agree, "db" means dumbbell and "rdl" means Romanian
//  deadlift. Candidates are then ranked: exact and prefix matches first, then
//  names that start with the query, then shorter names, with a boost for
//  things you've used before.
//

import Foundation

nonisolated enum SmartSearch {

    // MARK: - Documents

    /// One searchable thing. `tokens` come from the name; `extraTokens` from
    /// secondary text (muscles, equipment, other languages) and count less.
    struct Document<ID: Hashable> {
        let id: ID
        let name: String
        let tokens: [String]
        let extraTokens: [String]
        /// 0…1, added to the score — e.g. exercises you've logged before.
        let boost: Double

        init(id: ID, name: String, extra: [String] = [], boost: Double = 0) {
            self.id = id
            self.name = SmartSearch.normalize(name)
            self.tokens = SmartSearch.tokens(name)
            self.extraTokens = extra.flatMap(SmartSearch.tokens)
            self.boost = boost
        }
    }

    struct Hit<ID: Hashable> {
        let id: ID
        let score: Double
    }

    // MARK: - Normalisation

    /// Lowercase, no diacritics, punctuation turned into spaces.
    static func normalize(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "ß", with: "ss")
            .replacingOccurrences(of: "ł", with: "l")
        var out = ""
        out.reserveCapacity(folded.count)
        var lastSpace = true
        for ch in folded {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastSpace = false
            } else if !lastSpace {
                out.append(" ")
                lastSpace = true
            }
        }
        return out.trimmingCharacters(in: .whitespaces)
    }

    /// Canonical words of a string: normalised, split, abbreviations expanded,
    /// plurals and common variants collapsed.
    static func tokens(_ s: String) -> [String] {
        normalize(s).split(separator: " ").flatMap { canonical(String($0)) }
    }

    /// The canonical form(s) of one word. Most words map to themselves minus a
    /// plural "s"; a few gym and kitchen abbreviations expand to several words.
    static func canonical(_ raw: String) -> [String] {
        if let expansion = aliases[raw] { return expansion }
        var word = raw
        // Plurals: "raises" → "raise", "lunges" → "lunge", "calves" → "calf".
        if word.count > 3, word.hasSuffix("s"), !word.hasSuffix("ss") {
            word.removeLast()
            if word.hasSuffix("ie"), word.count > 4 { word.removeLast(2); word.append("y") } // "berries" → "berry"
        }
        if let expansion = aliases[word] { return expansion }
        return [word]
    }

    /// Variants and abbreviations → canonical words. Keys are already singular
    /// where that matters, because `canonical` strips the plural first.
    private static let aliases: [String: [String]] = [
        // Muscles
        "tricep": ["tricep"], "triceps": ["tricep"], "tri": ["tricep"], "tris": ["tricep"],
        "bicep": ["bicep"], "biceps": ["bicep"], "bi": ["bicep"], "bis": ["bicep"],
        "pec": ["chest"], "pecs": ["chest"], "pectoral": ["chest"],
        "delt": ["shoulder"], "delts": ["shoulder"], "deltoid": ["shoulder"],
        "quad": ["quadricep"], "quads": ["quadricep"], "quadriceps": ["quadricep"],
        "ham": ["hamstring"], "hams": ["hamstring"], "hammy": ["hamstring"],
        "glute": ["glute"], "glutes": ["glute"], "gluteus": ["glute"], "butt": ["glute"],
        "ab": ["abdominal"], "abs": ["abdominal"], "core": ["abdominal"],
        "lat": ["lat"], "lats": ["lat"], "latissimus": ["lat"],
        "calve": ["calf"], "calves": ["calf"],
        "trap": ["trap"], "traps": ["trap"], "trapezius": ["trap"],
        "forearm": ["forearm"], "forearms": ["forearm"],
        // Equipment
        "db": ["dumbbell"], "dumbell": ["dumbbell"], "dumbbells": ["dumbbell"],
        "bb": ["barbell"], "barbells": ["barbell"],
        "kb": ["kettlebell"], "kettlebells": ["kettlebell"],
        "ez": ["ez"], "ezbar": ["ez", "bar"],
        "bw": ["body", "weight"], "bodyweight": ["body", "weight"],
        "machine": ["machine"], "cable": ["cable"], "smith": ["smith"],
        // Movements and their spellings
        "pushdown": ["pushdown"], "pressdown": ["pushdown"], "pushdowns": ["pushdown"],
        "pulldown": ["pulldown"], "pulldowns": ["pulldown"],
        "pullup": ["pullup"], "pullups": ["pullup"], "chinup": ["chinup"], "chinups": ["chinup"],
        "pushup": ["pushup"], "pushups": ["pushup"],
        "situp": ["situp"], "situps": ["situp"],
        "fly": ["fly"], "flye": ["fly"], "flyes": ["fly"], "flies": ["fly"],
        "rdl": ["romanian", "deadlift"], "sldl": ["stiff", "leg", "deadlift"],
        "ohp": ["overhead", "press"], "overhead": ["overhead", "military"], "military": ["military", "overhead"],
        "bss": ["bulgarian", "split", "squat"],
        "skullcrusher": ["skullcrusher", "lying", "tricep", "extension"],
        "skullcrushers": ["skullcrusher", "lying", "tricep", "extension"],
        "hip": ["hip"], "thrust": ["thrust"], "thrusts": ["thrust"],
        "lunge": ["lunge"], "lunges": ["lunge"],
        "squat": ["squat"], "squats": ["squat"],
        "deadlift": ["deadlift"], "deadlifts": ["deadlift"], "dl": ["deadlift"],
        "row": ["row"], "rows": ["row"],
        "curl": ["curl"], "curls": ["curl"],
        "raise": ["raise"], "raises": ["raise"],
        "extension": ["extension"], "extensions": ["extension"], "ext": ["extension"],
        "press": ["press"], "presses": ["press"],
        "incline": ["incline"], "inc": ["incline"], "decline": ["decline"], "dec": ["decline"],
        "lateral": ["lateral", "side"], "side": ["side", "lateral"],
        "rear": ["rear", "reverse"], "reverse": ["reverse", "rear"],
        "seated": ["seated", "sitting"], "standing": ["standing"],
        "wide": ["wide"], "close": ["close", "narrow"], "narrow": ["narrow", "close"],
        // Foods
        "yoghurt": ["yogurt"], "yogurt": ["yogurt"],
        "veg": ["vegetable"], "veggie": ["vegetable"], "veggies": ["vegetable"],
        "protein": ["protein"], "whey": ["whey", "protein"],
        "chicken": ["chicken", "poulet"], "poulet": ["chicken", "poulet"],
        "potato": ["potato", "kartoffel"], "potatoes": ["potato", "kartoffel"],
        "oat": ["oat"], "oats": ["oat"], "oatmeal": ["oat"], "porridge": ["oat", "porridge"],
        "pb": ["peanut", "butter"]
    ]

    // MARK: - Ranking

    /// Ranks `documents` against `query`. Every query word must match
    /// somewhere in a document for it to count; the score orders the hits.
    static func rank<ID>(query: String, in documents: [Document<ID>], limit: Int = 60) -> [Hit<ID>] {
        let queryTokens = tokens(query)
        guard !queryTokens.isEmpty else { return [] }
        let normalizedQuery = normalize(query)

        var hits: [(Document<ID>, Double)] = []
        hits.reserveCapacity(64)

        for document in documents {
            var total = 0.0
            var matchedAll = true
            var firstMatchIndex: Int? = nil
            var inOrder = true
            var lastIndex = -1

            for (position, q) in queryTokens.enumerated() {
                var best = 0.0
                var bestIndex = -1
                for (index, t) in document.tokens.enumerated() {
                    let s = tokenScore(query: q, token: t)
                    if s > best { best = s; bestIndex = index }
                    if best >= 1 { break }
                }
                if best < 0.95 {
                    for t in document.extraTokens {
                        let s = tokenScore(query: q, token: t) * 0.7
                        if s > best { best = s; bestIndex = -1 }
                    }
                }
                if best == 0 { matchedAll = false; break }
                total += best
                if position == 0 { firstMatchIndex = bestIndex }
                if bestIndex >= 0 {
                    if bestIndex < lastIndex { inOrder = false }
                    lastIndex = bestIndex
                }
            }
            guard matchedAll else { continue }

            var score = total / Double(queryTokens.count)
            if document.name.hasPrefix(normalizedQuery) { score += 0.25 }
            else if firstMatchIndex == 0 { score += 0.12 }
            if inOrder, queryTokens.count > 1 { score += 0.06 }
            // Shorter names win ties: "Triceps Pushdown" before "Triceps Pushdown - Rope Attachment".
            score += 0.08 * (1 - min(Double(document.tokens.count), 8) / 8)
            score += min(max(document.boost, 0), 1) * 0.3
            hits.append((document, score))
        }

        hits.sort { a, b in
            if a.1 != b.1 { return a.1 > b.1 }
            if a.0.tokens.count != b.0.tokens.count { return a.0.tokens.count < b.0.tokens.count }
            return a.0.name < b.0.name
        }
        return hits.prefix(limit).map { Hit(id: $0.0.id, score: $0.1) }
    }

    /// How well one query word matches one document word, 0…1.
    static func tokenScore(query q: String, token t: String) -> Double {
        if q == t { return 1 }
        if t.hasPrefix(q) { return 0.9 - 0.02 * Double(min(t.count - q.count, 10)) }
        if q.count >= 4, t.contains(q) { return 0.72 }
        if q.count >= 3, t.count >= 3, q.hasPrefix(t) { return 0.55 }   // typed more than the word: "pushdowns" vs "pushdown"
        // Typos: one edit for short words, two for longer ones. Skip the
        // expensive comparison when the lengths alone rule it out.
        let allowed = q.count <= 3 ? 0 : (q.count <= 6 ? 1 : 2)
        guard allowed > 0 else { return 0 }
        let whole = abs(q.count - t.count) <= allowed ? editDistance(q, t, max: allowed) : allowed + 1
        if whole <= allowed { return 0.8 - 0.22 * Double(whole) }
        // Typo inside a prefix: "pushdw" against "pushdown".
        if t.count > q.count {
            let head = String(t.prefix(q.count + 1))
            let d = editDistance(q, head, max: allowed)
            if d <= allowed { return 0.66 - 0.2 * Double(d) }
        }
        return 0
    }

    /// Damerau–Levenshtein (optimal string alignment) distance, giving up as
    /// soon as it exceeds `max`.
    static func editDistance(_ a: String, _ b: String, max limit: Int) -> Int {
        let s = Array(a.utf8), t = Array(b.utf8)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }
        if abs(s.count - t.count) > limit { return limit + 1 }
        var previous2 = [Int](repeating: 0, count: t.count + 1)
        var previous = Array(0...t.count)
        var current = [Int](repeating: 0, count: t.count + 1)
        for i in 1...s.count {
            current[0] = i
            var rowMin = i
            for j in 1...t.count {
                let cost = s[i - 1] == t[j - 1] ? 0 : 1
                var value = Swift.min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    value = Swift.min(value, previous2[j - 2] + 1)   // transposition
                }
                current[j] = value
                if value < rowMin { rowMin = value }
            }
            if rowMin > limit { return limit + 1 }
            (previous2, previous, current) = (previous, current, previous2)
        }
        return previous[t.count]
    }
}
