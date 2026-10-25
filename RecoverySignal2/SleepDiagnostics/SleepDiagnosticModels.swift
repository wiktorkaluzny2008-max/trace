import Foundation

// Separate from DailyMetrics: raw delivery evidence, never an input to health scores.
nonisolated struct SleepDiagnosticSample: Codable, Identifiable, Sendable {
    var id: UUID
    var category: Int
    var start: Date
    var end: Date
    var firstObserved: Date
    var source: String
    var bundle: String
    var product: String?
    var device: String?
    var trigger: String
    var state: String
    var protectedDataAvailable: Bool
    var baseline: Bool
    var deletedAt: Date?

    var stage: String {
        switch category {
        case 0: "In bed"
        case 1: "Asleep (unspecified)"
        case 2: "Awake"
        case 3: "Core"
        case 4: "Deep"
        case 5: "REM"
        default: "Unknown (\(category))"
        }
    }
    var asleep: Bool { [1, 3, 4, 5].contains(category) }
    var latency: TimeInterval { firstObserved.timeIntervalSince(end) }
    var watch: Bool { product?.hasPrefix("Watch") == true || device?.localizedCaseInsensitiveContains("Watch") == true }
    var sourceKey: String { bundle + "|" + (product ?? "") + "|" + (device ?? "") }
    func eligible(since startOfRun: Date) -> Bool {
        !baseline && deletedAt == nil && end >= startOfRun && end > start && latency >= 0
    }
}

nonisolated struct SleepDiagnosticEvent: Codable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var trigger: String
    var state: String
    var protectedDataAvailable: Bool
    var lowPower: Bool
    var message: String
}

nonisolated struct SleepDiagnosticRun: Codable, Identifiable, Sendable {
    var id = UUID()
    var started = Date()
    // Fixed for the lifetime of this anchor. Never slide the predicate forward.
    var queryStart = Date().addingTimeInterval(-7 * 86400)
    var stopped: Date?
    var anchor: Data?
    var baselineComplete = false
    var samples: [SleepDiagnosticSample] = []
    var events: [SleepDiagnosticEvent] = []
}

nonisolated struct SleepDiagnosticArchive: Codable, Sendable {
    var version = 1
    var runs: [SleepDiagnosticRun] = []
}

nonisolated struct SleepLatencySummary {
    let values: [Double]
    init(_ samples: [SleepDiagnosticSample]) { values = samples.map(\.latency).sorted() }
    var mean: Double? { values.isEmpty ? nil : values.reduce(0, +) / Double(values.count) }
    var median: Double? {
        guard !values.isEmpty else { return nil }
        let i = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[i - 1] + values[i]) / 2 : values[i]
    }
    var maximum: Double? { values.last }
    func percentage(minutes: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        return 100 * Double(values.filter { $0 <= minutes * 60 }.count) / Double(values.count)
    }
    // Retrospective evidence only: a later recorded same-source sleep interval
    // contains the receipt time. An awake gap or merely being before wake-up is insufficient.
    static func receivedDuringSleep(_ sample: SleepDiagnosticSample, all: [SleepDiagnosticSample]) -> Bool {
        all.contains {
            $0.id != sample.id && $0.asleep && $0.deletedAt == nil && $0.sourceKey == sample.sourceKey &&
            $0.start <= sample.firstObserved && sample.firstObserved < $0.end
        }
    }
}
