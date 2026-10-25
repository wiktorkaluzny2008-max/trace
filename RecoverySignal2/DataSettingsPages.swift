//
//  DataSettingsPages.swift
//  RecoverySignal2
//
//  Settings → Your data: how to bring macros in from ChatGPT, and exporting
//  everything Trace keeps as CSV files you can open in Numbers or Excel.
//

import SwiftUI
import SwiftData

// MARK: - Log from ChatGPT

struct ChatGPTGuidePage: View {
    @State private var copied = false
    @State private var trying: PastedText?

    /// Asking for totals in a fixed shape makes the reply easy to read reliably.
    static let sampleReply = """
    Chicken rice bowl
    - Chicken breast, 150 g: 248 kcal, 46 g protein, 0 g carbs, 5 g fat
    - Basmati rice, 200 g cooked: 260 kcal, 5 g protein, 57 g carbs, 1 g fat
    - Olive oil, 1 tbsp: 119 kcal, 0 g protein, 0 g carbs, 14 g fat
    Total: Calories: 627 kcal, Protein: 51 g, Carbs: 57 g, Fat: 20 g
    """

    static let promptTip = "At the end, give the totals for the whole meal on one line as: Calories: X kcal, Protein: X g, Carbs: X g, Fat: X g"

    var body: some View {
        SettingsPage(title: "Log from ChatGPT") {
            SettingsNote("ChatGPT can't send data to other apps, but you can bring its numbers into Trace in a couple of taps. Trace reads the calories and macros, shows them to you, and logs them only when you tap Log.")

            SettingsBlock {
                step(1, "Ask ChatGPT for the totals",
                     "Add this line to your question so the numbers come back in a shape Trace reads every time.")
                Text(verbatim: Self.promptTip)
                    .font(.footnote.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                SettingsButton(title: copied ? "Copied" : "Copy this line", symbol: copied ? "checkmark" : "doc.on.doc") {
                    UIPasteboard.general.string = Self.promptTip
                    copied = true
                }
            }

            SettingsBlock {
                step(2, "Copy the reply, then paste in Trace",
                     "In ChatGPT, long-press the reply and copy it. In Trace, open Food, pick the meal and tap Paste.")
                step(3, "Or share it straight to Trace",
                     "In the Shortcuts app, make a shortcut that receives text from the Share Sheet and runs \u{201C}Log Macros in Trace\u{201D}. Then share any ChatGPT reply to that shortcut.")
            }

            SettingsBlock {
                Text("Try it").font(.subheadline.weight(.semibold))
                Text("See what Trace reads from a sample reply.")
                    .font(.footnote).foregroundStyle(Theme.textSecondary)
                SettingsButton(title: "Open a sample", symbol: "text.bubble") {
                    trying = PastedText(text: Self.sampleReply)
                }
            }
        }
        .sheet(item: $trying) { PasteMacrosSheet(text: $0.text) }
    }

    private func step(_ number: Int, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(verbatim: "\(number)")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 24, height: 24)
                .background(Theme.accent.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Export

struct DataExportPage: View {
    @Query(sort: \FoodEntry.date) private var food: [FoodEntry]
    @Query(sort: \WorkoutLog.start) private var workouts: [WorkoutLog]
    @Query(sort: \DailyMetrics.date) private var days: [DailyMetrics]
    @State private var files: [URL] = []

    var body: some View {
        SettingsPage(title: "Export your data") {
            SettingsBlock {
                row("fork.knife", "Food log", "\(food.count) entries")
                Divider().overlay(Theme.separator)
                row("dumbbell.fill", "Workouts", "\(workouts.count) sessions, one row per set")
                Divider().overlay(Theme.separator)
                row("calendar", "Daily metrics", "\(days.count) days of recovery, sleep, activity and nutrition")
                if files.isEmpty {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    ShareLink(items: files) {
                        Label("Export as CSV", systemImage: "square.and.arrow.up")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                }
            }
            SettingsNote("Three CSV files you can save to Files, AirDrop or open in Numbers or Excel. They're made on your iPhone and only go where you send them.")
        }
        .task { files = makeFiles() }
    }

    private func row(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Theme.accent).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold))
                Text(verbatim: detail).font(.caption).foregroundStyle(Theme.textTertiary)
            }
            Spacer()
        }
    }

    private func makeFiles() -> [URL] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let day = DateFormatter()
        day.dateFormat = "yyyy-MM-dd"
        day.locale = Locale(identifier: "en_US_POSIX")

        func cell(_ value: Any?) -> String {
            switch value {
            case let d as Double: return String(format: "%.2f", d)
            case let i as Int: return String(i)
            case let s as String:
                return s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" })
                    ? "\"\(s.replacingOccurrences(of: "\"", with: "\"\""))\"" : s
            case let b as Bool: return b ? "yes" : "no"
            default: return ""
            }
        }
        func csv(_ header: [String], _ rows: [[Any?]]) -> String {
            ([header.joined(separator: ",")] + rows.map { $0.map(cell).joined(separator: ",") }).joined(separator: "\n") + "\n"
        }

        let foodCSV = csv(["time", "meal", "name", "brand", "grams", "kcal", "protein_g", "carbs_g", "fat_g"],
                          food.map { [iso.string(from: $0.date), $0.slot.rawValue, $0.name, $0.brand, $0.grams,
                                      $0.kcal, $0.protein, $0.carbs, $0.fat] })

        var setRows: [[Any?]] = []
        for log in workouts {
            for exercise in log.exercises {
                for (index, set) in exercise.completedSets.enumerated() {
                    setRows.append([iso.string(from: log.start), log.name, exercise.name, index + 1, set.kind.rawValue,
                                    set.weightKg, set.reps, set.seconds, set.rir])
                }
            }
        }
        let workoutCSV = csv(["session_start", "workout", "exercise", "set", "kind", "weight_kg", "reps", "seconds", "rir"], setRows)

        let dayCSV = csv(["date", "hrv_ms", "resting_hr", "vo2max", "sleep_h", "deep_h", "rem_h", "steps", "active_kcal",
                          "strain", "training_load", "weight_kg", "eaten_kcal", "protein_g", "carbs_g", "fat_g"],
                         days.map { [day.string(from: $0.date), $0.hrvSDNN, $0.restingHeartRate, $0.vo2Max, $0.sleepAsleepHours,
                                     $0.sleepDeepHours, $0.sleepREMHours, $0.steps, $0.activeEnergyBurned, $0.strain,
                                     $0.trainingLoad, $0.bodyMassKg, $0.dietaryEnergyKcal, $0.proteinGrams,
                                     $0.carbsGrams, $0.fatGrams] })

        let folder = FileManager.default.temporaryDirectory.appending(path: "Trace export")
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let stamp = day.string(from: Date())
        var urls: [URL] = []
        for (name, body) in [("Trace food log", foodCSV), ("Trace workouts", workoutCSV), ("Trace daily metrics", dayCSV)] {
            let url = folder.appending(path: "\(name) \(stamp).csv")
            if (try? body.write(to: url, atomically: true, encoding: .utf8)) != nil { urls.append(url) }
        }
        return urls
    }
}
