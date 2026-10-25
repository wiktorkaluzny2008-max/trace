"""Host-side regression harness using the production set actions and hint logic.
UI haptics and notification scheduling are replaced by no-op adapters; WidgetKit
intent dispatch still requires a physical iPhone check.
"""
from pathlib import Path
import subprocess
import tempfile
root = Path(__file__).resolve().parents[1]
recorder = (root / 'RecoverySignal2/Workouts/WorkoutRecorder.swift').read_text()
models = (root / 'RecoverySignal2/Workouts/WorkoutModels.swift').read_text()

def block(text, signature):
    start = text.index(signature)
    first = text.index('{', start)
    depth = 1
    i = first + 1
    while depth:
        depth += (text[i] == '{') - (text[i] == '}')
        i += 1
    return text[start:i]

source = '''import Foundation
struct ExerciseTarget: Codable, Hashable {
    var weightKg: Double?; var reps: Int?; var seconds: Int?; var rir: Int = 2
}
enum MuscleFeedback { enum JointPain: String, Codable { case none } }
enum SetTracking: String, Codable { case weightReps, reps, duration }
struct UINotificationFeedbackGenerator {
    enum Kind { case error }; func notificationOccurred(_ kind: Kind) {}
}
struct UIImpactFeedbackGenerator {
    enum Style { case medium, light }
    init(style: Style) {}
    func impactOccurred() {}
}
'''
source += models[models.index('enum SetKind:'):models.index('@Model')]
source += block(recorder, 'struct ActiveWorkout:')
source += '''
final class WorkoutRecorder {
    let defaults = UserDefaults(suiteName: "Trace.LockScreen.Tests.\\(UUID().uuidString)")!
    private static let draftKey = "workout.activeDraft"
    var active: ActiveWorkout? { didSet { persist() } }
    var restEndsAt: Date?
    var rests = 0
    var saveError: String?
    var batchingDraft = false
    func persist() {
        guard !batchingDraft else { return }
        if let active, let data = try? JSONEncoder().encode(active) { defaults.set(data, forKey: Self.draftKey) }
    }
    func startRest(seconds: Int) { rests += 1; restEndsAt = Date().addingTimeInterval(Double(seconds)) }
    func cancelRest() { restEndsAt = nil }
'''
for signature in ['func update(', 'func toggleSet(', 'func setFromLockScreen(']:
    source += block(recorder, signature).replace('UserDefaults.standard', 'defaults') + '\n'
source += '''}
let r = WorkoutRecorder()
let previous = LoggedSet(weightKg: 80, reps: 10)
let warmup = LoggedSet(kind: .warmup)
let first = LoggedSet()
let second = LoggedSet()
let exercise = LoggedExercise(exerciseID: "bench", name: "Bench", primaryMuscle: "chest", tracking: .weightReps,
                              sets: [warmup, first, second], previous: [previous, previous, previous])
let workout = ActiveWorkout(name: "Test", exercises: [exercise])
r.active = workout
func act(_ set: UUID, done: Bool = true, workoutID: UUID = workout.id) {
    r.setFromLockScreen(workoutID: workoutID, exerciseID: exercise.id, setID: set, completed: done)
}
act(first.id, workoutID: UUID())
act(warmup.id)
act(second.id)
precondition(r.rests == 0) // wrong session, warmup and out-of-order controls are rejected.
act(first.id)
precondition(r.active!.exercises[0].sets[1].completed)
precondition(r.active!.exercises[0].sets[1].weightKg == 80 && r.active!.exercises[0].sets[1].reps == 10)
precondition(r.rests == 1 && r.restEndsAt != nil)
let stamp = r.active!.exercises[0].sets[1].completedAt
act(first.id)
precondition(r.rests == 1 && r.active!.exercises[0].sets[1].completedAt == stamp)
act(second.id)
act(first.id, done: false) // stale undo cannot clear an earlier set or cancel current rest.
precondition(r.active!.exercises[0].sets[1].completed && r.restEndsAt != nil)
act(second.id, done: false)
precondition(!r.active!.exercises[0].sets[2].completed && r.restEndsAt == nil)
act(second.id, done: false)
precondition(r.rests == 2)
let restored = try JSONDecoder().decode(ActiveWorkout.self, from: r.defaults.data(forKey: "workout.activeDraft")!)
precondition(restored.exercises[0].sets[1].completed && !restored.exercises[0].sets[2].completed)
// A first-time exercise with no inputs must never record a fictitious set.
r.active = ActiveWorkout(name: "Empty", exercises: [LoggedExercise(exerciseID: "new", name: "New", primaryMuscle: "other", tracking: .weightReps, sets: [LoggedSet()])])
func completeCurrent() {
    let w = r.active!, e = w.exercises[0]
    r.setFromLockScreen(workoutID: w.id, exerciseID: e.id, setID: e.sets[0].id, completed: true)
}
completeCurrent()
precondition(!r.active!.exercises[0].sets[0].completed)
r.update { $0.exercises[0].sets[0].weightKg = 0; $0.exercises[0].sets[0].reps = 8 }
completeCurrent()
precondition(r.active!.exercises[0].sets[0].completed) // zero external load is legitimate.
for tracking in [SetTracking.reps, .duration] {
    var e = LoggedExercise(exerciseID: "other", name: "Other", primaryMuscle: "other", tracking: tracking, sets: [LoggedSet()])
    e.sets[0].reps = tracking == .reps ? 12 : nil
    e.sets[0].seconds = tracking == .duration ? 30 : nil
    r.active = ActiveWorkout(name: "Test", exercises: [e])
    completeCurrent()
    precondition(r.active!.exercises[0].sets[0].completed)
}
r.active = nil
act(first.id)
precondition(r.active == nil)
print("PASS: session IDs, warmups, order, hint acceptance, duplicate taps, undo, rest, persistence, empty values and tracking modes")
'''
with tempfile.TemporaryDirectory(prefix='trace-workout-checks-') as folder:
    swift = Path(folder) / 'main.swift'
    swift.write_text(source)
    binary = Path(folder) / 'checks'
    subprocess.run(['xcrun', 'swiftc', '-module-cache-path', '/tmp/trace-workout-swift-cache', str(swift), '-o', str(binary)], check=True)
    subprocess.run([str(binary)], check=True)
# Prevent contract drift between extension and app.
app = (root / 'RecoverySignal2/Workouts/WorkoutLiveActivity.swift').read_text()
widget = (root / 'HealthWidgets/WorkoutActivityAttributes.swift').read_text()
assert block(app, 'nonisolated struct WorkoutActivityAttributes:') == block(widget, 'nonisolated struct WorkoutActivityAttributes:')
assert (root / 'RecoverySignal2/Workouts/UpdateWorkoutSetIntent.swift').read_text() == (root / 'HealthWidgets/UpdateWorkoutSetIntent.swift').read_text()
print('PASS: app/widget activity schema and intent definitions match')
