import SwiftUI

struct SleepAvailabilityView: View {
    @State private var monitor = SleepAvailabilityMonitor.shared
    @State private var night = Date()
    @State private var selectedRun: UUID?
    @State private var watchOnly = true
    @State private var starting = false

    private var run: SleepDiagnosticRun? {
        monitor.archive.runs.first { $0.id == selectedRun } ?? monitor.archive.runs.last
    }
    private var window: DateInterval {
        let calendar = Calendar.current
        let morning = calendar.startOfDay(for: night)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: morning)!
        return DateInterval(start: calendar.date(bySettingHour: 18, minute: 0, second: 0, of: yesterday)!,
                            end: calendar.date(bySettingHour: 12, minute: 0, second: 0, of: morning)!)
    }
    private var rows: [SleepDiagnosticSample] {
        (run?.samples ?? []).filter {
            $0.end > window.start && $0.start < window.end && (!watchOnly || $0.watch)
        }.sorted { $0.start < $1.start }
    }
    private var measured: [SleepDiagnosticSample] {
        guard let run else { return [] }
        return rows.filter { $0.asleep && $0.eligible(since: run.started) }
    }
    private func duration(_ seconds: Double?) -> String {
        guard let seconds else { return "—" }
        return String(format: "%.1f min", seconds / 60)
    }
    private func time(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .standard)
    }

    var body: some View {
        List {
            Section {
                Text("Measures when sleep samples reach Trace. Local only; no alarm is created and no sleep scores are changed.")
                    .font(.subheadline)
                if monitor.active {
                    Label(monitor.busy ? "Reading sleep data…" : "Monitoring enabled", systemImage: "waveform.path")
                    Text(monitor.deliveryStatus).font(.caption).foregroundStyle(.secondary)
                    Button("Check now") { monitor.checkNow() }.disabled(monitor.busy)
                    Button("Stop monitoring", role: .destructive) { monitor.stop() }.disabled(monitor.busy)
                } else {
                    Button(starting ? "Starting…" : "Start overnight experiment") {
                        starting = true
                        Task {
                            await monitor.start()
                            selectedRun = monitor.archive.runs.last?.id
                            starting = false
                        }
                    }.disabled(starting || monitor.preparing)
                }
                if let error = monitor.error { Text(error).foregroundStyle(.red).font(.caption) }
                if let run {
                    LabeledContent("Started", value: time(run.started))
                    LabeledContent("Initial baseline", value: run.baselineComplete ? "Captured" : "Waiting for a successful read")
                }
            } header: { Text("Sleep data availability") } footer: {
                Text("Allow Sleep read access in Health. An empty query cannot distinguish denied access from no data. Start before bedtime and wait for the initial baseline to be captured.")
            }
            Section("Night to inspect") {
                DatePicker("Night ending", selection: $night, displayedComponents: .date)
                Toggle("Apple Watch sources only", isOn: $watchOnly)
                Text("Window: previous day 18:00 to selected day 12:00, in your current time zone. Watch source detection uses the recorded product/device name.")
                    .font(.caption).foregroundStyle(.secondary)
                if monitor.archive.runs.count > 1 {
                    Picker("Experiment", selection: $selectedRun) {
                        ForEach(monitor.archive.runs) { item in
                            Text(time(item.started)).tag(Optional(item.id))
                        }
                    }
                }
            }
            summary
            Section {
                ForEach(rows) { sample in
                    NavigationLink {
                        sampleDetail(sample)
                    } label: {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(sample.stage).font(.subheadline.weight(.semibold))
                                Spacer()
                                Text(duration(sample.latency)).monospacedDigit()
                            }
                            Text("\(sample.start.formatted(date: .omitted, time: .shortened)) → \(sample.end.formatted(date: .omitted, time: .shortened))")
                            Text("Received \(time(sample.firstObserved)) · \(sample.state)")
                                .font(.caption).foregroundStyle(.secondary)
                            if sample.baseline || sample.deletedAt != nil || sample.end < (run?.started ?? .distantPast) || sample.latency < 0 {
                                Text("Excluded from latency summary: baseline, historical, deleted or invalid timing")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }
                }
                if rows.isEmpty { Text("No matching samples yet. Check source filtering, permissions and the event log.").foregroundStyle(.secondary) }
            } header: { Text("Samples · start → end / received / latency") }
            Section("Delivery and read events") {
                ForEach((run?.events ?? []).suffix(100).reversed()) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(time(event.date)) · \(event.trigger)").font(.caption.weight(.semibold))
                        Text(event.message).font(.caption)
                        Text("\(event.state) · Protected data \(event.protectedDataAvailable ? "available" : "unavailable") · Low power \(event.lowPower ? "on" : "off")")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("Showing the latest 100 events for this experiment. All events remain in the local diagnostic file.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Tonight’s test") {
                Text("Wear your Watch with sleep tracking enabled. Keep the paired iPhone nearby. Disconnect Xcode, lock the phone normally and leave Trace in the background; do not swipe it away. Keep your usual separate wake-up alarm.")
                Text("Tomorrow, open this screen and inspect background receipts before your wake-up time. A check on reopening is labelled separately. Try several nights; successful registration alone does not mean timely sleep delivery.")
                Text("This diagnostic file is protected on-device and excluded from backups. It can be written after the first unlock following a restart; this does not bypass HealthKit’s own protection. No network or AI services receive these logs.")
            }.font(.footnote)
        }
        .navigationTitle("Sleep diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if selectedRun == nil { selectedRun = monitor.archive.runs.last?.id } }
    }

    private var summary: some View {
        let stats = SleepLatencySummary(measured)
        let duringSleep = measured.filter { SleepLatencySummary.receivedDuringSleep($0, all: run?.samples ?? []) }
        return Section {
            LabeledContent("All matching samples", value: "\(rows.count)")
            LabeledContent("Eligible asleep samples", value: "\(measured.count)")
            LabeledContent("Median latency", value: duration(stats.median))
            LabeledContent("Average latency", value: duration(stats.mean))
            LabeledContent("Maximum latency", value: duration(stats.maximum))
            ForEach([1, 5, 10, 15, 30], id: \.self) { minutes in
                LabeledContent("Within \(minutes) min", value: stats.percentage(minutes: Double(minutes)).map { String(format: "%.0f%%", $0) } ?? "—")
            }
            LabeledContent("Received in background", value: "\(measured.filter { $0.state == "Background" }.count)")
            LabeledContent("Received during later sleep", value: "\(duringSleep.count)")
            LabeledContent("…and in background", value: "\(duringSleep.filter { $0.state == "Background" }.count)")
        } header: { Text("Observed latency") } footer: {
            Text("Statistics use new, non-deleted asleep samples only; initial history, pre-experiment intervals and negative latency are excluded. Latency is when Trace first read the sample, not its exact arrival in HealthKit. During later sleep means the receipt falls inside another same-source sleep interval recorded retrospectively; it is not live proof of sleep. Zero means no evidence yet, not that you were awake.")
        }
    }

    private func sampleDetail(_ sample: SleepDiagnosticSample) -> some View {
        List {
            LabeledContent("Stage", value: "\(sample.stage) (\(sample.category))")
            LabeledContent("Start", value: time(sample.start))
            LabeledContent("End", value: time(sample.end))
            LabeledContent("First observed", value: time(sample.firstObserved))
            LabeledContent("Latency", value: duration(sample.latency))
            LabeledContent("App state", value: sample.state)
            LabeledContent("Trigger", value: sample.trigger)
            LabeledContent("Source", value: sample.source)
            LabeledContent("Bundle", value: sample.bundle)
            LabeledContent("Product", value: sample.product ?? "Not supplied")
            LabeledContent("Device", value: sample.device ?? "Not supplied")
            LabeledContent("UUID", value: sample.id.uuidString)
            LabeledContent("Initial history", value: sample.baseline ? "Yes" : "No")
            if let deleted = sample.deletedAt { LabeledContent("Deletion observed", value: time(deleted)) }
        }
        .textSelection(.enabled)
        .navigationTitle("Sample evidence")
    }
}
