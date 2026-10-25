//
//  WatchWorkouts.swift
//  RecoverySignal2
//
//  Workouts recorded outside this app — the Apple Watch Workout app, Strava,
//  Fitness+ — read from Apple Health so they sit in the same history as the
//  sessions you log here. When you log a session in the app while the Watch
//  is also recording, the two are linked: the app log keeps your sets, the
//  Watch supplies heart rate and calories, and nothing is saved twice.
//

import Foundation
import HealthKit
import SwiftUI
import Charts

struct HealthWorkout: Identifiable, Hashable {
    let id: UUID
    let name: String
    let symbol: String
    let start: Date
    let end: Date
    let calories: Double?
    let averageHeartRate: Double?
    let maxHeartRate: Double?
    let distanceKm: Double?
    let source: String

    var duration: TimeInterval { end.timeIntervalSince(start) }

    init(_ workout: HKWorkout) {
        id = workout.uuid
        name = HealthKitManager.displayName(for: workout.workoutActivityType)
        symbol = Self.symbol(for: workout.workoutActivityType)
        start = workout.startDate
        end = workout.endDate
        calories = HealthKitManager.energyBurned(for: workout)
        let bpm = HKUnit.count().unitDivided(by: .minute())
        let hrStats = HKObjectType.quantityType(forIdentifier: .heartRate).flatMap { workout.statistics(for: $0) }
        averageHeartRate = hrStats?.averageQuantity()?.doubleValue(for: bpm)
        maxHeartRate = hrStats?.maximumQuantity()?.doubleValue(for: bpm)
        let distanceTypes: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        distanceKm = distanceTypes.lazy
            .compactMap { HKObjectType.quantityType(forIdentifier: $0).flatMap { workout.statistics(for: $0)?.sumQuantity() } }
            .first?.doubleValue(for: .meterUnit(with: .kilo))
        source = workout.sourceRevision.source.name
    }

    static func symbol(for type: HKWorkoutActivityType) -> String {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining: "figure.strengthtraining.traditional"
        case .coreTraining:        "figure.core.training"
        case .highIntensityIntervalTraining, .crossTraining: "figure.highintensity.intervaltraining"
        case .running:             "figure.run"
        case .walking:             "figure.walk"
        case .hiking:              "figure.hiking"
        case .cycling:             "figure.outdoor.cycle"
        case .swimming:            "figure.pool.swim"
        case .rowing:              "figure.rower"
        case .elliptical:          "figure.elliptical"
        case .yoga:                "figure.yoga"
        case .pilates:             "figure.pilates"
        case .dance:               "figure.dance"
        case .boxing:              "figure.boxing"
        case .climbing:            "figure.climbing"
        case .stairClimbing:       "figure.stair.stepper"
        default:                   "figure.mixed.cardio"
        }
    }
}

@MainActor
@Observable
final class HealthWorkoutFeed {
    static let shared = HealthWorkoutFeed()
    private(set) var workouts: [HealthWorkout] = []
    private(set) var isLoading = false

    private init() {}

    /// Workouts from the last `days` days that didn't come from this app.
    func load(days: Int = 120) async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let end = Date()
        guard let start = Calendar.current.date(byAdding: .day, value: -days, to: end),
              let raw = try? await HealthKitManager.shared.workouts(from: start, to: end) else { return }
        let ownBundle = Bundle.main.bundleIdentifier
        workouts = raw
            .filter { $0.sourceRevision.source.bundleIdentifier != ownBundle }
            .map(HealthWorkout.init)
            .sorted { $0.start > $1.start }
    }

    /// An outside workout that overlaps most of the given window — the Watch
    /// session recorded alongside an in-app log.
    func overlapping(start: Date, end: Date) async -> HealthWorkout? {
        await load(days: 2)
        let length = max(end.timeIntervalSince(start), 1)
        return workouts
            .map { w -> (HealthWorkout, Double) in
                let overlap = min(w.end, end).timeIntervalSince(max(w.start, start))
                return (w, overlap / length)
            }
            .filter { $0.1 >= 0.5 }
            .max { $0.1 < $1.1 }?.0
    }
}

struct HealthWorkoutDetailView: View {
    let workout: HealthWorkout
    @State private var heartRate: [TrendPoint] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(systemName: workout.symbol)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(LinearGradient(colors: [Theme.good, Theme.good.opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workout.name).font(.title3.weight(.semibold))
                        Text("\(workout.start.formatted(date: .abbreviated, time: .shortened)) · \(workout.source)")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                    }
                }

                StatGrid(tiles: [
                    StatTile(label: String(localized: "Duration"), value: durationText(workout.duration / 60), glyph: .training),
                    StatTile(label: String(localized: "Active calories"), value: workout.calories.map { DetailFormat.whole($0) } ?? "—", unit: "kcal", glyph: .energy),
                    StatTile(label: String(localized: "Avg heart rate"), value: workout.averageHeartRate.map { DetailFormat.whole($0) } ?? "—", unit: "bpm",
                             caption: workout.maxHeartRate.map { "Max \(DetailFormat.whole($0)) bpm" }, glyph: .heartRate),
                    StatTile(label: String(localized: "Distance"), value: workout.distanceKm.map { DetailFormat.decimal($0, 2) } ?? "—", unit: "km", glyph: .steps)
                ])

                if heartRate.count >= 2 {
                    ChartCard(title: String(localized: "Heart rate"), subtitle: String(localized: "Recorded by \(workout.source)")) {
                        Chart(heartRate) { p in
                            AreaMark(x: .value("Time", p.date), y: .value("bpm", p.value))
                                .foregroundStyle(LinearGradient(colors: [Theme.bad.opacity(0.3), Theme.bad.opacity(0)], startPoint: .top, endPoint: .bottom))
                            LineMark(x: .value("Time", p.date), y: .value("bpm", p.value))
                                .foregroundStyle(Theme.bad)
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 170)
                    }
                }

                Text("Synced from Apple Health. To add sets and weights, start a routine in Workouts while the Watch records — the two are linked automatically.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(workout.name)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            heartRate = ((try? await HealthKitManager.shared.heartRateSamples(from: workout.start, to: workout.end)) ?? [])
                .map { TrendPoint(date: $0.date, value: $0.bpm) }
        }
    }
}
