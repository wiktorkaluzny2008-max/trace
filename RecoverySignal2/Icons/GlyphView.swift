//
//  GlyphView.swift
//  RecoverySignal2
//
//  Draws a Glyph in a palette. Kept free of Theme (and so of UIKit) — the
//  app's brand palettes live in GlyphPalette+Theme.swift.
//

import SwiftUI

nonisolated struct GlyphPalette: Sendable {
    /// Gradient start for outlines and solid details (top-left).
    var primary: Color
    /// Gradient end (bottom-right).
    var secondary: Color
    /// The translucent body fill.
    var soft: Color

    /// Everything in one hue — for tiles tinted by severity or score band.
    static func mono(_ color: Color, soft: Double = 0.2) -> GlyphPalette {
        GlyphPalette(primary: color, secondary: color, soft: color.opacity(soft))
    }

    /// For glyphs sitting on a filled accent button.
    static let onAccent = GlyphPalette(primary: .white, secondary: .white.opacity(0.85), soft: .white.opacity(0.22))
}

/// Scales a 24-unit glyph path into whatever square it's given.
nonisolated struct GlyphShape: Shape {
    let unitPath: Path

    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / 24
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                          tx: rect.midX - 12 * scale,
                                          ty: rect.midY - 12 * scale)
        return unitPath.applying(transform)
    }
}

struct GlyphView: View {
    let glyph: Glyph
    let size: CGFloat
    let palette: GlyphPalette

    init(_ glyph: Glyph, size: CGFloat, palette: GlyphPalette) {
        self.glyph = glyph
        self.size = size
        self.palette = palette
    }

    var body: some View {
        let gradient = LinearGradient(colors: [palette.primary, palette.secondary],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)
        // 1.75 units on the 24 grid, but never thinner than ~1.1pt so small
        // header icons don't go spidery.
        let lineWidth = max(1.1, size * 1.75 / 24)

        ZStack {
            GlyphShape(unitPath: glyph.path(for: .soft))
                .fill(palette.soft)
            GlyphShape(unitPath: glyph.path(for: .line))
                .stroke(gradient, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            GlyphShape(unitPath: glyph.path(for: .solid))
                .fill(gradient)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
