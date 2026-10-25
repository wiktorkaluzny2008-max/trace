import Foundation
import ActivityKit

// Keep identical to the app definition.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    nonisolated struct ContentState: Codable, Hashable {
        var exerciseName: String
        var setsDone: Int
        var setsTotal: Int
        var restEndsAt: Date?
        // Optional for compatibility with activities created by an older app build.
        var workoutID: UUID?
        var exerciseID: UUID?
        var setID: UUID?
        var setNumber: Int?
        var setDescription: String?
        var canComplete: Bool?
        var undoExerciseID: UUID?
        var undoSetID: UUID?
    }

    var workoutName: String
    var start: Date
}
