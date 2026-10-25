//
//  TrendsView.swift
//  RecoverySignal
//

import SwiftUI
import SwiftData
import Charts

struct TrendsView: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var allDays: [DailyMetrics]

    private var lastMonth: [DailyMetrics] {
        Array(allDays.suffix(30))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    chartSection("HRV (SDNN)", unit: "ms") { $0.hrvSDNN }
                    chartSection("Resting Heart Rate", unit: "bpm") { $0.restingHeartRate }
                    chartSection("Sleep (asleep)", unit: "h") { $0.sleepAsleepHours }
                    chartSection("Body Weight", unit: "kg") { $0.bodyMassKg }
                    chartSection("Protein", unit: "g") { $0.proteinGrams }
                    chartSection("Steps", unit: "") { $0.steps }
                }
                .padding()
            }
            .navigationTitle("Trends")
        }
    }

    @ViewBuilder
    private func chartSection(_ title: String, unit: String, _ value: @escaping (DailyMetrics) -> Double?) -> some View {
        let points = lastMonth.compactMap { day -> (Date, Double)? in
            guard let v = value(day) else { return nil }
            return (day.date, v)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if points.isEmpty {
                Text("Not enough data yet").font(.caption).foregroundStyle(.secondary)
            } else {
                Chart(points, id: \.0) { point in
                    LineMark(x: .value("Date", point.0), y: .value(title, point.1))
                    PointMark(x: .value("Date", point.0), y: .value(title, point.1))
                        .symbolSize(20)
                }
                .frame(height: 140)
            }
        }
    }
}

#Preview {
    TrendsView()
}
