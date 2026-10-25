//
//  TonightPlanCard.swift
//  RecoverySignal2
//
//  Tonight's sleep need and the bedtime that meets it: the need broken into
//  its parts, a bedtime window, a goal switch, wake-time options and a
//  realistic step when the ideal is far from your habit.
//

import SwiftUI

struct TonightPlanCard: View {
    let days: [DailyMetrics]
    /// The short version for Today.
    var compact = false

    @State private var goal = SleepPlanner.goal
    @State private var wakeMode: WakeMode = SleepPlanner.oneOffWake != nil ? .once
        : SleepPlanner.useTypicalWake ? .usual : .everyDay
    @State private var wakeTime: Date = {
        let t = BedtimeAlarm.wakeTime
        return Calendar.current.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 0, second: 0, of: Date()) ?? Date()
    }()
    @State private var onceWakeTime: Date = SleepPlanner.oneOffWake ?? {
        let t = BedtimeAlarm.wakeTime
        return Calendar.current.date(bySettingHour: t.hour ?? 7, minute: t.minute ?? 0, second: 0, of: Date()) ?? Date()
    }()

    enum WakeMode: Hashable { case usual, everyDay, once }
    @State private var syncEnabled = false
    @State private var alarmDenied = false

    var body: some View {
        // Reading the state here makes the plan recompute when a control changes.
        let _ = (goal, wakeMode, wakeTime, onceWakeTime)
        if let plan = SleepPlanner.plan(days: days, goal: goal) {
            compact ? AnyView(compactCard(plan)) : AnyView(fullCard(plan))
        } else {
            Text("Tonight's plan appears once there's a wake time ahead.")
                .font(.footnote).foregroundStyle(Theme.textTertiary).card()
        }
    }

    // MARK: Compact (Today)

    private func compactCard(_ plan: SleepPlanner.Plan) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color(red: 0.07, green: 0.13, blue: 0.36))
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Theme.mint)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 2) {
                Text("IN BED BETWEEN")
                    .font(.system(size: 9, weight: .bold)).tracking(0.8)
                    .foregroundStyle(Theme.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(time(plan.windowStart))
                        .font(.system(size: 17, weight: .semibold))
                    Text("and \(time(plan.windowEnd))")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                }
                .monospacedDigit()
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                Text(plan.wakeSource == .tomorrowOnly
                     ? "Need \(DetailFormat.hoursMinutes(plan.need.total)) · wake \(time(plan.wake)) (set once)"
                     : "Need \(DetailFormat.hoursMinutes(plan.need.total)) · wake \(time(plan.wake))")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textTertiary)
        }
        .card()
    }

    // MARK: Full (Sleep page)

    private func fullCard(_ plan: SleepPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            // Banner
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Theme.mint)
                    Text("TONIGHT").font(.eyebrow).tracking(1.1).foregroundStyle(.white.opacity(0.8))
                    Spacer()
                    Text(SleepNeedModel.baseline.isPersonal ? "PERSONAL BASELINE" : "LEARNING YOUR BASELINE")
                        .font(.system(size: 9, weight: .bold)).tracking(0.7)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(.white.opacity(0.16), in: Capsule())
                }

                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Be in bed by")
                            .font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                        Text(time(plan.windowStart))
                            .font(.system(size: 34, weight: .semibold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("latest \(time(plan.windowEnd))")
                            .font(.system(size: 13, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Wake").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.75))
                        Text(time(plan.wake)).font(.system(size: 24, weight: .semibold)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                    }
                }
                .foregroundStyle(.white)

                timeline(plan)

                HStack(spacing: 0) {
                    bannerStat(DetailFormat.hoursMinutes(plan.need.total), "sleep need")
                    bannerStat(DetailFormat.hoursMinutes(plan.sleepTarget), "target (\(Int(plan.goal.share * 100))%)")
                    bannerStat(DetailFormat.hoursMinutes(plan.timeInBed), "time in bed")
                }
            }
            .padding(18)
            .background(LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.18), Color(red: 0.09, green: 0.16, blue: 0.42)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing))

            VStack(alignment: .leading, spacing: 16) {
                // Goal
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Goal", selection: $goal) {
                        ForEach(SleepPlanner.Goal.allCases) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: goal) { _, new in SleepPlanner.goal = new }
                    Text(LocalizedStringKey(goal.detail)).font(.caption).foregroundStyle(Theme.textTertiary)
                }

                wakeControls(plan)

                bedtimeMath(plan)

                needBreakdown(plan.need)

                // Options
                VStack(alignment: .leading, spacing: 8) {
                    Text("OTHER OPTIONS").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.textTertiary)
                    ForEach(plan.options) { option in
                        HStack {
                            Image(systemName: "bed.double").foregroundStyle(Theme.accent)
                            Text("Bed at \(time(option.bedtime))").monospacedDigit()
                            Spacer()
                            Image(systemName: "sunrise").foregroundStyle(Theme.warn)
                            Text("wake \(time(option.wake))").monospacedDigit()
                        }
                        .font(.subheadline)
                    }
                    if let realistic = plan.realisticBedtime, let share = plan.realisticShare, let habit = plan.typicalBedtime {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: "figure.walk.motion").foregroundStyle(Theme.good)
                            Text("You usually fall asleep around \(time(habit)). If \(time(plan.bedtime)) is too big a jump, aim for \(time(realistic)) tonight — about \(Int((share * 100).rounded()))% of your need — and move earlier over the next few nights.")
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(10)
                        .background(Theme.good.opacity(0.08), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                }

                HStack(spacing: 0) {
                    miniStat(String(localized: "\(Int(plan.latencyMinutes.rounded())) min"), "to fall asleep")
                    miniStat(String(localized: "\(Int(plan.nightWakingMinutes.rounded())) min"), "awake at night")
                    miniStat(plan.consistencyMinutes.map { "±\(Int($0.rounded())) min" } ?? "—", "bedtime spread")
                }

                if let spread = plan.consistencyMinutes, spread > 45 {
                    Label("Your bedtime varies by more than 45 minutes. A steadier schedule improves sleep quality as much as extra hours do.",
                          systemImage: "clock.arrow.2.circlepath")
                        .font(.caption).foregroundStyle(Theme.warn)
                }

                if let late = days.first(where: { Calendar.current.isDateInToday($0.date) })?.lateCaffeineMg, late > 0 {
                    Label("\(Int(late.rounded()))mg of caffeine after 2pm today. Its effects can last 5–6 hours, so it can make it harder to fall asleep or lighten your sleep tonight — the plan above isn't adjusted for it.",
                          systemImage: "cup.and.saucer.fill")
                        .font(.caption).foregroundStyle(Theme.warn)
                }

                HowItWorks(explainer: .sleepPlanner)
            }
            .padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous).strokeBorder(Theme.border, lineWidth: 0.5))
        .sensoryFeedback(.selection, trigger: goal)
    }

    // MARK: Wake time

    private func wakeControls(_ plan: SleepPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WAKE UP").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.textTertiary)
            Picker("Wake time", selection: $wakeMode) {
                Text("Usual").tag(WakeMode.usual)
                Text("Every day").tag(WakeMode.everyDay)
                Text("Just once").tag(WakeMode.once)
            }
            .pickerStyle(.segmented)
            .onChange(of: wakeMode) { _, mode in applyWake(mode) }

            switch wakeMode {
            case .usual:
                Text(plan.wakeSource == .usual
                     ? "Your usual wake time from the last 4 weeks: \(time(plan.wake))."
                     : "Not enough mornings recorded yet — using your every-day wake time, \(time(plan.wake)).")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            case .everyDay:
                DatePicker("Wake up at", selection: $wakeTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                    .onChange(of: wakeTime) { _, t in
                        BedtimeAlarm.wakeTime = Calendar.current.dateComponents([.hour, .minute], from: t)
                        rescheduleAlarm()
                    }
            case .once:
                DatePicker("Wake up at", selection: $onceWakeTime, displayedComponents: .hourAndMinute)
                    .font(.subheadline)
                    .onChange(of: onceWakeTime) { _, _ in applyWake(.once) }
                Text("Only for \(plan.wake.formatted(.dateTime.weekday(.wide))) morning. After that the plan goes back to your usual wake time.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }

            Divider().padding(.vertical, 2)

            Toggle(isOn: Binding(
                get: { syncEnabled },
                set: { newValue in
                    if newValue {
                        Task {
                            let granted = await WakeAlarmSync.enable(days: days)
                            syncEnabled = granted
                            alarmDenied = !granted
                        }
                    } else {
                        WakeAlarmSync.disable()
                        syncEnabled = false
                    }
                }
            )) {
                Label("Sync with a real alarm", systemImage: "alarm.fill")
                    .font(.subheadline)
            }
            .tint(Theme.accent)

            if alarmDenied {
                Text("Alarms aren't allowed for Trace. Turn it on in Settings → Trace → Alarms, then try again.")
                    .font(.caption).foregroundStyle(Theme.warn)
            } else if syncEnabled {
                Text("Sets a real alarm for \(time(plan.wake)) that updates itself whenever the wake time above changes — you won't need to also change it in Clock.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            } else {
                Text("Off. The wake time above only shapes tonight's plan; it doesn't wake you up. Turn this on to have a real alarm follow it automatically.")
                    .font(.caption).foregroundStyle(Theme.textTertiary)
            }
        }
        .sensoryFeedback(.selection, trigger: wakeMode)
        .task { syncEnabled = WakeAlarmSync.isEnabled }
    }

    private func applyWake(_ mode: WakeMode) {
        switch mode {
        case .usual:
            SleepPlanner.oneOffWake = nil
            SleepPlanner.useTypicalWake = true
        case .everyDay:
            SleepPlanner.oneOffWake = nil
            SleepPlanner.useTypicalWake = false
        case .once:
            let clock = Calendar.current.dateComponents([.hour, .minute], from: onceWakeTime)
            SleepPlanner.oneOffWake = SleepPlanner.nextOccurrence(of: clock)
        }
        rescheduleAlarm()
    }

    private func rescheduleAlarm() {
        let days = days
        Task {
            await BedtimeAlarm.reschedule(days: days)
            syncEnabled = WakeAlarmSync.isEnabled
        }
        // The Lock Screen shows tonight's bedtime too.
        BriefingService.update(with: days)
    }

    /// Wake time, minus everything that has to fit before it.
    private func bedtimeMath(_ plan: SleepPlanner.Plan) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW YOUR BEDTIME IS SET").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.textTertiary)
            mathRow("sunrise", Theme.warn, String(localized: "Wake up"), time(plan.wake))
            mathRow("moon.zzz", Theme.accent, String(localized: "Sleep (\(Int(plan.goal.share * 100))% of need, incl. debt)"),
                    "− " + DetailFormat.hoursMinutes(plan.sleepTarget))
            mathRow("eye", Theme.textSecondary, String(localized: "Awake during the night"),
                    "− \(Int(plan.nightWakingMinutes.rounded())) min")
            mathRow("hourglass", Theme.mint,
                    plan.latencyIsPersonal ? String(localized: "Falling asleep (your recent average)")
                                           : String(localized: "Falling asleep (typical, still learning)"),
                    "− \(Int(plan.latencyMinutes.rounded())) min")
            Divider().overlay(Theme.separator)
            mathRow("bed.double.fill", Theme.accentDeep, String(localized: "In bed, lights out"), time(plan.bedtime), bold: true)
        }
    }

    private func mathRow(_ icon: String, _ color: Color, _ label: String, _ value: String, bold: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 13, weight: .semibold)).foregroundStyle(color).frame(width: 20)
            Text(label).font(bold ? .subheadline.weight(.semibold) : .subheadline).foregroundStyle(Theme.textPrimary)
                .lineLimit(2).minimumScaleFactor(0.85)
            Spacer(minLength: 8)
            Text(value).font(bold ? .subheadline.weight(.semibold) : .subheadline).monospacedDigit()
                .foregroundStyle(bold ? Theme.textPrimary : Theme.textSecondary)
        }
    }

    /// Evening-to-morning bar: wind-down, time in bed, wake.
    private func timeline(_ plan: SleepPlanner.Plan) -> some View {
        let start = plan.windowStart.addingTimeInterval(-3600)
        let end = plan.wake.addingTimeInterval(1800)
        let span = end.timeIntervalSince(start)
        return VStack(spacing: 4) {
            GeometryReader { geo in
                let w = geo.size.width
                let x: (Date) -> CGFloat = { CGFloat($0.timeIntervalSince(start) / span) * w }
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.1))
                    Capsule()
                        .fill(LinearGradient(colors: [Theme.accent, Theme.mint], startPoint: .leading, endPoint: .trailing))
                        .frame(width: max(x(plan.wake) - x(plan.bedtime), 4))
                        .offset(x: x(plan.bedtime))
                    Rectangle().fill(.white.opacity(0.35))
                        .frame(width: max(x(plan.windowEnd) - x(plan.windowStart), 2), height: 22)
                        .offset(x: x(plan.windowStart))
                        .blendMode(.plusLighter)
                    if let habit = plan.typicalBedtime, habit > start, habit < end {
                        Rectangle().fill(Theme.warn).frame(width: 2, height: 22).offset(x: x(habit))
                    }
                }
            }
            .frame(height: 16)
            HStack {
                Text(time(start)); Spacer()
                if plan.typicalBedtime != nil {
                    HStack(spacing: 3) { Rectangle().fill(Theme.warn).frame(width: 2, height: 8); Text("usual") }
                    Spacer()
                }
                Text(time(end))
            }
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.white.opacity(0.55))
            .monospacedDigit()
        }
    }

    private func needBreakdown(_ need: SleepNeedModel.Need) -> some View {
        let base = SleepNeedModel.baseline
        return VStack(alignment: .leading, spacing: 8) {
            Text("WHY \(DetailFormat.hoursMinutes(need.total).uppercased())").font(.eyebrow).tracking(0.8).foregroundStyle(Theme.textTertiary)
            GeometryReader { geo in
                let total = max(need.baseline + need.strainExtra + need.debtExtra, 0.1)
                let scale = geo.size.width / total
                HStack(spacing: 2) {
                    segment(need.baseline * scale, Theme.accentDeep)
                    if need.strainExtra > 0 { segment(need.strainExtra * scale, Theme.accent) }
                    if need.debtExtra > 0 { segment(need.debtExtra * scale, Theme.warn) }
                }
                .overlay(alignment: .trailing) {
                    if need.napCredit > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .strokeBorder(Theme.good, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                            .frame(width: min(need.napCredit * scale, geo.size.width), height: 12)
                    }
                }
            }
            .frame(height: 12)
            LegendRow(color: Theme.accentDeep, label: base.isPersonal ? "Your baseline (\(base.nights) restorative nights)" : "Baseline (still learning)",
                      value: DetailFormat.hoursMinutes(need.baseline))
            LegendRow(color: Theme.accent, label: String(localized: "Today's strain"), value: need.strainExtra > 0.01 ? "+" + minutes(need.strainExtra) : "—")
            LegendRow(color: Theme.warn, label: String(localized: "Sleep debt"), value: need.debtExtra > 0.01 ? "+" + minutes(need.debtExtra) : "—")
            LegendRow(color: Theme.good, label: String(localized: "Naps today"), value: need.napCredit > 0.01 ? "−" + minutes(need.napCredit) : "—")
        }
    }

    private func segment(_ width: CGFloat, _ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous).fill(color).frame(width: max(width, 3), height: 12)
    }

    private func bannerStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 15, weight: .semibold)).monospacedDigit().foregroundStyle(.white)
            Text(LocalizedStringKey(label)).font(.system(size: 9)).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func miniStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.system(size: 14, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.textPrimary)
            Text(LocalizedStringKey(label)).font(.system(size: 9)).foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private func minutes(_ hours: Double) -> String {
        let m = Int((hours * 60).rounded())
        return m >= 60 ? DetailFormat.hoursMinutes(hours) : "\(m) min"
    }

    private func time(_ date: Date) -> String { date.formatted(date: .omitted, time: .shortened) }
}
