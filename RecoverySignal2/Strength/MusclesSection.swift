//
//  MusclesSection.swift
//  RecoverySignal2
//
//  The "Muscles" section on Trends: a week picker, the volume radar, the
//  front/back body map, and importing Hevy workouts from screenshots.
//

import SwiftUI
import SwiftData
import PhotosUI

struct MusclesSection: View {
    @Query(sort: \StrengthSession.date, order: .reverse) private var sessions: [StrengthSession]
    @Environment(\.modelContext) private var context

    @State private var weekOffset = 0
    @State private var showImporter = false

    private var calendar: Calendar { .current }

    private var weekStart: Date {
        let base = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? Date()
        return calendar.date(byAdding: .weekOfYear, value: weekOffset, to: base) ?? base
    }

    private var weekSessions: [StrengthSession] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: weekStart) else { return [] }
        return sessions.filter { week.contains($0.date) }
    }

    private var weeklySets: [Muscle: Double] {
        MuscleVolume.weeklySets(sessions: sessions, weekContaining: weekStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Muscles", icon: .training)

            VStack(alignment: .leading, spacing: 16) {
                weekPicker

                if weekSessions.isEmpty {
                    emptyState
                } else {
                    MuscleRadar(sets: weeklySets)
                        .frame(maxWidth: .infinity)

                    Divider().overlay(Theme.separator)

                    BodyMap(sets: weeklySets)
                        .frame(height: 280)
                    BodyMapLegend()

                    Text("Hard sets per muscle this week. Warm-ups don't count; a muscle gets a full set when it's the main target and half a set when it assists. Around 10–20 sets a week is the usual range for growth.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                importButton

                if !weekSessions.isEmpty {
                    sessionList
                }
            }
            .card(padding: 16)
        }
        .sheet(isPresented: $showImporter) {
            HevyImportView()
        }
    }

    private var weekPicker: some View {
        HStack {
            Button { weekOffset -= 1 } label: {
                Image(systemName: "chevron.left").font(.system(size: 14, weight: .semibold))
            }
            Spacer()
            VStack(spacing: 1) {
                Text(weekTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(weekSessions.count) workout\(weekSessions.count == 1 ? "" : "s") · \(weekSessions.reduce(0) { $0 + $1.hardSets }) hard sets")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.textTertiary)
            }
            Spacer()
            Button { weekOffset += 1 } label: {
                Image(systemName: "chevron.right").font(.system(size: 14, weight: .semibold))
            }
            .disabled(weekOffset >= 0)
        }
        .tint(Theme.accent)
    }

    private var weekTitle: String {
        switch weekOffset {
        case 0:  return "This week"
        case -1: return "Last week"
        default:
            let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            return "\(weekStart.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            GlyphView(.training, size: 36, palette: .muted)
            Text("No workouts imported for this week")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("After a session, screenshot the workout summary in Hevy and import it here. The radar and body map fill in from the sets.")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var importButton: some View {
        Button { showImporter = true } label: {
            Label("Import Hevy workout", systemImage: "square.and.arrow.down")
                .font(.subheadline.weight(.semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(.white)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sessionList: some View {
        VStack(spacing: 0) {
            ForEach(weekSessions) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text("\(session.date.formatted(.dateTime.weekday(.wide).day().month())) · \(session.exercises.count) exercises · \(session.hardSets) sets")
                            .font(.caption)
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Spacer()
                    Menu {
                        Button("Delete", role: .destructive) {
                            context.delete(session)
                            try? context.save()
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .foregroundStyle(Theme.textTertiary)
                            .frame(width: 30, height: 30)
                    }
                }
                .padding(.vertical, 8)
                if session.id != weekSessions.last?.id {
                    Divider().overlay(Theme.separator)
                }
            }
        }
    }
}

// MARK: - Import flow

struct HevyImportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var photoItems: [PhotosPickerItem] = []
    @State private var isReading = false
    @State private var errorMessage: String?
    @State private var workout: ImportedWorkout?
    @State private var date = Date()
    @State private var title = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if workout == nil {
                        instructions
                    }

                    if isReading {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Reading your workout…")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .card(padding: 20)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(Theme.bad)
                            .card()
                    }

                    if workout != nil {
                        review
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 32)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Import from Hevy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if workout != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { save() }
                            .disabled(workout?.exercises.isEmpty ?? true)
                    }
                }
            }
            .onChange(of: photoItems) { _, items in
                guard !items.isEmpty else { return }
                Task { await read(items) }
            }
        }
        .tint(Theme.accent)
    }

    private var instructions: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 8) {
                step(1, "Open the workout in Hevy (Profile → the workout).")
                step(2, "Screenshot it. For long workouts, scroll and take more screenshots — pick them all together.")
                step(3, "Choose the screenshots below. You'll check the result before anything is saved.")
            }

            PhotosPicker(selection: $photoItems, maxSelectionCount: 8, matching: .screenshots) {
                Label("Choose screenshots", systemImage: "photo.stack")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                    .foregroundStyle(.white)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isReading)
        }
        .card(padding: 16)
    }

    private func step(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Theme.accentDeep)
                .frame(width: 22, height: 22)
                .background(Theme.accent.opacity(0.12), in: Circle())
            Text(text)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var review: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Workout name", text: $title)
                .font(.headline)
            DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
                .font(.subheadline)
        }
        .card(padding: 16)

        SectionLabel(text: "Check what was read", icon: .training)

        VStack(spacing: 0) {
            ForEach(workout?.exercises ?? []) { exercise in
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(exercise.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                        Text(setSummary(exercise))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(Theme.textSecondary)
                        Text(muscleSummary(exercise))
                            .font(.caption2)
                            .foregroundStyle(Theme.accentDeep)
                    }
                    Spacer()
                    Button {
                        workout?.exercises.removeAll { $0.id == exercise.id }
                    } label: {
                        Image(systemName: "minus.circle")
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 10)
                if exercise.id != workout?.exercises.last?.id {
                    Divider().overlay(Theme.separator)
                }
            }
        }
        .card(padding: 14)

        Text("Remove anything that was misread, then tap Save. Importing the same workout again replaces it.")
            .font(.caption2)
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, 4)
    }

    private func setSummary(_ exercise: ImportedExercise) -> String {
        let hard = exercise.sets.filter(\.isHardSet)
        let warmups = exercise.sets.count - hard.count
        let detail = hard.map { set -> String in
            let reps = set.reps.map { "\(Int($0))" } ?? "–"
            guard let kg = set.weightKg else { return "\(reps) reps" }
            return "\(kg.formatted(.number.precision(.fractionLength(0...1))))kg×\(reps)"
        }.joined(separator: ", ")
        return "\(hard.count) set\(hard.count == 1 ? "" : "s")\(warmups > 0 ? " (+\(warmups) warm-up)" : "") · \(detail)"
    }

    private func muscleSummary(_ exercise: ImportedExercise) -> String {
        exercise.muscleWeights
            .sorted { ($0.value, $1.key.name) > ($1.value, $0.key.name) }
            .map { $0.value >= 1 ? $0.key.name : "\($0.key.name) (½)" }
            .joined(separator: " · ")
    }

    private func read(_ items: [PhotosPickerItem]) async {
        isReading = true
        errorMessage = nil
        defer { isReading = false }

        var images: [UIImage] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                images.append(image)
            }
        }

        do {
            let result = try await HevyScreenshotImporter.read(images)
            guard !result.exercises.isEmpty else {
                errorMessage = "No exercises found in those screenshots. Make sure they show a Hevy workout."
                return
            }
            workout = result
            title = result.title
            date = result.date ?? Date()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        guard let workout else { return }
        let calendar = Calendar.current
        let cleanTitle = title.trimmingCharacters(in: .whitespaces).isEmpty ? "Workout" : title

        // Re-importing the same workout (same day and name) replaces it.
        let existing = (try? context.fetch(FetchDescriptor<StrengthSession>())) ?? []
        for session in existing where calendar.isDate(session.date, inSameDayAs: date) && session.title == cleanTitle {
            context.delete(session)
        }

        context.insert(StrengthSession(date: date, title: cleanTitle, exercises: workout.exercises))
        try? context.save()
        dismiss()
    }
}
