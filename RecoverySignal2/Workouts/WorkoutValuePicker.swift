import SwiftUI

/// Native wheel for fast adjustment, with exact entry for fractional equipment.
struct WorkoutValuePicker: View {
    let exercise: LoggedExercise
    let set: LoggedSet
    let isWeight: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var recorder = WorkoutRecorder.shared
    @State private var value: Double
    @State private var wheel: Int

    init(exercise: LoggedExercise, set: LoggedSet, isWeight: Bool) {
        self.exercise = exercise; self.set = set; self.isWeight = isWeight
        let index = exercise.sets.firstIndex { $0.id == set.id } ?? 0
        let hint = exercise.hint(for: index)
        let initial = isWeight ? (set.weightKg ?? hint?.weightKg ?? 0)
            : Double(exercise.tracking == .duration ? (set.seconds ?? hint?.seconds ?? 30) : (set.reps ?? hint?.reps ?? 8))
        _value = State(initialValue: initial)
        _wheel = State(initialValue: Int(min(max(initial.isFinite ? initial / (isWeight ? 0.5 : 1) : 0, 0), 2000).rounded()))
    }
    private var unit: String { isWeight ? "kg" : exercise.tracking == .duration ? "sec" : "reps" }
    private var range: ClosedRange<Int> { 0...max(isWeight ? 1000 : 600, wheel) }

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Text("Exact value").font(.subheadline).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    LiveNumberField(value: $value, fractionDigits: isWeight ? 2 : 0)
                        .font(.title2.weight(.semibold)).monospacedDigit().multilineTextAlignment(.trailing)
                        .frame(width: 120, height: 48).accessibilityLabel("Exact value")
                    Text(unit).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 20)
                Picker(unit, selection: $wheel) {
                    ForEach(range, id: \.self) { step in
                        Text("\(DetailFormat.decimal(Double(step) * (isWeight ? 0.5 : 1), isWeight ? 1 : 0)) \(unit)").tag(step)
                    }
                }
                .pickerStyle(.wheel).frame(maxHeight: .infinity)
                .onChange(of: wheel) { _, new in value = Double(new) * (isWeight ? 0.5 : 1) }
                .sensoryFeedback(.selection, trigger: wheel)
            }
            .padding(.top, 12)
            .background(Theme.background)
            .navigationTitle(isWeight ? "Weight" : exercise.tracking == .duration ? "Duration" : "Repetitions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        recorder.update { workout in
                            guard let i = workout.exercises.firstIndex(where: { $0.id == exercise.id }),
                                  let j = workout.exercises[i].sets.firstIndex(where: { $0.id == set.id }) else { return }
                            if isWeight { workout.exercises[i].sets[j].weightKg = value }
                            else if exercise.tracking == .duration { workout.exercises[i].sets[j].seconds = Int(value) }
                            else { workout.exercises[i].sets[j].reps = Int(value) }
                        }
                        dismiss()
                    }.disabled(!value.isFinite || value < 0 || value > 100_000 || (!isWeight && value == 0))
                }
            }
        }.tint(Theme.accent)
    }
}
