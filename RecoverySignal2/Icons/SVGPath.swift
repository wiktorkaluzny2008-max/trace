//
//  SVGPath.swift
//  RecoverySignal2
//
//  Turns SVG path data ("M12 20.5 C…") into a SwiftUI Path, so the icon set
//  can be authored in the same notation any vector tool exports and previewed
//  in a browser from the exact same strings the app draws.
//
//  Supports the full command set: M L H V C S Q T A Z, absolute and relative,
//  implicit repeats, and compact number syntax like "1.5.5" or "3-2".
//  Pure SwiftUI + CoreGraphics — no UIKit — so it also compiles on macOS.
//

import SwiftUI

nonisolated enum SVGPath {

    static func path(_ data: String) -> Path {
        var parser = Parser(Array(data.utf8))
        return parser.run()
    }

    private struct Parser {
        let bytes: [UInt8]
        var i = 0
        var path = Path()
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        /// Last cubic / quadratic control point, for S and T reflection.
        var lastCubicControl: CGPoint?
        var lastQuadControl: CGPoint?

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func run() -> Path {
            var command: UInt8 = 0
            while true {
                skipSeparators()
                guard i < bytes.count else { break }
                let before = i

                if isCommand(bytes[i]) {
                    command = bytes[i]
                    i += 1
                } else if command == 0 {
                    break                        // numbers before any command: malformed
                }
                // A bare number after M/m continues as an implicit L/l.
                let issued = command
                execute(command)
                if issued == UInt8(ascii: "M") { command = UInt8(ascii: "L") }
                if issued == UInt8(ascii: "m") { command = UInt8(ascii: "l") }
                if issued == UInt8(ascii: "Z") || issued == UInt8(ascii: "z") { command = 0 }
                // Nothing consumed means the data is malformed; stop rather than spin forever.
                if i == before { break }
            }
            return path
        }

        // MARK: Commands

        mutating func execute(_ c: UInt8) {
            let relative = c >= UInt8(ascii: "a")
            let base = relative ? current : .zero

            switch c | 0x20 {                           // lowercase for matching
            case UInt8(ascii: "m"):
                guard let p = point(base) else { return }
                path.move(to: p)
                current = p; subpathStart = p
                clearControls()

            case UInt8(ascii: "l"):
                guard let p = point(base) else { return }
                path.addLine(to: p); current = p
                clearControls()

            case UInt8(ascii: "h"):
                guard let x = number() else { return }
                let p = CGPoint(x: (relative ? current.x : 0) + x, y: current.y)
                path.addLine(to: p); current = p
                clearControls()

            case UInt8(ascii: "v"):
                guard let y = number() else { return }
                let p = CGPoint(x: current.x, y: (relative ? current.y : 0) + y)
                path.addLine(to: p); current = p
                clearControls()

            case UInt8(ascii: "c"):
                guard let c1 = point(base), let c2 = point(base), let p = point(base) else { return }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastCubicControl = c2; lastQuadControl = nil

            case UInt8(ascii: "s"):
                guard let c2 = point(base), let p = point(base) else { return }
                let c1 = reflect(lastCubicControl)
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p; lastCubicControl = c2; lastQuadControl = nil

            case UInt8(ascii: "q"):
                guard let c1 = point(base), let p = point(base) else { return }
                path.addQuadCurve(to: p, control: c1)
                current = p; lastQuadControl = c1; lastCubicControl = nil

            case UInt8(ascii: "t"):
                guard let p = point(base) else { return }
                let c1 = reflect(lastQuadControl)
                path.addQuadCurve(to: p, control: c1)
                current = p; lastQuadControl = c1; lastCubicControl = nil

            case UInt8(ascii: "a"):
                guard let rx = number(), let ry = number(), let rotation = number(),
                      let large = flag(), let sweep = flag(), let p = point(base) else { return }
                addArc(to: p, rx: rx, ry: ry, rotationDegrees: rotation, largeArc: large, sweep: sweep)
                current = p
                clearControls()

            case UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
                clearControls()

            default:
                i = bytes.count                          // unknown command: stop cleanly
            }
        }

        mutating func clearControls() { lastCubicControl = nil; lastQuadControl = nil }

        func reflect(_ control: CGPoint?) -> CGPoint {
            guard let control else { return current }
            return CGPoint(x: 2 * current.x - control.x, y: 2 * current.y - control.y)
        }

        // MARK: Elliptical arc → cubic Béziers (SVG spec, appendix B.2.4)

        mutating func addArc(to end: CGPoint, rx rxIn: Double, ry ryIn: Double,
                             rotationDegrees: Double, largeArc: Bool, sweep: Bool) {
            let start = current
            if start == end { return }
            var rx = abs(rxIn), ry = abs(ryIn)
            if rx == 0 || ry == 0 { path.addLine(to: end); return }

            let phi = rotationDegrees * .pi / 180
            let cosPhi = cos(phi), sinPhi = sin(phi)

            // Step 1: move to a frame where the ellipse is axis-aligned at the chord midpoint.
            let dx = (Double(start.x) - Double(end.x)) / 2
            let dy = (Double(start.y) - Double(end.y)) / 2
            let x1 = cosPhi * dx + sinPhi * dy
            let y1 = -sinPhi * dx + cosPhi * dy

            // Radii too small to span the chord are scaled up just enough.
            let lambda = (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
            if lambda > 1 { let s = lambda.squareRoot(); rx *= s; ry *= s }

            // Step 2: centre in that frame.
            let num = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
            let den = rx * rx * y1 * y1 + ry * ry * x1 * x1
            let coef = (den == 0 ? 0 : max(0, num / den).squareRoot()) * (largeArc == sweep ? -1 : 1)
            let cxp = coef * (rx * y1 / ry)
            let cyp = coef * -(ry * x1 / rx)

            // Step 3: back to user space.
            let cx = cosPhi * cxp - sinPhi * cyp + (Double(start.x) + Double(end.x)) / 2
            let cy = sinPhi * cxp + cosPhi * cyp + (Double(start.y) + Double(end.y)) / 2

            // Step 4: start angle and sweep.
            func angle(_ ux: Double, _ uy: Double, _ vx: Double, _ vy: Double) -> Double {
                atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            }
            let ux = (x1 - cxp) / rx, uy = (y1 - cyp) / ry
            let vx = (-x1 - cxp) / rx, vy = (-y1 - cyp) / ry
            let theta1 = angle(1, 0, ux, uy)
            var delta = angle(ux, uy, vx, vy)
            if !sweep && delta > 0 { delta -= 2 * .pi }
            if sweep && delta < 0 { delta += 2 * .pi }

            // Split into ≤ 90° pieces; each is one cubic with handle length k.
            let segments = max(1, Int((abs(delta) / (.pi / 2)).rounded(.up)))
            let step = delta / Double(segments)
            let k = 4.0 / 3.0 * tan(step / 4)

            func map(_ x: Double, _ y: Double) -> CGPoint {
                CGPoint(x: cx + rx * x * cosPhi - ry * y * sinPhi,
                        y: cy + rx * x * sinPhi + ry * y * cosPhi)
            }

            for n in 0..<segments {
                let a1 = theta1 + Double(n) * step
                let a2 = a1 + step
                let c1 = map(cos(a1) - k * sin(a1), sin(a1) + k * cos(a1))
                let c2 = map(cos(a2) + k * sin(a2), sin(a2) - k * cos(a2))
                let p = n == segments - 1 ? end : map(cos(a2), sin(a2))
                path.addCurve(to: p, control1: c1, control2: c2)
            }
        }

        // MARK: Lexing

        func isCommand(_ b: UInt8) -> Bool {
            switch b {
            case UInt8(ascii: "M"), UInt8(ascii: "m"), UInt8(ascii: "L"), UInt8(ascii: "l"),
                 UInt8(ascii: "H"), UInt8(ascii: "h"), UInt8(ascii: "V"), UInt8(ascii: "v"),
                 UInt8(ascii: "C"), UInt8(ascii: "c"), UInt8(ascii: "S"), UInt8(ascii: "s"),
                 UInt8(ascii: "Q"), UInt8(ascii: "q"), UInt8(ascii: "T"), UInt8(ascii: "t"),
                 UInt8(ascii: "A"), UInt8(ascii: "a"), UInt8(ascii: "Z"), UInt8(ascii: "z"):
                return true
            default:
                return false
            }
        }

        mutating func skipSeparators() {
            while i < bytes.count, bytes[i] == 0x20 || bytes[i] == 0x2C || bytes[i] == 0x0A
                    || bytes[i] == 0x0D || bytes[i] == 0x09 {
                i += 1
            }
        }

        mutating func point(_ base: CGPoint) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: Double(base.x) + x, y: Double(base.y) + y)
        }

        /// Arc flags are single digits and may be written with no separator ("a4 4 0 01 8 0").
        mutating func flag() -> Bool? {
            skipSeparators()
            guard i < bytes.count, bytes[i] == UInt8(ascii: "0") || bytes[i] == UInt8(ascii: "1") else { return nil }
            defer { i += 1 }
            return bytes[i] == UInt8(ascii: "1")
        }

        mutating func number() -> Double? {
            skipSeparators()
            let start = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "-") || bytes[i] == UInt8(ascii: "+") { i += 1 }
            var sawDot = false, sawDigit = false
            while i < bytes.count {
                let b = bytes[i]
                if b >= 0x30 && b <= 0x39 { sawDigit = true; i += 1 }
                else if b == UInt8(ascii: ".") && !sawDot { sawDot = true; i += 1 }
                else { break }
            }
            if sawDigit, i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                var j = i + 1
                if j < bytes.count, bytes[j] == UInt8(ascii: "-") || bytes[j] == UInt8(ascii: "+") { j += 1 }
                if j < bytes.count, bytes[j] >= 0x30 && bytes[j] <= 0x39 {
                    i = j
                    while i < bytes.count, bytes[i] >= 0x30 && bytes[i] <= 0x39 { i += 1 }
                }
            }
            guard sawDigit, let text = String(bytes: bytes[start..<i], encoding: .ascii) else {
                i = start
                return nil
            }
            return Double(text)
        }
    }
}
