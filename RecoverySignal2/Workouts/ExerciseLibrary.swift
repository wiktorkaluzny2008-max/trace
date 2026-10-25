//
//  ExerciseLibrary.swift
//  RecoverySignal2
//
//  Every exercise you can add to a routine. The catalogue is the open,
//  public-domain free-exercise-db (github.com/yuhonas/free-exercise-db):
//  876 exercises across strength, powerlifting, olympic lifting, strongman,
//  plyometrics, cardio and stretching, each with step-by-step instructions,
//  muscles worked and a start/finish photo pair that the app animates as a
//  demonstration. It's downloaded once and cached, so it works offline after
//  the first launch. A handful of popular gym staples missing from that set
//  are built in, and you can add your own.
//

import Foundation
import SwiftUI
import UIKit

struct Exercise: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    var force: String?
    var level: String?
    var mechanic: String?
    var equipment: String?
    var primaryMuscles: [String]
    var secondaryMuscles: [String]
    var instructions: [String]
    var category: String?
    var images: [String]
    var isCustom: Bool = false

    enum CodingKeys: String, CodingKey {
        case id, name, force, level, mechanic, equipment, primaryMuscles, secondaryMuscles, instructions, category, images, isCustom
    }

    init(id: String, name: String, force: String? = nil, level: String? = nil, mechanic: String? = nil,
         equipment: String? = nil, primaryMuscles: [String], secondaryMuscles: [String] = [],
         instructions: [String] = [], category: String? = "strength", images: [String] = [], isCustom: Bool = false) {
        self.id = id
        self.name = name
        self.force = force
        self.level = level
        self.mechanic = mechanic
        self.equipment = equipment
        self.primaryMuscles = primaryMuscles
        self.secondaryMuscles = secondaryMuscles
        self.instructions = instructions
        self.category = category
        self.images = images
        self.isCustom = isCustom
    }

    /// Lenient decoding: the dataset leaves some fields null.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        force = try? c.decodeIfPresent(String.self, forKey: .force)
        level = try? c.decodeIfPresent(String.self, forKey: .level)
        mechanic = try? c.decodeIfPresent(String.self, forKey: .mechanic)
        equipment = try? c.decodeIfPresent(String.self, forKey: .equipment)
        primaryMuscles = (try? c.decodeIfPresent([String].self, forKey: .primaryMuscles)) ?? []
        secondaryMuscles = (try? c.decodeIfPresent([String].self, forKey: .secondaryMuscles)) ?? []
        instructions = (try? c.decodeIfPresent([String].self, forKey: .instructions)) ?? []
        category = try? c.decodeIfPresent(String.self, forKey: .category)
        images = (try? c.decodeIfPresent([String].self, forKey: .images)) ?? []
        isCustom = (try? c.decodeIfPresent(Bool.self, forKey: .isCustom)) ?? false
    }

    var imageURLs: [URL] {
        images.compactMap { URL(string: ExerciseLibrary.imageBase + $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) }
    }

    var primaryMuscle: String { primaryMuscles.first ?? category ?? "other" }

    var muscleLabel: String { primaryMuscles.map(\.capitalized).joined(separator: ", ") }

    var equipmentLabel: String { (equipment ?? "other").capitalized }

    /// What a set of this exercise records.
    var tracking: SetTracking {
        switch category {
        case "cardio", "stretching": return .duration
        default:
            if force == "static" { return .duration }
            if equipment == "body only" || equipment == nil { return .reps }
            return .weightReps
        }
    }
}

enum SetTracking: String, Codable {
    case weightReps, reps, duration
}

@MainActor
@Observable
final class ExerciseLibrary {
    static let shared = ExerciseLibrary()

    static let catalogueURL = URL(string: "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json")!
    static let imageBase = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"

    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    private(set) var catalogue: [Exercise] = []
    private(set) var custom: [Exercise] = []
    private(set) var state: LoadState = .idle

    /// Every exercise, sorted by name. Built once whenever the catalogue or
    /// your custom exercises change; the picker reads it on every keystroke.
    private(set) var all: [Exercise] = []

    private var index: [String: Exercise] = [:]

    private static let customKey = "exercises.custom"
    private static var cacheFile: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("exercise-catalogue.json")
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.customKey),
           let saved = try? JSONDecoder().decode([Exercise].self, from: data) {
            custom = saved
        }
        if let data = try? Data(contentsOf: Self.cacheFile),
           let cached = try? JSONDecoder().decode([Exercise].self, from: data), !cached.isEmpty {
            catalogue = cached
            state = .loaded
        }
        rebuildIndex()
    }

    func exercise(id: String) -> Exercise? { index[id] }

    /// Loads the catalogue from the network if it isn't cached, or if the
    /// cache is more than a month old.
    func loadIfNeeded() async {
        let age = (try? Self.cacheFile.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
            .map { Date().timeIntervalSince($0) } ?? .infinity
        guard state != .loading, catalogue.isEmpty || age > 30 * 86_400 else { return }
        state = .loading
        do {
            let (data, response) = try await URLSession.shared.data(from: Self.catalogueURL)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
            let decoded = try JSONDecoder().decode([Exercise].self, from: data)
            catalogue = decoded
            try? FileManager.default.createDirectory(at: Self.cacheFile.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: Self.cacheFile)
            state = .loaded
            rebuildIndex()
        } catch {
            state = catalogue.isEmpty ? .failed("Couldn't download the exercise library. Check your connection — the built-in staples still work.") : .loaded
        }
    }

    func addCustom(name: String, muscle: String, equipment: String, tracking: SetTracking) -> Exercise {
        let exercise = Exercise(id: "custom-\(UUID().uuidString)", name: name,
                                force: tracking == .duration ? "static" : nil,
                                equipment: tracking == .reps ? "body only" : equipment,
                                primaryMuscles: [muscle],
                                instructions: [],
                                category: tracking == .duration ? "cardio" : "strength",
                                isCustom: true)
        custom.append(exercise)
        saveCustom()
        return exercise
    }

    func deleteCustom(_ exercise: Exercise) {
        custom.removeAll { $0.id == exercise.id }
        saveCustom()
    }

    private func saveCustom() {
        UserDefaults.standard.set(try? JSONEncoder().encode(custom), forKey: Self.customKey)
        rebuildIndex()
    }

    private func rebuildIndex() {
        let catalogueIDs = Set(catalogue.map(\.id))
        all = (custom + catalogue + Self.supplements.filter { !catalogueIDs.contains($0.id) })
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        index = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: Filters

    static let muscles = ["chest", "shoulders", "biceps", "triceps", "forearms", "lats", "middle back", "lower back",
                          "traps", "neck", "abdominals", "quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]

    static let equipment = ["barbell", "dumbbell", "cable", "machine", "body only", "kettlebells", "bands",
                            "e-z curl bar", "medicine ball", "exercise ball", "foam roll", "other"]

    // MARK: Built-in staples the open dataset lacks

    static let supplements: [Exercise] = [
        Exercise(id: "rs-bulgarian-split-squat", name: "Bulgarian Split Squat (Dumbbell)", force: "push", level: "intermediate",
                 mechanic: "compound", equipment: "dumbbell", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes", "hamstrings"],
                 instructions: ["Stand a stride in front of a bench holding dumbbells at your sides, and rest the top of your back foot on the bench.",
                                "Keeping your torso tall, lower straight down until your front thigh is about parallel to the floor.",
                                "Drive through the whole front foot to stand back up. Finish all reps, then switch legs."]),
        Exercise(id: "rs-pec-deck", name: "Pec Deck (Machine)", force: "push", level: "beginner", mechanic: "isolation",
                 equipment: "machine", primaryMuscles: ["chest"], secondaryMuscles: ["shoulders"],
                 instructions: ["Sit with your back flat against the pad and elbows slightly bent on the handles at chest height.",
                                "Squeeze your arms together in a wide arc until the handles meet in front of your chest.",
                                "Pause, then open slowly until you feel a stretch across the chest."]),
        Exercise(id: "rs-hip-thrust-machine", name: "Hip Thrust (Machine)", force: "push", level: "beginner", mechanic: "compound",
                 equipment: "machine", primaryMuscles: ["glutes"], secondaryMuscles: ["hamstrings"],
                 instructions: ["Sit with your upper back on the pad and the belt across your hips, feet flat and shin-width apart.",
                                "Drive through your heels to raise your hips until your body forms a straight line from knees to shoulders.",
                                "Squeeze your glutes at the top, then lower under control."]),
        Exercise(id: "rs-overhead-press", name: "Overhead Press (Barbell)", force: "push", level: "intermediate", mechanic: "compound",
                 equipment: "barbell", primaryMuscles: ["shoulders"], secondaryMuscles: ["triceps", "traps"],
                 instructions: ["Stand with the bar resting on your front shoulders, hands just outside shoulder width, glutes and core braced.",
                                "Press the bar straight up, moving your head back slightly so it passes your face, then push your head through at lockout.",
                                "Lower the bar back to your shoulders under control."]),
        Exercise(id: "rs-seated-row-machine", name: "Seated Row (Machine)", force: "pull", level: "beginner", mechanic: "compound",
                 equipment: "machine", primaryMuscles: ["middle back"], secondaryMuscles: ["lats", "biceps"],
                 instructions: ["Sit with your chest against the pad and grab the handles with arms extended.",
                                "Pull your elbows back past your torso, squeezing your shoulder blades together.",
                                "Return slowly until your arms are straight and your shoulder blades spread."]),
        Exercise(id: "rs-chest-supported-row", name: "Chest-Supported Row (Dumbbell)", force: "pull", level: "beginner", mechanic: "compound",
                 equipment: "dumbbell", primaryMuscles: ["middle back"], secondaryMuscles: ["lats", "biceps", "shoulders"],
                 instructions: ["Lie face down on a bench set to about 30°, a dumbbell in each hand hanging straight down.",
                                "Row the dumbbells up toward your hips, keeping your chest on the pad.",
                                "Lower until your arms are fully extended."]),
        Exercise(id: "rs-chest-press-machine", name: "Chest Press (Machine)", force: "push", level: "beginner", mechanic: "compound",
                 equipment: "machine", primaryMuscles: ["chest"], secondaryMuscles: ["triceps", "shoulders"],
                 instructions: ["Set the seat so the handles line up with the middle of your chest.",
                                "Press the handles forward until your arms are nearly straight.",
                                "Return slowly until you feel a stretch in the chest."]),
        Exercise(id: "rs-lateral-raise-dumbbell", name: "Lateral Raise (Dumbbell)", force: "push", level: "beginner", mechanic: "isolation",
                 equipment: "dumbbell", primaryMuscles: ["shoulders"],
                 instructions: ["Stand holding dumbbells at your sides with a slight bend in the elbows.",
                                "Raise your arms out to the sides until they're level with your shoulders, leading with the elbows.",
                                "Lower slowly without letting the weights swing."]),
        Exercise(id: "rs-cable-lateral-raise", name: "Lateral Raise (Cable)", force: "push", level: "beginner", mechanic: "isolation",
                 equipment: "cable", primaryMuscles: ["shoulders"],
                 instructions: ["Stand side-on to a low cable, holding the handle with the far hand across your body.",
                                "Raise your arm out to the side to shoulder height.",
                                "Lower under control, keeping tension on the cable at the bottom."]),
        Exercise(id: "rs-reverse-pec-deck", name: "Reverse Pec Deck (Machine)", force: "pull", level: "beginner", mechanic: "isolation",
                 equipment: "machine", primaryMuscles: ["shoulders"], secondaryMuscles: ["middle back"],
                 instructions: ["Sit facing the pad with the handles in front of you at shoulder height.",
                                "Sweep your arms back and out until they're in line with your body, working the rear delts.",
                                "Return slowly to the start."]),
        Exercise(id: "rs-hip-abduction-machine", name: "Hip Abduction (Machine)", force: "push", level: "beginner", mechanic: "isolation",
                 equipment: "machine", primaryMuscles: ["abductors"], secondaryMuscles: ["glutes"],
                 instructions: ["Sit with the pads against the outside of your knees.",
                                "Push your legs apart as far as is comfortable.",
                                "Bring them back together slowly."]),
        Exercise(id: "rs-hip-adduction-machine", name: "Hip Adduction (Machine)", force: "pull", level: "beginner", mechanic: "isolation",
                 equipment: "machine", primaryMuscles: ["adductors"],
                 instructions: ["Sit with the pads against the inside of your knees, legs apart.",
                                "Squeeze your legs together.",
                                "Open slowly back to the start."]),
        Exercise(id: "rs-ab-wheel", name: "Ab Wheel Rollout", force: "pull", level: "intermediate", mechanic: "compound",
                 equipment: "other", primaryMuscles: ["abdominals"], secondaryMuscles: ["lats", "shoulders"],
                 instructions: ["Kneel holding the ab wheel under your shoulders.",
                                "Roll forward slowly, keeping your hips in line and your lower back from sagging.",
                                "Go as far as you can control, then pull back to the start with your abs."]),
        Exercise(id: "rs-hanging-leg-raise", name: "Hanging Leg Raise", force: "pull", level: "intermediate", mechanic: "isolation",
                 equipment: "body only", primaryMuscles: ["abdominals"],
                 instructions: ["Hang from a pull-up bar with straight arms.",
                                "Raise your legs until they're at least level with your hips, curling your pelvis up.",
                                "Lower slowly without swinging."]),
        Exercise(id: "rs-burpee", name: "Burpee", force: "push", level: "beginner", mechanic: "compound", equipment: "body only",
                 primaryMuscles: ["quadriceps"], secondaryMuscles: ["chest", "shoulders", "abdominals"],
                 instructions: ["Squat down and place your hands on the floor.", "Jump your feet back into a plank and do a push-up.",
                                "Jump your feet back to your hands, then jump up with arms overhead."], category: "plyometrics"),
        Exercise(id: "rs-jump-rope", name: "Jump Rope", force: nil, level: "beginner", mechanic: nil, equipment: "other",
                 primaryMuscles: ["calves"], secondaryMuscles: ["quadriceps", "shoulders"],
                 instructions: ["Hold the handles at hip height and turn the rope with your wrists.", "Jump just high enough for the rope to pass, landing softly on the balls of your feet."],
                 category: "cardio"),
        Exercise(id: "rs-battle-ropes", name: "Battle Ropes", force: nil, level: "beginner", mechanic: "compound", equipment: "other",
                 primaryMuscles: ["shoulders"], secondaryMuscles: ["abdominals", "forearms"],
                 instructions: ["Stand in a half squat holding one rope end in each hand.", "Whip the ropes up and down in fast alternating waves, keeping your core braced."],
                 category: "cardio"),
        Exercise(id: "rs-incline-walk", name: "Incline Treadmill Walk", force: nil, level: "beginner", mechanic: nil, equipment: "machine",
                 primaryMuscles: ["glutes"], secondaryMuscles: ["calves", "hamstrings"],
                 instructions: ["Set the treadmill to a 8–12% incline and a brisk walking pace.", "Walk tall without holding the rails."],
                 category: "cardio"),
        Exercise(id: "rs-pendlay-row", name: "Pendlay Row (Barbell)", force: "pull", level: "intermediate", mechanic: "compound",
                 equipment: "barbell", primaryMuscles: ["middle back"], secondaryMuscles: ["lats", "biceps", "lower back"],
                 instructions: ["Hinge until your torso is roughly parallel to the floor, bar resting on the ground.",
                                "Row the bar explosively to your lower chest without lifting your torso.",
                                "Return the bar to the floor to reset each rep."]),
        Exercise(id: "rs-smith-squat", name: "Squat (Smith Machine)", force: "push", level: "beginner", mechanic: "compound",
                 equipment: "machine", primaryMuscles: ["quadriceps"], secondaryMuscles: ["glutes", "hamstrings"],
                 instructions: ["Set the bar across your upper back with feet slightly in front of your body.",
                                "Unhook the bar and squat down until your thighs are at least parallel.",
                                "Drive back up through your whole foot."]),
        Exercise(id: "rs-cable-fly", name: "Cable Fly Crossover", force: "push", level: "beginner", mechanic: "isolation",
                 equipment: "cable", primaryMuscles: ["chest"], secondaryMuscles: ["shoulders"],
                 instructions: ["Stand between two high pulleys with a handle in each hand and a slight forward lean.",
                                "Bring your hands together in a wide hugging arc in front of your hips.",
                                "Open back up slowly to a stretch."]),
        Exercise(id: "rs-back-extension", name: "Back Extension (Hyperextension)", force: "pull", level: "beginner", mechanic: "compound",
                 equipment: "other", primaryMuscles: ["lower back"], secondaryMuscles: ["glutes", "hamstrings"],
                 instructions: ["Lock your ankles in a hyperextension bench with the pad just below your hips.",
                                "Lower your torso toward the floor with a flat back.",
                                "Raise back up until your body is in a straight line — don't over-arch."])
    ]
}

// MARK: - Images

/// Tiny image cache so scrolling a list of 800 exercises doesn't re-download.
actor ExerciseImageCache {
    static let shared = ExerciseImageCache()
    private let memory = NSCache<NSURL, UIImage>()
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 20 * 1024 * 1024, diskCapacity: 300 * 1024 * 1024)
        config.requestCachePolicy = .returnCacheDataElseLoad
        return URLSession(configuration: config)
    }()

    /// The photo, decoded here on the actor rather than at first draw on the
    /// main thread. `thumbnail` returns a copy downsampled for list rows, so a
    /// 48-point tile doesn't carry a full-size bitmap.
    func image(for url: URL, thumbnail: Bool = false) async -> UIImage? {
        let key = (thumbnail ? URL(string: url.absoluteString + "#thumb") ?? url : url) as NSURL
        if let cached = memory.object(forKey: key) { return cached }
        guard let (data, _) = try? await session.data(from: url), let raw = UIImage(data: data) else { return nil }
        let prepared: UIImage?
        if thumbnail {
            prepared = await raw.byPreparingThumbnail(ofSize: CGSize(width: 240, height: 240))
        } else {
            prepared = await raw.byPreparingForDisplay()
        }
        let image = prepared ?? raw
        memory.setObject(image, forKey: key)
        return image
    }
}

/// The animated demonstration: the dataset's start and finish photos
/// cross-fading in a loop, like a GIF. Falls back to a muscle icon. Photos fill
/// the frame (cropping the edges) so square thumbnails never show white bars.
struct ExerciseDemo: View {
    let exercise: Exercise
    var animated = true
    var cornerRadius: CGFloat = 10

    @State private var frames: [UIImage] = []
    @State private var finishedLoading = false

    /// No photos, or none could be loaded: draw the movement instead.
    private var showsFigure: Bool { exercise.images.isEmpty || (finishedLoading && frames.isEmpty) }

    var body: some View {
        // The frame is a plain colour with everything else overlaid on it, so
        // a photo (or a wide drawing) can never push the layout wider than the
        // space it was given.
        Color.white
            .overlay {
                if showsFigure {
                    ExerciseFigure(name: exercise.name, primaryMuscle: exercise.primaryMuscle, category: exercise.category,
                                   equipment: exercise.equipment, animated: animated,
                                   tint: Theme.accent, ink: Theme.textTertiary)
                        .padding(6)
                        .background(Theme.accent.opacity(0.05))
                } else if frames.isEmpty {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(Theme.accent.opacity(0.6))
                } else if animated && frames.count > 1 {
                    TimelineView(.periodic(from: .now, by: 0.9)) { context in
                        let index = Int(context.date.timeIntervalSinceReferenceDate / 0.9) % frames.count
                        ZStack {
                            ForEach(frames.indices, id: \.self) { i in
                                photo(frames[i]).opacity(i == index ? 1 : 0)
                            }
                        }
                        .animation(.easeInOut(duration: 0.35), value: index)
                    }
                } else {
                    photo(frames[0])
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
            .task(id: exercise.id) {
                var loaded: [UIImage] = []
                // Still thumbnails are the small tiles in lists and cards.
                for url in exercise.imageURLs.prefix(animated ? 2 : 1) {
                    if let image = await ExerciseImageCache.shared.image(for: url, thumbnail: !animated) { loaded.append(image) }
                }
                frames = loaded
                finishedLoading = true
            }
    }

    /// Fills the frame, cropping the edges, so square thumbnails never show white bars.
    private func photo(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
    }

    private var symbol: String {
        switch exercise.category {
        case "cardio":     "figure.run"
        case "stretching": "figure.flexibility"
        case "plyometrics": "figure.jumprope"
        default:           "dumbbell.fill"
        }
    }
}
