import SwiftUI
import SwiftData

/// Value-type drafts keep Cancel from changing a persisted workout.
struct WorkoutLogEditor: View {
    let log: WorkoutLog
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var notes: String
    @State private var exercises: [LoggedExercise]
    @State private var error: String?

    init(log: WorkoutLog) {
        self.log = log
        _name = State(initialValue: log.name)
        _notes = State(initialValue: log.notes)
        _exercises = State(initialValue: log.exercises)
    }

    private var valid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        exercises.allSatisfy { exercise in
            exercise.sets.allSatisfy { set in
                (set.weightKg.map { $0.isFinite && (0...2000).contains($0) } ?? true) &&
                (set.reps.map { (0...10000).contains($0) } ?? true) &&
                (set.seconds.map { (0...86400).contains($0) } ?? true) &&
                (set.rir.map { (0...10).contains($0) } ?? true)
            }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Name", text: $name)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                ForEach($exercises) { $exercise in
                    Section {
                        TextField("Notes", text: $exercise.notes, axis: .vertical)
                        ForEach($exercise.sets) { $set in
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Set \((exercise.sets.firstIndex(where: { $0.id == set.id }) ?? 0) + 1)")
                                    .font(.subheadline.weight(.semibold))
                                Picker("Set type", selection: $set.kind) {
                                    ForEach(SetKind.allCases, id: \.self) { kind in
                                        Text(kind.label).tag(kind)
                                    }
                                }
                                HStack(spacing: 16) {
                                    if exercise.tracking == .weightReps {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text("kg").font(.caption).foregroundStyle(Theme.textSecondary)
                                            LiveNumberField("0", value: $set.weightKg, fractionDigits: 2)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(exercise.tracking == .duration ? "Seconds" : "Reps")
                                            .font(.caption).foregroundStyle(Theme.textSecondary)
                                        if exercise.tracking == .duration {
                                            LiveNumberField("0", value: $set.seconds)
                                        } else {
                                            LiveNumberField("0", value: $set.reps)
                                        }
                                    }
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("RIR").font(.caption).foregroundStyle(Theme.textSecondary)
                                        LiveNumberField("—", value: $set.rir)
                                    }
                                }
                                .textFieldStyle(.roundedBorder)
                                Toggle("Completed", isOn: $set.completed)
                            }
                            .padding(.vertical, 6)
                        }
                    } header: { Text(exercise.name) }
                }
                Section {
                    Text("Changes update your workout history, volume and future exercise suggestions. Recorded time, heart rate and calories in Apple Health stay unchanged.")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                    if !valid {
                        Text("Enter a workout name and valid non-negative set values. RIR must be between 0 and 10.")
                            .font(.footnote).foregroundStyle(Theme.bad)
                    }
                    if let error { Text(error).font(.footnote).foregroundStyle(Theme.bad) }
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Edit workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!valid)
                }
            }
        }
    }

    private func save() {
        guard valid else { return }
        let oldName = log.name, oldNotes = log.notes, oldPayload = log.payload
        do {
            var updated = exercises
            for i in updated.indices {
                for j in updated[i].sets.indices {
                    if !updated[i].sets[j].completed {
                        updated[i].sets[j].completedAt = nil
                    } else if updated[i].sets[j].completedAt == nil {
                        updated[i].sets[j].completedAt = log.end
                    }
                }
            }
            let encoded = try JSONEncoder().encode(updated)
            log.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            log.notes = notes
            log.payload = encoded
            try context.save()
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            dismiss()
        } catch {
            log.name = oldName
            log.notes = oldNotes
            log.payload = oldPayload
            self.error = String(localized: "Could not save changes. Please try again.")
        }
    }
}
