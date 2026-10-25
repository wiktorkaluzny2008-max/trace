//
//  AdvancedAnalysisSections.swift
//  RecoverySignal2
//
//  The long-horizon models at the bottom of Analysis: energy balance and
//  body composition, heart and fitness, sleep coupling, activity spectrum,
//  mobility and allostatic load. The maths lives in AdvancedModels.swift.
//

import SwiftUI
import Charts

struct AdvancedAnalysisSections: View {
    let days: [DailyMetrics]
    private var profile: BodyProfile { BodyProfile.load() }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            header

            group("Energy balance & body composition", icon: .energy) {
                intakeBalanceCard
                forecastCard
                expenditureCard
            }
            group("Heart & fitness", icon: .heartRate) {
                heartRateRecoveryCard
                vo2Card
            }
            group("Sleep & recovery coupling", icon: .sleep) {
                sleepCouplingCard
            }
            group("Activity spectrum", icon: .activity) {
                activitySpectrumCard
            }
            group("Mobility & gait", icon: .steps) {
                mobilityCard
            }
            group("Wear & tear", icon: .fatigue) {
                allostaticCard
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Rectangle().fill(Theme.separator).frame(height: 1)
                Text("LONG-TERM MODELS")
                    .font(.eyebrow)
                    .tracking(1.2)
                    .foregroundStyle(Theme.fat)
                    .fixedSize()
                Rectangle().fill(Theme.separator).frame(height: 1)
            }
            Text("Research-grade calculations for muscle gain, weight control and longevity. They need weeks to months of data, so some unlock over time.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 8)
    }

    // MARK: - 1. Intake balance

    @ViewBuilder
    private var intakeBalanceCard: some View {
        if let balance = EnergyBalanceModel.intakeBalance(from: days) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(String(localized: "What your body says you ate"), subtitle: String(localized: "Intake-balance method, last \(balance.windowDays) days"))

                HStack(spacing: 0) {
                    bigStat(String(localized: "Implied"), DetailFormat.whole(balance.impliedIntake), "kcal/day", color: Theme.fat)
                    divider
                    bigStat(String(localized: "Logged"), balance.loggedIntake.map { DetailFormat.whole($0) } ?? "—", "kcal/day", color: Theme.accent)
                    divider
                    if let ratio = balance.loggingRatio {
                        bigStat(String(localized: "Log accuracy"), "\(Int((ratio * 100).rounded()))", "%",
                                color: abs(ratio - 1) < 0.1 ? Theme.good : Theme.warn)
                    } else {
                        bigStat(String(localized: "Log accuracy"), "—", "", color: Theme.textTertiary)
                    }
                }

                // Equation strip: expenditure + stored = implied.
                HStack(spacing: 6) {
                    equationChip(String(localized: "Burned"), DetailFormat.whole(balance.expenditure))
                    Text(balance.storagePerDay >= 0 ? "+" : "−").foregroundStyle(Theme.textTertiary)
                    equationChip(balance.storagePerDay >= 0 ? "Stored" : "Released", DetailFormat.whole(abs(balance.storagePerDay)))
                    Text("=").foregroundStyle(Theme.textTertiary)
                    equationChip(String(localized: "Eaten"), DetailFormat.whole(balance.impliedIntake), highlight: true)
                }
                .font(.subheadline.weight(.medium))

                if balance.weeks.count >= 2 {
                    Chart {
                        ForEach(balance.weeks) { week in
                            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("kcal", week.implied))
                                .foregroundStyle(by: .value("Kind", "Implied by body"))
                                .position(by: .value("Kind", "Implied by body"))
                                .cornerRadius(2)
                            if let logged = week.logged {
                                BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("kcal", logged))
                                    .foregroundStyle(by: .value("Kind", "Logged"))
                                    .position(by: .value("Kind", "Logged"))
                                    .cornerRadius(2)
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: ["Implied by body", "Logged"], range: [Theme.fat, Theme.accent])
                    .chartLegend(position: .bottom, alignment: .leading)
                    .chartXAxis { weekAxis }
                    .chartYAxis { trailingAxis }
                    .frame(height: 150)
                }

                footnote(String(localized: "Weight \(DetailFormat.signed(balance.weightChangePerWeek, 2)) kg/week × \(DetailFormat.whole(balance.kcalPerKg)) kcal/kg") +
                         (balance.leanShare.map { " (≈\(Int(($0 * 100).rounded()))% of change as lean tissue)" } ?? "") + ".")
                HowItWorks(explainer: .intakeBalance)
            }
            .card(padding: 18)
        } else {
            locked(.energy, "Needs 4 weeks of weight and Watch energy",
                   "Weigh in at least a few times a week and wear the Watch most days; this works backwards from expenditure and weight change.",
                   .intakeBalance)
        }
    }

    // MARK: - 2. Forecast

    @ViewBuilder
    private var forecastCard: some View {
        let goal = GoalSettings.load()
        let goalIntake = EnergyModel.maintenance(from: days).map { EnergyModel.targets(from: days, maintenance: $0).calories }
        if let forecast = EnergyBalanceModel.forecast(from: days, goalIntake: goal.phase == .maintain ? nil : goalIntake) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(String(localized: "Weight forecast"), subtitle: String(localized: "16 weeks ahead at your current intake, with metabolic adaptation"))

                HStack(spacing: 0) {
                    bigStat(String(localized: "Now"), DetailFormat.decimal(forecast.startWeight), "kg", color: Theme.textPrimary)
                    divider
                    bigStat(String(localized: "In 12 weeks"), forecast.weight(afterWeeks: 12).map { DetailFormat.decimal($0) } ?? "—", "kg", color: Theme.fat)
                    divider
                    bigStat(String(localized: "Plateau"), DetailFormat.decimal(forecast.plateauWeight), "kg", color: Theme.textSecondary)
                }

                Chart {
                    ForEach(forecast.history) { p in
                        PointMark(x: .value("Date", p.date), y: .value("kg", p.value))
                            .symbolSize(14)
                            .foregroundStyle(Theme.accent.opacity(0.5))
                    }
                    ForEach(forecast.points.filter { $0.scenario == EnergyBalanceModel.Forecast.current }) { p in
                        AreaMark(x: .value("Date", p.date), yStart: .value("Low", p.low), yEnd: .value("High", p.high))
                            .foregroundStyle(Theme.fat.opacity(0.15))
                    }
                    ForEach(forecast.points) { p in
                        LineMark(x: .value("Date", p.date), y: .value("kg", p.weight), series: .value("Scenario", p.scenario))
                            .foregroundStyle(p.scenario == EnergyBalanceModel.Forecast.current ? Theme.fat : Theme.good)
                            .lineStyle(StrokeStyle(lineWidth: 2.25, lineCap: .round,
                                                   dash: p.scenario == EnergyBalanceModel.Forecast.current ? [] : [5, 4]))
                    }
                    RuleMark(x: .value("Today", Calendar.current.startOfDay(for: Date())))
                        .foregroundStyle(Theme.separator)
                        .annotation(position: .top, alignment: .leading) {
                            Text("today").font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
                        }
                }
                .chartYScale(domain: domain(forecast.history.map(\.value) + forecast.points.flatMap { [$0.low, $0.high] }, pad: 0.4))
                .chartXAxis { monthAxis }
                .chartYAxis { trailingAxis }
                .frame(height: 170)

                HStack(spacing: 14) {
                    ChartLegendKey(kind: .dot, color: Theme.accent.opacity(0.5), label: String(localized: "Weigh-ins"))
                    ChartLegendKey(kind: .line, color: Theme.fat, label: String(localized: "\(DetailFormat.whole(forecast.intake)) kcal"))
                    if let goalIntake = forecast.goalIntake {
                        ChartLegendKey(kind: .line, color: Theme.good, label: String(localized: "Goal \(DetailFormat.whole(goalIntake)) kcal"))
                    }
                }

                footnote(String(localized: "Eating \(DetailFormat.whole(abs(forecast.imbalance))) kcal/day \(forecast.imbalance >= 0 ? String(localized: "above") : String(localized: "below")) expenditure. Half the move to the plateau takes about \(Int((forecast.halfLifeDays / 30).rounded())) months — which is why progress slows even when you stick to the plan."))
                HowItWorks(explainer: .weightForecast)
            }
            .card(padding: 18)
        } else {
            locked(.body, "Needs a week of weigh-ins and logged food",
                   "The forecast starts from your trend weight and the last two weeks of intake.", .weightForecast)
        }
    }

    // MARK: - 3. Expenditure

    @ViewBuilder
    private var expenditureCard: some View {
        if let breakdown = ExpenditureModel.breakdown(from: days) {
            let parts: [(String, Double, Color)] = [
                ("Resting", breakdown.recent.resting, Theme.textSecondary.opacity(0.55)),
                ("NEAT", breakdown.recent.neat, Theme.activity),
                ("Exercise", breakdown.recent.exercise, Theme.accent),
                ("Digestion", breakdown.recent.digestion, Theme.protein)
            ]
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(String(localized: "Where your calories go"), subtitle: String(localized: "Average per day, last 14 days"))

                HStack(alignment: .center, spacing: 16) {
                    Chart(parts, id: \.0) { part in
                        SectorMark(angle: .value("kcal", part.1), innerRadius: .ratio(0.62), angularInset: 1.5)
                            .foregroundStyle(part.2)
                            .cornerRadius(3)
                    }
                    .frame(width: 118, height: 118)
                    .overlay {
                        VStack(spacing: 0) {
                            Text(DetailFormat.whole(breakdown.recent.total))
                                .font(.system(size: 20, weight: .semibold))
                                .monospacedDigit()
                            Text("kcal/day").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        ForEach(parts, id: \.0) { part in
                            LegendRow(color: part.2, label: part.0,
                                      value: "\(DetailFormat.whole(part.1)) · \(Int((part.1 / max(breakdown.recent.total, 1) * 100).rounded()))%")
                        }
                    }
                }

                if breakdown.weeks.count >= 2 {
                    Chart {
                        ForEach(breakdown.weeks) { week in
                            ForEach([("Resting", week.resting), ("NEAT", week.neat), ("Exercise", week.exercise), ("Digestion", week.digestion)], id: \.0) { part in
                                BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("kcal", part.1))
                                    .foregroundStyle(by: .value("Part", part.0))
                            }
                        }
                    }
                    .chartForegroundStyleScale(domain: parts.map(\.0), range: parts.map(\.2))
                    .chartLegend(.hidden)
                    .chartXAxis { weekAxis }
                    .chartYAxis { trailingAxis }
                    .frame(height: 130)
                }

                if let change = breakdown.neatChange {
                    HStack(spacing: 10) {
                        GlyphTile(glyph: .steps, color: change < -15 ? Theme.warn : Theme.good, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("NEAT \(DetailFormat.signed(change, 0))% vs the 6 weeks before")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Text(change < -15
                                 ? "Everyday movement has dropped — a common, mostly unconscious response to eating less. Extra steps win it back."
                                 : "Everyday movement is holding steady, so your deficit or surplus isn't being quietly offset.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                HowItWorks(explainer: .expenditure)
            }
            .card(padding: 18)
        } else {
            locked(.energy, "Needs a couple of weeks of Watch energy",
                   "Splits your resting and active energy into what you burn at rest, in workouts, in everyday movement and digesting food.",
                   .expenditure)
        }
    }

    // MARK: - 4. Heart-rate recovery

    @ViewBuilder
    private var heartRateRecoveryCard: some View {
        if let hrr = HeartRateRecoveryModel.summary(from: days) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    cardTitle(String(localized: "Heart-rate recovery"), subtitle: String(localized: "Drop in the first minute after workouts"))
                    Spacer()
                    pill(hrr.band.label, color: hrr.band.color)
                }
                HStack(spacing: 0) {
                    bigStat(String(localized: "60-day average"), DetailFormat.whole(hrr.recentAverage), "bpm", color: Theme.textPrimary)
                    divider
                    bigStat(String(localized: "Latest"), DetailFormat.whole(hrr.latest.value), "bpm", color: Theme.textPrimary)
                    divider
                    if let previous = hrr.previousAverage {
                        bigStat(String(localized: "vs before"), DetailFormat.signed(hrr.recentAverage - previous, 0), "bpm",
                                color: hrr.recentAverage >= previous ? Theme.good : Theme.warn)
                    } else {
                        bigStat(String(localized: "vs before"), "—", "", color: Theme.textTertiary)
                    }
                }
                ZoneScale(value: hrr.recentAverage, range: 0...45,
                          zones: [(12, Theme.bad), (21, Theme.warn), (30, Theme.good), (45, Theme.good.opacity(0.7))],
                          labels: ["12", "21", "30"])
                if hrr.points.count >= 2 {
                    SparseLineChart(history: hrr.points, range: .year, style: ValueStyle(unit: "bpm"), height: 110)
                }
                HowItWorks(explainer: .heartRateRecovery)
            }
            .card(padding: 18)
        } else {
            locked(.heartRate, "Needs a workout recorded on the Watch",
                   "Apple Watch logs your 1-minute heart-rate recovery after sessions started in the Workout app. Lifting logged only in Hevy won't create it.",
                   .heartRateRecovery)
        }
    }

    // MARK: - 5. VO₂ max

    @ViewBuilder
    private var vo2Card: some View {
        if let fitness = FitnessModel.summary(from: days, profile: profile) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    cardTitle(String(localized: "VO₂ max & fitness age"),
                              subtitle: fitness.age.map { "Compared with \(fitness.female ? "women" : "men") aged \($0)" } ?? "Add your age in Health for a precise comparison")
                    Spacer()
                    pill(fitness.category.label, color: fitness.category.color)
                }

                HStack(spacing: 0) {
                    bigStat(String(localized: "VO₂ max"), DetailFormat.decimal(fitness.latest.value), "ml/kg/min", color: Theme.textPrimary)
                    divider
                    if let fitnessAge = fitness.fitnessAge {
                        bigStat(String(localized: "Fitness age"), "\(fitnessAge)", "yrs",
                                color: (fitness.age.map { fitnessAge <= $0 } ?? true) ? Theme.good : Theme.warn)
                    }
                    divider
                    bigStat(String(localized: "Per year"), fitness.changePerYear.map { DetailFormat.signed($0) } ?? "—", "", color: Theme.textSecondary)
                }

                ZoneScale(value: fitness.latest.value,
                          range: (fitness.thresholds[0] - 8)...(fitness.thresholds[3] + 8),
                          zones: [(fitness.thresholds[0], Theme.bad), (fitness.thresholds[1], Theme.warn),
                                  (fitness.thresholds[2], Theme.accent), (fitness.thresholds[3], Theme.good),
                                  (fitness.thresholds[3] + 8, Theme.good.opacity(0.7))],
                          labels: FitnessModel.Category.allCases.map(\.label))

                if fitness.points.count >= 2 {
                    SparseLineChart(history: fitness.points, range: .year, style: ValueStyle(unit: "ml/kg/min", decimals: 1), height: 110)
                }
                HowItWorks(explainer: .vo2Max)
            }
            .card(padding: 18)
        } else {
            locked(.lungs, "Needs a VO₂ max estimate",
                   "Apple Watch estimates VO₂ max after outdoor walks, runs or hikes of 20+ minutes with GPS.", .vo2Max)
        }
    }

    // MARK: - 6. Sleep coupling

    @ViewBuilder
    private var sleepCouplingCard: some View {
        if let result = SleepCouplingModel.analyse(from: days) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(String(localized: "How sleep moves your body"), subtitle: String(localized: "Correlations in your own last 120 days"))

                HStack(spacing: 0) {
                    bigStat(String(localized: "Deep"), result.deepShare.map { "\(Int($0.rounded()))" } ?? "—", "%", color: Theme.accentDeep)
                    divider
                    bigStat(String(localized: "REM"), result.remShare.map { "\(Int($0.rounded()))" } ?? "—", "%", color: Theme.mint)
                    divider
                    bigStat(String(localized: "Efficiency"), result.efficiency.map { "\(Int($0.rounded()))" } ?? "—", "%", color: Theme.textPrimary)
                }

                if result.scatter.count >= 14 {
                    let xs = result.scatter.map(\.x), ys = result.scatter.map(\.y)
                    let fit = Regression.fit(xs, ys)
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Deep sleep vs next-morning HRV")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        Chart {
                            ForEach(Array(result.scatter.enumerated()), id: \.offset) { _, p in
                                PointMark(x: .value("Deep min", p.x), y: .value("HRV", p.y))
                                    .symbolSize(26)
                                    .foregroundStyle(Theme.accentDeep.opacity(0.55))
                            }
                            if let fit, let lo = xs.min(), let hi = xs.max() {
                                LineMark(x: .value("Deep min", lo), y: .value("HRV", fit.intercept + fit.slope * lo), series: .value("S", "fit"))
                                    .foregroundStyle(Theme.fat)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                                LineMark(x: .value("Deep min", hi), y: .value("HRV", fit.intercept + fit.slope * hi), series: .value("S", "fit"))
                                    .foregroundStyle(Theme.fat)
                                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [5, 3]))
                            }
                        }
                        .chartYScale(domain: domain(ys, pad: 3))
                        .chartXScale(domain: domain(xs, pad: 5))
                        .chartXAxis {
                            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                                AxisGridLine().foregroundStyle(Theme.separator.opacity(0.5))
                                AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                            }
                        }
                        .chartYAxis { trailingAxis }
                        .frame(height: 150)
                        HStack {
                            Text("minutes of deep sleep →").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                            Spacer()
                            Text("HRV ms ↑").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        }
                    }
                }

                VStack(spacing: 10) {
                    ForEach(result.couplings) { coupling in
                        CouplingRow(coupling: coupling)
                    }
                }
                HowItWorks(explainer: .sleepCoupling)
            }
            .card(padding: 18)
        } else {
            locked(.sleep, "Needs 2 weeks of sleep with HRV",
                   "Looks for links between your sleep and next-day HRV, heart rate, movement and appetite.", .sleepCoupling)
        }
    }

    // MARK: - 7. Activity spectrum

    @ViewBuilder
    private var activitySpectrumCard: some View {
        if let spectrum = ActivitySpectrumModel.summary(from: days) {
            let minutes = spectrum.last7.moderateEquivalent
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    cardTitle(String(localized: "Intensity minutes"), subtitle: spectrum.source == .heartRate ? "From your heart rate, per week" : "From Apple's exercise minutes, per week")
                    Spacer()
                    pill(minutes >= 300 ? "Optimal" : (minutes >= 150 ? "Guideline met" : "Below guideline"),
                         color: minutes >= 150 ? Theme.good : Theme.warn)
                }

                HStack(alignment: .center, spacing: 16) {
                    ZStack {
                        ProgressRing(fraction: minutes / 150, color: Theme.good, lineWidth: 10)
                        VStack(spacing: 0) {
                            Text(DetailFormat.whole(minutes))
                                .font(.system(size: 22, weight: .semibold))
                                .monospacedDigit()
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Text("of 150").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                        }
                        .padding(.horizontal, 14)
                    }
                    .frame(width: 104, height: 104)

                    VStack(alignment: .leading, spacing: 7) {
                        LegendRow(color: Theme.mint.opacity(0.6), label: String(localized: "Light"), value: "\(DetailFormat.whole(spectrum.last7.light)) min")
                        LegendRow(color: Theme.accent, label: String(localized: "Moderate"), value: "\(DetailFormat.whole(spectrum.last7.moderate)) min")
                        LegendRow(color: Theme.fat, label: String(localized: "Vigorous ×2"), value: "\(DetailFormat.whole(spectrum.last7.vigorous)) min")
                        Text("Last 7 days · moderate-equivalent")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Chart {
                    ForEach(spectrum.weeks) { week in
                        ForEach([("Light", week.light), ("Moderate", week.moderate), ("Vigorous", week.vigorous)], id: \.0) { part in
                            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("min", part.1))
                                .foregroundStyle(by: .value("Intensity", part.0))
                        }
                    }
                    RuleMark(y: .value("Guideline", 150))
                        .foregroundStyle(Theme.good)
                        .lineStyle(StrokeStyle(lineWidth: 1.25, dash: [5, 3]))
                        .annotation(position: .top, alignment: .leading, spacing: 2) {
                            Text("WHO 150").font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.good)
                        }
                }
                .chartForegroundStyleScale(domain: ["Light", "Moderate", "Vigorous"], range: [Theme.mint.opacity(0.6), Theme.accent, Theme.fat])
                .chartLegend(.hidden)
                .chartXAxis { weekAxis }
                .chartYAxis { trailingAxis }
                .frame(height: 150)

                HowItWorks(explainer: .activitySpectrum)
            }
            .card(padding: 18)
        } else {
            locked(.activity, "Needs heart-rate or exercise-minute data",
                   "Splits your week into light, moderate and vigorous minutes and checks it against the WHO guideline.",
                   .activitySpectrum)
        }
    }

    // MARK: - 8. Mobility

    @ViewBuilder
    private var mobilityCard: some View {
        if let mobility = MobilityModel.summary(from: days) {
            VStack(alignment: .leading, spacing: 14) {
                cardTitle(String(localized: "How you walk"), subtitle: String(localized: "Measured by your iPhone · last 30 days"))

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(mobility.metrics) { metric in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(LocalizedStringKey(metric.label))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                            HStack(alignment: .firstTextBaseline, spacing: 3) {
                                Text(metric.value.formatted(.number.precision(.fractionLength(metric.decimals))))
                                    .font(.system(size: 21, weight: .semibold))
                                    .monospacedDigit()
                                Text(LocalizedStringKey(metric.unit)).font(.caption).foregroundStyle(Theme.textTertiary)
                                if let previous = metric.previous, previous != 0 {
                                    DeltaChip(percent: (metric.value - previous) / previous * 100, higherIsBetter: metric.higherIsBetter)
                                }
                            }
                            Text(LocalizedStringKey(metric.verdict))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(metric.color)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Theme.background, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                }

                if mobility.speedWeeks.count >= 3 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Walking speed, weekly average")
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                        SparseLineChart(history: mobility.speedWeeks, range: .year, style: ValueStyle(unit: "km/h", decimals: 1), height: 110)
                    }
                }
                HowItWorks(explainer: .mobility)
            }
            .card(padding: 18)
        } else {
            locked(.steps, "Needs walking data from your iPhone",
                   "Carry your iPhone in a pocket while walking; it records speed, step length, asymmetry and steadiness automatically.",
                   .mobility)
        }
    }

    // MARK: - 9. Allostatic load

    @ViewBuilder
    private var allostaticCard: some View {
        if let load = AllostaticLoadModel.summary(from: days) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    cardTitle(String(localized: "Allostatic load"), subtitle: String(localized: "Wear and tear across \(load.components.count) systems, vs your own year"))
                    Spacer()
                    pill(load.label, color: load.color)
                }

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(DetailFormat.signed(load.index, 2))
                        .font(.system(size: 34, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(load.color)
                    Text("SD").font(.subheadline.weight(.medium)).foregroundStyle(Theme.textTertiary)
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(load.highRiskCount) of \(load.components.count)")
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                        Text("in their worst quartile").font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
                    }
                }

                VStack(spacing: 8) {
                    ForEach(load.components) { component in
                        HStack(spacing: 10) {
                            Text(LocalizedStringKey(component.label))
                                .font(.caption)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 96, alignment: .leading)
                            // ZScoreBar draws positive as good, so flip: here positive is wear.
                            ZScoreBar(z: -component.z)
                            Image(systemName: component.inWorstQuartile ? "exclamationmark.circle.fill" : "circle")
                                .font(.caption)
                                .foregroundStyle(component.inWorstQuartile ? Theme.warn : Theme.separator)
                        }
                    }
                }

                if load.weeks.count >= 4 {
                    Chart {
                        ForEach(load.weeks) { week in
                            BarMark(x: .value("Week", week.date, unit: .weekOfYear), y: .value("Index", week.value))
                                .foregroundStyle(week.value > 0.5 ? Theme.warn : (week.value < 0 ? Theme.good.opacity(0.7) : Theme.accent.opacity(0.6)))
                                .cornerRadius(2)
                        }
                        RuleMark(y: .value("Zero", 0)).foregroundStyle(Theme.separator)
                    }
                    .chartXAxis { monthAxis }
                    .chartYAxis { trailingAxis }
                    .frame(height: 120)
                    footnote(String(localized: "Weekly index. Bars below zero are weeks with less wear than your normal."))
                }
                HowItWorks(explainer: .allostaticLoad)
            }
            .card(padding: 18)
        } else {
            locked(.fatigue, "Needs about 2 months of history",
                   "Compares resting HR, HRV, heart-rate recovery, sleep, active minutes and breathing rate with your own long-term weekly normal.",
                   .allostaticLoad)
        }
    }

    // MARK: - Pieces

    private func group<Content: View>(_ title: String, icon: Glyph, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: title, icon: icon)
            content()
        }
    }

    private func cardTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(subtitle))
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func bigStat(_ label: String, _ value: String, _ unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 20, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(LocalizedStringKey(unit)).font(.system(size: 9, weight: .medium)).foregroundStyle(Theme.textTertiary).lineLimit(1)
                }
            }
            Text(LocalizedStringKey(label)).font(.system(size: 10)).foregroundStyle(Theme.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private var divider: some View {
        Rectangle().fill(Theme.separator).frame(width: 1, height: 30)
    }

    private func equationChip(_ label: String, _ value: String, highlight: Bool = false) -> some View {
        VStack(spacing: 1) {
            Text(value).monospacedDigit().foregroundStyle(highlight ? Theme.fat : Theme.textPrimary)
            Text(LocalizedStringKey(label)).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background((highlight ? Theme.fat : Theme.textTertiary).opacity(0.08),
                    in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(LocalizedStringKey(text))
            .font(.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(color.opacity(0.13), in: Capsule())
            .fixedSize()
    }

    private func footnote(_ text: String) -> some View {
        Text(LocalizedStringKey(text))
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func locked(_ icon: Glyph, _ title: String, _ message: String, _ explainer: Explainer) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 13) {
                GlyphView(icon, size: 26, palette: .muted)
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(LocalizedStringKey(message))
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            HowItWorks(explainer: explainer)
        }
        .card()
    }

    private func domain(_ values: [Double], pad: Double) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        return (lo - pad)...(hi + pad)
    }

    private var weekAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisValueLabel(format: .dateTime.day().month(.abbreviated))
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var monthAxis: some AxisContent {
        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
            AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.system(size: 10))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    private var trailingAxis: some AxisContent {
        AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
            AxisGridLine().foregroundStyle(Theme.separator.opacity(0.7))
            AxisValueLabel().font(.system(size: 10)).foregroundStyle(Theme.textTertiary)
        }
    }
}

// MARK: - Components

/// One correlation as a sentence with a signed strength bar.
private struct CouplingRow: View {
    let coupling: SleepCouplingModel.Coupling

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("\(coupling.cause) → \(coupling.effect)")
                    .font(.caption)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("r \(DetailFormat.signed(coupling.r, 2))")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textSecondary)
            }
            GeometryReader { geo in
                let half = geo.size.width / 2
                let width = min(abs(coupling.r), 1) * half
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.track)
                    Rectangle().fill(Theme.separator).frame(width: 1).offset(x: half)
                    Capsule()
                        .fill(coupling.isSignificant ? Theme.fat : Theme.fat.opacity(0.35))
                        .frame(width: max(2, width))
                        .offset(x: coupling.r < 0 ? half - width : half)
                }
            }
            .frame(height: 6)
            Text("\(coupling.sentence) \(coupling.strength.capitalized), \(coupling.isSignificant ? "significant" : "not significant yet") · n=\(coupling.n)")
                .font(.caption)
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Horizontal scale split into coloured zones with a marker for your value.
struct ZoneScale: View {
    let value: Double
    let range: ClosedRange<Double>
    /// Upper bound of each zone and its colour, ascending.
    let zones: [(Double, Color)]
    var labels: [String] = []

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                let width = geo.size.width
                let span = range.upperBound - range.lowerBound
                let lowerBound = range.lowerBound, upperBound = range.upperBound
                let x: (Double) -> CGFloat = { v in CGFloat((min(max(v, lowerBound), upperBound) - lowerBound) / span) * width }

                ZStack(alignment: .leading) {
                    HStack(spacing: 2) {
                        ForEach(Array(zones.enumerated()), id: \.offset) { i, zone in
                            let lower = i == 0 ? range.lowerBound : zones[i - 1].0
                            Rectangle()
                                .fill(zone.1.opacity(0.45))
                                .frame(width: max(0, x(zone.0) - x(lower) - 2))
                        }
                    }
                    .clipShape(Capsule())

                    Circle()
                        .fill(Theme.surface)
                        .overlay(Circle().strokeBorder(Theme.textPrimary, lineWidth: 2.5))
                        .frame(width: 16, height: 16)
                        .offset(x: min(max(x(value) - 8, 0), width - 16))
                }
            }
            .frame(height: 16)

            if labels.count == zones.count {
                HStack(spacing: 0) {
                    ForEach(labels, id: \.self) { label in
                        Text(LocalizedStringKey(label))
                            .font(.system(size: 9))
                            .foregroundStyle(Theme.textTertiary)
                            .frame(maxWidth: .infinity)
                    }
                }
            } else if !labels.isEmpty {
                GeometryReader { geo in
                    let span = range.upperBound - range.lowerBound
                    ForEach(Array(labels.enumerated()), id: \.offset) { i, label in
                        if i < zones.count {
                            Text(LocalizedStringKey(label))
                                .font(.system(size: 9))
                                .foregroundStyle(Theme.textTertiary)
                                .position(x: CGFloat((zones[i].0 - range.lowerBound) / span) * geo.size.width, y: 5)
                        }
                    }
                }
                .frame(height: 10)
            }
        }
    }
}
