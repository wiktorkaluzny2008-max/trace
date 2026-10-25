//
//  TrainingLoadModel.swift
//  RecoverySignal2
//
//  Acute:chronic workload ratio (ACWR) over Banister TRIMP.
//
//  The 0.8–1.3 "sweet spot" and the elevated-risk zone above ~1.5 come from
//  Gabbett's training-load work in team sports. Two honest caveats the UI
//  repeats: that research is on squad athletes rather than individuals, and
//  ACWR as a construct has been criticised methodologically. Treat it as a
//  useful ramp-rate gauge, not a risk oracle.
//

import Foundation
import SwiftUI

enum TrainingLoadModel {

    enum Zone {
        case detraining, optimal, caution, highRisk

        var label: String {
            switch self {
            case .detraining: String(localized: "Ramping down")
            case .optimal:    String(localized: "Sweet spot")
            case .caution:    String(localized: "Ramping fast")
            case .highRisk:   String(localized: "Spike")
            }
        }

        var color: Color {
            switch self {
            case .detraining: Theme.textSecondary
            case .optimal:    Theme.good
            case .caution:    Theme.warn
            case .highRisk:   Theme.bad
            }
        }

        var explanation: String {
            switch self {
            case .detraining:
                String(localized: "You're training meaningfully less than your recent norm. Fine as a deload — a problem if it's drift.")
            case .optimal:
                String(localized: "Your current workload is well matched to what you've built up to.")
            case .caution:
                String(localized: "You're adding load faster than your base has adapted to. Worth holding here rather than climbing further.")
            case .highRisk:
                String(localized: "A sharp jump relative to your chronic load. This is the pattern most associated with injury in the training-load literature.")
            }
        }
    }

    struct Result {
        let acute: Double     // 7-day EWMA of daily TRIMP
        let chronic: Double   // 28-day EWMA of daily TRIMP
        let ratio: Double
        let zone: Zone
        let daysOfData: Int
        /// True when we have less than a full 28-day chronic window.
        let provisional: Bool
    }

    static func compute(from days: [DailyMetrics]) -> Result? {
        let sorted = days.sorted { $0.date < $1.date }
        // Missing days are treated as rest (zero load) — that's what they are.
        let loads = sorted.map { $0.trainingLoad ?? 0 }
        guard loads.count >= 14 else { return nil }

        guard let acute = Stats.ewma(Array(loads.suffix(21)), span: 7),
              let chronic = Stats.ewma(loads, span: 28),
              chronic > 0 else { return nil }

        let ratio = acute / chronic
        let zone: Zone = {
            switch ratio {
            case ..<0.8:   .detraining
            case ..<1.3:   .optimal
            case ..<1.5:   .caution
            default:       .highRisk
            }
        }()

        return Result(
            acute: acute,
            chronic: chronic,
            ratio: ratio,
            zone: zone,
            daysOfData: loads.count,
            provisional: loads.count < 28
        )
    }
}
