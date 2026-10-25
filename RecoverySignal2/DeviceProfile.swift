//
//  DeviceProfile.swift
//  RecoverySignal2
//
//  What the person wears, asked once during setup and changeable in Settings.
//  Recovery, strain, HRV and fatigue all need a heart-rate tracker; sleep
//  stages, sleep need and tonight's plan need a sleep tracker. Without them
//  those parts of the app would only ever say "not enough data", so they're
//  hidden and the app leads with food, training and body instead.
//

import SwiftUI

enum TrackerKind: String, CaseIterable, Identifiable {
    case appleWatch, other, none

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .appleWatch: "Apple Watch"
        case .other:      "Another watch or ring"
        case .none:       "Nothing, just my iPhone"
        }
    }

    var detail: LocalizedStringKey {
        switch self {
        case .appleWatch: "Heart rate, HRV and sleep, all synced to Apple Health."
        case .other:      "Oura, Garmin, Whoop, Fitbit and others that write to Apple Health."
        case .none:       "Trace focuses on food, training and your body. You can add a tracker later."
        }
    }

    var symbol: String {
        switch self {
        case .appleWatch: "applewatch"
        case .other:      "circle.circle"
        case .none:       "iphone"
        }
    }
}

enum DeviceProfile {
    static let kindKey = "device.kind"
    static let heartKey = "device.tracksHeart"
    static let sleepKey = "device.tracksSleep"

    /// Whether the question has been answered yet.
    static var isSet: Bool { UserDefaults.standard.string(forKey: kindKey) != nil }

    static var kind: TrackerKind {
        TrackerKind(rawValue: UserDefaults.standard.string(forKey: kindKey) ?? "") ?? .appleWatch
    }
    static var tracksHeart: Bool { UserDefaults.standard.object(forKey: heartKey) as? Bool ?? true }
    static var tracksSleep: Bool { UserDefaults.standard.object(forKey: sleepKey) as? Bool ?? true }

    static func save(kind: TrackerKind, heart: Bool, sleep: Bool) {
        let defaults = UserDefaults.standard
        defaults.set(kind.rawValue, forKey: kindKey)
        defaults.set(kind == .appleWatch ? true : (kind == .none ? false : heart), forKey: heartKey)
        defaults.set(kind == .appleWatch ? true : (kind == .none ? false : sleep), forKey: sleepKey)
    }

    static var summary: String {
        switch kind {
        case .appleWatch: return String(localized: "Apple Watch")
        case .none:       return String(localized: "No tracker")
        case .other:
            switch (tracksHeart, tracksSleep) {
            case (true, true):   return String(localized: "Watch or ring · heart rate and sleep")
            case (true, false):  return String(localized: "Watch or ring · heart rate")
            case (false, true):  return String(localized: "Watch or ring · sleep")
            case (false, false): return String(localized: "Watch or ring · steps only")
            }
        }
    }
}

/// The three choices, plus fine-tuning for other trackers, and what changes.
/// Shared by setup and Settings.
struct DeviceChoiceView: View {
    @Binding var kind: TrackerKind
    @Binding var heart: Bool
    @Binding var sleep: Bool

    private var effectiveHeart: Bool { kind == .appleWatch || (kind == .other && heart) }
    private var effectiveSleep: Bool { kind == .appleWatch || (kind == .other && sleep) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(spacing: 10) {
                ForEach(TrackerKind.allCases) { option in
                    Button {
                        withAnimation(.snappy) { kind = option }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: option.symbol)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(kind == option ? .white : Theme.accent)
                                .frame(width: 44, height: 44)
                                .background(kind == option ? Theme.accent : Theme.accent.opacity(0.12),
                                            in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                                Text(option.detail).font(.caption).foregroundStyle(Theme.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: kind == option ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 20))
                                .foregroundStyle(kind == option ? Theme.accent : Theme.textTertiary)
                        }
                        .padding(14)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(kind == option ? Theme.accent.opacity(0.6) : Theme.border, lineWidth: kind == option ? 1.5 : 0.5))
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(kind == option ? .isSelected : [])
                }
            }
            .sensoryFeedback(.selection, trigger: kind)

            if kind == .other {
                VStack(spacing: 0) {
                    Toggle(isOn: $heart) {
                        Label("Tracks heart rate and HRV", systemImage: "heart.fill").font(.subheadline.weight(.medium))
                    }
                    .padding(14)
                    Divider().overlay(Theme.separator)
                    Toggle(isOn: $sleep) {
                        Label("Tracks sleep", systemImage: "bed.double.fill").font(.subheadline.weight(.medium))
                    }
                    .padding(14)
                }
                .tint(Theme.accent)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("What you'll see").font(.footnote.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                feature("Food, macros and calorie targets", on: true)
                feature("Workouts, strength progress and the coach", on: true)
                feature("Weight and body composition", on: true)
                feature("Recovery score, strain, HRV and fatigue", on: effectiveHeart)
                feature("Sleep stages, sleep need and tonight's plan", on: effectiveSleep)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func feature(_ text: LocalizedStringKey, on: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: on ? "checkmark.circle.fill" : "minus.circle")
                .foregroundStyle(on ? Theme.good : Theme.textTertiary)
            Text(text)
                .font(.footnote)
                .foregroundStyle(on ? Theme.textPrimary : Theme.textTertiary)
                .strikethrough(!on, color: Theme.textTertiary)
        }
        .animation(.snappy, value: on)
    }
}

/// Settings → Your devices.
struct DevicesSettingsPage: View {
    @State private var kind = DeviceProfile.kind
    @AppStorage(DeviceProfile.heartKey) private var heart = true
    @AppStorage(DeviceProfile.sleepKey) private var sleep = true
    @State private var otherHeart = DeviceProfile.tracksHeart
    @State private var otherSleep = DeviceProfile.tracksSleep

    var body: some View {
        SettingsPage(title: "Your devices") {
            SettingsNote("Trace shows only what your devices can measure, so nothing sits empty waiting for data that won't come.")
            DeviceChoiceView(kind: $kind, heart: $otherHeart, sleep: $otherSleep)
            SettingsNote("Everything comes through Apple Health, so any device that writes heart rate or sleep there works. Change this any time.")
        }
        .onChange(of: kind) { _, _ in apply() }
        .onChange(of: otherHeart) { _, _ in apply() }
        .onChange(of: otherSleep) { _, _ in apply() }
    }

    private func apply() {
        DeviceProfile.save(kind: kind, heart: otherHeart, sleep: otherSleep)
        // Nudge the @AppStorage readers on other screens.
        heart = DeviceProfile.tracksHeart
        sleep = DeviceProfile.tracksSleep
    }
}
