//
//  Glyph.swift
//  RecoverySignal2
//
//  RecoverySignal's own icon set. Every glyph is drawn on a 24 × 24 grid in
//  three layers, which is what gives the set its consistent duotone look:
//
//    soft   — a translucent mint fill that gives the shape body
//    line   — the outline, 1.75 units, round caps and joins
//    solid  — small fully-coloured details (a dot, a star, a charge level)
//
//  Geometry is written in SVG path syntax so it can be previewed in any
//  browser exactly as the app draws it.
//

import SwiftUI

nonisolated enum Glyph: String, CaseIterable, Sendable {
    // Metric categories — shared by Today headers, Insights cards and the AI narrative
    case recovery, sleep, activity, training, nutrition, body
    // Recovery score bands
    case batteryFull, batteryHalf, batteryLow
    // Analysis
    case trainingLoad, fatigue, energy, patterns
    // Insights
    case spotlight, narrative, target
    // States
    case allClear, sparkle, watch, rest
    // Settings
    case key, database, flask, info
    // Individual metrics
    case hrv, heartRate, oxygen, lungs, steps, deepSleep, remSleep
    case protein, carbs, fat
    // Features
    case recipe, bell

    enum Layer: Sendable { case soft, line, solid }

    /// The icon for an insight / narrative topic. One mapping app-wide, so a
    /// flag always carries the same icon as the Today section its metric lives in.
    static func topic(_ name: String) -> Glyph {
        switch name.lowercased() {
        case "recovery":              .recovery
        case "sleep":                 .sleep
        case "activity":              .activity
        case "training":              .training
        case "nutrition":             .nutrition
        case "body":                  .body
        case "suggestion", "target":  .target
        default:                      .info
        }
    }

    enum Element: Sendable {
        case path(String, Layer)
        case circle(cx: CGFloat, cy: CGFloat, r: CGFloat, Layer)
        case rect(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, Layer)
        case ellipse(cx: CGFloat, cy: CGFloat, rx: CGFloat, ry: CGFloat, Layer)

        var layer: Layer {
            switch self {
            case .path(_, let l), .circle(_, _, _, let l), .rect(_, _, _, _, _, let l), .ellipse(_, _, _, _, let l):
                return l
            }
        }
    }

    /// All elements of one layer merged into a single path in 24-unit space.
    ///
    /// Built through CGMutablePath on purpose: a SwiftUI `Path` holding nothing
    /// but a single ellipse or rect gets a special-cased storage that renders as
    /// a frame-sized square once transformed and filled at small sizes (it showed
    /// up on the blood oxygen, deep and REM icons). A CGPath-backed Path is always
    /// drawn as real geometry.
    func path(for layer: Layer) -> Path {
        let out = CGMutablePath()
        for element in elements where element.layer == layer {
            switch element {
            case .path(let d, _):
                out.addPath(SVGPath.path(d).cgPath)
            case .circle(let cx, let cy, let r, _):
                out.addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
            case .rect(let x, let y, let w, let h, let r, _):
                out.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h),
                                   cornerWidth: r, cornerHeight: r)
            case .ellipse(let cx, let cy, let rx, let ry, _):
                out.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: 2 * rx, height: 2 * ry))
            }
        }
        return Path(out)
    }

    var elements: [Element] {
        switch self {

        // MARK: Categories

        case .recovery:
            let heart = "M12 20.2 C12 20.2 3.6 15.3 3.6 9.4 C3.6 6.5 5.8 4.3 8.5 4.3 C10 4.3 11.3 5.1 12 6.3 C12.7 5.1 14 4.3 15.5 4.3 C18.2 4.3 20.4 6.5 20.4 9.4 C20.4 15.3 12 20.2 12 20.2 Z"
            return [
                .path(heart, .soft),
                .path(heart, .line),
                .path("M6.6 11.6 H9.1 L10.5 9.1 L12.6 14.2 L14.1 11.6 H17.4", .line)
            ]

        case .sleep:
            let moon = "M13.2 4.2 A8.2 8.2 0 1 0 19.8 15.6 A6.4 6.4 0 0 1 13.2 4.2 Z"
            return [
                .path(moon, .soft),
                .path(moon, .line),
                .path("M18.2 3.2 Q18.55 5.05 20.4 5.4 Q18.55 5.75 18.2 7.6 Q17.85 5.75 16 5.4 Q17.85 5.05 18.2 3.2 Z", .solid)
            ]

        case .activity:
            // Side-on sneaker: tall heel collar on the left, laces sloping down to the toe.
            let shoe = "M4.6 19 H19.6 C20.7 19 21.6 18.1 21.6 17 C21.6 15 20.2 13.5 18.2 13.1 L14.9 12.4 L11 7.4 C10.5 6.8 9.7 6.7 9.1 7.1 C8.3 7.7 7.2 7.9 6.2 7.6 L4.9 7.2 C3.9 6.9 2.9 7.6 2.9 8.7 V17.3 C2.9 18.2 3.7 19 4.6 19 Z"
            return [
                .path(shoe, .soft),
                .path(shoe, .line),
                .path("M3 15.8 H21.4", .line),
                .path("M12.3 9.2 L10.3 10.8 M13.7 11 L11.7 12.6", .line)
            ]

        case .training:
            return [
                .rect(x: 5.3, y: 6.8, w: 3.1, h: 10.4, r: 1.3, .soft),
                .rect(x: 15.6, y: 6.8, w: 3.1, h: 10.4, r: 1.3, .soft),
                .rect(x: 5.3, y: 6.8, w: 3.1, h: 10.4, r: 1.3, .line),
                .rect(x: 15.6, y: 6.8, w: 3.1, h: 10.4, r: 1.3, .line),
                .rect(x: 2.4, y: 9.2, w: 2.9, h: 5.6, r: 1.1, .line),
                .rect(x: 18.7, y: 9.2, w: 2.9, h: 5.6, r: 1.1, .line),
                .path("M8.4 12 H15.6", .line)
            ]

        case .nutrition:
            let bowl = "M3.4 12.2 H20.6 C20.6 16.8 16.8 20.4 12 20.4 C7.2 20.4 3.4 16.8 3.4 12.2 Z"
            return [
                .path(bowl, .soft),
                .path(bowl, .line),
                .path("M12.3 12.2 C12.1 8.3 14.6 5.2 18.9 4.6 C19.3 8.6 16.6 11.9 12.3 12.2 Z", .solid),
                .path("M11.2 12.2 C10.9 9.8 9 8.1 6.2 8 C6.3 10.4 8.2 12.1 11.2 12.2 Z", .line)
            ]

        case .body:
            return [
                .rect(x: 3.5, y: 3.5, w: 17, h: 17, r: 4.6, .soft),
                .rect(x: 3.5, y: 3.5, w: 17, h: 17, r: 4.6, .line),
                .path("M7.6 11.4 A4.4 4.4 0 0 1 16.4 11.4 Z", .line),
                .path("M12 11.4 L14.1 8.6", .line),
                .circle(cx: 12, cy: 11.4, r: 1.15, .solid)
            ]

        // MARK: Recovery bands

        case .batteryFull:  return battery(level: 12.4)
        case .batteryHalf:  return battery(level: 6.6)
        case .batteryLow:   return battery(level: 2.9)

        // MARK: Analysis

        case .trainingLoad:
            return [
                .rect(x: 4, y: 14.4, w: 3.4, h: 5.9, r: 1.1, .soft),
                .rect(x: 10.3, y: 11.2, w: 3.4, h: 9.1, r: 1.1, .soft),
                .rect(x: 16.6, y: 8.4, w: 3.4, h: 11.9, r: 1.1, .soft),
                .rect(x: 4, y: 14.4, w: 3.4, h: 5.9, r: 1.1, .line),
                .rect(x: 10.3, y: 11.2, w: 3.4, h: 9.1, r: 1.1, .line),
                .rect(x: 16.6, y: 8.4, w: 3.4, h: 11.9, r: 1.1, .line),
                .path("M3.6 10.6 L8.8 6.8 L12.2 8.6 L19.8 3.6", .line),
                .path("M16.2 3.5 H19.9 V7.2", .line)
            ]

        case .fatigue:
            return [
                .rect(x: 2.6, y: 10, w: 18.8, h: 4, r: 2, .soft),
                .path("M2.6 12 C4.2 4.4 5.8 4.4 7.2 12 S10.2 17.6 11.6 12 S14.3 8.6 15.5 12 S17.6 14.2 18.7 12 S20.5 11 21.4 12", .line)
            ]

        case .energy:
            let flame = "M12 21 C8.1 21 5.6 18.2 5.6 14.8 C5.6 11 8.4 9.3 9.5 5.8 C9.8 4.8 11 4.4 11.7 5.2 C13.1 6.8 14 8.6 14.4 10.4 C15 9.6 15.3 8.7 15.4 7.9 C15.5 7.2 16.3 6.9 16.8 7.4 C18.2 8.9 18.4 11.9 18.4 14.8 C18.4 18.2 15.9 21 12 21 Z"
            return [
                .path(flame, .soft),
                .path(flame, .line),
                .path("M12 18.7 C10.6 18.7 9.6 17.6 9.6 16.3 C9.6 14.7 10.9 13.9 11.6 12.4 C13.3 13.5 14.4 14.8 14.4 16.3 C14.4 17.6 13.4 18.7 12 18.7 Z", .solid)
            ]

        case .patterns:
            return [
                .path("M8.9 6.8 L15.1 7.7 M6.9 8.9 L8.1 15.1 M15.8 9.7 L10.2 15.8 M17.6 10.4 L17.9 15.1 M10.9 17.5 L15.6 17.5", .line),
                .circle(cx: 6.5, cy: 6.5, r: 2.4, .soft),
                .circle(cx: 8.5, cy: 17.5, r: 2.4, .soft),
                .circle(cx: 18, cy: 17.5, r: 2.4, .soft),
                .circle(cx: 6.5, cy: 6.5, r: 2.4, .line),
                .circle(cx: 8.5, cy: 17.5, r: 2.4, .line),
                .circle(cx: 18, cy: 17.5, r: 2.4, .line),
                .circle(cx: 17.5, cy: 8, r: 2.6, .solid)
            ]

        // MARK: Insights

        case .spotlight:
            return [
                .circle(cx: 10.4, cy: 10.4, r: 6.6, .soft),
                .circle(cx: 10.4, cy: 10.4, r: 6.6, .line),
                .path("M15.3 15.3 L20.6 20.6", .line),
                .path("M10.4 7.2 Q10.8 10 13.6 10.4 Q10.8 10.8 10.4 13.6 Q10 10.8 7.2 10.4 Q10 10 10.4 7.2 Z", .solid)
            ]

        case .narrative:
            let page = "M6.6 3.5 H13.8 L18.6 8.3 V19 C18.6 19.9 17.9 20.5 17.1 20.5 H6.6 C5.8 20.5 5.1 19.9 5.1 19 V5 C5.1 4.2 5.8 3.5 6.6 3.5 Z"
            return [
                .path(page, .soft),
                .path(page, .line),
                .path("M13.8 3.5 V7 C13.8 7.7 14.4 8.3 15.1 8.3 H18.6", .line),
                .path("M8.3 12.1 H15.4 M8.3 15 H15.4 M8.3 17.9 H12.4", .line)
            ]

        case .target:
            return [
                .circle(cx: 11.4, cy: 12.6, r: 8.2, .soft),
                .circle(cx: 11.4, cy: 12.6, r: 8.2, .line),
                .circle(cx: 11.4, cy: 12.6, r: 4.4, .line),
                .circle(cx: 11.4, cy: 12.6, r: 1.6, .solid),
                .path("M11.4 12.6 L19.4 4.6 M16.8 4.2 L17.2 6.8 L19.8 7.2", .line)
            ]

        // MARK: States

        case .allClear:
            return [
                .circle(cx: 12, cy: 12, r: 8.6, .soft),
                .circle(cx: 12, cy: 12, r: 8.6, .line),
                .path("M8 12.3 L10.8 15 L16.2 9.3", .line)
            ]

        case .sparkle:
            let star = "M10.5 4.6 C11.1 9.4 12.9 11.9 17.9 13 C12.9 14.1 11.1 16.6 10.5 21.4 C9.9 16.6 8.1 14.1 3.1 13 C8.1 11.9 9.9 9.4 10.5 4.6 Z"
            return [
                .path(star, .soft),
                .path(star, .line),
                .path("M18.2 2.6 Q18.6 5 21 5.4 Q18.6 5.8 18.2 8.2 Q17.8 5.8 15.4 5.4 Q17.8 5 18.2 2.6 Z", .solid)
            ]

        case .watch:
            return [
                .rect(x: 5.8, y: 6, w: 12.4, h: 12, r: 3.6, .soft),
                .rect(x: 5.8, y: 6, w: 12.4, h: 12, r: 3.6, .line),
                .path("M8.4 6 L9.1 2.8 H14.9 L15.6 6 M8.4 18 L9.1 21.2 H14.9 L15.6 18", .line),
                .rect(x: 18.2, y: 10.3, w: 1.7, h: 3.4, r: 0.85, .solid),
                .path("M8.3 12 H9.9 L10.9 10.2 L12.6 13.8 L13.6 12 H15.7", .line)
            ]

        case .rest:
            let seat = "M3 12.6 C3 11.5 3.9 10.6 5 10.6 C6.1 10.6 7 11.5 7 12.6 V13.6 H17 V12.6 C17 11.5 17.9 10.6 19 10.6 C20.1 10.6 21 11.5 21 12.6 V16.4 C21 17.3 20.3 18 19.4 18 H4.6 C3.7 18 3 17.3 3 16.4 Z"
            return [
                .path(seat, .soft),
                .path("M5.6 10.8 V8.6 C5.6 7.2 6.7 6.1 8.1 6.1 H15.9 C17.3 6.1 18.4 7.2 18.4 8.6 V10.8", .line),
                .path(seat, .line),
                .path("M5.6 18 V20.2 M18.4 18 V20.2", .line)
            ]

        // MARK: Metrics

        case .hrv:
            // A trace whose beats are unevenly spaced — variability is the point.
            return [
                .rect(x: 2.6, y: 5, w: 18.8, h: 14, r: 4, .soft),
                .path("M2.8 13.4 H6 L7.4 8.4 L9.2 17.2 L10.6 13.4 H13.6 L14.8 9.6 L16.4 16.4 L17.6 13.4 H21.2", .line),
                .circle(cx: 7.4, cy: 8.4, r: 1.15, .solid),
                .circle(cx: 14.8, cy: 9.6, r: 1.15, .solid)
            ]

        case .heartRate:
            let heart = "M12 20.2 C12 20.2 3.6 15.3 3.6 9.4 C3.6 6.5 5.8 4.3 8.5 4.3 C10 4.3 11.3 5.1 12 6.3 C12.7 5.1 14 4.3 15.5 4.3 C18.2 4.3 20.4 6.5 20.4 9.4 C20.4 15.3 12 20.2 12 20.2 Z"
            return [
                .path(heart, .soft),
                .path(heart, .line),
                .path("M12 15.6 C12 15.6 8.4 13.5 8.4 11 C8.4 9.8 9.3 8.9 10.4 8.9 C11.1 8.9 11.7 9.3 12 9.8 C12.3 9.3 12.9 8.9 13.6 8.9 C14.7 8.9 15.6 9.8 15.6 11 C15.6 13.5 12 15.6 12 15.6 Z", .solid)
            ]

        case .oxygen:
            let drop = "M12 3.4 C12 3.4 5.4 10.6 5.4 14.6 C5.4 18.3 8.4 20.8 12 20.8 C15.6 20.8 18.6 18.3 18.6 14.6 C18.6 10.6 12 3.4 12 3.4 Z"
            return [
                .path(drop, .soft),
                .path(drop, .line),
                .circle(cx: 10.4, cy: 15.2, r: 2.2, .line),
                .circle(cx: 14.6, cy: 12.2, r: 1.1, .solid)
            ]

        case .lungs:
            let left = "M10.6 9.4 C10.6 7.7 9.4 6.9 8.2 7.5 C5.4 8.9 3.6 13 3.6 16.8 C3.6 19 5 20.2 6.9 19.6 L9.4 18.8 C10.1 18.6 10.6 17.9 10.6 17.2 Z"
            let right = "M13.4 9.4 C13.4 7.7 14.6 6.9 15.8 7.5 C18.6 8.9 20.4 13 20.4 16.8 C20.4 19 19 20.2 17.1 19.6 L14.6 18.8 C13.9 18.6 13.4 17.9 13.4 17.2 Z"
            return [
                .path(left, .soft),
                .path(right, .soft),
                .path(left, .line),
                .path(right, .line),
                .path("M12 3.4 V11.6 M12 11.6 L10.6 13 M12 11.6 L13.4 13", .line)
            ]

        case .steps:
            return [
                .ellipse(cx: 8.2, cy: 12.6, rx: 2.7, ry: 4.3, .soft),
                .ellipse(cx: 15.8, cy: 8.2, rx: 2.7, ry: 4.3, .soft),
                .ellipse(cx: 8.2, cy: 12.6, rx: 2.7, ry: 4.3, .line),
                .ellipse(cx: 15.8, cy: 8.2, rx: 2.7, ry: 4.3, .line),
                .circle(cx: 8.2, cy: 19.3, r: 1.6, .solid),
                .circle(cx: 15.8, cy: 14.9, r: 1.6, .solid)
            ]

        case .deepSleep:
            // Shortening lines settling toward the bottom — sleep getting deeper.
            return [
                .rect(x: 3.4, y: 4, w: 17.2, h: 16, r: 4.4, .soft),
                .path("M7 8.4 H17 M7 12.2 H14.4 M7 16 H11.2", .line),
                .circle(cx: 15.6, cy: 16, r: 1.5, .solid)
            ]

        case .remSleep:
            let eye = "M2.8 12.6 C5.2 8.4 8.4 6.4 12 6.4 C15.6 6.4 18.8 8.4 21.2 12.6 C18.8 16.8 15.6 18.8 12 18.8 C8.4 18.8 5.2 16.8 2.8 12.6 Z"
            return [
                .path(eye, .soft),
                .path(eye, .line),
                .circle(cx: 12, cy: 12.6, r: 2.6, .solid),
                .path("M12 2.8 V4.4 M6.2 4.2 L7.1 5.6 M17.8 4.2 L16.9 5.6", .line)
            ]

        case .protein:
            let egg = "M12 3.6 C8.6 3.6 5.8 9 5.8 13.8 C5.8 17.8 8.6 20.6 12 20.6 C15.4 20.6 18.2 17.8 18.2 13.8 C18.2 9 15.4 3.6 12 3.6 Z"
            return [
                .path(egg, .soft),
                .path(egg, .line),
                .circle(cx: 12, cy: 14.4, r: 2.8, .solid)
            ]

        case .carbs:
            return [
                .path("M11.6 9.6 C9.4 9.4 8 8 7.8 5.8 C10 6 11.4 7.4 11.6 9.6 Z M12.4 9.6 C14.6 9.4 16 8 16.2 5.8 C14 6 12.6 7.4 12.4 9.6 Z M11.6 14 C9.4 13.8 8 12.4 7.8 10.2 C10 10.4 11.4 11.8 11.6 14 Z M12.4 14 C14.6 13.8 16 12.4 16.2 10.2 C14 10.4 12.6 11.8 12.4 14 Z", .soft),
                .path("M11.6 9.6 C9.4 9.4 8 8 7.8 5.8 C10 6 11.4 7.4 11.6 9.6 Z M12.4 9.6 C14.6 9.4 16 8 16.2 5.8 C14 6 12.6 7.4 12.4 9.6 Z M11.6 14 C9.4 13.8 8 12.4 7.8 10.2 C10 10.4 11.4 11.8 11.6 14 Z M12.4 14 C14.6 13.8 16 12.4 16.2 10.2 C14 10.4 12.6 11.8 12.4 14 Z", .line),
                .path("M12 21 V9.6", .line),
                .ellipse(cx: 12, cy: 4.4, rx: 1.2, ry: 1.8, .solid)
            ]

        case .fat:
            let avocado = "M12 2.9 C9.4 2.9 8.2 6.6 7.1 10.1 C6.2 12.8 5.2 14.6 5.2 16.4 C5.2 19.1 8.1 21.1 12 21.1 C15.9 21.1 18.8 19.1 18.8 16.4 C18.8 14.6 17.8 12.8 16.9 10.1 C15.8 6.6 14.6 2.9 12 2.9 Z"
            return [
                .path(avocado, .soft),
                .path(avocado, .line),
                .circle(cx: 12, cy: 15.4, r: 3, .solid)
            ]

        // MARK: Features

        case .recipe:
            let hat = "M7 13.6 C4.8 13.4 3.4 11.6 3.6 9.6 C3.8 7.6 5.6 6.2 7.6 6.4 C8.2 4.6 10 3.4 12 3.4 C14 3.4 15.8 4.6 16.4 6.4 C18.4 6.2 20.2 7.6 20.4 9.6 C20.6 11.6 19.2 13.4 17 13.6 V17.4 H7 Z"
            return [
                .path(hat, .soft),
                .path(hat, .line),
                .rect(x: 7, y: 17.4, w: 10, h: 3.2, r: 0.9, .line),
                .circle(cx: 12, cy: 9.6, r: 1.15, .solid)
            ]

        case .bell:
            let bell = "M12 3.4 C8.7 3.4 6.4 6 6.4 9.2 V13.2 L4.6 16.4 H19.4 L17.6 13.2 V9.2 C17.6 6 15.3 3.4 12 3.4 Z"
            return [
                .path(bell, .soft),
                .path(bell, .line),
                .path("M9.6 18.4 C10 19.8 10.9 20.6 12 20.6 C13.1 20.6 14 19.8 14.4 18.4 Z", .solid)
            ]

        // MARK: Settings

        case .key:
            return [
                .circle(cx: 8, cy: 15.6, r: 4.3, .soft),
                .circle(cx: 8, cy: 15.6, r: 4.3, .line),
                .circle(cx: 8, cy: 15.6, r: 1.35, .solid),
                .path("M11 12.6 L19.6 4 M16.4 7.2 L18.4 9.2 M18.7 4.9 L20.6 6.8", .line)
            ]

        case .database:
            let can = "M4.6 6 C4.6 4.5 7.9 3.2 12 3.2 C16.1 3.2 19.4 4.5 19.4 6 V18 C19.4 19.5 16.1 20.8 12 20.8 C7.9 20.8 4.6 19.5 4.6 18 Z"
            return [
                .path(can, .soft),
                .ellipse(cx: 12, cy: 6, rx: 7.4, ry: 2.8, .line),
                .path("M4.6 6 V18 C4.6 19.5 7.9 20.8 12 20.8 C16.1 20.8 19.4 19.5 19.4 18 V6", .line),
                .path("M4.6 12 C4.6 13.5 7.9 14.8 12 14.8 C16.1 14.8 19.4 13.5 19.4 12", .line)
            ]

        case .flask:
            return [
                .path("M7.5 14.2 H16.5 L19 18.2 C19.6 19.3 18.8 20.5 17.6 20.5 H6.4 C5.2 20.5 4.4 19.3 5 18.2 Z", .soft),
                .path("M10.3 3.6 V9.2 L5 18.2 C4.4 19.3 5.2 20.5 6.4 20.5 H17.6 C18.8 20.5 19.6 19.3 19 18.2 L13.7 9.2 V3.6 M8.9 3.6 H15.1", .line),
                .circle(cx: 10.4, cy: 17.2, r: 0.95, .solid),
                .circle(cx: 13.9, cy: 16.1, r: 0.75, .solid)
            ]

        case .info:
            return [
                .circle(cx: 12, cy: 12, r: 8.6, .soft),
                .circle(cx: 12, cy: 12, r: 8.6, .line),
                .circle(cx: 12, cy: 8.2, r: 1.15, .solid),
                .path("M12 11.4 V16.4", .line)
            ]
        }
    }

    private func battery(level: CGFloat) -> [Element] {
        [
            .rect(x: 2.4, y: 7, w: 17.4, h: 10, r: 2.8, .soft),
            .rect(x: 2.4, y: 7, w: 17.4, h: 10, r: 2.8, .line),
            .rect(x: 20.5, y: 10, w: 1.8, h: 4, r: 0.9, .solid),
            .rect(x: 4.9, y: 9.5, w: level, h: 5, r: 1.2, .solid)
        ]
    }
}
