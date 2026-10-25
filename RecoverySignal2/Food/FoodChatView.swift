import SwiftUI
import SwiftData

struct FoodChatView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.foodLoggingDate) private var loggingDate
    @Environment(\.foodLoggingSlot) private var loggingSlot
    @Environment(\.scenePhase) private var scenePhase
    @Query private var entries: [FoodEntry]
    @State private var store = FoodChatStore.shared
    @State private var dictation = FoodDictation()
    @AppStorage("foodChat.speechLanguage") private var language = AppLanguage.current == .polish ? "pl-PL" : "en-GB"
    @State private var chatDay = Date()
    @State private var loaded = false
    @State private var text = ""
    @State private var prefix = ""
    private var busy: Bool { store.activeDays.contains(FoodChatStore.key(chatDay)) }
    @State private var saving: UUID?
    @State private var error: String?
    @State private var editing: FoodChatProposal?
    @State private var speechConsent = false
    @FocusState private var focused: Bool

    private var messages: [FoodChatMessage] { store.messages(on: chatDay) }
    private var loggedIDs: Set<String> { Set(entries.compactMap { $0.item?.id }) }
    private var latestProposalMessage: UUID? { messages.last(where: { $0.role == "assistant" })?.id }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    DatePicker("Chat day", selection: $chatDay, displayedComponents: .date)
                        .disabled(busy || saving != nil || dictation.recording || dictation.starting)
                    if messages.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Tell me about your meal", systemImage: "bubble.left.and.text.bubble.right")
                                .font(.headline)
                            Text("Type or dictate in English, Polish or German. Say today, tomorrow, yesterday or a specific date. Tap + to log a food; tap its name to change the portion.")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }.padding(.vertical)
                    }
                    ForEach(messages) { message in
                        VStack(alignment: .leading, spacing: 12) {
                            Text(verbatim: message.text)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: message.role == "user" ? .trailing : .leading)
                            ForEach(message.foods) { proposal in
                                foodRow(proposal, current: message.id == latestProposalMessage)
                            }
                        }
                        .padding(14)
                        .background(message.role == "user" ? Theme.accent.opacity(0.09) : Theme.textSecondary.opacity(0.05),
                                    in: RoundedRectangle(cornerRadius: 16))
                    }
                    if busy { ProgressView("Thinking…") }
                    if let requestError = store.requestErrors[FoodChatStore.key(chatDay)] {
                        Text(verbatim: requestError).font(.footnote).foregroundStyle(Theme.bad)
                        Button("Retry") { store.retry(on: chatDay, slot: loggingSlot ?? .forNow(), loggedIDs: loggedIDs) }
                            .disabled(busy)
                    }
                    if let issue = error ?? store.error ?? dictation.error {
                        Text(verbatim: issue).font(.footnote).foregroundStyle(Theme.bad)
                    }
                    Color.clear.frame(height: 1).id("chatBottom")
                }.padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("chatBottom", anchor: .bottom) } }
            .safeAreaInset(edge: .bottom, spacing: 0) { composer }
        }
        .background(Theme.background)
        .navigationTitle("Food chat")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            chatDay = loggingDate ?? Date()
        }
        .onChange(of: chatDay) { _, _ in text = ""; error = nil }
        .onChange(of: dictation.transcript) { _, value in
            text = prefix + (prefix.isEmpty || value.isEmpty ? "" : " ") + value
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { dictation.stop() } }
        .onDisappear { dictation.stop() }
        .sheet(item: $editing) { proposal in
            FoodChatPortionEditor(proposal: proposal) { updated in
                store.update(updated, on: chatDay)
            }
        }
        .alert("Online dictation", isPresented: $speechConsent) {
            Button("Continue") { beginDictation() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("On-device dictation is unavailable for this language. Apple may process your audio online. The transcript is only sent to the AI assistant when you tap Send.")
        }
    }

    private var composer: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("Dictation language", selection: $language) {
                    Text(verbatim: "English").tag("en-GB")
                    Text(verbatim: "Polski").tag("pl-PL")
                    Text(verbatim: "Deutsch").tag("de-DE")
                }.pickerStyle(.segmented)
                    .disabled(dictation.recording || dictation.starting)
                Button {
                    if dictation.recording { dictation.stop() }
                    else if dictation.supportsLocal(language) { beginDictation() }
                    else { speechConsent = true }
                } label: {
                    Image(systemName: dictation.recording ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.system(size: 32)).foregroundStyle(dictation.recording ? Theme.bad : Theme.accent)
                }
                .accessibilityLabel(dictation.recording ? Text("Stop dictation") : Text("Start dictation"))
                .disabled(busy || dictation.starting)
            }
            HStack(alignment: .bottom, spacing: 12) {
                TextField("Describe a meal…", text: $text, axis: .vertical)
                    .lineLimit(1...5).focused($focused)
                    .padding(12).background(Theme.textSecondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                    .disabled(dictation.recording || busy)
                Button {
                    send()
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 34))
                }
                .accessibilityLabel("Send")
                .disabled(busy || saving != nil || dictation.recording || dictation.starting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Chat history stays on this device. Relevant messages are shared with your selected AI provider when you send. Nutrition is estimated.")
                .font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .padding(12)
        .background(.regularMaterial)
    }

    private func beginDictation() {
        focused = false
        prefix = text.trimmingCharacters(in: .whitespacesAndNewlines)
        Task { await dictation.start(locale: language) }
    }

    private func foodRow(_ proposal: FoodChatProposal, current: Bool) -> some View {
        let added = loggedIDs.contains(proposal.food.id)
        let amount = proposal.food.amount(proposal.grams)
        return HStack(spacing: 12) {
            Button { editing = proposal } label: {
                VStack(alignment: .leading, spacing: 5) {
                    Text(verbatim: proposal.food.name).font(.subheadline.weight(.semibold))
                    Text(verbatim: "\(DetailFormat.safeInt(proposal.grams)) g · \(DetailFormat.safeInt(amount.kcal)) kcal")
                        .font(.caption).monospacedDigit()
                    MacroLine(protein: amount.protein, carbs: amount.carbs, fat: amount.fat)
                    Text("\(proposal.date.formatted(date: .abbreviated, time: .omitted)) · \(MealSlot(rawValue: proposal.slotRaw)?.label ?? proposal.slotRaw)")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if let warning = proposal.food.plausibilityWarning {
                        Text(verbatim: warning).font(.caption2).foregroundStyle(Theme.warn)
                    }
                    if !current && !added { Text("Replaced by a newer proposal").font(.caption2) }
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).disabled(added || !current || busy || saving != nil)
            Button { Task { await log(proposal) } } label: {
                if saving == proposal.id { ProgressView() }
                else {
                    Image(systemName: added ? "checkmark.circle.fill" : "plus.circle.fill")
                        .font(.system(size: 28)).foregroundStyle(added ? Theme.good : Theme.accent)
                }
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(added ? Text("Logged") : Text("Add food"))
            .disabled(added || !current || saving != nil || busy)
        }
    }

    private func send() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty && !busy else { return }
        focused = false
        error = nil
        store.send(input, on: chatDay, slot: loggingSlot ?? .forNow(), loggedIDs: loggedIDs)
        text = ""
    }

    private func log(_ proposal: FoodChatProposal) async {
        guard saving == nil, !loggedIDs.contains(proposal.food.id),
              let slot = MealSlot(rawValue: proposal.slotRaw) else { return }
        saving = proposal.id
        error = nil
        defer { saving = nil }
        do {
            _ = try await FoodLogger.log(proposal.food, grams: proposal.grams, slot: slot, at: proposal.date, context: context)
            try context.save()
            if !FoodLogger.lastSkipped.isEmpty {
                error = String(localized: "Saved locally, but some nutrition permissions are off in Apple Health.")
            }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            // FoodLogger already schedules the shared Health refresh. Release
            // the + buttons after saving rather than waiting for a full sync.
        } catch { self.error = error.localizedDescription }
    }
}

private struct FoodChatPortionEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var proposal: FoodChatProposal
    let onSave: (FoodChatProposal) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(verbatim: proposal.food.name).font(.headline)
                    HStack {
                        Text("Amount")
                        Spacer()
                        LiveNumberField("Grams", value: $proposal.grams).multilineTextAlignment(.trailing)
                        Text(verbatim: "g")
                    }
                    let amount = proposal.food.amount(proposal.grams)
                    Text(verbatim: "\(DetailFormat.safeInt(amount.kcal)) kcal")
                    MacroLine(protein: amount.protein, carbs: amount.carbs, fat: amount.fat)
                }
                Section {
                    DatePicker("Log date", selection: $proposal.date, displayedComponents: .date)
                    Picker("Meal", selection: $proposal.slotRaw) {
                        ForEach(MealSlot.allCases) { Text($0.label).tag($0.rawValue) }
                    }
                } footer: {
                    Text("Save changes, then tap + on the food to log it.")
                }
            }
            .navigationTitle("Serving size")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { onSave(proposal); dismiss() }
                        .disabled(!proposal.grams.isFinite || proposal.grams <= 0 || proposal.grams > 10000)
                }
            }
        }
    }
}
