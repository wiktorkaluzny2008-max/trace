//
//  HevyScreenshotImporter.swift
//  RecoverySignal2
//
//  Reads a Hevy workout from screenshots of its summary screen. Hevy keeps
//  per-set data out of Apple Health and its API needs Hevy Pro, so the
//  screenshot you'd take anyway is the free, exact route. Several screenshots
//  of one long workout are read together as one session.
//

import UIKit

struct ImportedWorkout {
    var title: String
    var date: Date?
    var exercises: [ImportedExercise]
}

enum HevyScreenshotImporter {

    static func read(_ screenshots: [UIImage]) async throws -> ImportedWorkout {
        let images = screenshots.compactMap { $0.preparedForUpload() }
        guard !images.isEmpty else {
            throw AIClient.AIError.requestFailed("Couldn't read those screenshots. Try again.")
        }

        let muscleKeys = Muscle.allCases.map(\.rawValue).joined(separator: ", ")

        let system = """
        You read workout logs from screenshots of the Hevy app. The images all belong to ONE workout,
        possibly scrolled across several screenshots — merge them and never list an exercise twice
        just because it appears on two overlapping screenshots.

        For every exercise, list every set in order. In Hevy, a set marked "W" is a warm-up,
        "F" is a failure set, "D" is a drop set; otherwise it is a normal set.
        Weights: convert lbs to kg (× 0.4536). Bodyweight exercises have weight_kg null.
        Duration or distance-only sets (e.g. cardio): include the exercise with reps null.
        If a value isn't visible, use null rather than guessing.

        For each exercise also give the muscles it trains, using ONLY these keys:
        \(muscleKeys)
        Split shoulders precisely: lateral raises are sideDelts, face pulls / reverse flys are rearDelts,
        presses and front raises are frontDelts.

        Respond with JSON only, in exactly this shape:
        {"title": string, "date": "YYYY-MM-DD" | null,
         "exercises": [{"name": string,
                        "sets": [{"type": "warmup" | "normal" | "failure" | "dropset", "weight_kg": number | null, "reps": number | null}],
                        "primary_muscles": [string], "secondary_muscles": [string]}]}
        Use the exercise names exactly as Hevy shows them. date is the workout date if visible.
        """

        let text = try await AIClient().send(system: system,
                                             user: "Extract this workout.",
                                             maxTokens: 4000, temperature: 0.1, json: true,
                                             images: images,
                                             onDeviceContext: { await OnDeviceAI.screenText(images) },
                                             accepts: { (try? JSONDecoder().decode(RawWorkout.self, from: Data($0.utf8)))?.exercises?.isEmpty == false })
        do {
            let raw = try JSONDecoder().decode(RawWorkout.self, from: Data(text.utf8))
            return raw.converted()
        } catch {
            throw AIClient.AIError.requestFailed("The workout came back in an unexpected format. Try again, or crop the screenshots to the workout.")
        }
    }

    // MARK: Decoding

    private struct RawWorkout: Decodable {
        let title: String?
        let date: String?
        let exercises: [RawExercise]?

        func converted() -> ImportedWorkout {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"

            let exercises = (exercises ?? []).compactMap { raw -> ImportedExercise? in
                let sets = raw.sets.map {
                    ImportedSet(kind: ImportedSet.Kind(rawValue: $0.type?.lowercased() ?? "") ?? .normal,
                                weightKg: $0.weightKg, reps: $0.reps)
                }
                guard !raw.name.trimmingCharacters(in: .whitespaces).isEmpty, !sets.isEmpty else { return nil }
                return ImportedExercise(name: raw.name, sets: sets,
                                        aiPrimary: raw.primary.compactMap(Muscle.init(rawValue:)),
                                        aiSecondary: raw.secondary.compactMap(Muscle.init(rawValue:)))
            }
            return ImportedWorkout(title: (title?.isEmpty == false ? title : nil) ?? "Workout",
                                   date: date.flatMap(formatter.date(from:)),
                                   exercises: exercises)
        }
    }

    private struct RawExercise: Decodable {
        let name: String
        let sets: [RawSet]
        let primary: [String]
        let secondary: [String]

        enum CodingKeys: String, CodingKey {
            case name, sets
            case primary = "primary_muscles"
            case secondary = "secondary_muscles"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            sets = (try? c.decode([RawSet].self, forKey: .sets)) ?? []
            primary = (try? c.decode([String].self, forKey: .primary)) ?? []
            secondary = (try? c.decode([String].self, forKey: .secondary)) ?? []
        }
    }

    private struct RawSet: Decodable {
        let type: String?
        let weightKg: Double?
        let reps: Double?

        enum CodingKeys: String, CodingKey {
            case type
            case weightKg = "weight_kg"
            case reps
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            type = try? c.decode(String.self, forKey: .type)
            weightKg = Self.number(c, .weightKg)
            reps = Self.number(c, .reps)
        }

        private static func number(_ c: KeyedDecodingContainer<CodingKeys>, _ key: CodingKeys) -> Double? {
            if let v = try? c.decode(Double.self, forKey: key) { return v }
            guard let s = try? c.decode(String.self, forKey: key) else { return nil }
            return Double(s.prefix { $0.isNumber || $0 == "." })
        }
    }
}
