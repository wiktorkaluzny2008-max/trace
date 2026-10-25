//
//  AppIntro.swift
//  RecoverySignal2
//
//  The launch intro is the app icon assembling itself. On the icon's charcoal
//  the barbell fades in, the ember heartbeat draws through the bar (with a
//  double haptic beat on the spike), the rounded tile settles in around it, and
//  the "Trace" wordmark rises underneath. Then everything lifts away into the app.
//
//  Cold launch only, skippable with a tap, and switchable off in
//  Settings → Appearance & feedback.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class AppLaunch {
    static let shared = AppLaunch()
    /// False while the intro is on screen; the score reveal waits for it.
    var introFinished = false
    private init() {}
}

struct AppIntroView: View {
    var onFinish: () -> Void

    @State private var drawn: CGFloat = 0
    @State private var barShown = false
    @State private var tileShown = false
    @State private var wordmarkShown = false
    @State private var exiting = false
    @State private var finished = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let tile: CGFloat = 148
    private static let drawTime = 0.95
    private static let ember = Color(red: 1.0, green: 0.478, blue: 0.239)

    var body: some View {
        ZStack {
            BrandBackground()
                .ignoresSafeArea()
                .opacity(exiting ? 0 : 1)

            VStack(spacing: 26) {
                ZStack {
                    // The icon's tile: a slightly lighter charcoal, like the Home Screen icon.
                    RoundedRectangle(cornerRadius: Self.tile * 0.2237, style: .continuous)
                        .fill(Color(red: 0.11, green: 0.12, blue: 0.14))
                        .overlay {
                            RoundedRectangle(cornerRadius: Self.tile * 0.2237, style: .continuous)
                                .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.45), radius: 24, y: 12)
                        .scaleEffect(tileShown ? 1 : 1.35)
                        .opacity(tileShown ? 1 : 0)

                    // The bar and plates, then the pulse drawing through them.
                    BrandBarShape()
                        .stroke(.white, style: StrokeStyle(lineWidth: Self.tile * BrandMark.barWidth / 1024, lineCap: .round))
                        .opacity(barShown ? 1 : 0)
                    BrandPlatesShape()
                        .fill(.white)
                        .opacity(barShown ? 1 : 0)
                    BrandPulseShape()
                        .trim(from: 0, to: drawn)
                        .stroke(Self.ember.opacity(0.7), style: StrokeStyle(lineWidth: Self.tile * 44 / 1024 * 2.2,
                                                                            lineCap: .round, lineJoin: .round))
                        .blur(radius: 9)
                    BrandPulseShape()
                        .trim(from: 0, to: drawn)
                        .stroke(Self.ember, style: StrokeStyle(lineWidth: Self.tile * 44 / 1024, lineCap: .round, lineJoin: .round))
                }
                .frame(width: Self.tile, height: Self.tile)

                VStack(spacing: 8) {
                    TraceWordmark(size: 46, color: .white)
                    Text("Train. Fuel. Recover.")
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .offset(y: wordmarkShown ? 0 : 14)
                .opacity(wordmarkShown ? 1 : 0)
                .blur(radius: wordmarkShown ? 0 : 6)
            }
            .offset(y: -20)
            .scaleEffect(exiting ? 0.92 : 1)
            .opacity(exiting ? 0 : 1)
        }
        .contentShape(Rectangle())
        .onTapGesture { finish() }
        .allowsHitTesting(!exiting)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Trace")
        .accessibilityAddTraits(.isButton)
        .accessibilityHint("Double-tap to skip")
        .task { await play() }
    }

    // MARK: Sequence

    private func play() async {
        if reduceMotion {
            drawn = 1; barShown = true; tileShown = true; wordmarkShown = true
            try? await Task.sleep(for: .milliseconds(900))
            finish()
            return
        }

        let heavy = UIImpactFeedbackGenerator(style: .heavy)
        let light = UIImpactFeedbackGenerator(style: .light)
        let soft = UIImpactFeedbackGenerator(style: .soft)
        heavy.prepare(); light.prepare(); soft.prepare()

        withAnimation(.easeOut(duration: 0.35)) { barShown = true }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(.linear(duration: Self.drawTime)) { drawn = 1 }

        // The beat lands as the line reaches the top of the spike.
        try? await Task.sleep(for: .seconds(Self.drawTime * BrandPulseShape.spikeFraction))
        guard !finished else { return }
        heavy.impactOccurred(intensity: 1)
        try? await Task.sleep(for: .milliseconds(150))
        light.impactOccurred(intensity: 0.8)

        // The tile settles in as the line finishes.
        try? await Task.sleep(for: .seconds(max(0, Self.drawTime * (1 - BrandPulseShape.spikeFraction) - 0.35)))
        guard !finished else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.72)) { tileShown = true }

        try? await Task.sleep(for: .milliseconds(260))
        guard !finished else { return }
        withAnimation(.easeOut(duration: 0.55)) { wordmarkShown = true }
        try? await Task.sleep(for: .milliseconds(320))
        soft.impactOccurred(intensity: 0.5)

        try? await Task.sleep(for: .milliseconds(900))
        finish()
    }

    private func finish() {
        guard !finished else { return }
        finished = true
        withAnimation(.easeInOut(duration: 0.45)) { exiting = true }
        Task {
            try? await Task.sleep(for: .milliseconds(450))
            onFinish()
        }
    }
}

// MARK: - Brand pieces shared by the intro and Settings

/// The icon's charcoal gradient.
struct BrandBackground: View {
    static let top = Color(red: 0.125, green: 0.137, blue: 0.161)
    static let bottom = Color(red: 0.047, green: 0.051, blue: 0.063)

    var body: some View {
        LinearGradient(colors: [Self.top, Self.bottom], startPoint: .top, endPoint: .bottom)
    }
}

/// The logo's bar, on the same 1024 grid as the app icon.
struct BrandBarShape: Shape {
    func path(in rect: CGRect) -> Path { BrandMark.barPath(in: rect) }
}

/// The logo's plates, on the same 1024 grid as the app icon.
struct BrandPlatesShape: Shape {
    func path(in rect: CGRect) -> Path { BrandMark.platesPath(in: rect) }
}

/// The logo's heartbeat as a Shape, on the same 1024 grid as the app icon, so it
/// can be trimmed and animated.
struct BrandPulseShape: Shape {
    func path(in rect: CGRect) -> Path { BrandMark.pulsePath(in: rect) }

    /// How far along the line (0…1) the top of the spike sits.
    static let spikeFraction: Double = {
        let points = BrandMark.classicPoints
        var lengths: [Double] = [0]
        for i in 1..<points.count {
            lengths.append(lengths[i - 1] + hypot(points[i].0 - points[i - 1].0, points[i].1 - points[i - 1].1))
        }
        return lengths[6] / (lengths.last ?? 1)
    }()
}

/// "Trace" as a wordmark: SF Pro Rounded, bold and tightly set, so the letters
/// share the logo's rounded stroke ends.
struct TraceWordmark: View {
    var size: CGFloat = 28
    var color: Color = Theme.textPrimary

    var body: some View {
        Text(verbatim: "Trace")
            .font(.system(size: size, weight: .bold, design: .rounded))
            .tracking(-size * 0.03)
            .foregroundStyle(color)
            .lineLimit(1)
    }
}
