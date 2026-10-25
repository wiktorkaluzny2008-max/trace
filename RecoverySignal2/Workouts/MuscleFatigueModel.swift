//
//  MuscleFatigueModel.swift
//  RecoverySignal2
//
//  "Legs still loaded from Tuesday" — a rough, local complement to the
//  HRV/RHR-based recovery score, which is a whole-body measure and has no way
//  to see that one muscle group is still repairing from a heavy session.
//
//  Not a measurement: it's an exponential decay from the sets you logged,
//  with a 2-day half-life (roughly how long the literature puts peak
//  soreness/protein-synthesis elevation for a typical hard session). A muscle
//  trained today reads "fully loaded"; by 4 days out it's treated as clear.
//

import Foundation

enum MuscleFatigueModel {

    struct Status: Identifiable {
        let muscle: Muscle
        let daysAgo: Int
        let sets: Double
        /// 0...1, decayed from the session — how "loaded" the muscle still reads.
        let load: Double

        var id: String { muscle.rawValue }
    }

    static let halfLifeDays = 2.0
    private static let minimumLoad = 0.2
    private static let maximumDaysAgo = 4

    /// The most recent qualifying (main-target) session for each muscle, decayed by time since.
    static func stillLoaded(logs: [WorkoutLog], now: Date = Date()) -> [Status] {
        let calendar = Calendar.current
        var lastSession: [Muscle: (date: Date, sets: Double)] = [:]

        for log in logs.sorted(by: { $0.start < $1.start }) {
            for exercise in log.exercises {
                let hard = Double(exercise.workingSets.count)
                guard hard > 0 else { continue }
                for (muscle, weight) in LoggedMuscleVolume.weights(for: exercise) where weight >= 0.75 {
                    lastSession[muscle] = (log.start, hard * weight)
                }
            }
        }

        return lastSession.compactMap { muscle, info -> Status? in
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: info.date),
                                               to: calendar.startOfDay(for: now)).day ?? maximumDaysAgo + 1
            guard days >= 0, days <= maximumDaysAgo else { return nil }
            let load = pow(0.5, Double(days) / halfLifeDays)
            guard load >= minimumLoad else { return nil }
            return Status(muscle: muscle, daysAgo: days, sets: info.sets, load: load)
        }.sorted { $0.load > $1.load }
    }
}
