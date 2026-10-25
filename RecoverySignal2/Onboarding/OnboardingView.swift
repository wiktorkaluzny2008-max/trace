//
//  OnboardingView.swift
//  RecoverySignal2
//
//  The setup screens. One idea per screen, a short reason for every question,
//  and each answer goes straight into the same settings the rest of the app
//  uses — so everything here can be changed later in Settings.
//

import SwiftUI
import SwiftData
import HealthKit
import UserNotifications

struct OnboardingView: View {
    @State private var coordinator = OnboardingCoordinator.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            header
            ZStack {
                if let step = coordinator.current {
                    stepView(step)
                        .id(step)
                        .transition(reduceMotion ? .opacity : .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(maxHeight: .infinity)
        }
        .background(Theme.background.ignoresSafeArea())
        .animation(reduceMotion ? nil : Theme.Motion.settle, value: coordinator.index)
        .sensoryFeedback(.selection, trigger: coordinator.index)
        .interactiveDismissDisabled()
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                coordinator.back()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.textPrimary)
            .opacity(coordinator.index > 0 ? 1 : 0)
            .disabled(coordinator.index == 0)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Capsule().fill(Theme.accent)
                        .frame(width: max(geo.size.width * coordinator.progress, 6))
                        .animation(reduceMotion ? nil : Theme.Motion.settle, value: coordinator.progress)
                }
            }
            .frame(height: 5)

            Text(verbatim: "\(coordinator.index + 1)/\(coordinator.steps.count)")
                .font(.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 36, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private func stepView(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome:       WelcomeStep()
        case .devices:       DevicesStep()
        case .health:        HealthStep()
        case .aboutYou:      AboutYouStep()
        case .goal:          GoalStep()
        case .sleep:         SleepStep()
        case .food:          FoodTourStep()
        case .ai:            AIStep()
        case .notifications: NotificationsStep()
        case .lockScreen:    LockScreenStep()
        case .done:          DoneStep()
        }
    }
}

// MARK: - Shared layout

/// Icon, title and explanation on top; content in the middle; buttons pinned at the bottom.
private struct StepPage<Content: View>: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    var primaryTitle: LocalizedStringKey = "Continue"
    var primaryEnabled = true
    var showsSkip = false
    var primaryAction: (() -> Void)? = nil
    @ViewBuilder let content: Content

    private var coordinator: OnboardingCoordinator { .shared }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 14) {
                        Image(systemName: icon)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(tint)
                            .frame(width: 60, height: 60)
                            .background(tint.opacity(0.13), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                        Text(title)
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(subtitle)
                            .font(.body)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    content
                }
                .padding(.horizontal, 22)
                .padding(.top, 18)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            VStack(spacing: 6) {
                Button {
                    (primaryAction ?? { coordinator.next() })()
                } label: {
                    Text(primaryTitle)
                }
                .buttonStyle(.primary)
                .disabled(!primaryEnabled)

                if showsSkip {
                    Button("Skip for now") { coordinator.next() }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.vertical, 8)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 10)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(detail).font(.footnote).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ChoiceCard: View {
    let title: String
    let detail: String
    let icon: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(selected ? Theme.onAction : Theme.textSecondary)
                    .frame(width: 40, height: 40)
                    .background(selected ? Theme.actionFill : Theme.surfaceRaised, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title).font(.headline).foregroundStyle(Theme.textPrimary)
                    Text(verbatim: detail).font(.footnote).foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(selected ? Theme.accent : Theme.separator)
            }
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(selected ? Theme.accent : .clear, lineWidth: 1.5))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

// MARK: - 1 Welcome

private struct WelcomeStep: View {
    @State private var language = AppLanguage.current
    @State private var confirmSwitch = false

    var body: some View {
        StepPage(icon: "waveform.path.ecg", tint: Theme.accent,
                 title: "Your AI health analyst",
                 subtitle: "Trace sits on top of your Apple Watch and explains what actually drives your recovery and performance, not just what your numbers were.",
                 primaryAction: {
                     if language != AppLanguage.current { confirmSwitch = true } else { OnboardingCoordinator.shared.next() }
                 }) {
            VStack(alignment: .leading, spacing: 16) {
                InfoRow(icon: "link", tint: Theme.good, title: "Connects it all",
                        detail: "Food, training, sleep and biometrics read together, so you see what moves your recovery.")
                InfoRow(icon: "checkmark.seal.fill", tint: Theme.accent, title: "Evidence, not guesses",
                        detail: "Every finding shows how many days stand behind it, measured against your own normal.")
                InfoRow(icon: "applewatch", tint: Theme.activity, title: "Built on your Watch",
                        detail: "No new tracker to buy or wear. It explains the data you already collect.")
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                Text("Language").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 10) {
                    ForEach(AppLanguage.allCases) { lang in
                        Button {
                            language = lang
                        } label: {
                            HStack(spacing: 8) {
                                Text(verbatim: lang.flag)
                                Text(verbatim: lang.nativeName).font(.subheadline.weight(.semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .foregroundStyle(language == lang ? .white : Theme.textPrimary)
                            .background(language == lang ? Theme.accent : Theme.surface,
                                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .alert("Switch language?", isPresented: $confirmSwitch) {
            Button("Cancel", role: .cancel) { language = AppLanguage.current }
            Button("Close app") {
                OnboardingCoordinator.shared.saveForRelaunch()
                language.apply()
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
            }
        } message: {
            Text("Trace will close to switch language. Open it again and setup continues where you left off.")
        }
    }
}

// MARK: - Devices

private struct DevicesStep: View {
    @State private var kind = DeviceProfile.isSet ? DeviceProfile.kind : .appleWatch
    @State private var heart = DeviceProfile.tracksHeart
    @State private var sleep = DeviceProfile.tracksSleep

    var body: some View {
        StepPage(icon: "applewatch.side.right", tint: Theme.accent,
                 title: "What do you wear?",
                 subtitle: "Trace reads heart rate and sleep from a watch or ring through Apple Health. Tell it what you have, and it only shows what your devices can measure.",
                 primaryAction: {
                     DeviceProfile.save(kind: kind, heart: heart, sleep: sleep)
                     OnboardingCoordinator.shared.next()
                 }) {
            DeviceChoiceView(kind: $kind, heart: $heart, sleep: $sleep)
        }
    }
}

// MARK: - 2 Apple Health

private struct HealthStep: View {
    @State private var connected = false
    @State private var working = false

    var body: some View {
        StepPage(icon: "heart.text.square.fill", tint: Theme.bad,
                 title: "Connect Apple Health",
                 subtitle: "Trace works from the data your Watch, scale and food apps already put in Health.",
                 primaryTitle: connected ? "Continue" : "Connect Apple Health",
                 primaryEnabled: !working,
                 primaryAction: {
                     if connected { OnboardingCoordinator.shared.next() } else { Task { await connect() } }
                 }) {
            VStack(alignment: .leading, spacing: 16) {
                InfoRow(icon: "arrow.down.circle.fill", tint: Theme.accent, title: "Reads",
                        detail: "Heart rate, HRV, sleep, steps, energy, workouts, weight and nutrition.")
                InfoRow(icon: "arrow.up.circle.fill", tint: Theme.good, title: "Writes",
                        detail: "Food you log, weigh-ins and workouts you record in the app.")
                InfoRow(icon: "lock.fill", tint: Theme.textSecondary, title: "Stays on your iPhone",
                        detail: "Raw Health data never leaves your device.")
            }
            .padding(16)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if connected {
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.good)
            }
            Text("In the next sheet, tap “Turn On All” and then “Allow”. You can change this any time in Settings → Health.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
        .task {
            let status = try? await HealthKitManager.shared.store.statusForAuthorizationRequest(
                toShare: HealthAccess.shareTypes, read: HealthKitManager.shared.readTypes)
            connected = status == .unnecessary
        }
    }

    private func connect() async {
        working = true
        await HealthAccess.requestAllIfNeeded()
        working = false
        connected = true
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Start pulling history now, so Today has numbers by the end of setup.
        HealthSync.shared.refreshSoon(after: .milliseconds(100))
    }
}

// MARK: - 3 About you

private struct AboutYouStep: View {
    @State private var isFemale: Bool?
    @State private var age = 30
    @State private var heightCm = 175
    @State private var weightTenths = 750
    @State private var hasHealthWeight = false
    @State private var weightEdited = false
    @State private var loaded = false

    var body: some View {
        StepPage(icon: "person.fill", tint: Theme.fat,
                 title: "About you",
                 subtitle: "Used for calorie targets and heart-rate zones. Anything already in Apple Health is filled in.",
                 primaryEnabled: isFemale != nil,
                 primaryAction: save) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    sexButton(String(localized: "Female"), true)
                    sexButton(String(localized: "Male"), false)
                }
                wholeStepper(title: "Age", value: $age, range: 13...100, unit: String(localized: "years"))
                wholeStepper(title: "Height", value: $heightCm, range: 120...230, unit: "cm")
                StepperValueCard(title: "Weight", unit: "kg", tenths: $weightTenths, range: 300...2500, color: Theme.accent,
                                 caption: hasHealthWeight ? String(localized: "Your latest weigh-in from Apple Health") : nil)
                    .onChange(of: weightTenths) { _, _ in if loaded { weightEdited = true } }
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
        .task { await load() }
    }

    private func sexButton(_ label: String, _ value: Bool) -> some View {
        Button {
            isFemale = value
        } label: {
            Text(verbatim: label)
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isFemale == value ? .white : Theme.textPrimary)
                .background(isFemale == value ? Theme.accent : Theme.surface,
                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isFemale)
    }

    private func wholeStepper(title: LocalizedStringKey, value: Binding<Int>, range: ClosedRange<Int>, unit: String) -> some View {
        HStack {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Button { if value.wrappedValue > range.lowerBound { value.wrappedValue -= 1 } } label: {
                Image(systemName: "minus").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.borderless)
            .buttonRepeatBehavior(.enabled)
            Text(verbatim: "\(value.wrappedValue)")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .frame(minWidth: 56)
            Text(verbatim: unit).font(.caption).foregroundStyle(Theme.textTertiary).frame(width: 36, alignment: .leading)
            Button { if value.wrappedValue < range.upperBound { value.wrappedValue += 1 } } label: {
                Image(systemName: "plus").font(.system(size: 15, weight: .bold)).frame(width: 40, height: 40)
                    .background(Theme.accent.opacity(0.12), in: Circle())
            }
            .buttonStyle(.borderless)
            .buttonRepeatBehavior(.enabled)
        }
        .foregroundStyle(Theme.accent)
        .padding(14)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .sensoryFeedback(.selection, trigger: value.wrappedValue)
    }

    private func load() async {
        guard !loaded else { return }
        loaded = true
        let saved = BodyProfile.load()
        let health = await HealthKitManager.shared.bodyProfile()
        isFemale = health.isFemale ?? saved.isFemale
        if let a = health.ageYears ?? saved.ageYears { age = a }
        if let h = health.heightCm ?? saved.heightCm { heightCm = Int(h.rounded()) }
        await BodyLogStore.shared.load(days: 365)
        if let w = BodyLogStore.shared.latestWeight?.value {
            weightTenths = Int((w * 10).rounded())
            hasHealthWeight = true
        }
        // Changes made while loading aren't the user's.
        try? await Task.sleep(for: .milliseconds(50))
        weightEdited = false
    }

    private func save() {
        var profile = BodyProfile.load()
        profile.isFemale = isFemale
        profile.ageYears = age
        profile.heightCm = Double(heightCm)
        profile.save()
        // A weigh-in only if Health has none yet — never overwrite real scale data.
        let weight = Double(weightTenths) / 10
        let latest = BodyLogStore.shared.latestWeight?.value
        if weightEdited, latest == nil || abs((latest ?? 0) - weight) >= 0.05 {
            Task { try? await BodyLogStore.shared.save(weightKg: weight, bodyFatPercent: nil, at: Date()) }
        }
        OnboardingCoordinator.shared.next()
    }
}

// MARK: - 4 Goal

private struct GoalStep: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var days: [DailyMetrics]
    @State private var goal = GoalSettings.load()

    private var preview: (kcal: Double, protein: Double, isEstimate: Bool)? {
        let profile = BodyProfile.load()
        let weight = days.compactMap(\.bodyMassKg).first ?? BodyLogStore.shared.latestWeight?.value
        if let maintenance = EnergyModel.maintenance(from: days, profile: profile) {
            let t = NutritionTargets(maintenance: maintenance, bodyMassKg: weight, goal: goal)
            return (t.calories, t.proteinGrams, false)
        }
        // No Watch history yet: resting energy × a light-activity factor.
        guard let resting = MaintenanceModel.mifflinStJeor(profile: profile, bodyMassKg: weight) else { return nil }
        let kcal = max(resting * 1.45 + goal.signedDailyAdjustment, resting)
        return (kcal, (weight ?? 70) * goal.phase.proteinGramsPerKg, true)
    }

    var body: some View {
        StepPage(icon: "target", tint: Theme.good,
                 title: "What's your goal?",
                 subtitle: "Sets your daily calories and protein. Targets keep adjusting to how your body responds.",
                 primaryAction: {
                     goal.save()
                     OnboardingCoordinator.shared.next()
                 }) {
            VStack(spacing: 10) {
                ForEach(GoalSettings.Phase.allCases) { phase in
                    ChoiceCard(title: phase.label, detail: detail(phase), icon: icon(phase), selected: goal.phase == phase) {
                        goal.phase = phase
                        goal.rateKgPerWeek = phase.defaultRate
                    }
                }
            }

            if goal.phase != .maintain {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Pace").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        ForEach(goal.phase.rateOptions, id: \.self) { rate in
                            Button {
                                goal.rateKgPerWeek = rate
                            } label: {
                                Text(verbatim: "\(rate.formatted(.number.precision(.fractionLength(0...2)))) kg/wk")
                                    .font(.subheadline.weight(.semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 12)
                                    .foregroundStyle(goal.rateKgPerWeek == rate ? .white : Theme.textPrimary)
                                    .background(goal.rateKgPerWeek == rate ? Theme.accent : Theme.surface,
                                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let preview {
                HStack(spacing: 0) {
                    previewStat(Int(preview.kcal.rounded()).formatted(), String(localized: "kcal a day"), Theme.accent)
                    Divider().frame(height: 36)
                    previewStat("\(Int(preview.protein.rounded())) g", String(localized: "protein"), Theme.protein)
                }
                .padding(.vertical, 14)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .animation(.snappy, value: preview.kcal)
                if preview.isEstimate {
                    Text("A starting estimate. After about a week of Apple Watch wear it's replaced by what you actually burn.")
                        .font(.footnote)
                        .foregroundStyle(Theme.textTertiary)
                }
            }
        }
    }

    private func previewStat(_ value: String, _ label: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(verbatim: value)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .contentTransition(.numericText())
            Text(verbatim: label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func detail(_ phase: GoalSettings.Phase) -> String {
        switch phase {
        case .cut:      String(localized: "A calorie deficit with high protein to keep muscle.")
        case .maintain: String(localized: "Hold your weight while you train.")
        case .bulk:     String(localized: "A small surplus to gain muscle with little fat.")
        }
    }

    private func icon(_ phase: GoalSettings.Phase) -> String {
        switch phase {
        case .cut:      "arrow.down.right"
        case .maintain: "equal"
        case .bulk:     "arrow.up.right"
        }
    }
}

// MARK: - 5 Sleep

private struct SleepStep: View {
    @State private var wake: Date = {
        let t = BedtimeAlarm.wakeTime
        return Calendar.current.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 0, second: 0, of: Date()) ?? Date()
    }()
    @State private var sleepGoal = SleepPlanner.goal

    var body: some View {
        StepPage(icon: "moon.stars.fill", tint: Theme.accentDeep,
                 title: "Your sleep",
                 subtitle: "Trace works out how much sleep you need each night and when to be in bed. It never sets an alarm on its own — you can optionally have a real one follow your wake time, later in Settings.",
                 primaryAction: {
                     BedtimeAlarm.wakeTime = Calendar.current.dateComponents([.hour, .minute], from: wake)
                     SleepPlanner.useTypicalWake = true
                     SleepPlanner.goal = sleepGoal
                     OnboardingCoordinator.shared.next()
                 }) {
            VStack(alignment: .leading, spacing: 8) {
                Text("I usually wake up at").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                DatePicker("", selection: $wake, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .frame(maxWidth: .infinity)
                    .frame(height: 140)
                    .clipped()
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                Text("Once your Watch has a week of mornings, your real wake time is used. You can set a one-off time for any night.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textTertiary)
            }

            VStack(spacing: 10) {
                ForEach(SleepPlanner.Goal.allCases) { goal in
                    ChoiceCard(title: goal.label, detail: goal.detail,
                               icon: goal == .peak ? "sparkles" : goal == .perform ? "bolt.fill" : "tortoise.fill",
                               selected: sleepGoal == goal) { sleepGoal = goal }
                }
            }
        }
    }
}

// MARK: - 6 Food tour

private struct FoodTourStep: View {
    var body: some View {
        StepPage(icon: "fork.knife", tint: Theme.protein,
                 title: "Logging food",
                 subtitle: "Tap the fork at the top of Today. Everything you log is saved to Apple Health.") {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                tile("magnifyingglass", "Search", "Swiss database and products")
                tile("barcode.viewfinder", "Barcode", "Scan the pack")
                tile("text.bubble", "Describe", "Type it, AI estimates")
                tile("square.and.pencil", "Manual", "Enter macros yourself")
                tile("camera.viewfinder", "Photo", "Recognised on your phone")
                tile("book.closed", "Recipes", "Build once, log in a tap")
            }
            InfoRow(icon: "cart.fill", tint: Theme.accent, title: "Add several at once",
                    detail: "Foods collect into one meal and are logged together.")
            InfoRow(icon: "exclamationmark.triangle.fill", tint: Theme.warn, title: "Using another food app too?",
                    detail: "Log each meal in only one app — otherwise it counts twice in Apple Health.")
        }
    }

    private func tile(_ icon: String, _ title: LocalizedStringKey, _ detail: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.caption2).foregroundStyle(Theme.textSecondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(12)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

// MARK: - 7 AI

private struct AIStep: View {
    @State private var key = KeychainStore.get(APIKeyName.gemini) ?? ""

    private var trimmed: String { key.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        StepPage(icon: "sparkles", tint: GeminiStyle.blue,
                 title: "AI features",
                 subtitle: OnDeviceAI.isAvailable
                    ? "Your iPhone has Apple Intelligence, so most AI features already work on the phone with no key. Add a Gemini key for sharper photo estimates."
                    : "Optional. Gemini describes meals from text or photos, suggests recipes and writes your weekly summary.",
                 primaryTitle: trimmed.isEmpty ? "Continue without AI" : "Save key",
                 primaryAction: {
                     if !trimmed.isEmpty { KeychainStore.set(trimmed, for: APIKeyName.gemini) }
                     OnboardingCoordinator.shared.next()
                 }) {
            HStack(spacing: 8) {
                Text("Powered by").font(.subheadline).foregroundStyle(GeminiStyle.silver)
                GeminiMark(size: 20)
                GeminiWordmark(size: 18)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Your Gemini API key").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textSecondary)
                SecureField("AIza…", text: $key)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(14)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                    Label("Get a free key at aistudio.google.com", systemImage: "arrow.up.right.square")
                        .font(.footnote.weight(.medium))
                }
            }

            Text("The key is stored in your iPhone's Keychain. Only summaries and what you choose to describe or photograph are sent — never raw Health data. Everything else in the app works without it.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - 8 Notifications

private struct NotificationsStep: View {
    @State private var briefing = true
    @State private var weighIn = false
    @State private var working = false

    var body: some View {
        StepPage(icon: "bell.badge.fill", tint: Theme.warn,
                 title: "Notifications",
                 subtitle: "Just two, both optional. No alarms and no wind-down reminders.",
                 primaryEnabled: !working,
                 showsSkip: true,
                 primaryAction: { Task { await apply() } }) {
            VStack(spacing: 0) {
                toggleRow("sun.max.fill", Theme.warn, "Morning recovery read",
                          "Your score and what it means, once last night's sleep has synced.", $briefing)
                Divider().padding(.leading, 56)
                toggleRow("scalemass.fill", Theme.accent, "Weigh-in reminder",
                          "A nudge each morning to step on the scale before breakfast.", $weighIn)
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func toggleRow(_ icon: String, _ tint: Color, _ title: LocalizedStringKey, _ detail: LocalizedStringKey,
                           _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 32, height: 32)
                    .background(tint.opacity(0.12), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .tint(Theme.accent)
        .padding(14)
    }

    private func apply() async {
        working = true
        defer { working = false }
        if briefing || weighIn {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
        BriefingService.isEnabled = briefing
        BriefingService.reschedule()
        BodyLogStore.reminderEnabled = weighIn
        _ = await BodyLogStore.scheduleReminder()
        OnboardingCoordinator.shared.next()
    }
}

// MARK: - 9 Lock Screen

private struct LockScreenStep: View {
    @State private var liveActivity = MacroLiveActivity.isEnabled
    @Query(sort: \DailyMetrics.date, order: .reverse) private var days: [DailyMetrics]

    var body: some View {
        StepPage(icon: "lock.iphone", tint: Theme.accent,
                 title: "On your Lock Screen",
                 subtitle: "See what you've eaten and when to go to bed without opening the app.",
                 showsSkip: true,
                 primaryAction: {
                     MacroLiveActivity.isEnabled = liveActivity
                     let days = days
                     Task { await MacroLiveActivity.sync(days: days) }
                     OnboardingCoordinator.shared.next()
                 }) {
            // A look-alike of the rectangular widget on a wallpaper-ish backdrop.
            ZStack {
                LinearGradient(colors: [Color(red: 0.62, green: 0.82, blue: 0.86), Color(red: 0.30, green: 0.48, blue: 0.85)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                VStack(spacing: 10) {
                    Text(Date(), format: .dateTime.hour().minute())
                        .font(.system(size: 54, weight: .semibold, design: .rounded))
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(1640, format: .number).font(.system(size: 20, weight: .semibold, design: .rounded))
                                .lineLimit(1).fixedSize()
                            Text("kcal eaten").font(.system(size: 10, weight: .medium)).opacity(0.75).lineLimit(1)
                            Spacer()
                            Image(systemName: "moon.fill").font(.system(size: 9))
                            Text(verbatim: "22:45").font(.system(size: 13, weight: .semibold, design: .rounded))
                        }
                        HStack(spacing: 8) {
                            mini("P", 112, 0.7); mini("C", 180, 0.62); mini("F", 52, 0.6)
                        }
                    }
                    .frame(width: 210)
                    .padding(10)
                    .background(.white.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .foregroundStyle(.white)
                .padding(.vertical, 24)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            VStack(alignment: .leading, spacing: 10) {
                InfoRow(icon: "1.circle.fill", tint: Theme.accent, title: "Touch and hold the Lock Screen",
                        detail: "Then tap Customise → Lock Screen.")
                InfoRow(icon: "2.circle.fill", tint: Theme.accent, title: "Tap the widget area under the time",
                        detail: "Choose Trace → Today or Bedtime.")
            }

            Toggle(isOn: $liveActivity) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Live Activity").font(.subheadline.weight(.semibold))
                    Text("Calories, macros and bedtime on the Lock Screen and Dynamic Island, updated as you log.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
            }
            .tint(Theme.accent)
            .padding(14)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func mini(_ letter: String, _ value: Int, _ fill: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(letter) \(value)").font(.system(size: 10, weight: .semibold, design: .rounded))
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.3))
                    Capsule().fill(.white).frame(width: geo.size.width * fill)
                }
            }
            .frame(height: 2.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - 10 Done

private struct DoneStep: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var days: [DailyMetrics]

    var body: some View {
        let goal = GoalSettings.load()
        let profile = BodyProfile.load()
        let weight = days.compactMap(\.bodyMassKg).first ?? BodyLogStore.shared.latestWeight?.value
        let measured = EnergyModel.maintenance(from: days, profile: profile)
            .map { NutritionTargets(maintenance: $0, bodyMassKg: weight, goal: goal) }
        // Before a week of Watch data: the same starting estimate as the goal step.
        let estimated: (kcal: Double, protein: Double)? = measured == nil
            ? MaintenanceModel.mifflinStJeor(profile: profile, bodyMassKg: weight).map {
                (max($0 * 1.45 + goal.signedDailyAdjustment, $0), (weight ?? 70) * goal.phase.proteinGramsPerKg) }
            : nil
        let target = measured.map { ($0.calories, $0.proteinGrams) } ?? estimated
        // A bedtime only means something once a few nights are recorded.
        let nights = days.prefix(28).filter { ($0.sleepAsleepHours ?? 0) > 2 }.count
        let plan = nights >= 3 ? SleepPlanner.plan(days: Array(days)) : nil

        return StepPage(icon: "checkmark.seal.fill", tint: Theme.good,
                        title: "You're all set",
                        subtitle: "Numbers fill in as Apple Health syncs. The recovery score appears after about a week of Watch wear.",
                        primaryTitle: "Start",
                        primaryAction: {
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            OnboardingCoordinator.shared.finish()
                        }) {
            VStack(spacing: 0) {
                summaryRow("target", Theme.good, String(localized: "Goal"),
                           goal.phase == .maintain ? goal.phase.label
                           : "\(goal.phase.label) · \(goal.rateKgPerWeek.formatted(.number.precision(.fractionLength(0...2)))) kg/wk")
                if let target {
                    Divider().padding(.leading, 52)
                    summaryRow("flame.fill", Theme.accent, String(localized: "Daily target"),
                               "\(Int(target.0.rounded()).formatted()) kcal · \(Int(target.1.rounded())) g protein")
                }
                if let plan {
                    Divider().padding(.leading, 52)
                    summaryRow("moon.fill", Theme.accentDeep, String(localized: "Tonight"),
                               String(localized: "In bed by \(plan.windowStart.formatted(date: .omitted, time: .shortened))"))
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            Text("You can change any of this in Settings, or run setup again from there.")
                .font(.footnote)
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private func summaryRow(_ icon: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12), in: Circle())
            Text(verbatim: label).font(.subheadline).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(verbatim: value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(14)
    }
}
