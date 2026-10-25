//
//  GlyphPalette+Theme.swift
//  RecoverySignal2
//
//  The app's brand palettes for the icon set. Built from Theme, so every
//  glyph follows light/dark mode automatically.
//

import SwiftUI

extension GlyphPalette {
    /// Neutral category symbols keep orange reserved for actions and completion.
    static var brand: GlyphPalette {
        GlyphPalette(primary: Theme.textSecondary, secondary: Theme.textSecondary, soft: Theme.textTertiary.opacity(0.14))
    }

    /// Greyed out, for features that are still locked.
    static var muted: GlyphPalette {
        GlyphPalette(primary: Theme.textTertiary, secondary: Theme.textTertiary, soft: Theme.textTertiary.opacity(0.14))
    }
}

extension GlyphView {
    /// Brand-coloured glyph — use this unless the icon needs to carry a status colour.
    init(_ glyph: Glyph, size: CGFloat) {
        self.init(glyph, size: size, palette: .brand)
    }
}

/// A glyph on a softly tinted rounded tile, as used in list rows and cards.
struct GlyphTile: View {
    let glyph: Glyph
    var color: Color = Theme.textSecondary
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(color.opacity(0.12))
            GlyphView(glyph, size: size * 0.56, palette: .mono(color, soft: 0.24))
        }
        .frame(width: size, height: size)
    }
}
