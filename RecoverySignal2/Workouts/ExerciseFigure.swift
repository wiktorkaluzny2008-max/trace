//
//  ExerciseFigure.swift
//  RecoverySignal2
//
//  A drawn stand-in for exercises that have no photo: a stick figure that
//  moves between the start and end of the lift, with the bar, dumbbells,
//  cable or bench it uses. The movement is picked from the exercise's name
//  (falling back to the muscle it works), so every exercise gets a sensible
//  picture without needing an image.
//

import SwiftUI

// MARK: - Movement patterns

enum FigureKind: CaseIterable {
    case lateralRaise, curl, overheadPress, benchPress, inclineBench, fly, row, pullUp, squat, hinge, lunge
    case legExtension, legCurl, calfRaise, tricepsExtension, crunch, plank, pushUp, shrug, bridge, run, stretch

    /// Chooses the movement from the exercise's name, then its muscle.
    static func classify(name: String, primaryMuscle: String, category: String?) -> FigureKind {
        let n = " " + name.lowercased() + " "
        func has(_ words: String...) -> Bool { words.contains { n.contains($0) } }

        if category == "stretching" { return .stretch }
        if has("lateral raise", "side raise", "front raise", "raise to the side") { return .lateralRaise }
        if has("leg curl", "hamstring curl", "nordic") { return .legCurl }
        if has("leg extension") { return .legExtension }
        if has("curl") { return .curl }
        if has("tricep", "pushdown", "push down", "skull", "kickback") && !has("glute") { return .tricepsExtension }
        if has("incline") && has("press", "bench") { return .inclineBench }
        if has("shoulder press", "overhead", "military", "arnold", "push press", "handstand") { return .overheadPress }
        if has("leg press", "squat", "hack") && !has("split squat", "bulgarian") { return .squat }
        if has("lunge", "split squat", "bulgarian", "step-up", "step up") { return .lunge }
        if has("bench", "chest press", "floor press", "decline") { return .benchPress }
        if has(" fly", "flye", "crossover", "pec deck", "reverse fly", "butterfly") { return .fly }
        if has("upright row", "shrug") { return .shrug }
        if has("pulldown", "pull-down", "pull down", "pull-up", "pullup", "pull up", "chin") { return .pullUp }
        if has(" row") { return .row }
        if has("deadlift", "good morning", "romanian", "hyperextension", "swing", "rack pull", "clean", "snatch") { return .hinge }
        if has("calf") { return .calfRaise }
        if has("push-up", "pushup", "push up", "dip") { return .pushUp }
        if has("plank") { return .plank }
        if has("crunch", "sit-up", "situp", "sit up", "leg raise", "knee raise", "twist", "ab wheel", "rollout") { return .crunch }
        if has("thrust", "bridge", "hip raise") { return .bridge }
        if category == "cardio" || has("run", "jog", "sprint", "jump", "skip", "burpee") { return .run }

        switch primaryMuscle.lowercased() {
        case "biceps", "forearms":          return .curl
        case "triceps":                     return .tricepsExtension
        case "shoulders":                   return .lateralRaise
        case "chest":                       return .benchPress
        case "lats", "middle back":         return .row
        case "quadriceps", "adductors", "abductors": return .squat
        case "hamstrings", "glutes", "lower back":   return .hinge
        case "calves":                      return .calfRaise
        case "abdominals":                  return .crunch
        case "traps", "neck":               return .shrug
        default:                            return .curl
        }
    }
}

enum FigureEquipment {
    case none, barbell, dumbbell, cable, machine

    static func from(_ equipment: String?, name: String) -> FigureEquipment {
        let e = (equipment ?? "").lowercased()
        let n = name.lowercased()
        if e.contains("cable") || n.contains("cable") { return .cable }
        if e.contains("barbell") || e.contains("bar") || n.contains("barbell") { return .barbell }
        if e.contains("dumbbell") || e.contains("kettlebell") || n.contains("dumbbell") { return .dumbbell }
        if e.contains("machine") || n.contains("machine") { return .machine }
        return .none
    }
}

// MARK: - Poses

private enum Joint: CaseIterable { case head, neck, hip, shL, shR, elL, elR, haL, haR, kL, kR, fL, fR }

private struct Pose {
    var p: [Joint: CGPoint]

    /// Same pose with some joints moved (coordinates are on a 100 × 100 grid).
    func with(_ changes: [Joint: (Double, Double)]) -> Pose {
        var copy = self
        for (joint, xy) in changes { copy.p[joint] = CGPoint(x: xy.0, y: xy.1) }
        return copy
    }

    static func make(_ values: [Joint: (Double, Double)]) -> Pose {
        Pose(p: values.mapValues { CGPoint(x: $0.0, y: $0.1) })
    }

    func lerp(_ other: Pose, _ t: Double) -> Pose {
        var out = p
        for joint in Joint.allCases {
            guard let a = p[joint], let b = other.p[joint] else { continue }
            out[joint] = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
        }
        return Pose(p: out)
    }

    /// Standing, seen from the front, arms hanging.
    static let front = make([
        .head: (50, 20), .neck: (50, 30), .hip: (50, 58),
        .shL: (42, 32), .shR: (58, 32), .elL: (39, 45), .elR: (61, 45), .haL: (38, 58), .haR: (62, 58),
        .kL: (46, 75), .kR: (54, 75), .fL: (45, 91), .fR: (55, 91)
    ])

    /// Standing, seen from the side (facing right), arms hanging.
    static let side = make([
        .head: (52, 20), .neck: (50, 30), .hip: (48, 58),
        .shL: (50, 30), .shR: (50, 30), .elL: (49, 45), .elR: (49, 45), .haL: (51, 58), .haR: (51, 58),
        .kL: (47, 75), .kR: (50, 75), .fL: (45, 91), .fR: (52, 91)
    ])
}

/// One movement: where the body starts and ends, and what it holds or sits on.
private struct Movement {
    var start: Pose
    var end: Pose
    /// Side views draw the far-side limbs lighter.
    var sideView = false
    /// Fixed lines (bench, seat, bar above), in grid coordinates.
    var fixtures: [(CGPoint, CGPoint)] = []
    /// Where a cable runs from, if it does.
    var cableAnchor: CGPoint? = nil
    /// Which hand holds the cable.
    var cableHand: Joint = .haR
    /// A rope or bar held in both hands.
    var cableBoth = false
    /// Working with one arm only (the other stays at the side).
    var floor = true
}

private func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x, y: y) }

private extension FigureKind {
    var movement: Movement {
        switch self {
        case .lateralRaise:
            return Movement(
                start: .front,
                end: Pose.front.with([.elL: (31, 34), .haL: (19, 36), .elR: (69, 34), .haR: (81, 36)]),
                cableAnchor: pt(80, 91), cableHand: .haL)

        case .curl:
            return Movement(
                start: .front,
                end: Pose.front.with([.elL: (40, 46), .haL: (41, 31), .elR: (60, 46), .haR: (59, 31)]),
                cableAnchor: pt(50, 91), cableBoth: true)

        case .overheadPress:
            return Movement(
                start: Pose.front.with([.elL: (33, 40), .haL: (37, 27), .elR: (67, 40), .haR: (63, 27)]),
                end: Pose.front.with([.elL: (40, 17), .haL: (43, 6), .elR: (60, 17), .haR: (57, 6)]))

        case .benchPress:
            let lying = Pose.make([
                .head: (20, 52), .neck: (29, 55), .hip: (58, 55),
                .shL: (29, 55), .shR: (29, 55), .elL: (30, 40), .elR: (30, 40), .haL: (30, 26), .haR: (30, 26),
                .kL: (72, 45), .kR: (72, 45), .fL: (76, 61), .fR: (76, 61)])
            return Movement(
                start: lying,
                end: lying.with([.elL: (38, 52), .elR: (38, 52), .haL: (30, 45), .haR: (30, 45)]),
                sideView: true,
                fixtures: [(pt(16, 61), pt(66, 61)), (pt(24, 63), pt(24, 82)), (pt(58, 63), pt(58, 82))])

        case .inclineBench:
            let inclined = Pose.make([
                .head: (30, 34), .neck: (37, 41), .hip: (58, 58),
                .shL: (37, 41), .shR: (37, 41), .elL: (44, 30), .elR: (44, 30), .haL: (48, 16), .haR: (48, 16),
                .kL: (72, 50), .kR: (72, 50), .fL: (78, 66), .fR: (78, 66)])
            return Movement(
                start: inclined,
                end: inclined.with([.elL: (46, 46), .elR: (46, 46), .haL: (41, 34), .haR: (41, 34)]),
                sideView: true,
                fixtures: [(pt(22, 30), pt(62, 66)), (pt(64, 66), pt(64, 84)), (pt(34, 52), pt(34, 84))])

        case .fly:
            return Movement(
                start: Pose.front.with([.elL: (31, 35), .haL: (19, 40), .elR: (69, 35), .haR: (81, 40)]),
                end: Pose.front.with([.elL: (39, 43), .haL: (47, 48), .elR: (61, 43), .haR: (53, 48)]),
                cableAnchor: pt(12, 10), cableHand: .haL)

        case .row:
            let bent = Pose.make([
                .head: (73, 38), .neck: (64, 42), .hip: (38, 56),
                .shL: (64, 42), .shR: (64, 42), .elL: (63, 55), .elR: (63, 55), .haL: (63, 68), .haR: (63, 68),
                .kL: (42, 74), .kR: (44, 74), .fL: (40, 91), .fR: (46, 91)])
            return Movement(
                start: bent,
                end: bent.with([.elL: (50, 50), .elR: (50, 50), .haL: (60, 58), .haR: (60, 58)]),
                sideView: true)

        case .pullUp:
            let hang = Pose.make([
                .head: (50, 28), .neck: (50, 38), .hip: (50, 64),
                .shL: (43, 40), .shR: (57, 40), .elL: (37, 24), .elR: (63, 24), .haL: (33, 8), .haR: (67, 8),
                .kL: (47, 78), .kR: (53, 78), .fL: (46, 91), .fR: (54, 91)])
            let up = Pose.make([
                .head: (50, 16), .neck: (50, 26), .hip: (50, 52),
                .shL: (43, 28), .shR: (57, 28), .elL: (33, 24), .elR: (67, 24), .haL: (33, 8), .haR: (67, 8),
                .kL: (47, 66), .kR: (53, 66), .fL: (46, 80), .fR: (54, 80)])
            return Movement(start: hang, end: up, fixtures: [(pt(20, 8), pt(80, 8))], floor: false)

        case .squat:
            let deep = Pose.make([
                .head: (55, 30), .neck: (49, 40), .hip: (36, 66),
                .shL: (49, 40), .shR: (49, 40), .elL: (44, 42), .elR: (44, 42), .haL: (52, 34), .haR: (52, 34),
                .kL: (58, 62), .kR: (60, 62), .fL: (52, 91), .fR: (58, 91)])
            let stand = Pose.side.with([.elL: (46, 38), .elR: (46, 38), .haL: (52, 33), .haR: (52, 33)])
            return Movement(start: stand, end: deep, sideView: true)

        case .hinge:
            let bottom = Pose.make([
                .head: (66, 38), .neck: (57, 44), .hip: (34, 54),
                .shL: (57, 44), .shR: (57, 44), .elL: (57, 58), .elR: (57, 58), .haL: (57, 71), .haR: (57, 71),
                .kL: (45, 72), .kR: (47, 72), .fL: (43, 91), .fR: (49, 91)])
            let top = Pose.side.with([.elL: (50, 46), .elR: (50, 46), .haL: (52, 62), .haR: (52, 62)])
            return Movement(start: bottom, end: top, sideView: true)

        case .lunge:
            let down = Pose.make([
                .head: (50, 26), .neck: (50, 36), .hip: (50, 62),
                .shL: (50, 36), .shR: (50, 36), .elL: (49, 49), .elR: (49, 49), .haL: (50, 61), .haR: (50, 61),
                .kL: (67, 66), .kR: (38, 82), .fL: (66, 91), .fR: (26, 91)])
            let up = Pose.side.with([.elL: (49, 46), .elR: (49, 46), .haL: (50, 60), .haR: (50, 60)])
            return Movement(start: up, end: down, sideView: true)

        case .legExtension:
            let seated = Pose.make([
                .head: (38, 20), .neck: (38, 30), .hip: (40, 58),
                .shL: (38, 30), .shR: (38, 30), .elL: (46, 44), .elR: (46, 44), .haL: (52, 54), .haR: (52, 54),
                .kL: (60, 58), .kR: (60, 58), .fL: (60, 80), .fR: (60, 80)])
            return Movement(
                start: seated,
                end: seated.with([.fL: (84, 60), .fR: (84, 60)]),
                sideView: true,
                fixtures: [(pt(28, 60), pt(52, 60)), (pt(32, 26), pt(32, 62)), (pt(40, 62), pt(40, 90))])

        case .legCurl:
            let seated = Pose.make([
                .head: (38, 20), .neck: (38, 30), .hip: (40, 58),
                .shL: (38, 30), .shR: (38, 30), .elL: (46, 44), .elR: (46, 44), .haL: (52, 54), .haR: (52, 54),
                .kL: (62, 58), .kR: (62, 58), .fL: (84, 60), .fR: (84, 60)])
            return Movement(
                start: seated,
                end: seated.with([.fL: (60, 82), .fR: (60, 82)]),
                sideView: true,
                fixtures: [(pt(28, 60), pt(52, 60)), (pt(32, 26), pt(32, 62)), (pt(40, 62), pt(40, 90))])

        case .calfRaise:
            var raised = Pose.side
            for joint in [Joint.head, .neck, .hip, .shL, .shR, .elL, .elR, .haL, .haR, .kL, .kR] {
                if let q = raised.p[joint] { raised.p[joint] = CGPoint(x: q.x, y: q.y - 5) }
            }
            raised.p[.fL] = CGPoint(x: 54, y: 87)
            raised.p[.fR] = CGPoint(x: 56, y: 87)
            return Movement(start: Pose.side.with([.fL: (52, 91), .fR: (55, 91)]), end: raised, sideView: true)

        case .tricepsExtension:
            let up = Pose.front.with([.elL: (40, 46), .haL: (43, 34), .elR: (60, 46), .haR: (57, 34)])
            let down = Pose.front.with([.elL: (40, 46), .haL: (41, 60), .elR: (60, 46), .haR: (59, 60)])
            return Movement(start: up, end: down, cableAnchor: pt(50, 4), cableBoth: true)

        case .crunch:
            let lying = Pose.make([
                .head: (22, 62), .neck: (30, 66), .hip: (58, 66),
                .shL: (30, 66), .shR: (30, 66), .elL: (27, 58), .elR: (27, 58), .haL: (24, 62), .haR: (24, 62),
                .kL: (72, 52), .kR: (72, 52), .fL: (78, 66), .fR: (78, 66)])
            return Movement(
                start: lying,
                end: lying.with([.head: (36, 46), .neck: (41, 54), .elL: (38, 46), .elR: (38, 46), .haL: (35, 49), .haR: (35, 49)]),
                sideView: true)

        case .plank:
            let hold = Pose.make([
                .head: (22, 54), .neck: (29, 57), .hip: (58, 61),
                .shL: (29, 57), .shR: (29, 57), .elL: (30, 70), .elR: (30, 70), .haL: (40, 71), .haR: (40, 71),
                .kL: (72, 65), .kR: (72, 65), .fL: (86, 70), .fR: (86, 70)])
            return Movement(start: hold, end: hold.with([.hip: (58, 59), .neck: (29, 56)]), sideView: true)

        case .pushUp:
            let up = Pose.make([
                .head: (22, 46), .neck: (29, 50), .hip: (58, 60),
                .shL: (29, 50), .shR: (29, 50), .elL: (29, 61), .elR: (29, 61), .haL: (29, 72), .haR: (29, 72),
                .kL: (72, 65), .kR: (72, 65), .fL: (86, 70), .fR: (86, 70)])
            let down = Pose.make([
                .head: (24, 60), .neck: (30, 62), .hip: (58, 65),
                .shL: (30, 62), .shR: (30, 62), .elL: (40, 66), .elR: (40, 66), .haL: (30, 72), .haR: (30, 72),
                .kL: (72, 68), .kR: (72, 68), .fL: (86, 71), .fR: (86, 71)])
            return Movement(start: up, end: down, sideView: true)

        case .shrug:
            var raised = Pose.front
            raised.p[.neck] = CGPoint(x: 50, y: 28)
            raised.p[.shL] = CGPoint(x: 42, y: 29); raised.p[.shR] = CGPoint(x: 58, y: 29)
            raised.p[.elL] = CGPoint(x: 39, y: 42); raised.p[.elR] = CGPoint(x: 61, y: 42)
            raised.p[.haL] = CGPoint(x: 38, y: 55); raised.p[.haR] = CGPoint(x: 62, y: 55)
            raised.p[.head] = CGPoint(x: 50, y: 19)
            return Movement(start: .front, end: raised)

        case .bridge:
            let down = Pose.make([
                .head: (20, 66), .neck: (28, 66), .hip: (54, 66),
                .shL: (28, 66), .shR: (28, 66), .elL: (34, 66), .elR: (34, 66), .haL: (42, 66), .haR: (42, 66),
                .kL: (70, 50), .kR: (70, 50), .fL: (76, 66), .fR: (76, 66)])
            let up = down.with([.hip: (54, 48), .neck: (30, 62), .head: (22, 62), .kL: (70, 48), .kR: (70, 48)])
            return Movement(start: down, end: up, sideView: true)

        case .run:
            let a = Pose.make([
                .head: (54, 20), .neck: (50, 30), .hip: (46, 58),
                .shL: (50, 30), .shR: (50, 30), .elL: (60, 40), .elR: (40, 42), .haL: (66, 30), .haR: (34, 50),
                .kL: (62, 64), .kR: (38, 74), .fL: (58, 80), .fR: (26, 82)])
            let b = Pose.make([
                .head: (54, 20), .neck: (50, 30), .hip: (46, 58),
                .shL: (50, 30), .shR: (50, 30), .elL: (40, 42), .elR: (60, 40), .haL: (34, 50), .haR: (66, 30),
                .kL: (38, 74), .kR: (62, 64), .fL: (26, 82), .fR: (58, 80)])
            return Movement(start: a, end: b, sideView: true)

        case .stretch:
            let reach = Pose.front.with([.elL: (43, 16), .haL: (47, 4), .elR: (57, 16), .haR: (53, 4)])
            let lean = Pose.make([
                .head: (58, 22), .neck: (52, 30), .hip: (46, 58),
                .shL: (45, 32), .shR: (59, 30), .elL: (48, 18), .elR: (66, 16), .haL: (54, 6), .haR: (74, 8),
                .kL: (44, 75), .kR: (52, 75), .fL: (43, 91), .fR: (53, 91)])
            return Movement(start: reach, end: lean)
        }
    }
}

// MARK: - The view

/// A moving stick figure for an exercise with no photo.
struct ExerciseFigure: View {
    let name: String
    let primaryMuscle: String
    var category: String?
    var equipment: String?
    var animated = true
    /// Where to freeze the movement (0 = start, 1 = finish) when not animated.
    var frozenPhase = 0.85
    var tint: Color = .blue
    var ink: Color = .gray

    var body: some View {
        let kind = FigureKind.classify(name: name, primaryMuscle: primaryMuscle, category: category)
        let gear = FigureEquipment.from(equipment, name: name)
        if animated {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                // Eases from the start to the finish and back over ~2.6 s.
                let phase = (1 - cos(t * 2 * .pi / 2.6)) / 2
                canvas(kind, gear, phase)
            }
        } else {
            canvas(kind, gear, frozenPhase)
        }
    }

    private func canvas(_ kind: FigureKind, _ gear: FigureEquipment, _ phase: Double) -> some View {
        Canvas { context, size in
            draw(kind.movement, kind, gear, phase, &context, size)
        }
        .accessibilityHidden(true)
    }

    private func draw(_ move: Movement, _ kind: FigureKind, _ gear: FigureEquipment, _ phase: Double,
                      _ context: inout GraphicsContext, _ size: CGSize) {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let scale = side / 100
        func at(_ p: CGPoint) -> CGPoint { CGPoint(x: origin.x + p.x * scale, y: origin.y + p.y * scale) }

        let pose = move.start.lerp(move.end, phase)
        func j(_ joint: Joint) -> CGPoint { pose.p[joint] ?? .zero }
        let lineWidth = max(side * 0.045, 1.4)
        let stroke = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        let gearStroke = StrokeStyle(lineWidth: lineWidth * 0.8, lineCap: .round, lineJoin: .round)

        func line(_ points: [CGPoint], _ color: Color, _ style: StrokeStyle) {
            var path = Path()
            guard let first = points.first else { return }
            path.move(to: at(first))
            for p in points.dropFirst() { path.addLine(to: at(p)) }
            context.stroke(path, with: .color(color), style: style)
        }

        // Floor and fixed furniture.
        if move.floor {
            line([CGPoint(x: 8, y: 92.5), CGPoint(x: 92, y: 92.5)], ink.opacity(0.25), StrokeStyle(lineWidth: max(lineWidth * 0.5, 1), lineCap: .round))
        }
        for (a, b) in move.fixtures { line([a, b], ink.opacity(0.55), gearStroke) }

        // Far limbs first, so the near ones sit on top in side views.
        let farOpacity = move.sideView ? 0.45 : 1
        line([j(.hip), j(.kR), j(.fR)], tint.opacity(farOpacity), stroke)
        line([j(.neck), j(.shR), j(.elR), j(.haR)], tint.opacity(farOpacity), stroke)

        // Torso, near leg, near arm.
        line([j(.neck), j(.hip)], tint, stroke)
        line([j(.hip), j(.kL), j(.fL)], tint, stroke)
        line([j(.neck), j(.shL), j(.elL), j(.haL)], tint, stroke)
        if !move.sideView { line([j(.shL), j(.shR)], tint, stroke) }

        // Head.
        let headCenter = at(j(.head))
        let radius = 6.2 * scale
        context.stroke(Path(ellipseIn: CGRect(x: headCenter.x - radius, y: headCenter.y - radius, width: radius * 2, height: radius * 2)),
                       with: .color(tint), style: stroke)

        drawGear(gear, kind, move, pose, &context, at, scale, lineWidth, ink)
    }

    private func drawGear(_ gear: FigureEquipment, _ kind: FigureKind, _ move: Movement, _ pose: Pose,
                          _ context: inout GraphicsContext, _ at: (CGPoint) -> CGPoint, _ scale: Double,
                          _ lineWidth: Double, _ ink: Color) {
        func j(_ joint: Joint) -> CGPoint { pose.p[joint] ?? .zero }
        let hands = [j(.haL), j(.haR)]
        let thick = StrokeStyle(lineWidth: lineWidth * 1.5, lineCap: .round)

        func plate(_ p: CGPoint, _ tall: Double) {
            var path = Path()
            path.move(to: at(CGPoint(x: p.x, y: p.y - tall)))
            path.addLine(to: at(CGPoint(x: p.x, y: p.y + tall)))
            context.stroke(path, with: .color(ink), style: thick)
        }

        switch gear {
        case .barbell:
            if move.sideView {
                // Seen end-on: a bar with a plate.
                let p = hands[0]
                plate(p, 5.5)
                context.fill(Path(ellipseIn: CGRect(x: at(p).x - 1.8 * scale, y: at(p).y - 1.8 * scale, width: 3.6 * scale, height: 3.6 * scale)), with: .color(ink))
            } else {
                var path = Path()
                let (l, r) = (hands[0], hands[1])
                path.move(to: at(CGPoint(x: l.x - 12, y: l.y)))
                path.addLine(to: at(CGPoint(x: r.x + 12, y: r.y)))
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: lineWidth * 0.9, lineCap: .round))
                plate(CGPoint(x: l.x - 10, y: l.y), 5)
                plate(CGPoint(x: r.x + 10, y: r.y), 5)
            }
        case .dumbbell, .machine:
            guard gear == .dumbbell else { break }
            for p in (move.sideView ? [hands[0]] : hands) {
                var bar = Path()
                bar.move(to: at(CGPoint(x: p.x - 3.5, y: p.y)))
                bar.addLine(to: at(CGPoint(x: p.x + 3.5, y: p.y)))
                context.stroke(bar, with: .color(ink), style: thick)
            }
        case .cable:
            do {
                let anchor = move.cableAnchor ?? CGPoint(x: 80, y: 92)
                var cable = Path()
                for hand in (move.cableBoth ? [Joint.haL, .haR] : [move.cableHand]) {
                    cable.move(to: at(anchor))
                    cable.addLine(to: at(j(hand)))
                }
                context.stroke(cable, with: .color(ink.opacity(0.8)), style: StrokeStyle(lineWidth: max(lineWidth * 0.35, 0.8), lineCap: .round))
                let r = 2.4 * scale
                context.fill(Path(ellipseIn: CGRect(x: at(anchor).x - r, y: at(anchor).y - r, width: r * 2, height: r * 2)), with: .color(ink))
            }
        case .none:
            break
        }
    }
}
