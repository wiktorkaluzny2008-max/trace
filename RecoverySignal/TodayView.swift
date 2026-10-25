//
//  TodayView.swift
//  RecoverySignal
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var allDays: [DailyMetrics]
    @Environment(\.modelContext) private var context

    private var today: DailyMetrics? { allDays.first }

    var body: some View {
        NavigationStack {
            List {
                if let today {
                    Section("Recovery") {
                        metricRow("HRV (SDNN)", today.hrvSDNN, "ms")
                        metricRow("Resting HR", today.restingHeartRate, "bpm")
                        metricRow("Blood oxygen", today.oxygenSaturation.map { $0 * 100 }, "%")
                    }
                    Section("Sleep last night") {
                        metricRow("Asleep", today.sleepAsleepHours, "h")
                        metricRow("Deep sleep", today.sleepDeepHours, "h")
                        metricRow("REM sleep", today.sleepREMHours, "h")
                    }
                    Section("Activity") {
                        metricRow("Steps", today.steps, "")
                        metricRow("Active energy", today.activeEnergyBurned, "kcal")
                        if today.hadWorkout {
                            Text(today.workoutIsResistance ? "Resistance workout logged" : "Workout logged")
                                .foregroundStyle(.secondary)
                        }
                    }
                    Section("Nutrition") {
                        metricRow("Calories in", today.dietaryEnergyKcal, "kcal")
                        metricRow("Protein", today.proteinGrams, "g")
                        metricRow("Carbs", today.carbsGrams, "g")
                        metricRow("Fat", today.fatGrams, "g")
                    }
                    Section("Body") {
                        metricRow("Weight", today.bodyMassKg, "kg")
                        metricRow("VO2 max", today.vo2Max, "ml/kg/min")
                    }
                } else {
                    ContentUnavailableView(
                        "No data yet",
                        systemImage: "waveform.path.ecg",
                        description: Text("Pull to refresh once your Watch and Yazio have synced some data to Health.")
                    )
                }
            }
            .refreshable { await refresh() }
            .navigationTitle("Today")
        }
    }

    @ViewBuilder
    private func metricRow(_ label: String, _ value: Double?, _ unit: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            if let value {
                Text(unit.isEmpty ? String(format: "%.0f", value) : String(format: "%.1f %@", value, unit))
                    .foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        }
    }

    private func refresh() async {
        let aggregator = MetricsAggregator(context: context)
        try? await aggregator.refresh()
    }
}

#Preview {
    TodayView()
}
