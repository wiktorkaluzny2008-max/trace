//
//  StrengthModels.swift
//  RecoverySignal2
//
//  Strength sessions imported from Hevy screenshots, and the muscle taxonomy
//  used by the radar and body map. Shoulders are deliberately split into
//  front, side and rear delts — Hevy itself only knows "shoulders".
//

import Foundation
import SwiftData

enum Muscle: String, CaseIterable, Codable, Identifiable {
    // Ordered to walk around the body, so neighbours on the radar are
    // neighbours anatomically.
    case chest, frontDelts, sideDelts, rearDelts, traps, upperBack, lats, lowerBack
    case biceps, triceps, forearms, abs, obliques
    case glutes, quads, hamstrings, adductors, calves

    var id: String { rawValue }

    var name: String {
        switch self {
        case .chest:      String(localized: "Chest")
        case .frontDelts: String(localized: "Front delts")
        case .sideDelts:  String(localized: "Side delts")
        case .rearDelts:  String(localized: "Rear delts")
        case .traps:      String(localized: "Traps")
        case .upperBack:  String(localized: "Upper back")
        case .lats:       String(localized: "Lats")
        case .lowerBack:  String(localized: "Lower back")
        case .biceps:     String(localized: "Biceps")
        case .triceps:    String(localized: "Triceps")
        case .forearms:   String(localized: "Forearms")
        case .abs:        String(localized: "Abs")
        case .obliques:   String(localized: "Obliques")
        case .glutes:     String(localized: "Glutes")
        case .quads:      String(localized: "Quads")
        case .hamstrings: String(localized: "Hamstrings")
        case .adductors:  String(localized: "Adductors")
        case .calves:     String(localized: "Calves")
        }
    }
}

struct ImportedSet: Codable, Hashable {
    enum Kind: String, Codable { case warmup, normal, failure, dropset }
    var kind: Kind
    var weightKg: Double?
    var reps: Double?

    /// Warm-ups prime the muscle but aren't training stimulus, so they don't count.
    var isHardSet: Bool { kind != .warmup }
}

struct ImportedExercise: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var sets: [ImportedSet]
    /// The AI's own muscle guess, used only when no naming rule matches.
    var aiPrimary: [Muscle]
    var aiSecondary: [Muscle]

    var hardSets: Int { sets.filter(\.isHardSet).count }

    /// Primary muscles get 1 set per hard set, secondary muscles 0.5.
    var muscleWeights: [Muscle: Double] {
        MuscleMapping.weights(for: name) ?? {
            var w: [Muscle: Double] = [:]
            aiSecondary.forEach { w[$0] = 0.5 }
            aiPrimary.forEach { w[$0] = 1 }
            return w
        }()
    }
}

@Model
final class StrengthSession {
    var id: UUID
    var date: Date
    var title: String
    var importedAt: Date
    /// JSON-encoded [ImportedExercise] — keeps the schema simple and flexible.
    var payload: Data

    init(date: Date, title: String, exercises: [ImportedExercise]) {
        id = UUID()
        self.date = date
        self.title = title
        importedAt = Date()
        payload = (try? JSONEncoder().encode(exercises)) ?? Data()
    }

    var exercises: [ImportedExercise] {
        PayloadCache.decode([ImportedExercise].self, from: payload, owner: self, slot: "exercises", fallback: [])
    }

    var hardSets: Int { exercises.reduce(0) { $0 + $1.hardSets } }
}

enum MuscleVolume {

    /// Hard sets per muscle within the week containing `date`.
    static func weeklySets(sessions: [StrengthSession], weekContaining date: Date,
                           calendar: Calendar = .current) -> [Muscle: Double] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return [:] }
        var totals: [Muscle: Double] = [:]
        for session in sessions where week.contains(session.date) {
            for exercise in session.exercises {
                let sets = Double(exercise.hardSets)
                for (muscle, weight) in exercise.muscleWeights {
                    totals[muscle, default: 0] += sets * weight
                }
            }
        }
        return totals
    }
}
