//
//  InsightsView.swift
//  RecoverySignal
//
//  Two layers of interpretation: fast, deterministic rule-engine flags at the
//  top, and a slower, richer AI-written weekly narrative below (generated on
//  demand to avoid surprise API costs).
//

import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query(sort: \DailyMetrics.date, order: .reverse) private var allDays: [DailyMetrics]
    @Query(sort: \Insight.date, order: .reverse) private var storedInsights: [Insight]
    @Query(sort: \WeeklyNarrative.generatedAt, order: .reverse) private var narratives: [WeeklyNarrative]
    @Environment(\.modelContext) private var context

    @State private var isGenerating = false
    @State private var errorMessage: String?

    private var recentDays: [DailyMetrics] { Array(allDays.prefix(14)) }

    var body: some View {
        NavigationStack {
            List {
                Section("This week's flags") {
                    let liveInsights = InsightRules.evaluate(recentDays: recentDays)
                    if liveInsights.isEmpty {
                        Text("Nothing flagged right now.").foregroundStyle(.secondary)
                    } else {
                        ForEach(liveInsights, id: \.title) { insight in
                            insightRow(insight)
                        }
                    }
                }

                Section("Weekly narrative") {
                    if let latest = narratives.first {
                        Text(latest.text)
                        Text(latest.generatedAt, style: .relative)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No narrative generated yet.").foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await generateNarrative() }
                    } label: {
                        if isGenerating {
                            ProgressView()
                        } else {
                            Text("Generate weekly narrative")
                        }
                    }
                    .disabled(isGenerating || recentDays.isEmpty)

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Insights")
        }
    }

    @ViewBuilder
    private func insightRow(_ insight: Insight) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                severityIcon(insight.severity)
                Text(insight.title).font(.subheadline).bold()
            }
            Text(insight.detail).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func severityIcon(_ severity: InsightSeverity) -> some View {
        let (symbol, color): (String, Color) = switch severity {
        case .info: ("info.circle", .blue)
        case .notice: ("exclamationmark.circle", .orange)
        case .warning: ("exclamationmark.triangle.fill", .red)
        }
        return Image(systemName: symbol).foregroundStyle(color)
    }

    private func generateNarrative() async {
        isGenerating = true
        errorMessage = nil
        defer { isGenerating = false }

        do {
            let flags = InsightRules.evaluate(recentDays: recentDays)
            let input = NarrativeService.WeekSummaryInput(days: Array(recentDays.prefix(7)), insights: flags)
            let text = try await NarrativeService().generateWeeklyNarrative(input)

            let calendar = Calendar.current
            let weekStart = calendar.date(byAdding: .day, value: -7, to: Date()) ?? Date()
            let narrative = WeeklyNarrative(weekStartDate: weekStart, text: text)
            context.insert(narrative)
            try context.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    InsightsView()
}
