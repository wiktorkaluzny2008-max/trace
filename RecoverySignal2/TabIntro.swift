//
//  TabIntro.swift
//  RecoverySignal2
//
//  Today, Trends and Analysis answer three different questions. The ⓘ in the
//  corner of each opens a guide comparing all three.
//

import SwiftUI

enum AppTab: CaseIterable, Identifiable {
    case today, trends, analysis

    var id: Self { self }

    var name: String {
        switch self {
        case .today:    String(localized: "Today")
        case .trends:   String(localized: "Trends")
        case .analysis: String(localized: "Analysis")
        }
    }

    var tag: String {
        switch self {
        case .today:    String(localized: "NOW")
        case .trends:   String(localized: "OVER TIME")
        case .analysis: String(localized: "WHY")
        }
    }

    var question: String {
        switch self {
        case .today:    String(localized: "How am I doing right now?")
        case .trends:   String(localized: "How has each number moved?")
        case .analysis: String(localized: "Why is it moving, and where is it heading?")
        }
    }

    var summary: String {
        switch self {
        case .today:
            String(localized: "This morning's readings, scored against your own normal, with what to do about them today.")
        case .trends:
            String(localized: "The history of one metric at a time, drawn the way that suits it. Pick a range on any chart.")
        case .analysis:
            String(localized: "Models that combine several metrics — training load, fatigue, energy balance, fitness and long-term health markers.")
        }
    }

    var details: [String] {
        switch self {
        case .today:
            ["Recovery, strain and sleep need for today",
             "Last night's sleep, today's activity, food and weight",
             "Tap any card for its full page"]
        case .trends:
            ["One chart per metric, from 7 days to a year",
             "Averages and comparisons with longer periods",
             "No modelling — just what was measured"]
        case .analysis:
            ["Calculations that need weeks or months of data",
             "Energy balance, weight forecast, fitness age, wear-and-tear score",
             "Every card explains its formula and its limits"]
        }
    }

    var timeScale: String {
        switch self {
        case .today:    String(localized: "Last 24 hours")
        case .trends:   String(localized: "Days to a year")
        case .analysis: String(localized: "Weeks to months")
        }
    }

    var color: Color {
        switch self {
        case .today:    Theme.accent
        case .trends:   Theme.carbs
        case .analysis: Theme.fat
        }
    }
}

/// The ⓘ in a tab's top corner. It opens the guide to Today, Trends and
/// Analysis with the current tab highlighted, so the pages themselves stay
/// free of explanatory banners.
struct TabInfoButton: View {
    /// Draws its own round background, for use outside a navigation bar.
    var filled = false
    @Environment(\.tabNavigator) private var navigator

    var body: some View {
        Button {
            navigator.showGuide()
        } label: {
            Image(systemName: "info")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: filled ? 34 : nil, height: filled ? 34 : nil)
                .background {
                    if filled {
                        Circle().fill(Theme.surface)
                            .overlay(Circle().strokeBorder(Theme.border, lineWidth: 0.5))
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("About this page")
    }
}

struct TabGuideSheet: View {
    /// The tab showing behind this sheet; nil when it's Insights or Settings.
    let current: AppTab?
    /// Switches the tab behind the sheet, so closing it lands you there.
    var onSelect: (AppTab) -> Void = { _ in }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Three tabs, three questions. Today tells you what to do now, Trends shows what happened, Analysis explains why and predicts what's next.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 6) {
                        Image(systemName: "hand.tap")
                        Text("Tap a tab to switch to it — you'll be there when you close this.")
                    }
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.accent)

                    ForEach(AppTab.allCases) { tab in
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(LocalizedStringKey(tab.name))
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(Theme.textPrimary)
                                Text(LocalizedStringKey(tab.tag))
                                    .font(.system(size: 10, weight: .bold))
                                    .tracking(1)
                                    .foregroundStyle(tab.color)
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 3)
                                    .background(tab.color.opacity(0.13), in: Capsule())
                                Spacer()
                                if tab == current {
                                    Label("You're here", systemImage: "checkmark.circle.fill")
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundStyle(tab.color)
                                        .transition(.scale.combined(with: .opacity))
                                } else {
                                    HStack(spacing: 3) {
                                        Text("Switch")
                                        Image(systemName: "arrow.right")
                                    }
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Theme.textTertiary)
                                }
                            }
                            Text(LocalizedStringKey(tab.question))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(tab.color)
                            Text(LocalizedStringKey(tab.summary))
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            VStack(alignment: .leading, spacing: 5) {
                                ForEach(tab.details, id: \.self) { line in
                                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                                        Circle().fill(tab.color).frame(width: 5, height: 5)
                                        Text(line)
                                            .font(.footnote)
                                            .foregroundStyle(Theme.textPrimary)
                                    }
                                }
                            }
                            HStack(spacing: 5) {
                                Image(systemName: "clock")
                                Text("Time scale: \(tab.timeScale)")
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Theme.textTertiary)
                        }
                        .card()
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                                .strokeBorder(tab == current ? tab.color : .clear, lineWidth: 1.5)
                        )
                        .scaleEffect(tab == current ? 1 : 0.985)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            guard tab != current else { return }
                            withAnimation(.snappy) { onSelect(tab) }
                        }
                        .accessibilityAddTraits(.isButton)
                        .accessibilityHint(tab == current ? String(localized: "Current tab") : String(localized: "Switches to \(tab.name)"))
                    }
                }
                .padding(18)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Today, Trends, Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
