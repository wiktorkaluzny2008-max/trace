//
//  BodyLogStore.swift
//  RecoverySignal2
//
//  Weight and body-fat entries, read from and written to Apple Health. Health
//  stays the single source of truth: entries logged here, by a smart scale or
//  in the Health app all show up together, and the rest of the app (trend
//  weight, adaptive maintenance, forecasts) picks them up on the next refresh.
//

import Foundation
import HealthKit
import UserNotifications

struct BodyEntry: Identifiable, Hashable {
    enum Kind: Hashable { case weight, bodyFat }

    let id: UUID
    let kind: Kind
    let date: Date
    /// kg for weight, percent (0–100) for body fat.
    let value: Double
    let source: String
    /// Only entries this app wrote can be deleted from here.
    let isOwn: Bool
}

@MainActor
@Observable
final class BodyLogStore {
    static let shared = BodyLogStore()

    private(set) var weights: [BodyEntry] = []
    private(set) var bodyFat: [BodyEntry] = []
    private(set) var isLoading = false

    private let store = HealthKitManager.shared.store
    private var samplesByID: [UUID: HKQuantitySample] = [:]

    private init() {}

    private static var weightType: HKQuantityType { HKQuantityType(.bodyMass) }
    private static var fatType: HKQuantityType { HKQuantityType(.bodyFatPercentage) }

    var latestWeight: BodyEntry? { weights.first }
    var latestBodyFat: BodyEntry? { bodyFat.first }

    // MARK: Reading

    func load(days: Int = 365) async {
        isLoading = true
        defer { isLoading = false }
        let start = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        async let w = samples(Self.weightType, from: start)
        async let f = samples(Self.fatType, from: start)
        let (weightSamples, fatSamples) = await (w, f)
        let own = Bundle.main.bundleIdentifier

        samplesByID = Dictionary((weightSamples + fatSamples).map { ($0.uuid, $0) }, uniquingKeysWith: { a, _ in a })
        weights = weightSamples.map {
            BodyEntry(id: $0.uuid, kind: .weight, date: $0.startDate,
                      value: $0.quantity.doubleValue(for: .gramUnit(with: .kilo)),
                      source: $0.sourceRevision.source.name, isOwn: $0.sourceRevision.source.bundleIdentifier == own)
        }
        bodyFat = fatSamples.map {
            BodyEntry(id: $0.uuid, kind: .bodyFat, date: $0.startDate,
                      value: $0.quantity.doubleValue(for: .percent()) * 100,
                      source: $0.sourceRevision.source.name, isOwn: $0.sourceRevision.source.bundleIdentifier == own)
        }
    }

    private func samples(_ type: HKQuantityType, from start: Date) async -> [HKQuantitySample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil, options: [])
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)]
        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                      sortDescriptors: sort) { _, samples, _ in
                continuation.resume(returning: samples as? [HKQuantitySample] ?? [])
            }
            store.execute(query)
        }
    }

    // MARK: Writing

    enum SaveError: LocalizedError {
        case notAllowed

        var errorDescription: String? {
            String(localized: "Trace isn't allowed to save weight to Apple Health. Turn it on in Settings → Health → Data Access & Devices → Trace.")
        }
    }

    func save(weightKg: Double, bodyFatPercent: Double?, at date: Date) async throws {
        let allowed = await HealthAccess.writable([Self.weightType, Self.fatType])
        guard allowed.contains(Self.weightType) else { throw SaveError.notAllowed }

        var objects: [HKObject] = [
            HKQuantitySample(type: Self.weightType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: weightKg),
                             start: date, end: date)
        ]
        if let bodyFatPercent, allowed.contains(Self.fatType) {
            objects.append(HKQuantitySample(type: Self.fatType, quantity: HKQuantity(unit: .percent(), doubleValue: bodyFatPercent / 100),
                                            start: date, end: date))
        }
        try await store.save(objects)
        await load()
    }

    func delete(_ entry: BodyEntry) async {
        guard entry.isOwn, let sample = samplesByID[entry.id] else { return }
        try? await store.delete(sample)
        await load()
    }

    // MARK: Reminder

    private static let reminderKey = "bodyLog.reminder"
    private static let reminderHourKey = "bodyLog.reminderHour"
    private static let reminderMinuteKey = "bodyLog.reminderMinute"
    private static let reminderID = "bodyLog.weighIn"

    static var reminderEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: reminderKey) }
        set { UserDefaults.standard.set(newValue, forKey: reminderKey) }
    }

    static var reminderTime: DateComponents {
        get {
            let d = UserDefaults.standard
            return DateComponents(hour: d.object(forKey: reminderHourKey) as? Int ?? 7,
                                  minute: d.object(forKey: reminderMinuteKey) as? Int ?? 15)
        }
        set {
            UserDefaults.standard.set(newValue.hour, forKey: reminderHourKey)
            UserDefaults.standard.set(newValue.minute, forKey: reminderMinuteKey)
        }
    }

    /// Daily "weigh in" nudge, best done after the bathroom and before breakfast.
    static func scheduleReminder() async -> Bool {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [reminderID])
        guard reminderEnabled else { return true }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "Morning weigh-in")
        content.body = String(localized: "Step on the scale before breakfast — same time each day gives the cleanest trend.")
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: reminderTime, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: reminderID, content: content, trigger: trigger))
        return true
    }
}
