//
//  GeminiBadge.swift
//  RecoverySignal2
//
//  Today's "Powered by Gemini" badge and the Gemini sparkle used wherever
//  Gemini does the work. Tapping it explains what the AI does in the app and whether it's
//  connected.
//

import SwiftUI

/// Four-pointed star with concave sides, the shape associated with Gemini.
struct GeminiSparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = min(rect.width, rect.height) / 2
        let tips = [CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x + r, y: c.y),
                    CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x - r, y: c.y)]
        var path = Path()
        path.move(to: tips[0])
        // Each side curves inward; the control point sits a little out from the
        // centre toward that quadrant's corner, which gives the logo's full body.
        let corners = [CGPoint(x: 1, y: -1), CGPoint(x: 1, y: 1), CGPoint(x: -1, y: 1), CGPoint(x: -1, y: -1)]
        for i in 1...4 {
            let k = corners[i - 1]
            path.addQuadCurve(to: tips[i % 4], control: CGPoint(x: c.x + k.x * r * 0.14, y: c.y + k.y * r * 0.14))
        }
        path.closeSubpath()
        return path
    }
}

enum GeminiStyle {
    static let blue   = Color(red: 0.26, green: 0.52, blue: 0.96)
    static let red    = Color(red: 0.92, green: 0.26, blue: 0.21)
    static let yellow = Color(red: 0.98, green: 0.74, blue: 0.02)
    static let green  = Color(red: 0.20, green: 0.66, blue: 0.33)
    /// For text and SF Symbols that sit beside the mark.
    static let gradient = [blue, Color(red: 0.45, green: 0.45, blue: 0.95), blue]
    /// Brushed-metal grey for the "Powered by" lead-in.
    static let silver = LinearGradient(colors: [Color(white: 0.78), Color(white: 0.56), Color(white: 0.72)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
    /// The blue-to-violet-to-rose sweep of the Gemini wordmark.
    static let wordmark = LinearGradient(colors: [Color(red: 0.28, green: 0.59, blue: 0.89),
                                                  Color(red: 0.57, green: 0.47, blue: 0.78),
                                                  Color(red: 0.79, green: 0.40, blue: 0.45)],
                                         startPoint: .leading, endPoint: .trailing)
}

/// "Gemini" set in the brand's gradient.
struct GeminiWordmark: View {
    var size: CGFloat = 15

    var body: some View {
        Text(verbatim: "Gemini")
            .font(.system(size: size, weight: .medium))
            .tracking(-0.2)
            .foregroundStyle(GeminiStyle.wordmark)
    }
}

/// The Gemini sparkle in Google's colours: red at the top, blue on the right
/// and through the centre, green at the bottom, yellow on the left.
struct GeminiMark: View {
    var size: CGFloat = 16

    var body: some View {
        ZStack {
            GeminiSparkle()
                .fill(AngularGradient(
                    stops: [
                        .init(color: GeminiStyle.blue, location: 0.00),   // right
                        .init(color: GeminiStyle.blue, location: 0.10),
                        .init(color: GeminiStyle.green, location: 0.25),  // bottom
                        .init(color: GeminiStyle.yellow, location: 0.47), // left
                        .init(color: GeminiStyle.red, location: 0.64),
                        .init(color: GeminiStyle.red, location: 0.78),    // top
                        .init(color: GeminiStyle.blue, location: 0.90),
                        .init(color: GeminiStyle.blue, location: 1.00)
                    ],
                    center: .center))
            GeminiSparkle()
                .fill(RadialGradient(colors: [GeminiStyle.blue, GeminiStyle.blue.opacity(0)],
                                     center: UnitPoint(x: 0.6, y: 0.5), startRadius: 0, endRadius: size * 0.3))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Today's attribution: powered by Gemini.
struct GeminiBadge: View {
    @State private var showsInfo = false
    @State private var shimmer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            showsInfo = true
        } label: {
            HStack(spacing: 4) {
                if OnDeviceAI.standsInForGemini {
                    Image(systemName: "apple.intelligence")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(GeminiStyle.wordmark)
                        .scaleEffect(shimmer ? 1.06 : 0.94)
                    Text("On-device AI")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(GeminiStyle.wordmark)
                } else {
                    Text("Powered by")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(GeminiStyle.silver)
                    GeminiMark(size: 11)
                        .frame(width: 12, height: 12)
                        .scaleEffect(shimmer ? 1.06 : 0.94)
                        .rotationEffect(.degrees(shimmer ? 8 : -8))
                    GeminiWordmark(size: 11)
                }
            }
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(OnDeviceAI.standsInForGemini ? "On-device AI" : "Powered by Gemini")
        .sensoryFeedback(.selection, trigger: showsInfo)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) { shimmer = true }
        }
        .sheet(isPresented: $showsInfo) {
            GeminiInfoSheet()
                .presentationDetents([.medium, .large])
        }
    }
}

struct GeminiInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    private var hasKey: Bool { !(KeychainStore.get(APIKeyName.gemini) ?? "").isEmpty }
    private var model: String? { UserDefaults.standard.string(forKey: "ai.geminiModel") }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        GeminiMark(size: 44)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(OnDeviceAI.standsInForGemini ? "Apple Intelligence, on your iPhone" : "Powered by Google Gemini")
                                .font(.headline)
                                .foregroundStyle(Theme.textPrimary)
                            HStack(spacing: 5) {
                                Circle().fill(hasKey || OnDeviceAI.isUsable ? Theme.good : Theme.warn).frame(width: 7, height: 7)
                                Text(hasKey ? (model.map { "Connected · \($0)" } ?? "Connected") : (OnDeviceAI.isUsable ? "No key needed for most features" : "Add your API key in Settings"))
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }

                    VStack(spacing: 0) {
                        feature("camera.viewfinder", "Snap a meal", "Estimates calories and macros from a photo and your description.")
                        Divider().overlay(Theme.separator)
                        feature("fork.knife", "Meal ideas", "Recipes sized to the calories and macros you have left today.")
                        Divider().overlay(Theme.separator)
                        feature("text.alignleft", "Weekly narrative", "Turns the week's numbers into a plain-English read in Insights.")
                    }
                    .card(padding: 4)

                    Text("When Apple Intelligence is on, most of this runs on your iPhone and nothing is sent anywhere. Otherwise aggregated numbers, remaining macros, your dietary notes and photos you choose are sent to Google. Raw Health samples never leave your phone. Recovery, strain and all the analysis maths run on your iPhone without AI.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("AI in Trace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(GeminiStyle.blue)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

/// Small inline "Gemini" tag for screens where Gemini produces the content.
struct PoweredByGemini: View {
    var body: some View {
        HStack(spacing: 4) {
            GeminiMark(size: 12)
            Text("Gemini")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Theme.surface, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.border, lineWidth: 0.5))
    }
}
