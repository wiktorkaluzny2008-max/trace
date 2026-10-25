//
//  RecoverySignalApp.swift
//  RecoverySignal
//
//  App entry point: sets up SwiftData, requests HealthKit authorization on
//  first launch, and kicks off a metrics refresh whenever the app opens or
//  HealthKit tells us new data has arrived in the background.
//

import SwiftUI
import SwiftData

@main
struct RecoverySignalApp: App {
    let modelContainer: ModelContainer

    init() {
        do {
            modelContainer = try ModelContainer(for: DailyMetrics.self, Insight.self, WeeklyNarrative.self)
        } catch {
            fatalError("Failed to create SwiftData container: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(modelContainer)
                .task {
                    await bootstrap()
                }
        }
    }

    @MainActor
    private func bootstrap() async {
        do {
            try await HealthKitManager.shared.requestAuthorization()
            let aggregator = MetricsAggregator(context: modelContainer.mainContext)
            try await aggregator.refresh()

            HealthKitManager.shared.enableBackgroundDelivery {
                Task { @MainActor in
                    try? await aggregator.refresh(days: 3)
                }
            }
        } catch {
            print("Bootstrap failed: \(error)")
        }
    }
}
