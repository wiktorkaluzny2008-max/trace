//
//  ContentView.swift
//  RecoverySignal2
//

import SwiftUI
import SwiftData

/// Lets any screen switch tabs, open the tracker, or open the Today / Trends / Analysis guide.
struct TabNavigator {
    var selected: AppTab? = nil
    var select: (AppTab) -> Void = { _ in }
    var showGuide: () -> Void = {}
    /// Jumps to the Train tab.
    var openTrain: () -> Void = {}
    /// Opens Settings as a sheet over the current tab.
    var openSettings: () -> Void = {}
}

extension EnvironmentValues {
    @Entry var tabNavigator = TabNavigator()
}

struct ContentView: View {
    enum Tab: String, Hashable { case today, train, trends, analysis, insights }

    /// Remembered across launches, so the app reopens where you left it.
    @SceneStorage("selectedTab") private var selection: Tab = .today
    @State private var showsGuide = false
    @State private var showsSettings = false
    @State private var recorder = WorkoutRecorder.shared
    @State private var launch = AppLaunch.shared
    @State private var showsIntro = AppPrefs.launchAnimation
    @State private var onboarding = OnboardingCoordinator.shared
    @Environment(\.modelContext) private var context
    @State private var inbox = MacroPasteInbox.shared

    private var selectedAppTab: AppTab? {
        switch selection {
        case .today:    .today
        case .trends:   .trends
        case .analysis: .analysis
        default:        nil
        }
    }

    var body: some View {
        ZStack {
            tabs
            if showsIntro {
                AppIntroView {
                    showsIntro = false
                    introDone()
                }
                .transition(.identity)
                .zIndex(1)
            }
        }
        .task {
            // With the launch animation switched off, go straight to what follows it.
            if !showsIntro && !launch.introFinished { introDone() }
        }
        .task {
            // Build the food search index while the intro plays, not on the
            // first keystroke in the food screen.
            try? await Task.sleep(for: .seconds(1.5))
            SwissFoodDatabase.warmUp()
            PolishProductDatabase.warmUp()
        }
        #if DEBUG
        // Development only: `-tab trends` opens a tab directly.
        .task {
            let args = ProcessInfo.processInfo.arguments
            #if targetEnvironment(simulator)
            // Simulator only: `-seedLocal` fills the app's own store without touching Health.
            if args.contains("-seedLocal") {
                do { try SampleDataSeeder.seedLocal(context: context) } catch { print("Local seeding failed: \(error)") }
            }
            // Simulator only: `-seedSampleData` fills Health with a month of sample readings.
            if args.contains("-seedSampleData") {
                do {
                    try await SampleDataSeeder.seed(context: context)
                    try await MetricsAggregator(context: context).refresh(days: SampleDataSeeder.dayCount)
                    SampleDataSeeder.attachReadiness(context: context)
                } catch {
                    print("Seeding failed: \(error)")
                }
            }
            #endif
            if args.contains("-pasteSample") { inbox.pending = PastedText(text: ChatGPTGuidePage.sampleReply) }
            guard let i = args.firstIndex(of: "-tab"), i + 1 < args.count else { return }
            let tabs: [String: Tab] = ["today": .today, "train": .train, "trends": .trends, "analysis": .analysis, "insights": .insights]
            if let tab = tabs[args[i + 1]] { selection = tab }
            if args[i + 1] == "settings" { showsSettings = true }
        }
        #endif
        .fullScreenCover(isPresented: $onboarding.isPresented) {
            OnboardingView()
        }
        // Anything that asks for the tracker lands on the Train tab.
        .onChange(of: recorder.showsHome) { _, shows in
            if shows {
                recorder.showsHome = false
                selection = .train
            }
        }
        .fullScreenCover(isPresented: $recorder.showsActive) {
            ActiveWorkoutView()
        }
        // Macros sent in from Shortcuts, once the intro is out of the way.
        .sheet(item: Binding(get: { launch.introFinished ? inbox.pending : nil },
                             set: { inbox.pending = $0 })) { item in
            PasteMacrosSheet(text: item.text)
        }
        .sheet(isPresented: $showsGuide) {
            TabGuideSheet(current: selectedAppTab) { tab in switchTo(tab) }
                .presentationDetents([.large])
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
    }

    private var tabs: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "house.fill") }
                .tag(Tab.today)

            NavigationStack {
                WorkoutsHomeView(embedded: true, asTab: true)
                    .navigationDestination(for: WorkoutLog.self) { WorkoutLogDetailView(log: $0) }
            }
            .tabItem { Label("Train", systemImage: "dumbbell.fill") }
            .tag(Tab.train)

            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.xyaxis.line") }
                .tag(Tab.trends)

            AnalysisView()
                .tabItem { Label("Analysis", systemImage: "function") }
                .tag(Tab.analysis)

            InsightsView()
                .tabItem { Label("Insights", systemImage: "sparkles") }
                .tag(Tab.insights)
        }
        .tint(Theme.accent)
        .sensoryFeedback(.selection, trigger: selection)
        .environment(\.tabNavigator, TabNavigator(
            selected: selectedAppTab,
            select: { tab in switchTo(tab) },
            showGuide: { showsGuide = true },
            openTrain: { selection = .train },
            openSettings: { showsSettings = true }
        ))
    }

    private func introDone() {
        launch.introFinished = true
        Task {
            await onboarding.prepare()
            onboarding.presentIfNeeded()
        }
    }

    private func switchTo(_ tab: AppTab) {
        do {
            switch tab {
            case .today:    selection = .today
            case .trends:   selection = .trends
            case .analysis: selection = .analysis
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [DailyMetrics.self, Insight.self, WeeklyNarrative.self], inMemory: true)
}
