//
//  HealthAccess.swift
//  RecoverySignal2
//
//  One place that deals with Apple Health permission, and one place that keeps
//  the app's numbers in step with Health.
//
//  Permission: everything the app reads and writes is requested together, and
//  only when iOS says the request would show something new. Saves never ask
//  again — they write whichever types are allowed and skip the rest, so one
//  switched-off macro can't block logging a meal.
//
//  Syncing: refreshes are coalesced (several Health updates arriving together
//  trigger one refresh) and run on a timer while the app is open, after every
//  log, and whenever Health tells us nutrition data changed.
//

import Foundation
import HealthKit
import SwiftData

enum HealthAccess {
    private static var store: HKHealthStore { HealthKitManager.shared.store }

    static let nutritionTypes: [HKQuantityType] = [
        HKQuantityType(.dietaryEnergyConsumed), HKQuantityType(.dietaryProtein),
        HKQuantityType(.dietaryCarbohydrates), HKQuantityType(.dietaryFatTotal)
    ]

    static let hydrationTypes: [HKQuantityType] = [
        HKQuantityType(.dietaryWater), HKQuantityType(.dietaryCaffeine)
    ]

    static var shareTypes: Set<HKSampleType> {
        Set<HKSampleType>(nutritionTypes)
            .union(hydrationTypes)
            .union([HKQuantityType(.bodyMass), HKQuantityType(.bodyFatPercentage),
                    HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()])
    }

    /// Shows the Health sheet only if there's something the user hasn't been asked about yet.
    static func requestAllIfNeeded() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let read = HealthKitManager.shared.readTypes
        let status = try? await store.statusForAuthorizationRequest(toShare: shareTypes, read: read)
        guard status == .shouldRequest else { return }
        try? await store.requestAuthorization(toShare: shareTypes, read: read)
    }

    /// The types from this list the app may write right now. Only prompts if
    /// one of them has never been asked about.
    static func writable<T: HKSampleType>(_ types: [T]) async -> [T] {
        if types.contains(where: { store.authorizationStatus(for: $0) == .notDetermined }) {
            await requestAllIfNeeded()
        }
        return types.filter { store.authorizationStatus(for: $0) == .sharingAuthorized }
    }
}

@MainActor
final class HealthSync {
    static let shared = HealthSync()
    private init() {}

    private var container: ModelContainer?
    private var pending: Task<Void, Never>?
    private var ticker: Task<Void, Never>?

    func attach(_ container: ModelContainer) {
        self.container = container
    }

    /// Refresh the last couple of days from Health after `delay`, folding any
    /// requests that arrive in the meantime into the same refresh.
    func refreshSoon(after delay: Duration = .seconds(1)) {
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.refreshNow()
        }
    }

    func refreshNow() async {
        guard let context = container?.mainContext else { return }
        try? await MetricsAggregator(context: context).refresh(days: 2)
        BriefingService.update(with: (try? context.fetch(FetchDescriptor<DailyMetrics>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
    }

    /// While the app is open, recheck Health every minute — catches food
    /// logged in other apps and Health writes that land a little late.
    func startTicking() {
        guard ticker == nil else { return }
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard !Task.isCancelled else { return }
                await self?.refreshNow()
            }
        }
    }

    func stopTicking() {
        ticker?.cancel()
        ticker = nil
    }
}
