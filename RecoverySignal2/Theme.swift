//
//  Theme.swift
//  RecoverySignal2
//
//  Shared design system — "Iron & Ember". A charcoal, dark-first base with
//  one saturated ember accent for actions and progress; green / amber / red
//  stay reserved strictly for status. Big numbers use a condensed display
//  face so they read at a glance between sets.
//

import SwiftUI
import UIKit

enum Theme {

    // MARK: - Surfaces

    static let background     = adaptive(light: 0xF4F4F5, dark: 0x000000)
    static let surface        = adaptive(light: 0xFFFFFF, dark: 0x0D0D0E)
    /// A step above `surface`, for controls and inner panels on a card.
    static let surfaceRaised  = adaptive(light: 0xF0F0F2, dark: 0x1B1B1E)
    static let separator      = adaptive(light: 0xE3E3E6, dark: 0x2B2B2F)
    static let track          = adaptive(light: 0xE7E7EA, dark: 0x252529)
    /// Hairline card outline, used instead of drop shadows.
    static let border         = adaptive(light: 0xDFDFE3, dark: 0x28282C)

    // MARK: - Text

    static let textPrimary    = adaptive(light: 0x161618, dark: 0xF7F7F8)
    static let textSecondary  = adaptive(light: 0x56565E, dark: 0xB6B6BF)
    static let textTertiary   = adaptive(light: 0x686871, dark: 0x92929D)

    // MARK: - Accent & status

    /// Ember: the one colour that means "do this" or "progress".
    static let accent         = adaptive(light: 0xB84109, dark: 0xFF7A3D)
    /// Orange fill and dark ink maintain contrast in both appearances.
    static let actionFill     = Color(red: 1, green: 122 / 255, blue: 61 / 255)
    static let onAction       = Color(red: 0.08, green: 0.035, blue: 0.015)
    static let accentDeep     = adaptive(light: 0xC2400A, dark: 0xFF5A14)
    /// Secondary accent: the light end of accent gradients.
    static let mint           = adaptive(light: 0xA94012, dark: 0xFFB37A)

    static let good           = adaptive(light: 0x187746, dark: 0x3CCB7F)
    static let warn           = adaptive(light: 0x966000, dark: 0xFFB340)
    static let bad            = adaptive(light: 0xD93A3A, dark: 0xFF6259)

    // MARK: - Macros
    // Distinct from the ember accent and from each other; never status colours.

    static let protein        = adaptive(light: 0x236E98, dark: 0x4FB0E8)
    static let carbs          = adaptive(light: 0x7650BA, dark: 0xA98DF0)
    static let fat            = adaptive(light: 0x84621C, dark: 0xD9B45A)

    // MARK: - Movement

    /// Steps, cardio and everyday movement.
    static let activity       = adaptive(light: 0x176B5D, dark: 0x45BFA9)
    static let activityDeep   = adaptive(light: 0x176B5D, dark: 0x1F8F7C)
    /// Strength training is the brand, so it shares the accent.
    static let training       = accent

    // MARK: - Sleep
    // Night blues, so sleep never borrows the ember accent: deep is the
    // darkest stage, REM the lightest.

    static let sleepDeep      = adaptive(light: 0x2B57C8, dark: 0x3D6FE0)
    static let sleepCore      = adaptive(light: 0x4F86E6, dark: 0x6A9CF0)
    static let sleepREM       = adaptive(light: 0x8FB6F2, dark: 0xA7CAF7)
    static let sleepNight     = adaptive(light: 0x1B2A6B, dark: 0x151E4E)

    // MARK: - Shape

    static let cornerRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let pageInset: CGFloat = 20
    static let minimumTarget: CGFloat = 44

    enum Motion {
        static let press = Animation.spring(response: 0.24, dampingFraction: 0.86)
        static let settle = Animation.spring(response: 0.36, dampingFraction: 0.88)
    }

    /// The accent sweep used on primary buttons and hero fills.
    static var accentGradient: LinearGradient {
        LinearGradient(colors: [accentDeep, accent], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    // MARK: - Helpers

    /// Builds a color that resolves differently in light and dark mode.
    /// `nonisolated` so the trait-collection closure isn't main-actor bound.
    nonisolated private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}

// MARK: - Typography

extension Font {
    static var heroScore: Font { .display(56) }
    static var metricValue: Font { .system(.title3, design: .default, weight: .semibold) }
    static var eyebrow: Font { .system(.caption2, design: .default, weight: .semibold) }
    /// Big glanceable numbers: bold and condensed, so "12 480 kg" fits on a tile.
    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .title1).scaledValue(for: size), weight: weight).width(.condensed)
    }
    /// Screen titles.
    static var screenTitle: Font { .largeTitle.weight(.bold) }
}

// MARK: - Card styling

private struct CardModifier: ViewModifier {
    var padding: CGFloat

    @Environment(\.displayScale) private var displayScale

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: shape)
            // A true one-pixel hairline instead of a floating shadow.
            .overlay(shape.strokeBorder(Theme.border, lineWidth: 1 / displayScale))
    }
}

extension View {
    func card(padding: CGFloat = 18) -> some View {
        modifier(CardModifier(padding: padding))
    }
}

// MARK: - Buttons

/// Filled orange is reserved for a screen's primary action.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(isEnabled ? Theme.onAction : Theme.textTertiary)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(isEnabled ? Theme.actionFill : Theme.track, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(reduceMotion ? nil : Theme.Motion.press, value: configuration.isPressed)
    }
}

/// Quiet counterpart: tinted text on a raised surface.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .padding(.vertical, 13)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

// MARK: - Small shared components

/// Uppercase section label with an optional glyph, e.g. [heart] RECOVERY.
/// The glyph sits outside the tracked text so letter-spacing doesn't pull it
/// away from the label.
struct SectionLabel: View {
    let text: String
    var icon: Glyph? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                GlyphView(icon, size: 17)
            }
            // Look the label up first; uppercasing the English key would skip the translation.
            Text(LocalizedStringKey(text))
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 4)
    }
}

/// Little "+4%" pill showing change versus a recent baseline.
struct DeltaChip: View {
    let percent: Double?
    /// nil means "no inherent good/bad direction" — the chip stays neutral.
    var higherIsBetter: Bool?

    var body: some View {
        if let percent, abs(percent) >= 1 {
            let rising = percent > 0
            let color: Color = {
                guard let higherIsBetter else { return Theme.textTertiary }
                return rising == higherIsBetter ? Theme.good : Theme.bad
            }()

            HStack(spacing: 2) {
                Image(systemName: rising ? "arrow.up.right" : "arrow.down.right")
                    .font(.system(size: 9, weight: .bold))
                Text("\(abs(Int(percent.rounded())))%")
                    .font(.system(size: 11, weight: .semibold))
                    .monospacedDigit()
            }
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
        }
    }
}

/// A small coloured tag — "BULK", "PR", "WEEK 3".
struct TagPill: View {
    let text: String
    var color: Color = Theme.accent

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.14), in: Capsule())
    }
}
