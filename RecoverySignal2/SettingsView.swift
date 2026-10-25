//
//  SettingsView.swift
//  RecoverySignal2
//
//  Settings as the app's own hub rather than a system list: a header with the
//  current state, then grouped cards that open one page per topic (goal,
//  training, appearance, notifications, AI, privacy, language, about).
//

import SwiftUI
import SwiftData

// MARK: - Preferences

/// Small app-wide preferences that more than one screen reads.
enum AppPrefs {
    static let appearanceKey = "pref.appearance"
    static let animateScoreKey = "pref.animateScore"
    static let revealHapticsKey = "pref.revealHaptics"
    static let aiEnabledKey = "ai.enabled"
    static let onDeviceFirstKey = "ai.onDeviceFirst"
    static let launchAnimationKey = "pref.launchAnimation"

    /// 0 follows the iPhone, 1 is light, 2 is dark.
    static func scheme(_ raw: Int) -> ColorScheme? {
        switch raw {
        case 1: .light
        case 2: .dark
        default: nil
        }
    }

    static var animateScore: Bool { UserDefaults.standard.object(forKey: animateScoreKey) as? Bool ?? true }
    static var revealHaptics: Bool { UserDefaults.standard.object(forKey: revealHapticsKey) as? Bool ?? true }
    static var aiEnabled: Bool { UserDefaults.standard.object(forKey: aiEnabledKey) as? Bool ?? true }
    /// Try Apple Intelligence on the phone before sending anything to Gemini.
    static var onDeviceFirst: Bool { UserDefaults.standard.object(forKey: onDeviceFirstKey) as? Bool ?? true }
    /// Play the logo intro when the app starts cold.
    static var launchAnimation: Bool { UserDefaults.standard.object(forKey: launchAnimationKey) as? Bool ?? false }
}

// MARK: - Hub

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \DailyMetrics.date, order: .forward) private var days: [DailyMetrics]
    @AppStorage(AppPrefs.aiEnabledKey) private var aiEnabled = true
    @AppStorage(AppPrefs.appearanceKey) private var appearance = 2
    @AppStorage(CoachSettings.key) private var coachEnabled = true
    /// Redraws the devices row when it changes.
    @AppStorage(DeviceProfile.kindKey) private var deviceKind = ""
    @State private var goal = GoalSettings.load()
    @State private var language = AppLanguage.current
    @State private var showsLayout = false
    @AppStorage(TodayLayout.stampKey) private var layoutRaw = ""
    @State private var apiKeyRefresh = 0

    #if targetEnvironment(simulator)
    @Environment(\.modelContext) private var context
    @State private var isSeeding = false
    @State private var seedError: String?
    #endif

    private var hasKey: Bool { let _ = apiKeyRefresh; return !(KeychainStore.get(APIKeyName.gemini) ?? "").isEmpty }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    header

                    group("Personal") {
                        navRow(icon: "target", tint: Theme.accent, title: "Goal & nutrition", subtitle: goalSummary) {
                            GoalSettingsPage()
                        }
                        navRow(icon: "applewatch", tint: Theme.bad, title: "Your devices", subtitle: DeviceProfile.summary) {
                            DevicesSettingsPage()
                        }
                        navRow(icon: "dumbbell.fill", tint: Theme.accentDeep, title: "Training",
                               subtitle: coachEnabled ? "Progression coach on" : "Progression coach off") {
                            TrainingSettingsPage()
                        }
                    }

                    group("Experience") {
                        navRow(icon: "paintpalette.fill", tint: Theme.fat, title: "Appearance & feedback",
                               subtitle: ["Match iPhone", "Light", "Dark"][min(max(appearance, 0), 2)]) {
                            AppearanceSettingsPage()
                        }
                        Button { showsLayout = true } label: {
                            rowContent(icon: "rectangle.3.group.fill", tint: Theme.accent, title: "Today layout",
                                       subtitle: "Reorder and hide sections", chevron: true)
                        }
                        .buttonStyle(.plain)
                        navRow(icon: "bell.badge.fill", tint: Theme.warn, title: "Notifications & Lock Screen",
                               subtitle: "Briefing, macros on the Lock Screen") {
                            NotificationSettingsPage()
                        }
                        navRow(icon: "globe", tint: Theme.mint, title: "Language", subtitle: language.nativeName) {
                            LanguageSettingsPage()
                        }
                    }

                    group("Intelligence & privacy") {
                        navRow(icon: "sparkles", tint: GeminiStyle.blue, title: "AI assistant",
                               subtitle: !aiEnabled ? "Turned off" : (hasKey ? (OnDeviceAI.isAvailable ? "Apple Intelligence + Gemini" : "Gemini connected")
                                                     : (OnDeviceAI.isAvailable ? "Apple Intelligence, on your iPhone" : "Add your Gemini key"))) {
                            AISettingsPage()
                        }
                        navRow(icon: "lock.shield.fill", tint: Theme.good, title: "Privacy & data",
                               subtitle: "What stays on your iPhone") {
                            PrivacySettingsPage()
                        }
                    }

                    group("Your data") {
                        navRow(icon: "text.bubble.fill", tint: Theme.good, title: "Log from ChatGPT",
                               subtitle: "Paste macros or share a reply to Trace") {
                            ChatGPTGuidePage()
                        }
                        navRow(icon: "square.and.arrow.up.fill", tint: Theme.accentDeep, title: "Export your data",
                               subtitle: "Food log, workouts and daily metrics as CSV") {
                            DataExportPage()
                        }
                    }

                    group("Diagnostics") {
                        navRow(icon: "waveform.path", tint: Theme.accent, title: "Sleep data availability",
                               subtitle: "Local overnight delivery experiment") {
                            SleepAvailabilityView()
                        }
                    }

                    group("About") {
                        navRow(icon: "info.circle.fill", tint: Theme.textTertiary, title: "About Trace",
                               subtitle: "Version, credits, setup") {
                            AboutSettingsPage()
                        }
                    }

                    #if targetEnvironment(simulator)
                    group("Developer") {
                        Button {
                            Task {
                                isSeeding = true
                                seedError = nil
                                do {
                                    try await SampleDataSeeder.seed(context: context)
                                    try await MetricsAggregator(context: context).refresh(days: SampleDataSeeder.dayCount)
                                    SampleDataSeeder.attachReadiness(context: context)
                                } catch {
                                    seedError = error.localizedDescription
                                }
                                isSeeding = false
                            }
                        } label: {
                            rowContent(icon: "testtube.2", tint: Theme.textTertiary, title: "Seed sample data",
                                       subtitle: seedError ?? "Simulator only", chevron: false, busy: isSeeding)
                        }
                        .buttonStyle(.plain)
                        .disabled(isSeeding)
                    }
                    #endif
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                goal = GoalSettings.load()
                language = AppLanguage.current
                apiKeyRefresh += 1
            }
            .sheet(isPresented: $showsLayout) {
                TodayLayoutEditor { layoutRaw = TodayLayout.stamp() }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                BrandMark(line: Theme.actionFill, zoom: 1.1)
                    .frame(width: 52, height: 52)
                    .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    TraceWordmark(size: 26, color: Theme.textPrimary)
                    Text("Train. Fuel. Recover.")
                        .font(.subheadline).foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { profileChips }
                VStack(alignment: .leading, spacing: 8) { profileChips }
            }
        }
        .card(padding: 20)
    }

    @ViewBuilder private var profileChips: some View {
        chip(goalSummary, "target")
        chip(!aiEnabled ? "AI off" : (hasKey ? "Gemini on" : (OnDeviceAI.isAvailable ? "On-device AI" : "AI not set up")), "sparkles")
    }

    private func chip(_ text: String, _ symbol: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
            Text(LocalizedStringKey(text)).font(.system(size: 12, weight: .semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .foregroundStyle(Theme.textSecondary)
        .background(Theme.surfaceRaised, in: Capsule())
    }

    private var goalSummary: String {
        goal.phase == .maintain
            ? String(localized: "Maintain")
            : "\(goal.phase.label) · \(goal.rateKgPerWeek.formatted(.number.precision(.fractionLength(0...2)))) kg/week"
    }

    // MARK: Building blocks

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: String.LocalizationValue(title)).uppercased())
                .font(.eyebrow)
                .tracking(0.7)
                .foregroundStyle(Theme.textTertiary)
                .padding(.leading, 6)
            _VariadicView.Tree(SettingsCardLayout()) { content() }
        }
    }

    private func navRow<Destination: View>(icon: String, tint: Color, title: String, subtitle: String,
                                           @ViewBuilder destination: () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            rowContent(icon: icon, tint: tint, title: title, subtitle: subtitle, chevron: true)
        }
        .buttonStyle(.plain)
    }

    private func rowContent(icon: String, tint: Color, title: String, subtitle: String, chevron: Bool, busy: Bool = false) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(Theme.textSecondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if busy { ProgressView() }
            if chevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }
}

/// Stacks a group's rows in one bordered card with hairlines between them.
private struct SettingsCardLayout: _VariadicView_UnaryViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(children.enumerated()), id: \.offset) { index, child in
                if index > 0 { Divider().overlay(Theme.separator).padding(.leading, 60) }
                child
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

// MARK: - Page kit

/// A settings sub-page: scrolling cards on the app background.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 40)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle(LocalizedStringKey(title))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A bordered card holding rows.
struct SettingsBlock<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) { content }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
    }
}

struct SettingsNote: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(LocalizedStringKey(text))
            .font(.footnote)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, 6)
    }
}

struct SettingsToggle: View {
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                if let subtitle {
                    Text(LocalizedStringKey(subtitle)).font(.caption).foregroundStyle(Theme.textTertiary)
                }
            }
        }
        .tint(Theme.accent)
    }
}

/// A full-width button in the app's accent.
struct SettingsButton: View {
    let title: String
    var symbol: String? = nil
    var role: ButtonRole? = nil
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) {
            HStack(spacing: 8) {
                if let symbol { Image(systemName: symbol) }
                Text(LocalizedStringKey(title))
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(role == .destructive ? Theme.bad : Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background((role == .destructive ? Theme.bad : Theme.accent).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Goal & nutrition

struct GoalSettingsPage: View {
    @State private var goal = GoalSettings.load()
    @State private var customPaceChosen = false

    private static let customPaceTag = -1.0

    private var isCustomPace: Bool {
        customPaceChosen || !goal.phase.rateOptions.contains(goal.rateKgPerWeek)
    }

    private var paceSelection: Binding<Double> {
        Binding(
            get: { isCustomPace ? Self.customPaceTag : goal.rateKgPerWeek },
            set: { newValue in
                if newValue == Self.customPaceTag {
                    customPaceChosen = true
                } else {
                    customPaceChosen = false
                    goal.rateKgPerWeek = newValue
                }
            }
        )
    }

    var body: some View {
        SettingsPage(title: "Goal & nutrition") {
            SettingsBlock {
                Text("Goal").font(.subheadline.weight(.semibold))
                Picker("Goal", selection: $goal.phase) {
                    ForEach(GoalSettings.Phase.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .onChange(of: goal.phase) { _, phase in
                    goal.rateKgPerWeek = phase.defaultRate
                    customPaceChosen = false
                }

                if goal.phase != .maintain {
                    Divider().overlay(Theme.separator)
                    HStack {
                        Text("Pace").font(.subheadline.weight(.semibold))
                        Spacer()
                        Picker("Pace", selection: paceSelection) {
                            ForEach(goal.phase.rateOptions, id: \.self) { rate in
                                Text("\(rate.formatted(.number.precision(.fractionLength(0...2)))) kg / week").tag(rate)
                            }
                            Text("Custom…").tag(Self.customPaceTag)
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                    }
                    if isCustomPace {
                        HStack {
                            Text("Custom pace").foregroundStyle(Theme.textSecondary)
                            Spacer()
                            LiveNumberField("0.30", value: $goal.rateKgPerWeek, fractionDigits: 2)
                                .multilineTextAlignment(.trailing)
                                .monospacedDigit()
                                .frame(width: 70)
                                .onChange(of: goal.rateKgPerWeek) { _, rate in
                                    if rate > goal.phase.maxRate { goal.rateKgPerWeek = goal.phase.maxRate }
                                }
                            Text("kg / week").foregroundStyle(Theme.textTertiary)
                        }
                        Stepper("Adjust by 0.05", value: $goal.rateKgPerWeek, in: 0.05...goal.phase.maxRate, step: 0.05)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            SettingsNote(footer)

            SettingsBlock {
                Text("Dietary notes").font(.subheadline.weight(.semibold))
                TextField("e.g. vegetarian, no nuts", text: $goal.dietaryNotes, axis: .vertical)
                    .padding(12)
                    .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            SettingsNote("Used when the AI suggests meals, so recipes fit how you eat.")
        }
        .onChange(of: goal) { _, newValue in newValue.save() }
    }

    private var footer: String {
        switch goal.phase {
        case .maintain:
            return String(localized: "Calorie rings target your maintenance. Protein \(GoalSettings.Phase.maintain.proteinGramsPerKg.formatted()) g per kg bodyweight.")
        case .cut, .bulk:
            let kcal = Int(abs(goal.signedDailyAdjustment).rounded())
            let direction = goal.phase == .cut ? "below" : "above"
            let caution = goal.rateKgPerWeek > (goal.phase == .cut ? 1.0 : 0.5)
                ? (goal.phase == .cut ? String(localized: " Faster than ~1% of bodyweight a week risks losing muscle.") : String(localized: " Gaining faster than ~0.5 kg a week is mostly fat."))
                : ""
            return String(localized: "Rings target about \(kcal) kcal/day \(direction) maintenance, with protein at \(goal.phase.proteinGramsPerKg.formatted()) g/kg. Targets never drop below what your body burns at rest.\(caution)")
        }
    }
}

// MARK: - Training

struct TrainingSettingsPage: View {
    @AppStorage(CoachSettings.key) private var coachEnabled = true

    var body: some View {
        SettingsPage(title: "Training") {
            SettingsBlock {
                SettingsToggle(title: "Progression coach", subtitle: "Weight, rep and set suggestions", isOn: $coachEnabled)
            }
            SettingsNote("Suggests weight, reps and sets for each exercise, plans weekly sets per muscle in training blocks with deloads, asks how muscles felt and flags exercises that hurt your joints. When off, you still log reps in reserve and the app keeps calculating in the background, so it's ready if you turn it on.")
        }
    }
}

// MARK: - Appearance

struct AppearanceSettingsPage: View {
    @AppStorage(AppPrefs.appearanceKey) private var appearance = 2
    @AppStorage(AppPrefs.animateScoreKey) private var animateScore = true
    @AppStorage(AppPrefs.revealHapticsKey) private var revealHaptics = true
    @AppStorage(AppPrefs.launchAnimationKey) private var launchAnimation = false

    var body: some View {
        SettingsPage(title: "Appearance & feedback") {
            SettingsBlock {
                Text("Theme").font(.subheadline.weight(.semibold))
                Picker("Theme", selection: $appearance) {
                    Text("Match iPhone").tag(0)
                    Text("Light").tag(1)
                    Text("Dark").tag(2)
                }
                .pickerStyle(.segmented)
            }
            SettingsNote("Match iPhone switches with your system light and dark setting.")

            SettingsBlock {
                SettingsToggle(title: "Launch animation",
                               subtitle: "The logo draws itself when Trace starts. Tap it to skip.", isOn: $launchAnimation)
                Divider().overlay(Theme.separator)
                SettingsToggle(title: "Animate the recovery score",
                               subtitle: "The ring counts up the first time you open the app each day", isOn: $animateScore)
                Divider().overlay(Theme.separator)
                SettingsToggle(title: "Haptics during the reveal",
                               subtitle: "A rumble that follows the ring, then a tap when it lands", isOn: $revealHaptics)
                    .disabled(!animateScore)
                    .opacity(animateScore ? 1 : 0.5)
            }
            SettingsNote("Respects the iPhone's System Haptics setting and Reduce Motion.")
        }
    }
}

// MARK: - Notifications & Lock Screen

struct NotificationSettingsPage: View {
    @Query(sort: \DailyMetrics.date, order: .forward) private var days: [DailyMetrics]
    @State private var liveActivityEnabled = MacroLiveActivity.isEnabled
    @State private var briefingEnabled = BriefingService.isEnabled
    @State private var briefingTime: Date = {
        let t = BriefingService.time
        return Calendar.current.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 30, second: 0, of: Date()) ?? Date()
    }()

    var body: some View {
        SettingsPage(title: "Notifications & Lock Screen") {
            SettingsBlock {
                SettingsToggle(title: "Morning briefing", subtitle: "Your recovery score and a one-line read", isOn: $briefingEnabled)
                    .onChange(of: briefingEnabled) { _, enabled in
                        Task {
                            if enabled, await !BriefingService.requestPermission() {
                                briefingEnabled = false
                                return
                            }
                            BriefingService.isEnabled = enabled
                            BriefingService.reschedule()
                        }
                    }
                if briefingEnabled {
                    Divider().overlay(Theme.separator)
                    DatePicker("Not before", selection: $briefingTime, displayedComponents: .hourAndMinute)
                        .font(.subheadline.weight(.semibold))
                        .onChange(of: briefingTime) { _, time in
                            BriefingService.time = Calendar.current.dateComponents([.hour, .minute], from: time)
                            BriefingService.reschedule()
                        }
                }
            }
            SettingsNote("Sent once last night's sleep and HRV have synced, and not before this time.")

            SettingsBlock {
                SettingsToggle(title: "Macros on the Lock Screen", subtitle: "Calories, macros and tonight's bedtime", isOn: $liveActivityEnabled)
                    .onChange(of: liveActivityEnabled) { _, enabled in
                        MacroLiveActivity.isEnabled = enabled
                        Task { await MacroLiveActivity.sync(days: days) }
                    }
                if liveActivityEnabled && !MacroLiveActivity.systemAllowsActivities {
                    Label("Live Activities are switched off for this app in the iPhone's Settings.", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.warn)
                }
            }
            SettingsNote("Also appears in the Dynamic Island and updates whenever you log food. For a permanent version, add the Today or Bedtime widget to your Lock Screen.")
        }
    }
}

// MARK: - Language

struct LanguageSettingsPage: View {
    @State private var language = AppLanguage.current
    @State private var pending: AppLanguage?

    var body: some View {
        SettingsPage(title: "Language") {
            VStack(spacing: 0) {
                ForEach(Array(AppLanguage.allCases.enumerated()), id: \.element.id) { index, lang in
                    if index > 0 { Divider().overlay(Theme.separator) }
                    Button {
                        if lang != language { pending = lang }
                    } label: {
                        HStack(spacing: 12) {
                            Text(verbatim: lang.flag).font(.system(size: 22))
                            Text(verbatim: lang.nativeName).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if lang == language {
                                Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))

            SettingsNote("Changes the language of the whole app, including AI replies. Exercise names and instructions from the exercise library stay in English.")
        }
        .alert("Switch language?", isPresented: Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })) {
            Button("Cancel", role: .cancel) { pending = nil }
            Button("Close app") {
                guard let new = pending else { return }
                new.apply()
                language = new
                // iOS only reads the language at launch; the app reopens in the new one.
                UIApplication.shared.perform(#selector(NSXPCConnection.suspend))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) }
            }
        } message: {
            Text("Trace will close to switch language. Open it again from your Home Screen.")
        }
    }
}

// MARK: - AI

struct AISettingsPage: View {
    @AppStorage(AppPrefs.aiEnabledKey) private var aiEnabled = true
    @AppStorage(AppPrefs.onDeviceFirstKey) private var onDeviceFirst = true
    @State private var apiKey: String = KeychainStore.get(APIKeyName.gemini) ?? ""
    @State private var saved = false
    @State private var showsGuide = false

    private var trimmed: String { apiKey.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var hasKey: Bool { !(KeychainStore.get(APIKeyName.gemini) ?? "").isEmpty }

    var body: some View {
        SettingsPage(title: "AI assistant") {
            SettingsBlock {
                SettingsToggle(title: "Use AI features",
                               subtitle: "Meal ideas, meal estimates, recipe calculator, workout import, weekly narrative", isOn: $aiEnabled)
            }
            SettingsNote("Turn this off and no AI runs at all and nothing is sent to Google. All the scoring, trends and analysis run on your iPhone either way.")

            SettingsBlock {
                HStack(alignment: .top) {
                    Text("Apple Intelligence").font(.subheadline.weight(.semibold))
                    Spacer(minLength: 16)
                    Text(OnDeviceAI.statusText)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.trailing)
                }
                Divider().overlay(Theme.separator)
                SettingsToggle(title: "Use it first",
                               subtitle: "Runs on your iPhone: private, free, works offline. On iOS 27 bigger requests and photos can use Apple's private cloud. Gemini steps in if neither can.",
                               isOn: $onDeviceFirst)
                    .disabled(!OnDeviceAI.isAvailable)
                    .opacity(OnDeviceAI.isAvailable ? 1 : 0.5)
            }
            SettingsNote("Apple Intelligence handles the weekly narrative, meal ideas, meal estimates, the recipe calculator, workout import and the performance explanation. Before iOS 27 it can't look at photos or screenshots, so those go to Gemini if you've added a key; without one, the phone reads them locally, which is less exact. Apple's private cloud is Apple's servers, not your phone, with Apple's privacy protections.")

            SettingsBlock {
                HStack {
                    Text("Status").font(.subheadline.weight(.semibold))
                    Spacer()
                    Circle().fill(!aiEnabled ? Theme.textTertiary : (hasKey ? Theme.good : Theme.warn)).frame(width: 7, height: 7)
                    Text(!aiEnabled ? "Off" : (hasKey ? "Connected" : (OnDeviceAI.isAvailable ? "Optional" : "No key added")))
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Divider().overlay(Theme.separator)
                SecureField("Paste your key (starts with AIza)", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(12)
                    .background(Theme.track.opacity(0.6), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .onChange(of: apiKey) { _, _ in saved = false }
                SettingsButton(title: saved ? "Saved" : "Save key", symbol: saved ? "checkmark.circle.fill" : nil) {
                    KeychainStore.set(trimmed, for: APIKeyName.gemini)
                    saved = true
                }
                .disabled(trimmed.isEmpty)
                .opacity(trimmed.isEmpty ? 0.5 : 1)
                Button { showsGuide = true } label: {
                    Label("How to get a free key", systemImage: "questionmark.circle")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentDeep)
                }
                .buttonStyle(.plain)
            }
            SettingsNote("Stored in your iPhone's Keychain. Only aggregated stats, remaining macros and your dietary notes are sent, never raw Health samples.")

        }
        .sheet(isPresented: $showsGuide) {
            GeminiKeyGuide().presentationDetents([.large])
        }
    }
}

// MARK: - Privacy & data

struct PrivacySettingsPage: View {
    @Environment(\.modelContext) private var context
    @State private var isRefreshing = false
    @State private var confirmingKeyRemoval = false

    var body: some View {
        SettingsPage(title: "Privacy & data") {
            SettingsBlock {
                point("iphone", Theme.good, "Stays on your iPhone",
                      "Your Health samples, workouts, food log, weight, scores and every calculation. Nothing is uploaded to a Trace server, because there isn't one.")
                Divider().overlay(Theme.separator)
                point("icloud.fill", Theme.accent, "Sent to Apple's private cloud, only on iOS 27 and only for big requests",
                      "When a request is too large for the on-device model, Apple Intelligence can run it on Apple's Private Cloud Compute servers. Apple says it isn't stored or shared, even with Apple.")
                Divider().overlay(Theme.separator)
                point("sparkles", GeminiStyle.blue, "Sent to Google Gemini, only when Apple Intelligence can't do it",
                      "Aggregated stats for the weekly narrative, remaining macros and dietary notes for meal ideas, and photos or text you choose for meal estimates.")
                Divider().overlay(Theme.separator)
                point("heart.text.square.fill", Theme.protein, "Written to Apple Health",
                      "Only the workouts you record and the food, water and caffeine you log in the app.")
            }

            SettingsBlock {
                SettingsButton(title: "Review Health permissions", symbol: "heart.fill") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                SettingsButton(title: isRefreshing ? "Refreshing…" : "Refresh from Health", symbol: "arrow.clockwise") {
                    Task {
                        isRefreshing = true
                        try? await MetricsAggregator(context: context).refresh(days: 60)
                        isRefreshing = false
                    }
                }
                .disabled(isRefreshing)
                SettingsButton(title: "Remove saved Gemini key", symbol: "key.slash", role: .destructive) {
                    confirmingKeyRemoval = true
                }
            }
            SettingsNote("Health permissions are managed in the iPhone's Settings → Health → Data Access & Devices.")
        }
        .confirmationDialog("Remove your Gemini key?", isPresented: $confirmingKeyRemoval, titleVisibility: .visible) {
            Button("Remove key", role: .destructive) { KeychainStore.set("", for: APIKeyName.gemini) }
        } message: {
            Text("AI features stop working until you add a key again.")
        }
    }

    private func point(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title)).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
                Text(LocalizedStringKey(detail)).font(.footnote).foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - About

struct AboutSettingsPage: View {
    var body: some View {
        SettingsPage(title: "About Trace") {
            SettingsBlock {
                HStack {
                    Text("Version").font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(verbatim: "\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"))")
                        .foregroundStyle(Theme.textSecondary)
                }
                SettingsButton(title: "Run setup again", symbol: "sparkles.rectangle.stack") {
                    OnboardingCoordinator.shared.presentFull()
                }
            }

            SettingsBlock {
                Text("What it does").font(.subheadline.weight(.semibold))
                Text("Trace is an AI health analyst for strength athletes. It sits on top of your Apple Watch and connects your food, training, sleep and biometrics to explain what actually drives your recovery and performance, rather than adding another tracker.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("How it works with your data").font(.subheadline.weight(.semibold)).padding(.top, 4)
                Text("Trace reads Watch biomarkers and Yazio nutrition data (synced via Apple Health) to surface trends and plain-language insights. It only writes the workouts you log and the food you log to Health, and nothing leaves your device except the aggregated stats sent to the AI when you use it.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsBlock {
                Text("Data sources").font(.subheadline.weight(.semibold))
                credit("Swiss Food Composition Database", "Federal Food Safety and Veterinary Office (FSVO)")
                credit("USDA FoodData Central", "U.S. Department of Agriculture, public domain")
                credit("Open Food Facts", "Community product database, ODbL licence")
                credit("free-exercise-db", "Exercise library and photos, public domain")
            }

            SettingsNote("Trace gives general wellness information from your own data. It is not a medical device and doesn't diagnose, treat or prevent any condition. Talk to a doctor about health concerns.")
        }
    }

    private func credit(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(LocalizedStringKey(title)).font(.footnote.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(detail)).font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Gemini key guide

/// Step-by-step: how to get a free Gemini API key from Google AI Studio.
struct GeminiKeyGuide: View {
    @Environment(\.dismiss) private var dismiss

    private let steps: [(title: String, detail: String)] = [
        ("Open Google AI Studio", "Go to aistudio.google.com/apikey in Safari, or tap the button below."),
        ("Sign in with Google", "Use any Google account. There's no card needed for the free tier."),
        ("Create an API key", "Tap “Create API key”. If it asks for a project, choose “Create API key in new project”."),
        ("Copy the key", "It's a long text that starts with “AIza”. Tap the copy icon next to it."),
        ("Paste it here", "Come back to Trace, paste it into the key field in Settings, and tap Save key.")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("The AI features (weekly narrative, meal ideas, photo and text meal estimates) run on Google's Gemini. You bring your own free key, so there's no subscription and nothing is shared with anyone but Google.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.system(size: 12, weight: .semibold))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 24, height: 24)
                                    .background(Theme.accent.opacity(0.12), in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(LocalizedStringKey(step.title))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(LocalizedStringKey(step.detail))
                                        .font(.footnote)
                                        .foregroundStyle(Theme.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                    .card(padding: 16)

                    Link(destination: URL(string: "https://aistudio.google.com/apikey")!) {
                        HStack {
                            Image(systemName: "safari")
                            Text("Open Google AI Studio")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }

                    Text("Treat the key like a password. It's stored in your iPhone's Keychain and never leaves the device except to talk to Google. The free tier has daily limits, which are plenty for personal use.")
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(18)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Get a Gemini key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

#Preview {
    SettingsView()
        .modelContainer(for: [DailyMetrics.self, Insight.self, WeeklyNarrative.self], inMemory: true)
}
