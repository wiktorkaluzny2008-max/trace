// Run with the command in SLEEP_AVAILABILITY_DIAGNOSTIC.md. No HealthKit writes.
import Foundation

@main
struct SleepDiagnosticChecks {
    static func main() throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        func sample(_ latency: Double, category: Int = 3) -> SleepDiagnosticSample {
            SleepDiagnosticSample(id: UUID(), category: category, start: start.addingTimeInterval(60),
                end: start.addingTimeInterval(120), firstObserved: start.addingTimeInterval(120 + latency),
                source: "Test Watch", bundle: "test.watch", product: "Watch1,1", device: "Test device",
                trigger: "Observer", state: "Background", protectedDataAvailable: false, baseline: false)
        }
        let empty = SleepLatencySummary([])
        precondition(empty.mean == nil && empty.median == nil && empty.percentage(minutes: 1) == nil)
        let rows = [sample(0), sample(60), sample(300), sample(600)]
        let stats = SleepLatencySummary(rows)
        precondition(stats.mean == 240 && stats.median == 180 && stats.maximum == 600)
        precondition(stats.percentage(minutes: 1) == 50 && stats.percentage(minutes: 5) == 75)
        precondition(stats.percentage(minutes: 10) == 100)
        precondition(SleepLatencySummary([sample(10), sample(20), sample(30)]).median == 20)
        precondition(sample(1).eligible(since: start))
        precondition(!sample(-1).eligible(since: start))
        precondition(!sample(10).eligible(since: start.addingTimeInterval(180)))
        var old = sample(10)
        old.baseline = true
        precondition(!old.eligible(since: start))
        old.baseline = false
        old.deletedAt = start
        precondition(!old.eligible(since: start))
        precondition(!sample(1, category: 0).asleep && !sample(1, category: 2).asleep)
        precondition(sample(1, category: 1).asleep && sample(1, category: 4).asleep && sample(1, category: 5).asleep)
        precondition(sample(1, category: 99).stage == "Unknown (99)")
        let first = sample(60)
        var later = sample(100)
        later.start = start.addingTimeInterval(170)
        later.end = start.addingTimeInterval(240)
        precondition(SleepLatencySummary.receivedDuringSleep(first, all: [first, later]))
        later.category = 2
        precondition(!SleepLatencySummary.receivedDuringSleep(first, all: [later]))
        later.category = 3
        later.bundle = "other.source"
        precondition(!SleepLatencySummary.receivedDuringSleep(first, all: [later]))
        later.bundle = first.bundle
        later.end = first.firstObserved // Half-open interval: end is not asleep.
        precondition(!SleepLatencySummary.receivedDuringSleep(first, all: [later]))
        var run = SleepDiagnosticRun()
        run.samples = rows
        run.anchor = Data([1, 2, 3])
        let archive = SleepDiagnosticArchive(runs: [run])
        let roundTrip = try JSONDecoder().decode(SleepDiagnosticArchive.self, from: JSONEncoder().encode(archive))
        precondition(roundTrip.runs[0].samples.map(\.id) == rows.map(\.id))
        precondition(roundTrip.runs[0].samples.map(\.firstObserved) == rows.map(\.firstObserved))
        precondition(roundTrip.runs[0].anchor == run.anchor)
        print("Sleep diagnostic checks passed: statistics, exclusions, stages, retrospective evidence, persistence.")
    }
}
