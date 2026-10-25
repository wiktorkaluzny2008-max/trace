//
//  SettingsView.swift
//  RecoverySignal
//

import SwiftUI
import SwiftData

struct SettingsView: View {
    @State private var apiKey: String = KeychainStore.get(APIKeyName.anthropic) ?? ""
    @State private var saved = false
    @Environment(\.modelContext) private var context
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Anthropic API key", text: $apiKey)
                        .textContentType(.password)
                        .autocorrectionDisabled()
                    Button("Save key") {
                        KeychainStore.set(apiKey, for: APIKeyName.anthropic)
                        saved = true
                    }
                    if saved {
                        Text("Saved to Keychain.").font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("AI narrative")
                } footer: {
                    Text("Used only to generate your weekly narrative summary. Get a key at console.anthropic.com. Only aggregated weekly stats are sent — never raw Health samples.")
                }

                Section("Data") {
                    Button {
                        Task {
                            isRefreshing = true
                            let aggregator = MetricsAggregator(context: context)
                            try? await aggregator.refresh(days: 60)
                            isRefreshing = false
                        }
                    } label: {
                        HStack {
                            Text("Refresh from Health now")
                            if isRefreshing {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isRefreshing)
                }

                Section("About") {
                    Text("RecoverySignal reads Watch biomarkers and Yazio nutrition data (synced via Apple Health) to surface trends and plain-language insights. Nothing is written back to Health, and nothing leaves your device except the aggregated weekly stats sent for the AI narrative, if you generate one.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
