//
//  RecoverySignal2App.swift
//  RecoverySignal2
//
//  App entry point: sets up SwiftData, requests HealthKit authorization on
//  first launch, and kicks off a metrics refresh whenever the app opens or
//  HealthKit tells us new data has arrived in the background.
//

import SwiftUI
import SwiftData
import UserNotifications

@main
struct RecoverySignal2App: App {
    @UIApplicationDelegateAdaptor(SleepDiagnosticAppDelegate.self) private var sleepDiagnosticDelegate
    let modelContainer: ModelContainer
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(AppPrefs.appearanceKey) private var appearance = 2

    init() {
        UNUserNotificationCenter.current().delegate = ForegroundNotificationDelegate.shared
        do {
            modelContainer = try ModelContainer(for: DailyMetrics.self, Insight.self, WeeklyNarrative.self, SavedRecipe.self, StrengthSession.self,
                                                WorkoutRoutine.self, WorkoutLog.self, FoodEntry.self, UserFood.self, DayTag.self, SavedMeal.self)
        } catch {
            // Health data can be rebuilt, but workouts, routines, food logs and
            // recipes can't — so a store that won't open is moved aside as a
            // backup (never deleted) and a fresh one is started.
            print("SwiftData migration failed (\(error)) — keeping a backup and starting a new store.")
            let url = URL.applicationSupportDirectory.appending(path: "default.store")
            let stamp = Int(Date().timeIntervalSince1970)
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(filePath: url.path() + suffix)
                let backup = URL.applicationSupportDirectory.appending(path: "backup-\(stamp)-default.store\(suffix)")
                try? FileManager.default.moveItem(at: source, to: backup)
            }
            do {
                modelContainer = try ModelContainer(for: DailyMetrics.self, Insight.self, WeeklyNarrative.self, SavedRecipe.self, StrengthSession.self,
                                                WorkoutRoutine.self, WorkoutLog.self, FoodEntry.self, UserFood.self, DayTag.self, SavedMeal.self)
            } catch {
                fatalError("Failed to create SwiftData container: \(error)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(AppPrefs.scheme(appearance))
                .modelContainer(modelContainer)
                .task {
                    HealthSync.shared.attach(modelContainer)
                    await bootstrap()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        SleepAvailabilityMonitor.shared.restore(trigger: "Foreground")
                        HealthSync.shared.refreshSoon(after: .milliseconds(300))
                        HealthSync.shared.startTicking()
                    } else {
                        HealthSync.shared.stopTicking()
                    }
                }
        }
    }

    @MainActor
    private func bootstrap() async {
        // Setup asks for Health itself, with an explanation — don't pop the sheet before it.
        await OnboardingCoordinator.shared.waitUntilReady()
        #if DEBUG
        // Development only: preview the launch intro without the Health sheet.
        if ProcessInfo.processInfo.arguments.contains("-skipHealth") { return }
        #endif
        do {
            try await HealthKitManager.shared.requestAuthorization()
            let context = modelContainer.mainContext
            let aggregator = MetricsAggregator(context: context)
            try await aggregator.refresh()
            BriefingService.reschedule()
            BriefingService.update(with: allDays(in: context))
            await BedtimeAlarm.reschedule(days: allDays(in: context))

            // Background wake-ups are what let the morning briefing arrive
            // shortly after last night's sleep and HRV sync.
            HealthKitManager.shared.enableBackgroundDelivery {
                // Several types often change together (a meal writes four) —
                // one refresh covers them all.
                Task { @MainActor in HealthSync.shared.refreshSoon(after: .seconds(2)) }
            }
            HealthSync.shared.startTicking()
        } catch {
            print("Bootstrap failed: \(error)")
        }
    }
}

@MainActor
private func allDays(in context: ModelContext) -> [DailyMetrics] {
    (try? context.fetch(FetchDescriptor<DailyMetrics>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? []
}
