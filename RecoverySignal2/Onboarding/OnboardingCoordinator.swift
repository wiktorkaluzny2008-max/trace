//
//  OnboardingCoordinator.swift
//  RecoverySignal2
//
//  Decides which setup steps to show. It doesn't ask "is this a new user?" —
//  it checks what's actually missing, so:
//
//    • a fresh install gets the whole flow;
//    • an existing user only sees steps for things never set up (or for steps
//      added in a later setup version);
//    • Settings → "Run setup again" replays everything.
//
//  Launch waits on it: Health isn't requested behind the user's back while the
//  Health step is still to come.
//

import Foundation
import HealthKit
import UserNotifications
import Observation

enum OnboardingStep: Int, CaseIterable, Identifiable, Codable {
    case welcome, health, aboutYou, goal, sleep, food, ai, notifications, lockScreen, done
    /// Added later, so it sits at the end of the raw values; `flow` puts it in place.
    case devices
    var id: Int { rawValue }

    /// The order setup runs in.
    static let flow: [OnboardingStep] = [.welcome, .devices, .health, .aboutYou, .goal, .sleep, .food, .ai,
                                         .notifications, .lockScreen, .done]

    /// Steps that can be skipped without the app losing its core.
    var isOptional: Bool {
        switch self {
        case .ai, .notifications, .lockScreen: true
        default: false
        }
    }
}

@MainActor
@Observable
final class OnboardingCoordinator {
    static let shared = OnboardingCoordinator()

    /// Bump when a step is added, so existing users see just the new steps.
    static let currentVersion = 2

    private(set) var steps: [OnboardingStep] = []
    var index = 0
    var isPresented = false

    private var decided = false
    private var shouldShow = false
    private var preparing: Task<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    private enum Key {
        static let completedVersion = "onboarding.completedVersion"
        static let resumeSteps = "onboarding.resumeSteps"
        static let resumeIndex = "onboarding.resumeIndex"
        static let sleepSet = "onboarding.sleepSet"
        static let aiAnswered = "onboarding.aiAnswered"
        static let lockScreenSeen = "onboarding.lockScreenSeen"
    }

    private init() {}

    var current: OnboardingStep? { steps.indices.contains(index) ? steps[index] : nil }
    var progress: Double { steps.count > 1 ? Double(index) / Double(steps.count - 1) : 1 }

    // MARK: Deciding

    /// Works out the steps. Safe to call from several places; the work runs once.
    func prepare() async {
        if decided { return }
        if let preparing { return await preparing.value }
        let task = Task { await decide() }
        preparing = task
        await task.value
    }

    /// After the intro: show setup if it has steps.
    func presentIfNeeded() {
        if shouldShow && !isPresented { isPresented = true }
    }

    private func decide() async {
        let defaults = UserDefaults.standard

        #if DEBUG
        // Development only: `-onboardingStep 3` opens the full flow at that step.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-onboardingStep"), i + 1 < args.count, let n = Int(args[i + 1]) {
            steps = OnboardingStep.flow
            index = min(max(n, 0), steps.count - 1)
            decide(show: true)
            return
        }
        #endif

        // Came back from a language switch mid-setup: carry on where we were.
        if let raw = defaults.array(forKey: Key.resumeSteps) as? [Int] {
            steps = raw.compactMap(OnboardingStep.init(rawValue:))
            index = min(defaults.integer(forKey: Key.resumeIndex), max(steps.count - 1, 0))
            defaults.removeObject(forKey: Key.resumeSteps)
            defaults.removeObject(forKey: Key.resumeIndex)
            decide(show: !steps.isEmpty)
            return
        }

        guard defaults.integer(forKey: Key.completedVersion) < Self.currentVersion else {
            decide(show: false)
            return
        }

        let isFresh = defaults.object(forKey: "historyBackfilledDays") == nil
        var needed: [OnboardingStep]
        if isFresh {
            needed = OnboardingStep.flow
        } else {
            needed = await missingSteps()
            if !needed.isEmpty { needed.append(.done) }
        }

        if needed.isEmpty {
            markComplete()
            decide(show: false)
        } else {
            steps = needed
            index = 0
            decide(show: true)
        }
    }

    private func missingSteps() async -> [OnboardingStep] {
        let defaults = UserDefaults.standard
        var missing: [OnboardingStep] = []

        let store = HealthKitManager.shared.store
        let status = try? await store.statusForAuthorizationRequest(toShare: HealthAccess.shareTypes,
                                                                   read: HealthKitManager.shared.readTypes)
        if status == .shouldRequest { missing.append(.health) }

        let profile = BodyProfile.load()
        if profile.heightCm == nil || profile.ageYears == nil || profile.isFemale == nil { missing.append(.aboutYou) }

        if !DeviceProfile.isSet { missing.insert(.devices, at: 0) }
        if defaults.object(forKey: "goal.phase") == nil { missing.append(.goal) }

        if !defaults.bool(forKey: Key.sleepSet) && defaults.object(forKey: "bedtime.wakeHour") == nil { missing.append(.sleep) }

        let hasKey = !(KeychainStore.get(APIKeyName.gemini) ?? "").isEmpty
        if !hasKey && !OnDeviceAI.isAvailable && !defaults.bool(forKey: Key.aiAnswered) { missing.append(.ai) }

        let notifications = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        if notifications == .notDetermined { missing.append(.notifications) }

        if !defaults.bool(forKey: Key.lockScreenSeen) { missing.append(.lockScreen) }
        return missing
    }

    private func decide(show: Bool) {
        decided = true
        shouldShow = show
        if !show { release() }
    }

    // MARK: Waiting

    /// Suspends until setup is decided and, if shown, finished.
    func waitUntilReady() async {
        await prepare()
        if !shouldShow { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func release() {
        let pending = waiters
        waiters = []
        pending.forEach { $0.resume() }
    }

    // MARK: Moving through

    func next() {
        if let step = current { remember(step) }
        if index < steps.count - 1 {
            index += 1
        } else {
            finish()
        }
    }

    func back() {
        if index > 0 { index -= 1 }
    }

    func finish() {
        markComplete()
        shouldShow = false
        isPresented = false
        release()
        HealthSync.shared.refreshSoon(after: .milliseconds(200))
    }

    /// Settings → Run setup again.
    func presentFull() {
        steps = OnboardingStep.flow
        index = 0
        decided = true
        shouldShow = true
        isPresented = true
    }

    /// Before the app closes to switch language, so setup resumes afterwards.
    func saveForRelaunch() {
        UserDefaults.standard.set(steps.map(\.rawValue), forKey: Key.resumeSteps)
        UserDefaults.standard.set(index + 1, forKey: Key.resumeIndex)
    }

    private func remember(_ step: OnboardingStep) {
        let defaults = UserDefaults.standard
        switch step {
        case .sleep:      defaults.set(true, forKey: Key.sleepSet)
        case .ai:         defaults.set(true, forKey: Key.aiAnswered)
        case .lockScreen: defaults.set(true, forKey: Key.lockScreenSeen)
        default: break
        }
    }

    private func markComplete() {
        UserDefaults.standard.set(Self.currentVersion, forKey: Key.completedVersion)
    }
}
