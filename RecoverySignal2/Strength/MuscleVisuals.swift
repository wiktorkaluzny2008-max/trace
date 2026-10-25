//
//  MuscleVisuals.swift
//  RecoverySignal2
//
//  The muscle radar (weekly sets per muscle as distance from the centre, dots
//  joined into a shape) and the front/back body map (darker = more sets).
//

import SwiftUI

/// Sets at which a muscle reads as "fully trained" — the top of the commonly
/// cited 10–20 hard sets per week range for hypertrophy.
enum MuscleScale {
    static let fullSets = 20.0

    static func intensity(_ sets: Double) -> Double {
        min(max(sets / fullSets, 0), 1)
    }
}

// MARK: - Radar

struct MuscleRadar: View {
    let sets: [Muscle: Double]

    private var outerSets: Double {
        // Grow past 20 only if a muscle actually exceeds it, in steps of 5.
        max(MuscleScale.fullSets, ((sets.values.max() ?? 0) / 5).rounded(.up) * 5)
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let radius = size / 2 - 46
            let muscles = Muscle.allCases
            let points = muscles.enumerated().map { index, muscle in
                point(index: index, count: muscles.count, value: (sets[muscle] ?? 0) / outerSets,
                      radius: radius, center: center)
            }

            ZStack {
                // Rings at 10 sets, 20 sets and the outer edge.
                ForEach(ringValues, id: \.self) { value in
                    Circle()
                        .stroke(value == outerSets ? Theme.border : Theme.separator,
                                style: StrokeStyle(lineWidth: 1, dash: value == outerSets ? [] : [3, 3]))
                        .frame(width: radius * 2 * value / outerSets, height: radius * 2 * value / outerSets)
                        .position(center)
                }

                // Spokes.
                Path { path in
                    for index in muscles.indices {
                        path.move(to: center)
                        path.addLine(to: point(index: index, count: muscles.count, value: 1, radius: radius, center: center))
                    }
                }
                .stroke(Theme.separator, lineWidth: 0.75)

                // The volume shape.
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.closeSubpath()
                }
                .fill(Theme.accent.opacity(0.12))

                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                    path.closeSubpath()
                }
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 1.75, lineJoin: .round))

                ForEach(Array(points.enumerated()), id: \.offset) { index, p in
                    Circle()
                        .fill((sets[muscles[index]] ?? 0) > 0 ? Theme.accentDeep : Theme.textTertiary)
                        .frame(width: 6, height: 6)
                        .position(p)
                }

                // Labels just outside the rim.
                ForEach(Array(muscles.enumerated()), id: \.offset) { index, muscle in
                    let labelPoint = point(index: index, count: muscles.count, value: 1, radius: radius + 26, center: center)
                    VStack(spacing: 0) {
                        Text(muscle.name)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(Theme.textSecondary)
                        Text(formatSets(sets[muscle] ?? 0))
                            .font(.system(size: 9, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle((sets[muscle] ?? 0) > 0 ? Theme.textPrimary : Theme.textTertiary)
                    }
                    .fixedSize()
                    .position(labelPoint)
                }

                // Ring captions along the top spoke's right edge.
                ForEach(ringValues.filter { $0 < outerSets }, id: \.self) { value in
                    Text("\(Int(value))")
                        .font(.system(size: 8))
                        .foregroundStyle(Theme.textTertiary)
                        .position(x: center.x + 8, y: center.y - radius * value / outerSets + 6)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var ringValues: [Double] {
        [10, 20, outerSets].filter { $0 <= outerSets }.uniqued()
    }

    private func point(index: Int, count: Int, value: Double, radius: Double, center: CGPoint) -> CGPoint {
        let angle = (Double(index) / Double(count)) * 2 * .pi - .pi / 2
        return CGPoint(x: center.x + cos(angle) * radius * value, y: center.y + sin(angle) * radius * value)
    }

    private func formatSets(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))" : value.formatted(.number.precision(.fractionLength(1)))
    }

    private var accessibilitySummary: String {
        Muscle.allCases.map { "\($0.name) \(formatSets(sets[$0] ?? 0)) sets" }.joined(separator: ", ")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

// MARK: - Body map

struct BodyMap: View {
    let sets: [Muscle: Double]

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            figure(BodyMapShapes.front, label: "Front")
            figure(BodyMapShapes.back, label: "Back")
        }
    }

    private func figure(_ regions: [BodyRegion], label: String) -> some View {
        VStack(spacing: 6) {
            Canvas { context, size in
                let scale = min(size.width / BodyMapShapes.width, size.height / BodyMapShapes.height)
                let offsetX = (size.width - BodyMapShapes.width * scale) / 2
                let base = CGAffineTransform(translationX: offsetX, y: 0).scaledBy(x: scale, y: scale)
                let mirror = base.translatedBy(x: BodyMapShapes.width, y: 0).scaledBy(x: -1, y: 1)

                for transform in [base, mirror] {
                    for region in regions {
                        let path = SVGPath.path(region.path).applying(transform)
                        context.fill(path, with: .color(fill(for: region.muscle)))
                        context.stroke(path, with: .color(Theme.surface), lineWidth: 0.9)
                    }
                }
            }
            .aspectRatio(BodyMapShapes.width / BodyMapShapes.height, contentMode: .fit)

            Text(label.uppercased())
                .font(.eyebrow)
                .tracking(0.8)
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fill(for muscle: Muscle?) -> Color {
        guard let muscle else { return Theme.track.opacity(0.9) }
        let sets = sets[muscle] ?? 0
        guard sets > 0 else { return Theme.track }
        return Theme.accentDeep.opacity(0.16 + 0.84 * MuscleScale.intensity(sets))
    }
}

/// "0 · 10 · 20+ sets" colour key for the body map.
struct BodyMapLegend: View {
    var body: some View {
        HStack(spacing: 8) {
            Text("0")
            LinearGradient(colors: [Theme.track, Theme.accentDeep.opacity(0.58), Theme.accentDeep],
                           startPoint: .leading, endPoint: .trailing)
                .frame(height: 6)
                .clipShape(Capsule())
            Text("\(Int(MuscleScale.fullSets))+ sets / week")
        }
        .font(.system(size: 10))
        .monospacedDigit()
        .foregroundStyle(Theme.textTertiary)
    }
}
