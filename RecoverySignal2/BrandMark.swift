//
//  BrandMark.swift
//  RecoverySignal2
//
//  The logo: a barbell with a heartbeat running through the bar — lifting and
//  the body's signal in one mark. The bar and plates are drawn in one colour,
//  the pulse in the accent. Drawn in code on a 1024 grid so it stays sharp at
//  every size, and shared by the in-app header, the launch intro and the app
//  icon (which is rendered from the same geometry).
//

import SwiftUI

struct BrandMark: View {
    /// The bar and plates.
    var line: Color = .white
    /// The pulse through the bar.
    var accent: Color = Color(red: 1.0, green: 0.478, blue: 0.239)
    /// Scales the mark about its centre.
    var zoom = 1.0

    /// The icon's charcoal tile.
    static let tile = Color(red: 0.082, green: 0.090, blue: 0.106)

    /// The pulse on a 1024 grid, left to right. Index 6 is the top of the spike.
    static let classicPoints: [(Double, Double)] = [
        (330, 512), (420, 512), (452, 470), (484, 512), (520, 512), (548, 560),
        (600, 300), (652, 700), (690, 512), (724, 512)
    ]

    /// Bar stroke width, on the 1024 grid.
    static let barWidth = 52.0
    /// Pulse stroke width, on the 1024 grid.
    static let pulseWidth = 44.0

    /// The bar as a path on the 1024 grid.
    static func barPath(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let origin = CGPoint(x: rect.midX - 512 * s, y: rect.midY - 512 * s)
        var path = Path()
        path.move(to: CGPoint(x: origin.x + 120 * s, y: origin.y + 512 * s))
        path.addLine(to: CGPoint(x: origin.x + 904 * s, y: origin.y + 512 * s))
        return path
    }

    /// The four plates as filled rounded rectangles on the 1024 grid.
    static func platesPath(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let origin = CGPoint(x: rect.midX - 512 * s, y: rect.midY - 512 * s)
        var path = Path()
        // (x, width, height) — inner plates are taller than outer ones.
        let plates: [(Double, Double, Double)] = [(150, 68, 220), (232, 68, 300), (724, 68, 300), (806, 68, 220)]
        for (x, w, h) in plates {
            let r = CGRect(x: origin.x + x * s, y: origin.y + (512 - h / 2) * s, width: w * s, height: h * s)
            path.addRoundedRect(in: r, cornerSize: CGSize(width: 18 * s, height: 18 * s), style: .continuous)
        }
        return path
    }

    /// The pulse as a path on the 1024 grid.
    static func pulsePath(in rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 1024
        let origin = CGPoint(x: rect.midX - 512 * s, y: rect.midY - 512 * s)
        var path = Path()
        for (index, point) in classicPoints.enumerated() {
            let p = CGPoint(x: origin.x + point.0 * s, y: origin.y + point.1 * s)
            index == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        return path
    }

    var body: some View {
        Canvas { context, size in
            let side = min(size.width, size.height) * zoom
            let rect = CGRect(x: (size.width - side) / 2, y: (size.height - side) / 2, width: side, height: side)
            let s = side / 1024
            context.stroke(Self.barPath(in: rect), with: .color(line),
                           style: StrokeStyle(lineWidth: Self.barWidth * s, lineCap: .round))
            context.fill(Self.platesPath(in: rect), with: .color(line))
            context.stroke(Self.pulsePath(in: rect), with: .color(accent),
                           style: StrokeStyle(lineWidth: Self.pulseWidth * s, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
