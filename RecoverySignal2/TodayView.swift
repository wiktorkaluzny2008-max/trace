//
//  TodayView.swift
//  RecoverySignal2
//

import SwiftUI
import SwiftData

struct TodayView: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var allDays: [DailyMetrics]
    @Query private var dayTags: [DayTag]
    @Environment(\.modelContext) private var context

    private var today: DailyMetrics? { allDays.first }
    private var recent: [DailyMetrics] { Array(allDays.prefix(RecoveryScore.baselineDays + 1)) }
    private var score: RecoveryScore? { RecoveryScore.compute(from: recent, excluded: DayTagStore.excludedDates(dayTags)) }
    /// Height, age and sex cached from Health on the last refresh.
    private var profile: BodyProfile { BodyProfile.load() }
    @State private var path = NavigationPath()
    /// The page open on Today (Food, Sleep…), restored after iOS closes the app.
    @SceneStorage("today.path") private var savedPath: Data?
    @State private var restoredPath = false
    @State private var workoutRecorder = WorkoutRecorder.shared
    @Query(sort: \WorkoutLog.start, order: .reverse) private var workoutLogs: [WorkoutLog]
    @State private var editingLayout = false
    @State private var showsRecoveryDrivers = false
    /// Changes whenever the section order or visibility is edited, so the page redraws.
    @AppStorage(TodayLayout.stampKey) private var layoutRaw = ""
    /// What the person wears (Settings → Your devices); sections a device can't feed are hidden.
    @AppStorage(DeviceProfile.heartKey) private var tracksHeart = true
    @AppStorage(DeviceProfile.sleepKey) private var tracksSleep = true
    @Environment(\.tabNavigator) private var navigator

    // Score reveal: the ring counts up from 0 with haptic ticks when the app opens.
    @State private var displayedScore: Double = 0
    @State private var revealedValue: Int?
    @State private var isRevealing = false
    @State private var haptics = ScoreRevealHaptics()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 24) {
                    todayHeader

                    if let active = workoutRecorder.active {
                        Button { workoutRecorder.showsActive = true } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "figure.strengthtraining.traditional")
                                    .font(.system(size: 18, weight: .semibold))

                                VStack(alignment: .leading, spacing: 1) {
                                    Text("\(active.name) in progress").font(.subheadline.weight(.semibold))
                                    Text(active.start, style: .timer).font(.caption.monospacedDigit()).opacity(0.85)
                                }
                                Spacer()
                                Text("Resume").font(.subheadline.weight(.semibold))
                                Image(systemName: "chevron.right").font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(Theme.textPrimary)
                            .padding(18)
                            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }

                    ForEach(visibleSections) { item in
                        if !item.needsDailyMetrics || today != nil {
                            todaySection(item, today: today)
                                .contextMenu { sectionMenu(item) }
                        }
                    }

                    Button {
                        editingLayout = true
                    } label: {
                        Label("Edit Today", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(.horizontal, 18)
                .padding(.top, 2)
                .padding(.bottom, 36)
            }
            .background(Theme.background.ignoresSafeArea())
            // A real navigation bar: the large title collapses as you scroll and
            // the system blurs whatever passes under the status bar, instead of
            // cards sliding beneath the clock and the back-to-app arrow.
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        navigator.openSettings()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .tint(Theme.textPrimary)
                    .accessibilityLabel("Settings")
                }
            }
            #if DEBUG
            // Development only: `-openDetail sleep` launches straight into a page
            // so screens can be checked without tapping through.
            .task {
                let args = ProcessInfo.processInfo.arguments
                if args.contains("-resetTodayNavigation") {
                    restoredPath = true
                    savedPath = nil
                    path = NavigationPath()
                }
                if args.contains("-openLatestLog"), path.isEmpty {
                    // Wait for the store (and any seeding) before opening the newest session.
                    for _ in 0..<30 where workoutLogs.isEmpty { try? await Task.sleep(for: .milliseconds(200)) }
                    if let log = workoutLogs.first { path.append(log) }
                    return
                }
                guard let i = args.firstIndex(of: "-openDetail"), i + 1 < args.count, path.isEmpty else { return }
                let routes: [String: DetailRoute] = ["recovery": .recovery, "sleep": .sleep, "activity": .activity,
                                                     "nutrition": .nutrition, "body": .body, "weight": .weight, "food": .food, "workouts": .workouts]
                if let route = routes[args[i + 1]] { path.append(route) }
            }
            #endif
            .navigationDestination(for: WorkoutLog.self) { WorkoutLogDetailView(log: $0) }
            .navigationDestination(for: DetailRoute.self) { route in
                switch route {
                case .recovery:  RecoveryDetailView()
                case .sleep:     SleepDetailView()
                case .activity:  ActivityDetailView()
                case .nutrition: NutritionDetailView()
                case .body:      BodyDetailView()
                case .workouts:  WorkoutsHomeView(embedded: true)
                case .weight:    BodyLogView()
                case .food:      FoodLogView()
                }
            }
            .refreshable { await refresh() }
            .onAppear {
                guard !restoredPath else { return }
                restoredPath = true
                if let savedPath, let representation = try? JSONDecoder().decode(NavigationPath.CodableRepresentation.self, from: savedPath) {
                    path = NavigationPath(representation)
                }
            }
            .onChange(of: path) { _, newPath in
                // Only pages that can be rebuilt are remembered (a workout log isn't).
                savedPath = newPath.codable.flatMap { try? JSONEncoder().encode($0) }
            }
            .task(id: score?.value) { await revealScore() }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    Task { await revealScore() }
                default:
                    break
                }
            }
            .sheet(isPresented: $editingLayout) {
                TodayLayoutEditor { layoutRaw = TodayLayout.stamp() }
                    .presentationDetents([.medium, .large])
            }
        }
    }

    // MARK: - Header

    private var actionsLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
    }
    private var recoveryLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 16))
    }

    /// Under the system's large "Today" title: the date and phase as one quiet
    /// line, then the two things you log every day. Settings lives in the
    /// navigation bar, where iOS puts it.
    private var todayHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            ViewThatFits(in: .horizontal) {
                HStack { dateLabel; Spacer(); goalLabel }
                VStack(alignment: .leading, spacing: 8) { dateLabel; goalLabel }
            }
            quickActions
        }
    }

    private var dateLabel: some View {
        Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide)))
            .font(.subheadline).foregroundStyle(Theme.textSecondary)
    }
    private var goalLabel: some View {
        Text(phaseLabel(GoalSettings.load()))
            .font(.caption.weight(.medium)).foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Theme.surfaceRaised, in: Capsule())
    }

    /// "Bulk · +0.25 kg/wk" — the phase you're in, from Settings → Goal.
    private func phaseLabel(_ goal: GoalSettings) -> String {
        switch goal.phase {
        case .maintain: return String(localized: "Maintain")
        case .bulk:     return String(localized: "Bulk +\(goal.rateKgPerWeek.formatted(.number.precision(.fractionLength(0...2)))) kg/wk")
        case .cut:      return String(localized: "Cut −\(goal.rateKgPerWeek.formatted(.number.precision(.fractionLength(0...2)))) kg/wk")
        }
    }

    /// Two pills: log food, log a weigh-in. Training has its own tab, so it
    /// doesn't need a shortcut here.
    private var quickActions: some View {
        actionsLayout {
            quickAction("fork.knife", title: "Log food", tint: Theme.accent) { path.append(DetailRoute.food) }
            quickAction("scalemass.fill", title: "Weigh in", tint: Theme.accent) { path.append(DetailRoute.weight) }
        }
    }

    private func quickAction(_ symbol: String, title: LocalizedStringKey, tint: Color, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Hero

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let score {
                recoveryLayout {
                    ZStack {
                        Circle()
                            .fill(score.band.color.opacity(0.13))
                            .blur(radius: 18)
                            .frame(width: 122, height: 122)
                        ScoreRing(progress: displayedScore / 100, color: score.band.color)
                            .padding(10)
                        VStack(spacing: 3) {
                            RingValueText(text: "\(Int(displayedScore.rounded()))%", size: 40)
                            Text("TODAY")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.1)
                                .foregroundStyle(Theme.textTertiary)
                        }
                    }
                    .frame(width: 142, height: 142)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Recovery \(Int(displayedScore.rounded())) percent")

                    VStack(alignment: .leading, spacing: 9) {
                        HStack(spacing: 6) {
                            Circle().fill(score.band.color).frame(width: 7, height: 7)
                            Text(score.band.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(score.band.color)
                        }
                        Text(LocalizedStringKey(score.headline))
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Based on your recent personal baseline")
                            .font(.caption2)
                            .foregroundStyle(Theme.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                recoveryStats(score)

                Button {
                    withAnimation(reduceMotion ? nil : Theme.Motion.settle) { showsRecoveryDrivers.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(Theme.accent)
                        Text(showsRecoveryDrivers ? "Hide score details" : "What shaped this score")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(score.drivers.count)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Theme.textTertiary)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Theme.textTertiary)
                            .rotationEffect(.degrees(showsRecoveryDrivers ? 180 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Shows the readings contributing to recovery")

                if showsRecoveryDrivers {
                    VStack(spacing: 11) {
                        ForEach(score.drivers) { driver in driverRow(driver) }
                    }
                    .padding(14)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            } else if let last = lastScore {
                HStack(spacing: 16) {
                    GlyphView(.watch, size: 36)
                        .frame(width: 64, height: 64)
                        .background(Theme.track, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Today's readings aren't in yet").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Your Watch's sleep and HRV haven't synced yet.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                        Text("Last score \(last.score.value)% · \(last.date.formatted(.dateTime.weekday(.wide)))")
                            .font(.caption.weight(.semibold)).foregroundStyle(last.score.band.color)
                    }
                }
                .padding(.vertical, 6)
            } else {
                HStack(spacing: 16) {
                    GlyphView(.watch, size: 36)
                        .frame(width: 64, height: 64)
                        .background(Theme.track, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Not enough data yet").font(.headline).foregroundStyle(Theme.textPrimary)
                        Text("Recovery compares readings with your own normal. Sync at least a week of Watch data to get started.")
                            .font(.footnote).foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .card(padding: 18)
        .background(alignment: .top) {
            if let score {
                LinearGradient(colors: [score.band.color.opacity(0.09), .clear], startPoint: .top, endPoint: .center)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
                    .allowsHitTesting(false)
            }
        }
    }

    /// Without a heart-rate tracker there's no recovery to score, so Today leads
    /// with what the phone does know: food against target, and training.
    private var noTrackerCard: some View {
        let targets = EnergyModel.maintenance(from: Array(allDays), profile: profile)
            .map { EnergyModel.targets(from: Array(allDays), maintenance: $0) }
        let eaten = today.flatMap { Calendar.current.isDateInToday($0.date) ? $0.dietaryEnergyKcal : nil } ?? 0
        let protein = today.flatMap { Calendar.current.isDateInToday($0.date) ? $0.proteinGrams : nil } ?? 0
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let sessions = workoutLogs.filter { $0.start >= weekAgo }.count
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 18) {
                ZStack {
                    ScoreRing(progress: targets.map { min(eaten / max($0.calories, 1), 1) } ?? 0, color: Theme.accent)
                        .padding(8)
                    VStack(spacing: 1) {
                        Text(verbatim: "\(DetailFormat.safeInt(eaten))")
                            .font(.system(size: 26, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(Theme.textPrimary)
                        Text("KCAL").font(.system(size: 9, weight: .bold)).tracking(1).foregroundStyle(Theme.textTertiary)
                    }
                }
                .frame(width: 118, height: 118)

                VStack(alignment: .leading, spacing: 10) {
                    if let targets {
                        stat("\(DetailFormat.safeInt(max(targets.calories - eaten, 0))) kcal left",
                             "of \(DetailFormat.safeInt(targets.calories)) today")
                        stat("\(DetailFormat.safeInt(protein)) g protein",
                             "of \(DetailFormat.safeInt(targets.proteinGrams)) g")
                    } else {
                        stat("\(DetailFormat.safeInt(protein)) g protein", "eaten today")
                    }
                    stat("\(sessions) workout\(sessions == 1 ? "" : "s")", "in the last 7 days")
                }
                Spacer(minLength: 0)
            }
            Label("Recovery and strain need a watch or ring that tracks heart rate. Got one? Add it in Settings → Your devices.",
                  systemImage: "applewatch.slash")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 18)
    }

    private func stat(_ value: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: value).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(verbatim: detail).font(.caption).foregroundStyle(Theme.textTertiary)
        }
    }

    private func recoveryStats(_ score: RecoveryScore) -> some View {
        let strain = today?.strain
        return HStack(spacing: 0) {
            recoveryStat(strain.map { $0.formatted(.number.precision(.fractionLength(1))) } ?? "—",
                         label: "Strain", detail: strain.map { StrainModel.Level($0).label } ?? "no data", tint: Theme.accent)
            Rectangle().fill(Theme.separator).frame(width: 1, height: 34)
            recoveryStat(score.sleepPerformance.map { "\(Int(($0 * 100).rounded()))%" } ?? "—",
                         label: "Sleep", detail: "performance", tint: Theme.mint)
            Rectangle().fill(Theme.separator).frame(width: 1, height: 34)
            recoveryStat(score.sleepNeed.map { DetailFormat.hoursMinutes($0.total) } ?? "—",
                         label: "Sleep need", detail: "tonight", tint: Theme.textPrimary)
        }
        .padding(.vertical, 13)
        .background(Theme.background.opacity(0.9), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private func recoveryStat(_ value: String, label: LocalizedStringKey, detail: String, tint: Color) -> some View {
        VStack(spacing: 3) {
            Text(verbatim: value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(Theme.textPrimary).lineLimit(1)
            Text(LocalizedStringKey(detail)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// One recovery input: its reading, and a bar showing how far it sits
    /// above or below your normal (or, for sleep, how much of the need was met).
    private func driverRow(_ driver: RecoveryScore.Driver) -> some View {
        HStack(spacing: 10) {
            Text(LocalizedStringKey(driver.label))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 72, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                if let deviation = driver.deviation {
                    ZScoreBar(z: deviation)
                } else {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.track)
                            Capsule()
                                .fill(Theme.mint)
                                .frame(width: max(4, geo.size.width * driver.fraction))
                        }
                    }
                    .frame(height: 7)
                }
                Text(LocalizedStringKey(driver.detail))
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Text("\(Int((driver.fraction * 100).rounded()))")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(driver.fraction >= 0.67 ? Theme.good : (driver.fraction >= 0.34 ? Theme.warn : Theme.bad))
                .frame(width: 26, alignment: .trailing)
        }
    }

    // MARK: - Sections

    // MARK: - Layout

    private var visibleSections: [TodaySection] {
        let _ = layoutRaw
        func supported(_ section: TodaySection) -> Bool {
            switch section {
            case .recovery:        return tracksHeart
            case .sleep, .tonight: return tracksSleep
            default:               return true
            }
        }
        #if DEBUG
        // Development only: `-todaySections nutrition,sleep` shows just those,
        // so each part of the page can be screenshotted without scrolling.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-todaySections"), i + 1 < args.count {
            return args[i + 1].split(separator: ",").compactMap { TodaySection(rawValue: String($0)) }.filter(supported)
        }
        #endif
        return TodayLayout.order.filter { !TodayLayout.hidden.contains($0) && supported($0) }
    }

    @ViewBuilder
    private func todaySection(_ item: TodaySection, today: DailyMetrics?) -> some View {
        switch item {
        case .session:
            VStack(alignment: .leading, spacing: 10) {
                detailHeader("Today's session", icon: nil) { navigator.openTrain() }
                TrainingHeroCard(days: Array(allDays.prefix(14))) { navigator.openTrain() }
            }
        case .volume:
            VStack(alignment: .leading, spacing: 10) {
                detailHeader("Weekly sets", icon: nil) { navigator.select(.trends) }
                WeeklySetsCard { navigator.select(.trends) }
            }
        case .records:
            VStack(alignment: .leading, spacing: 10) {
                detailHeader("Personal records", icon: nil) { navigator.openTrain() }
                RecordsCard { navigator.openTrain() }
            }
        case .readiness:
            VStack(alignment: .leading, spacing: 10) {
                if tracksHeart {
                    detailHeader("Recovery", icon: nil, route: .recovery)
                    heroCard
                } else {
                    detailHeader("Today", icon: nil, route: .food)
                    noTrackerCard
                }
            }
        default:
            if let today { metricsSection(item, today: today) }
        }
    }

    @ViewBuilder
    private func metricsSection(_ item: TodaySection, today: DailyMetrics) -> some View {
        switch item {
        case .recovery:
            section("Heart & fitness", icon: .heartRate, route: .recovery, trend: \.hrvSDNN, items: [
                MetricItem(glyph: .hrv, label: String(localized: "HRV"), value: recent(\.hrvSDNN).value, unit: "ms",
                           delta: delta(\.hrvSDNN), higherIsBetter: true, asOf: recent(\.hrvSDNN).asOf),
                MetricItem(glyph: .heartRate, label: String(localized: "Resting HR"), value: recent(\.restingHeartRate).value, unit: "bpm",
                           delta: delta(\.restingHeartRate), higherIsBetter: false, asOf: recent(\.restingHeartRate).asOf),
                MetricItem(glyph: .oxygen, label: String(localized: "Blood oxygen"), value: recent(\.oxygenSaturation).value.map { $0 * 100 },
                           unit: "%", decimals: 1, higherIsBetter: true, asOf: recent(\.oxygenSaturation).asOf),
                MetricItem(glyph: .lungs, label: String(localized: "VO₂ max"), value: recent(\.vo2Max, days: 30).value, unit: "ml/kg", decimals: 1,
                           higherIsBetter: true, asOf: recent(\.vo2Max, days: 30).asOf)
            ])
        case .sleep:
            section("Sleep", icon: .sleep, route: .sleep, trend: \.sleepAsleepHours,
                    chart: .bars(history: history(\.sleepAsleepHours),
                                 style: ValueStyle(unit: "h", decimals: 1, duration: true),
                                 color: Theme.sleepCore, compare: true, key: "sleep"),
                    items: [
                MetricItem(glyph: .sleep, label: String(localized: "Asleep"), value: today.sleepAsleepHours, unit: "h", decimals: 1,
                           delta: delta(\.sleepAsleepHours), higherIsBetter: true),
                MetricItem(glyph: .deepSleep, label: String(localized: "Deep"), value: today.sleepDeepHours, unit: "h", decimals: 1,
                           higherIsBetter: true),
                MetricItem(glyph: .remSleep, label: String(localized: "REM"), value: today.sleepREMHours, unit: "h", decimals: 1,
                           higherIsBetter: true)
            ])
        case .tonight:
            VStack(alignment: .leading, spacing: 10) {
                detailHeader("Tonight", icon: .sleep, route: .sleep)
                TonightPlanCard(days: Array(allDays), compact: true)
                    .opensDetail(.sleep, path: $path)
            }
        case .activity:
            section("Activity", icon: .activity, route: .activity, trend: \.steps,
                    chart: .bars(history: history(\.steps), style: ValueStyle(),
                                 color: Theme.activity, compare: false, key: "steps"),
                    items: [
                MetricItem(glyph: .steps, label: String(localized: "Steps"), value: today.steps, unit: "",
                           delta: delta(\.steps), higherIsBetter: true),
                MetricItem(glyph: .energy, label: String(localized: "Active energy"), value: today.activeEnergyBurned, unit: "kcal",
                           delta: delta(\.activeEnergyBurned), higherIsBetter: true)
            ])
        case .training:
            trainingSection(today)
        case .nutrition:
            nutritionSection(today)
        case .body:
            section("Body", icon: .body, route: .body, trend: \.bodyMassKg, items: [
                MetricItem(glyph: .body, label: String(localized: "Weight"), value: recent(\.bodyMassKg, days: 30).value, unit: "kg", decimals: 1,
                           delta: delta(\.bodyMassKg), asOf: recent(\.bodyMassKg, days: 30).asOf)
            ] + (today.bodyFatPercent == nil ? [] : [
                MetricItem(glyph: .fat, label: String(localized: "Body fat"), value: today.bodyFatPercent, unit: "%", decimals: 1,
                           delta: delta(\.bodyFatPercent), higherIsBetter: false),
                MetricItem(glyph: .protein, label: String(localized: "Lean mass"), value: today.leanBodyMassKg, unit: "kg", decimals: 1,
                           higherIsBetter: true)
            ]))
        case .dayTags:
            DayTagsCard()
        case .maintenance:
            VStack(alignment: .leading, spacing: 10) {
                detailHeader("Maintenance calories", icon: .energy, route: .body)
                AdaptiveMaintenanceCard(days: allDays, compact: true, excludedDates: DayTagStore.excludedDates(dayTags))
                    .opensDetail(.body, path: $path)
            }
        case .session, .volume, .records, .readiness:
            EmptyView()
        }
    }

    @ViewBuilder
    private func sectionMenu(_ item: TodaySection) -> some View {
        let order = visibleSections
        if let i = order.firstIndex(of: item) {
            if i > 0 {
                Button("Move up", systemImage: "arrow.up") { move(item, by: -1) }
            }
            if i < order.count - 1 {
                Button("Move down", systemImage: "arrow.down") { move(item, by: 1) }
            }
        }
        Button("Hide", systemImage: "eye.slash") {
            withAnimation(.snappy) { TodayLayout.hidden.insert(item); layoutRaw = TodayLayout.stamp() }
        }
        Divider()
        Button("Edit Today…", systemImage: "slider.horizontal.3") { editingLayout = true }
    }

    private func move(_ item: TodaySection, by step: Int) {
        let visible = visibleSections
        guard let i = visible.firstIndex(of: item), visible.indices.contains(i + step) else { return }
        let neighbour = visible[i + step]
        var order = TodayLayout.order
        guard let a = order.firstIndex(of: item), let b = order.firstIndex(of: neighbour) else { return }
        order.swapAt(a, b)
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        withAnimation(.snappy) { TodayLayout.order = order; layoutRaw = TodayLayout.stamp() }
    }


    /// One card per category: the first item is the headline metric, shown
    /// with its two-week trend; the rest sit underneath.
    @ViewBuilder
    private func section(_ title: String, icon: Glyph? = nil, route: DetailRoute,
                         trend keyPath: KeyPath<DailyMetrics, Double?>, chart: CategoryChartStyle = .line,
                         items: [MetricItem]) -> some View {
        if let hero = items.first {
            VStack(alignment: .leading, spacing: 10) {
                detailHeader(title, icon: icon, route: route)
                CategoryCard(hero: hero, trend: trend(keyPath), others: Array(items.dropFirst()), chart: chart)
                    .opensDetail(route, path: $path)
            }
        }
    }

    /// Section header that opens the section's page.
    private func detailHeader(_ title: String, icon: Glyph?, route: DetailRoute) -> some View {
        detailHeader(title, icon: icon) { path.append(route) }
    }

    /// One quiet, consistent header for every section: the title in plain
    /// semibold with a small chevron, no icons, no coloured links. The whole
    /// row is the button. (`icon` is kept for call sites; it isn't drawn.)
    private func detailHeader(_ title: String, icon: Glyph?, action: @escaping () -> Void) -> some View {
        TodaySectionHeader(title: title, action: action)
    }

    /// Today's value, or the most recent one within `days` (with its date)
    /// when today's reading hasn't synced yet.
    private func recent(_ keyPath: KeyPath<DailyMetrics, Double?>, days: Int = 3) -> (value: Double?, asOf: Date?) {
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Calendar.current.startOfDay(for: Date())) ?? .distantPast
        guard let day = allDays.first(where: { $0.date >= cutoff && $0[keyPath: keyPath] != nil }) else { return (nil, nil) }
        return (day[keyPath: keyPath], Calendar.current.isDateInToday(day.date) ? nil : day.date)
    }

    /// The latest score from the past week, for when today's can't be computed yet.
    private var lastScore: (date: Date, score: RecoveryScore)? {
        let sorted = allDays.sorted { $0.date < $1.date }
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? .distantPast
        for index in sorted.indices.reversed() where sorted[index].date >= cutoff {
            let window = Array(sorted[max(0, index - RecoveryScore.baselineDays)...index])
            if let score = RecoveryScore.compute(from: window, excluded: DayTagStore.excludedDates(dayTags)),
               sorted[index].hrvSDNN != nil || sorted[index].sleepAsleepHours != nil {
                return (sorted[index].date, score)
            }
        }
        return nil
    }

    /// Every stored day of a metric, oldest first — for charts that compare
    /// the last two weeks with a longer average.
    private func history(_ keyPath: KeyPath<DailyMetrics, Double?>) -> [TrendPoint] {
        allDays.reversed().compactMap { day in
            day[keyPath: keyPath].map { TrendPoint(date: day.date, value: $0) }
        }
    }

    /// The last two weeks of a metric, oldest first, skipping days without data.
    private func trend(_ keyPath: KeyPath<DailyMetrics, Double?>, days: Int = 14) -> [TrendPoint] {
        allDays.prefix(days).reversed().compactMap { day in
            day[keyPath: keyPath].map { TrendPoint(date: day.date, value: $0) }
        }
    }

    // MARK: - Nutrition

    @ViewBuilder
    private func nutritionSection(_ today: DailyMetrics) -> some View {
        let maintenance = EnergyModel.maintenance(from: allDays, profile: profile)
        let goal = GoalSettings.load()
        let targets = maintenance.map { EnergyModel.targets(from: allDays, maintenance: $0) }

        VStack(alignment: .leading, spacing: 10) {
            detailHeader("Nutrition", icon: .nutrition, route: .nutrition)
            NutritionRingsCard(
                calories: today.dietaryEnergyKcal,
                protein: today.proteinGrams,
                carbs: today.carbsGrams,
                fat: today.fatGrams,
                targets: targets,
                goal: goal.phase
            )
            .opensDetail(.nutrition, path: $path)
        }

    }

    // MARK: - Training

    @ViewBuilder
    private func trainingSection(_ today: DailyMetrics) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            detailHeader("Training log", icon: .training) { navigator.openTrain() }

            // Sessions logged in the app, plus Health workouts not already linked to one.
            let appLogs = workoutLogs.filter { Calendar.current.isDateInToday($0.start) }
            ForEach(appLogs) { log in
                AppWorkoutCard(log: log)
                    .contentShape(Rectangle())
                    .onTapGesture { path.append(log) }
            }
            if today.hadWorkout && !(appLogs.contains { $0.healthWorkoutID != nil || $0.savedToHealth } && appLogs.count >= today.workoutCount) {
                TrainingCard(day: today)
                    .opensDetail(.activity, path: $path)
            } else if appLogs.isEmpty {
                HStack(spacing: 12) {
                    GlyphView(.rest, size: 24)
                    Text("No session logged today — rest counts too")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                .card()
            }

            weeklyLoadCard
                .opensDetail(.activity, path: $path)
        }
    }

    private var weeklyLoadCard: some View {
        let week = allDays.prefix(7)
        let weekStart = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-6 * 86_400)
        // In-app sessions that never reached Health still count.
        let appOnly = workoutLogs.filter { $0.start >= weekStart && !$0.savedToHealth && $0.healthWorkoutID == nil }
        let sessions = week.reduce(0) { $0 + $1.workoutCount } + appOnly.count
        let totalMinutes = week.compactMap(\.workoutMinutes).reduce(0, +) + appOnly.reduce(0) { $0 + $1.duration / 60 }
        let strengthMinutes = week.compactMap(\.strengthMinutes).reduce(0, +) + appOnly.reduce(0) { $0 + $1.duration / 60 }

        return HStack(spacing: 0) {
            loadStat(String(localized: "Sessions"), "\(sessions)")
            statDivider
            loadStat(String(localized: "Total"), durationText(totalMinutes))
            statDivider
            loadStat(String(localized: "Strength"), durationText(strengthMinutes))
        }
        .card(padding: 14)
    }

    private func loadStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(label))
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(width: 1, height: 26)
    }

    // MARK: - Data

    /// Percentage change of today's value versus the mean of the prior 7 days.
    private func delta(_ keyPath: KeyPath<DailyMetrics, Double?>) -> Double? {
        guard let current = today?[keyPath: keyPath] else { return nil }
        let history = allDays.dropFirst().prefix(7).compactMap { $0[keyPath: keyPath] }
        guard history.count >= 3 else { return nil }
        let average = history.reduce(0, +) / Double(history.count)
        guard average != 0 else { return nil }
        return (current - average) / average * 100
    }

    private static let lastRevealKey = "scoreReveal.lastDay"

    /// Counts the ring and number up from 0 to today's score, ticking a light
    /// haptic every 5 points and landing on a beat that matches the band.
    /// Plays only on the first open of the day — the morning check-in — and
    /// afterwards the ring simply shows the score, silently.
    private func revealScore() async {
        guard let score else {
            displayedScore = 0
            return
        }
        let target = Double(score.value)
        guard AppPrefs.animateScore else {
            displayedScore = target
            return
        }
        guard !isRevealing else { return }
        let calendar = Calendar.current
        if let last = UserDefaults.standard.object(forKey: Self.lastRevealKey) as? Date,
           calendar.isDateInToday(last) {
            displayedScore = target
            return
        }

        isRevealing = true
        // Wait for the launch intro to clear so the reveal is actually seen.
        for _ in 0..<60 where !AppLaunch.shared.introFinished {
            try? await Task.sleep(for: .milliseconds(100))
        }
        UserDefaults.standard.set(Date(), forKey: Self.lastRevealKey)
        defer {
            isRevealing = false
            revealedValue = score.value
        }

        if reduceMotion {
            displayedScore = target
            if AppPrefs.revealHaptics { haptics.land(on: score.band) }
            return
        }

        let hapticsOn = AppPrefs.revealHaptics
        if hapticsOn { haptics.prepare() }
        displayedScore = 0
        try? await Task.sleep(for: .milliseconds(250))   // let the screen settle first

        let duration = 1.4
        let frames = 84
        // Core Haptics plays the whole choreography as one pattern timed to the
        // ring; without it, fall back to firing impacts from the animation loop.
        // With haptics off, `patterned` stays true so no fallback impacts fire either.
        let patterned = hapticsOn ? haptics.playReveal(target: target, duration: duration, band: score.band) : true
        var lastTickBucket = 0
        for frame in 1...frames {
            if Task.isCancelled { break }
            let t = Double(frame) / Double(frames)
            let eased = 1 - pow(1 - t, 3)                 // fast start, gentle finish
            displayedScore = eased * target

            let bucket = Int(displayedScore / 5)
            if !patterned, bucket > lastTickBucket {
                lastTickBucket = bucket
                haptics.tick(progress: eased)
            }
            try? await Task.sleep(for: .seconds(duration / Double(frames)))
        }

        displayedScore = target
        if Task.isCancelled {
            haptics.stop()
        } else if !patterned {
            haptics.land(on: score.band)
        }
    }

    private func refresh() async {
        let aggregator = MetricsAggregator(context: context)
        try? await aggregator.refresh()
        BriefingService.update(with: Array(allDays))
    }
}

// MARK: - Components

/// "Nutrition ›" — the one header style used above every card on Today.
struct TodaySectionHeader: View {
    let title: String
    var action: () -> Void = {}

    var body: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        } label: {
            HStack(spacing: 5) {
                // Look the title up first; it may be a localisation key.
                Text(String(localized: String.LocalizationValue(title)))
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.leading, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ScoreRing: View {
    let progress: Double
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, style: StrokeStyle(lineWidth: 14, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.005, min(progress, 1)))
                .stroke(
                    AngularGradient(
                        gradient: Gradient(colors: [color.opacity(0.5), color]),
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: 14, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
        }
    }
}

/// A number that has to fit inside a small ring: never wraps, shrinks if it
/// must, and draws a trailing % as a smaller raised sign so "100%" stays one
/// compact line instead of spilling the sign under the digits.
struct RingValueText: View {
    let text: String
    var size: CGFloat = 14
    var color: Color = Theme.textPrimary

    var body: some View {
        let isPercent = text.hasSuffix("%")
        HStack(alignment: .firstTextBaseline, spacing: 0.5) {
            Text(isPercent ? String(text.dropLast()) : text)
                .font(.system(size: size, weight: .semibold))
            if isPercent {
                Text("%")
                    .font(.system(size: size * 0.62, weight: .semibold))
                    .opacity(0.75)
            }
        }
        .monospacedDigit()
        .foregroundStyle(color)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .fixedSize()
    }
}

/// Formats a duration given in minutes as "45m" or "1h 20m".
func durationText(_ minutes: Double) -> String {
    guard minutes > 0 else { return "—" }
    let total = Int(minutes.rounded())
    let hours = total / 60
    let mins = total % 60
    return hours > 0 ? "\(hours)h \(mins)m" : "\(mins)m"
}

/// A session logged in the app's workout tracker.
struct AppWorkoutCard: View {
    let log: WorkoutLog

    var body: some View {
        HStack(spacing: 13) {
            GlyphTile(glyph: .training)
            VStack(alignment: .leading, spacing: 3) {
                Text(log.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(log.setCount) sets · \(DetailFormat.whole(log.volume)) kg" + (log.averageHeartRate.map { " · \(Int($0.rounded())) bpm" } ?? ""))
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 4)
            Text(durationText(log.duration / 60))
                .font(.metricValue)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .card()
    }
}

struct TrainingCard: View {
    let day: DailyMetrics

    private var subtitleParts: [String] {
        var parts: [String] = []
        if let energy = day.workoutEnergyKcal, energy > 0 {
            parts.append("\(Int(energy.rounded())) kcal")
        }
        if let hr = day.workoutAvgHeartRate, hr > 0 {
            parts.append("avg \(Int(hr.rounded())) bpm")
        }
        if day.workoutCount > 1 {
            parts.append("\(day.workoutCount) sessions")
        }
        return parts
    }

    var body: some View {
        HStack(spacing: 13) {
            GlyphTile(glyph: day.workoutIsResistance ? .training : .activity)

            VStack(alignment: .leading, spacing: 3) {
                Text(day.primaryWorkoutName ?? "Workout")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                if !subtitleParts.isEmpty {
                    Text(subtitleParts.joined(separator: " · "))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 4)

            Text(durationText(day.workoutMinutes ?? 0))
                .font(.metricValue)
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
        }
        .card()
    }
}

struct MetricItem: Identifiable {
    let id = UUID()
    var glyph: Glyph? = nil
    let label: String
    let value: Double?
    let unit: String
    var decimals: Int = 0
    var delta: Double? = nil
    var higherIsBetter: Bool? = nil
    /// Set when the value is from an earlier day because today's isn't in yet.
    var asOf: Date? = nil
}

struct MetricCard: View {
    let item: MetricItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let glyph = item.glyph {
                    GlyphView(glyph, size: 17)
                }
                Text(LocalizedStringKey(item.label))
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                DeltaChip(percent: item.delta, higherIsBetter: item.higherIsBetter)
            }

            if let value = item.value {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(formatted(value))
                        .font(.metricValue)
                        .monospacedDigit()
                        .foregroundStyle(Theme.textPrimary)
                    if !item.unit.isEmpty {
                        Text(LocalizedStringKey(item.unit))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }
            } else {
                Text("—")
                    .font(.metricValue)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .card(padding: 14)
    }

    private func formatted(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(item.decimals)))
    }
}

#Preview {
    TodayView()
        .modelContainer(for: [DailyMetrics.self, Insight.self, WeeklyNarrative.self], inMemory: true)
}


private extension View {
    /// Makes a whole card open its detail page on tap. Dragging on a chart
    /// inside still inspects points rather than navigating.
    func opensDetail(_ route: DetailRoute, path: Binding<NavigationPath>) -> some View {
        contentShape(Rectangle())
            .onTapGesture { path.wrappedValue.append(route) }
    }
}
