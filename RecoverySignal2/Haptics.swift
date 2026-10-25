//
//  Haptics.swift
//  RecoverySignal2
//
//  Haptic choreography for the recovery score reveal.
//
//  On iPhones with a Taptic Engine the whole reveal is one Core Haptics pattern:
//  a rumble that swells as the ring fills, sharp ticks every 5 points timed to
//  the ring's easing curve, and a heavy landing that differs by recovery band.
//  Devices without Core Haptics fall back to strong UIKit impacts.
//  Both respect the phone's System Haptics setting.
//

import UIKit
import CoreHaptics

@MainActor
final class ScoreRevealHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?

    private let tickFallback = UIImpactFeedbackGenerator(style: .rigid)
    private let landFallback = UIImpactFeedbackGenerator(style: .heavy)
    private let notificationFallback = UINotificationFeedbackGenerator()

    func prepare() {
        tickFallback.prepare()
        landFallback.prepare()
        notificationFallback.prepare()

        guard engine == nil, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            let engine = try CHHapticEngine()
            engine.isAutoShutdownEnabled = true
            // The system can stop the engine (e.g. app backgrounded); restart on demand.
            engine.resetHandler = { [weak engine] in try? engine?.start() }
            try engine.start()
            self.engine = engine
        } catch {
            engine = nil
        }
    }

    /// Plays the full reveal as one pattern, synchronised with a ring that eases
    /// out cubically over `duration`. Returns false if Core Haptics isn't
    /// available, so the caller can drive the UIKit fallback frame by frame.
    func playReveal(target: Double, duration: Double, band: RecoveryScore.Band) -> Bool {
        guard let engine, target > 0 else { return false }

        var events: [CHHapticEvent] = []

        // The swell underneath the whole fill.
        events.append(CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.75),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25)
            ],
            relativeTime: 0,
            duration: duration
        ))

        // A tick each time the displayed score crosses a multiple of 5. The ring
        // follows eased = 1 − (1 − t)³, so solve for t to land ticks on the number.
        var points = 5.0
        while points < target {
            let eased = points / target
            let t = 1 - pow(1 - eased, 1.0 / 3.0)
            events.append(transient(intensity: 0.7 + 0.3 * eased, sharpness: 0.5 + 0.45 * eased, at: t * duration))
            points += 5
        }

        events += landing(for: band, at: duration)

        // Everything grows from about half strength to full as the ring fills.
        let swell = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.5),
                .init(relativeTime: duration * 0.8, value: 0.9),
                .init(relativeTime: duration, value: 1.0)
            ],
            relativeTime: 0
        )

        do {
            let pattern = try CHHapticPattern(events: events, parameterCurves: [swell])
            let player = try engine.makePlayer(with: pattern)
            try engine.start()
            try player.start(atTime: CHHapticTimeImmediate)
            self.player = player
            return true
        } catch {
            return false
        }
    }

    /// Stops a reveal that's cut short (e.g. the app is closed mid-animation).
    func stop() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        player = nil
    }

    // MARK: Fallback (no Core Haptics)

    func tick(progress: Double) {
        tickFallback.impactOccurred(intensity: 0.6 + 0.4 * min(max(progress, 0), 1))
    }

    func land(on band: RecoveryScore.Band) {
        switch band {
        case .strong:
            notificationFallback.notificationOccurred(.success)
            landFallback.impactOccurred(intensity: 1.0)
        case .moderate:
            landFallback.impactOccurred(intensity: 1.0)
        case .strained:
            notificationFallback.notificationOccurred(.warning)
        }
    }

    // MARK: Pattern pieces

    private func transient(intensity: Double, sharpness: Double, at time: Double) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(min(intensity, 1))),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(min(sharpness, 1)))
            ],
            relativeTime: time
        )
    }

    private func thud(at time: Double, length: Double) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.15)
            ],
            relativeTime: time,
            duration: length
        )
    }

    private func landing(for band: RecoveryScore.Band, at end: Double) -> [CHHapticEvent] {
        switch band {
        case .strong:
            // Two big, bright hits over a deep thud — a celebratory "ba-dum".
            return [transient(intensity: 1, sharpness: 0.7, at: end),
                    thud(at: end, length: 0.22),
                    transient(intensity: 1, sharpness: 0.9, at: end + 0.16)]
        case .moderate:
            // One firm, rounded hit.
            return [transient(intensity: 1, sharpness: 0.5, at: end),
                    thud(at: end, length: 0.16)]
        case .strained:
            // Three sharp warning pulses.
            return [transient(intensity: 1, sharpness: 1, at: end),
                    transient(intensity: 1, sharpness: 1, at: end + 0.13),
                    transient(intensity: 1, sharpness: 1, at: end + 0.26)]
        }
    }
}
