//
//  SicknessRiskModel.swift
//  RecoverySignal2
//
//  An early "you might be coming down with something" flag: wrist
//  temperature, resting heart rate and breathing rate rising together,
//  sustained over 2 days rather than a single reading (a single elevated day
//  is as likely to be a hard workout or a hot room as illness). These three
//  moving the same way at once is the classic early-infection signature in
//  wearable studies (elevated temperature, tachycardia, faster breathing).
//
//  HONESTY NOTE: this doesn't distinguish illness from a hard training day —
//  training also raises resting HR and, less reliably, wrist temperature and
//  breathing rate for a day or two afterwards. A high acute:chronic workload
//  ratio at the same time is a real confound this model doesn't correct for.
//  Treat it as "worth paying attention to", not a diagnosis.
//

import Foundation

enum SicknessRiskModel {

    struct Component: Identifiable {
        let id = UUID()
        let label: String
        let z: Double
    }

    struct Signal {
        let components: [Component]
        /// Mean z-score across whichever of the 3 inputs were available.
        let compositeZ: Double
    }

    private static let baselineWindow = 30
    private static let recentWindow = 2
    private static let riseThreshold = 0.8

    /// Nil unless at least 2 of the 3 inputs are present and elevated together.
    static func evaluate(from days: [DailyMetrics]) -> Signal? {
        let sorted = days.sorted { $0.date < $1.date }
        guard sorted.count >= baselineWindow + recentWindow else { return nil }

        let history = Array(sorted.dropLast(recentWindow).suffix(baselineWindow))
        let recent = Array(sorted.suffix(recentWindow))

        func recentZ(_ keyPath: KeyPath<DailyMetrics, Double?>) -> Double? {
            let baseline = history.compactMap { $0[keyPath: keyPath] }
            let recentValues = recent.compactMap { $0[keyPath: keyPath] }
            guard recentValues.count == recentWindow, let mean = Stats.mean(recentValues) else { return nil }
            return Stats.zScore(mean, in: baseline)
        }

        var components: [Component] = []
        if let z = recentZ(\.wristTemperature), z >= 0 { components.append(.init(label: String(localized: "Wrist temperature"), z: z)) }
        if let z = recentZ(\.restingHeartRate), z >= 0 { components.append(.init(label: String(localized: "Resting HR"), z: z)) }
        if let z = recentZ(\.respiratoryRate), z >= 0 { components.append(.init(label: String(localized: "Breathing rate"), z: z)) }

        guard components.count >= 2 else { return nil }
        let composite = components.reduce(0) { $0 + $1.z } / Double(components.count)
        guard composite >= riseThreshold, components.allSatisfy({ $0.z >= 0.3 }) else { return nil }

        return Signal(components: components.sorted { $0.z > $1.z }, compositeZ: composite)
    }
}
