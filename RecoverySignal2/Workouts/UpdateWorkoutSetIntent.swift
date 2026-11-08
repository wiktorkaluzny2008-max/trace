import AppIntents
import Foundation

struct UpdateWorkoutSetIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Update workout set"
    static var openAppWhenRun: Bool = false
    static var isDiscoverable: Bool = false

    @Parameter(title: "Workout") var workoutID: String
    @Parameter(title: "Exercise") var exerciseID: String
    @Parameter(title: "Set") var setID: String
    @Parameter(title: "Completed") var completed: Bool

    init() {}
    init(workoutID: UUID, exerciseID: UUID, setID: UUID, completed: Bool) {
        self.workoutID = workoutID.uuidString
        self.exerciseID = exerciseID.uuidString
        self.setID = setID.uuidString
        self.completed = completed
    }

    #if TRACE_WIDGET_EXTENSION
    private func requireAppProcess() throws {
        throw NSError(domain: "Trace.Workout", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Open Trace to continue your workout."])
    }
    #endif

    @MainActor
    func perform() async throws -> some IntentResult {
        #if TRACE_WIDGET_EXTENSION
        // LiveActivityIntent dispatches to the app target, where the recorder lives.
        try requireAppProcess()
        #else
        if let workout = UUID(uuidString: workoutID), let exercise = UUID(uuidString: exerciseID), let set = UUID(uuidString: setID) {
            let recorder = WorkoutRecorder.shared
            recorder.setFromLockScreen(workoutID: workout, exerciseID: exercise, setID: set, completed: completed)
            // Write the draft and publish the final snapshot now, then await it,
            // before the system suspends the intent process.
            recorder.flushDraft()
            await WorkoutLiveActivity.flush()
        }
        #endif
        return .result()
    }
}
