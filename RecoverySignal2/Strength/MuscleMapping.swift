//
//  MuscleMapping.swift
//  RecoverySignal2
//
//  Exercise name → muscles worked. Name-based rules come first because they
//  can split the shoulder (a lateral raise is side delts, a face pull is rear
//  delts), which no generic "shoulders" label can. Rules are checked in order,
//  so more specific phrases sit above general ones ("leg curl" before "curl").
//  Unmatched exercises fall back to the AI's muscle guess.
//
//  Each rule says how much one hard set counts toward each muscle it trains:
//  1 = a full set for the target muscle, 0.5 = a half set for a muscle that
//  works hard but isn't the limiting one, 0.25 = a small contribution.
//
//  Why fractions: in the largest volume meta-regression to date (Pelland et
//  al., Sports Medicine 2025; 67 studies), counting indirect sets as half a
//  set ("fractional" volume) predicted muscle growth better than counting
//  them fully or ignoring them. Exercise-specific tweaks follow training
//  studies where they exist:
//    • Squats don't grow the hamstrings (Kubo 2019: ~0% change) but do grow
//      glutes and adductors → hamstrings 0, glutes/adductors 0.75.
//    • Lat pulldowns alone grew the biceps almost as much as pulldowns plus
//      curls (Gentil 2013) → biceps 0.5, 0.75 for underhand chin-ups.
//    • Bench press grows the triceps, especially the lateral head (Brandão
//      2020) → triceps 0.5; close-grip and dips count more.
//    • Hip thrusts barely grow the hamstrings (Plotkin 2023) → 0.25.
//

import Foundation

enum MuscleMapping {

    private struct Rule {
        let keywords: [String]
        let excluding: [String]
        let sets: [Muscle: Double]

        init(_ keywords: [String], not excluding: [String] = [], _ sets: [Muscle: Double]) {
            self.keywords = keywords
            self.excluding = excluding
            self.sets = sets
        }
    }

    private static let rules: [Rule] = [
        // Shoulders — split by movement.
        Rule(["face pull", "rear delt", "rear lateral", "reverse fly", "reverse pec deck", "rear fly"],
             [.rearDelts: 1, .upperBack: 0.5, .traps: 0.25]),
        Rule(["lateral raise", "lat raise", "side raise", "y raise"],
             [.sideDelts: 1, .traps: 0.25]),
        Rule(["upright row"], [.sideDelts: 1, .traps: 0.5, .biceps: 0.25]),
        Rule(["front raise"], [.frontDelts: 1, .chest: 0.25]),
        Rule(["overhead press", "shoulder press", "military press", "arnold press", "push press", " ohp ", "landmine press", "handstand push"],
             [.frontDelts: 1, .sideDelts: 0.5, .triceps: 0.5, .traps: 0.25]),

        // Chest.
        Rule(["close grip bench", "close-grip bench", "close-grip barbell bench", "close-grip dumbbell press", "close grip press", "close-grip press", "jm press"],
             [.triceps: 1, .chest: 0.5, .frontDelts: 0.5]),
        Rule(["incline bench press", "incline barbell", "incline press", "incline dumbbell press", "incline chest", "incline smith"],
             [.chest: 1, .frontDelts: 0.75, .triceps: 0.5]),
        Rule(["decline bench", "decline barbell bench", "decline dumbbell bench", "decline dumbbell press", "decline press"], [.chest: 1, .triceps: 0.5, .frontDelts: 0.25]),
        Rule(["bench press", "chest press", "floor press", "dumbbell press"], not: ["close grip", "close-grip"],
             [.chest: 1, .frontDelts: 0.5, .triceps: 0.5]),
        Rule(["push up", "push-up", "pushup"],
             [.chest: 1, .frontDelts: 0.5, .triceps: 0.5, .abs: 0.25]),
        Rule(["chest dip", "dips", "dip "], not: ["bench dip", "squat"],
             [.chest: 1, .triceps: 1, .frontDelts: 0.5]),
        Rule(["fly", "flye", "pec deck", "crossover", "cable cross"], not: ["back fly", "lunge"],
             [.chest: 1, .frontDelts: 0.25]),

        // Back.
        Rule(["pullover", "straight arm", "straight-arm"], [.lats: 1, .triceps: 0.25]),
        Rule(["chin up", "chin-up", "chinup", "underhand", "reverse grip pulldown", "supinated pulldown"],
             [.lats: 1, .biceps: 0.75, .upperBack: 0.5, .rearDelts: 0.25, .forearms: 0.25]),
        Rule(["pull up", "pull-up", "pullup", "pulldown", "pull down"],
             [.lats: 1, .biceps: 0.5, .upperBack: 0.5, .rearDelts: 0.25, .forearms: 0.25]),
        Rule(["shrug"], [.traps: 1, .forearms: 0.25]),
        Rule(["back extension", "hyperextension", "reverse hyper"],
             [.lowerBack: 1, .glutes: 0.5, .hamstrings: 0.5]),
        Rule(["romanian", " rdl ", "stiff leg", "stiff-leg", "good morning"],
             [.hamstrings: 1, .glutes: 0.75, .lowerBack: 0.5, .forearms: 0.25]),
        Rule(["deadlift", "rack pull"],
             [.glutes: 1, .lowerBack: 1, .hamstrings: 0.5, .quads: 0.5, .traps: 0.25, .forearms: 0.25, .upperBack: 0.25]),
        Rule(["seal row", "chest supported row", "chest-supported row"], not: ["upright"],
             [.upperBack: 1, .lats: 0.75, .rearDelts: 0.5, .biceps: 0.5]),
        Rule([" row"], not: ["upright"],
             [.upperBack: 1, .lats: 0.75, .rearDelts: 0.5, .biceps: 0.5, .lowerBack: 0.25, .forearms: 0.25]),

        // Legs.
        Rule(["hip thrust", "glute bridge"], [.glutes: 1, .hamstrings: 0.25, .quads: 0.25]),
        Rule(["glute kickback", "hip abduct", "abduction"], [.glutes: 1]),
        Rule(["leg curl", "hamstring curl", "nordic"], [.hamstrings: 1, .calves: 0.25]),
        Rule(["leg extension"], [.quads: 1]),
        Rule(["adduct"], [.adductors: 1]),
        Rule(["calf", "calves"], [.calves: 1]),
        Rule(["lunge", "split squat", "bulgarian", "step up", "step-up"],
             [.quads: 1, .glutes: 0.75, .adductors: 0.5]),
        Rule(["leg press", "hack"], [.quads: 1, .glutes: 0.5, .adductors: 0.5]),
        Rule(["squat"], [.quads: 1, .glutes: 0.75, .adductors: 0.75, .lowerBack: 0.25]),

        // Arms.
        Rule(["wrist curl", "farmer", "forearm", "reverse curl"], [.forearms: 1]),
        Rule(["hammer curl"], [.biceps: 1, .forearms: 0.75]),
        Rule(["curl"], [.biceps: 1, .forearms: 0.25]),
        Rule(["tricep", "pushdown", "push down", "skull crusher", "skullcrusher", "overhead extension", "kickback",
              "bench dip"],
             [.triceps: 1]),

        // Core.
        Rule(["oblique", "russian twist", "side plank", "woodchop", "wood chop", "side bend"],
             [.obliques: 1, .abs: 0.5]),
        Rule(["crunch", "sit up", "sit-up", "situp", "leg raise", "knee raise", "plank", "ab wheel",
              "rollout", "hollow", "v up", "v-up", "dead bug"],
             [.abs: 1, .obliques: 0.5]),
    ]

    /// Sets credited to each muscle for one hard set of this exercise, or
    /// nil if no rule recognises the name.
    static func weights(for exerciseName: String) -> [Muscle: Double]? {
        let name = " " + exerciseName.lowercased() + " "
        // Stretches and foam rolling don't build volume.
        if name.contains("stretch") || name.contains("smr") { return [:] }
        return rules.first { rule in
            rule.keywords.contains(where: name.contains) && !rule.excluding.contains(where: name.contains)
        }?.sets
    }
}
