import HealthKit
import Observation
import UIKit

@MainActor
@Observable
final class SleepAvailabilityMonitor {
    static let shared = SleepAvailabilityMonitor()
    private(set) var archive = SleepDiagnosticArchive()
    private(set) var error: String?
    private(set) var busy = false
    private(set) var preparing = false
    private(set) var deliveryStatus = "Not requested"
    private let store = HealthKitManager.shared.store
    private let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
    private var observer: HKObserverQuery?
    private var query: HKAnchoredObjectQuery?
    private var requestID: UUID?
    private var timeout: Task<Void, Never>?
    private var completions: [() -> Void] = []
    private var pendingCompletions: [() -> Void] = []
    private var retryRequested = false
    private var loaded = false
    private var file: URL { URL.applicationSupportDirectory.appending(path: "SleepAvailability/observations.json") }
    var active: Bool { archive.runs.last.map { $0.stopped == nil } ?? false }

    private init() { load() }

    private func load() {
        do {
            do {
                let saved = try JSONDecoder().decode(SleepDiagnosticArchive.self, from: Data(contentsOf: file))
                guard saved.version == 1 else { throw failure("Unsupported diagnostic file version; original file preserved.") }
                archive = saved
            } catch let readError as NSError where readError.domain == NSCocoaErrorDomain && readError.code == NSFileReadNoSuchFileError {
                // Before first unlock, absence cannot safely be treated as a new experiment.
                guard UIApplication.shared.isProtectedDataAvailable else {
                    throw failure("Unlock the phone once to load the diagnostic log.")
                }
            }
            loaded = true
            error = nil
        } catch { self.error = "Cannot read diagnostic log: \(error.localizedDescription)" }
    }

    // Archive and anchor commit together. A failed disk write cannot advance the cursor.
    @discardableResult
    private func commit(_ next: SleepDiagnosticArchive) -> Bool {
        do {
            var folder = file.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
            var resource = URLResourceValues()
            resource.isExcludedFromBackup = true
            try folder.setResourceValues(resource)
            try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            archive = next
            error = nil
            return true
        } catch { self.error = "Diagnostic log was not saved: \(error.localizedDescription)"; return false }
    }

    private func failure(_ message: String) -> NSError {
        NSError(domain: "Trace.SleepAvailability", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
    private var state: String {
        switch UIApplication.shared.applicationState {
        case .active: "Foreground"
        case .background: "Background"
        default: "Inactive"
        }
    }
    private func event(_ trigger: String, _ message: String, at date: Date = Date()) -> SleepDiagnosticEvent {
        SleepDiagnosticEvent(date: date, trigger: trigger, state: state,
            protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
            lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, message: message)
    }
    private func record(_ trigger: String, _ message: String, at date: Date = Date()) {
        guard !archive.runs.isEmpty else { return }
        var next = archive
        next.runs[next.runs.count - 1].events.append(event(trigger, message, at: date))
        commit(next)
    }

    func start() async {
        guard !active, !preparing, loaded else { return }
        preparing = true
        defer { preparing = false }
        do {
            guard HKHealthStore.isHealthDataAvailable() else { throw failure("HealthKit is unavailable.") }
            // Read-only request; completion does not reveal whether read access was granted.
            try await store.requestAuthorization(toShare: [], read: [type])
            var next = archive
            next.runs.append(SleepDiagnosticRun())
            guard commit(next) else { return }
            restore(trigger: "Start")
        } catch { self.error = error.localizedDescription }
    }

    func stop() {
        guard active, !busy else { return }
        var next = archive
        next.runs[next.runs.count - 1].stopped = Date()
        next.runs[next.runs.count - 1].events.append(event("Stop", "Monitoring stopped; results retained."))
        guard commit(next) else { return }
        if let observer { store.stop(observer) }
        observer = nil
        // Existing Trace observers cover quantities only; this prototype owns sleep delivery.
        preparing = true
        store.disableBackgroundDelivery(for: type) { _, error in
            Task { @MainActor in
                if let error { self.record("Disable delivery", error.localizedDescription) }
                self.deliveryStatus = "Stopped"
                self.preparing = false
            }
        }
    }

    // Called during didFinishLaunching, independent of onboarding, UI tasks and aggregation.
    func restore(trigger: String) {
        if !loaded { load() }
        guard loaded, active else { return }
        if observer == nil {
            let observer = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                let arrived = Date()
                Task { @MainActor in
                    guard self.active else { completion(); return }
                    if let error {
                        self.record("Observer error", error.localizedDescription, at: arrived)
                        completion()
                        return
                    }
                    self.record("Observer callback", "HealthKit change notification (not sample receipt).", at: arrived)
                    self.fetch(trigger: "Observer", completion: completion)
                }
            }
            self.observer = observer
            store.execute(observer)
            deliveryStatus = "Requesting immediate delivery"
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { success, error in
                Task { @MainActor in
                    self.deliveryStatus = success ? "Immediate delivery registered" : "Delivery registration failed"
                    self.record("Registration", error?.localizedDescription ?? self.deliveryStatus)
                }
            }
        }
        fetch(trigger: trigger)
    }

    func checkNow() { restore(trigger: "Manual check") }

    private func fetch(trigger: String, completion: (() -> Void)? = nil) {
        guard active else { completion?(); return }
        if busy {
            // A callback arriving mid-read belongs to the next read, not the in-flight snapshot.
            if let completion { pendingCompletions.append(completion) }
            retryRequested = true
            return
        }
        if let completion { completions.append(completion) }
        busy = true
        let id = UUID()
        requestID = id
        let run = archive.runs[archive.runs.count - 1]
        do {
            let anchor = try run.anchor.map { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
            let predicate = HKQuery.predicateForSamples(withStart: run.queryStart, end: nil)
            record(trigger, "Read started; background refresh status \(UIApplication.shared.backgroundRefreshStatus.rawValue).")
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor ?? nil,
                                             limit: HKObjectQueryNoLimit) { _, samples, deleted, anchor, queryError in
                // Capture at data callback, before hopping onto the UI executor.
                let observed = Date()
                Task { @MainActor in
                    guard self.requestID == id else { return }
                    if let queryError {
                        self.record(trigger, "Read failed: \(queryError.localizedDescription)", at: observed)
                    } else {
                        do {
                            guard let anchor else { throw self.failure("HealthKit returned no anchor.") }
                            var next = self.archive
                            let i = next.runs.count - 1
                            var known = Set(next.runs[i].samples.map(\.id))
                            for sample in (samples as? [HKCategorySample]) ?? [] where known.insert(sample.uuid).inserted {
                                let revision = sample.sourceRevision
                                let device = sample.device.map { [$0.name, $0.model, $0.hardwareVersion, $0.softwareVersion].compactMap { $0 }.joined(separator: " · ") }
                                next.runs[i].samples.append(SleepDiagnosticSample(
                                    id: sample.uuid, category: sample.value, start: sample.startDate, end: sample.endDate,
                                    firstObserved: observed, source: revision.source.name, bundle: revision.source.bundleIdentifier,
                                    product: revision.productType, device: device, trigger: trigger, state: self.state,
                                    protectedDataAvailable: UIApplication.shared.isProtectedDataAvailable,
                                    baseline: !next.runs[i].baselineComplete, deletedAt: nil))
                            }
                            let deletedIDs = Set((deleted ?? []).map(\.uuid))
                            for j in next.runs[i].samples.indices where deletedIDs.contains(next.runs[i].samples[j].id) {
                                next.runs[i].samples[j].deletedAt = observed
                            }
                            next.runs[i].anchor = try NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
                            next.runs[i].baselineComplete = true
                            next.runs[i].events.append(self.event(trigger, "Read complete: \(samples?.count ?? 0) additions, \(deletedIDs.count) deletions.", at: observed))
                            self.commit(next)
                        } catch { self.record(trigger, "Processing failed: \(error.localizedDescription)", at: observed) }
                    }
                    self.finish()
                }
            }
            self.query = query
            store.execute(query)
            timeout = Task { @MainActor in
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled, self.requestID == id else { return }
                self.record(trigger, "Read timed out; anchor retained. Retry on next callback, unlock or foreground.")
                self.finish()
            }
        } catch {
            record(trigger, "Anchor could not be decoded: \(error.localizedDescription)")
            finish()
        }
    }

    private func finish() {
        timeout?.cancel()
        timeout = nil
        if let query { store.stop(query) }
        query = nil
        requestID = nil
        busy = false
        let callbacks = completions
        completions = []
        callbacks.forEach { $0() }
        if retryRequested {
            retryRequested = false
            completions = pendingCompletions
            pendingCompletions = []
            fetch(trigger: "Coalesced change")
        }
    }
}

final class SleepDiagnosticAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SleepAvailabilityMonitor.shared.restore(trigger: "Launch")
        return true
    }
    func applicationProtectedDataDidBecomeAvailable(_ application: UIApplication) {
        SleepAvailabilityMonitor.shared.restore(trigger: "Protected data available")
    }
}
