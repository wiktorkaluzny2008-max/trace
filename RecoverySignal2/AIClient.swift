//
//  AIClient.swift
//  RecoverySignal2
//
//  One place that talks to the language model, shared by the weekly narrative
//  and meal ideas. Uses Google's Gemini API (free tier) over REST.
//
//  Google renames and retires models regularly, so no model name is hard-coded
//  as the only option: on first use the app asks the API which models this key
//  can call and picks the newest stable "Flash" model (fast, and on the free
//  tier). The choice is cached, and re-discovered if that model ever disappears.
//
//  JSON output mode guarantees valid JSON but not a particular shape, so
//  callers describe the shape in the prompt and decode leniently.
//

import Foundation

struct AIClient {

    static let baseURL = "https://generativelanguage.googleapis.com/v1beta"
    /// Used only if model discovery itself fails.
    static let fallbackModels = ["gemini-2.5-flash", "gemini-flash-latest", "gemini-2.5-flash-lite"]

    private static let modelKey = "ai.geminiModel"

    enum AIError: LocalizedError {
        case missingAPIKey
        case disabled
        case invalidAPIKey
        case noModelAvailable
        case blocked
        case overloaded
        case emptyResponse
        case truncated
        case timedOut
        case requestFailed(String)

        var errorDescription: String? {
            switch self {
            case .missingAPIKey:    String(localized: "Add your Google Gemini API key in Settings first.")
            case .disabled:         String(localized: "AI features are turned off. Turn them on in Settings → AI assistant.")
            case .invalidAPIKey:    String(localized: "Google rejected the API key. Check it in Settings — Gemini keys usually start with AIza.")
            case .noModelAvailable: String(localized: "No usable Gemini model was found for this key. Check the key at aistudio.google.com.")
            case .blocked:          String(localized: "Gemini declined to answer this one. Try rephrasing your dietary notes.")
            case .overloaded:       String(localized: "Google's Gemini servers are busy right now, even on the backup models. Try again in a few minutes.")
            case .emptyResponse:    String(localized: "The AI returned an empty response. Try again.")
            case .truncated:        String(localized: "The AI's reply was cut off. Try again.")
            case .timedOut:         String(localized: "Gemini did not reply in time, including one fallback attempt. Your chat is saved. Check your connection and tap Retry.")
            case .requestFailed(let message): message
            }
        }
    }

    /// Sends one system + user turn and returns the reply text.
    /// `images` attaches photos (a meal, workout screenshots) for the model to look at.
    ///
    /// Apple Intelligence on the phone goes first for text requests (and is the only route
    /// without a Gemini key); Gemini takes over when it can't. `accepts` lets the caller
    /// check that the on-device answer has the shape it needs, since the small model is
    /// less reliable at exact JSON. Requests with `images` go to Gemini when there's a key;
    /// without one, `onDeviceContext` supplies what Vision read from the images as text.
    func send(system: String, user: String, maxTokens: Int = 1500,
              temperature: Double = 0.7, json: Bool = false, images: [Data] = [],
              onDeviceContext: (() async -> String)? = nil,
              accepts: ((String) -> Bool)? = nil) async throws -> String {
        guard AppPrefs.aiEnabled else { throw AIError.disabled }
        let system = system + AppLanguage.aiInstruction
        let apiKey = KeychainStore.get(APIKeyName.gemini) ?? ""
        let hasKey = !apiKey.isEmpty

        if OnDeviceAI.isAvailable {
            let textOnly = images.isEmpty
            // iOS 27 Apple Intelligence can look at the photos itself; earlier it only gets
            // what Vision read from them as text.
            let seesImages = !textOnly && OnDeviceAI.canSeeImages
            let wanted = (textOnly || seesImages) ? (AppPrefs.onDeviceFirst || !hasKey)
                                                  : (!hasKey && onDeviceContext != nil)
            if wanted {
                var prompt = user
                if !textOnly, !seesImages, let context = await onDeviceContext?() { prompt += "\n\n" + context }
                if let text = await onDevice(system: system, user: prompt, maxTokens: maxTokens,
                                             temperature: temperature, json: json,
                                             images: seesImages ? images : [], accepts: accepts) {
                    return text
                }
            }
        }
        guard hasKey else {
            if OnDeviceAI.isAvailable {
                throw AIError.requestFailed(String(localized: "Apple Intelligence couldn't handle this one on the phone. Add a Gemini key in Settings → AI assistant for a fuller answer."))
            }
            throw AIError.missingAPIKey
        }

        return try await AIBackgroundExecution.run {
            try await sendGemini(apiKey: apiKey, system: system, user: user,
                                 maxTokens: maxTokens, temperature: temperature, json: json, images: images)
        }
    }

    private func sendGemini(apiKey: String, system: String, user: String, maxTokens: Int,
                            temperature: Double, json: Bool, images: [Data]) async throws -> String {
        var tried: Set<String> = []
        var sawBusyModel = false
        var timeoutCount = 0

        // Walk down the ranked models: newest Flash first, then older or Lite ones.
        for _ in 0..<5 {
            try Task.checkCancellation()
            // A timed-out request gets only one recovery attempt. Avoid another
            // discovery round-trip when the connection is already slow.
            let selectedModel: String?
            if timeoutCount > 0 {
                selectedModel = Self.fallbackModels.first { !tried.contains($0) }
            } else {
                selectedModel = try await nextModel(apiKey: apiKey, excluding: tried)
            }
            guard let model = selectedModel else { break }
            tried.insert(model)

            // One quick retry on the same model for a momentary overload,
            // then move on to the next model rather than making you wait.
            for attempt in 0..<2 {
                try Task.checkCancellation()
                do {
                    let text = try await generate(model: model, apiKey: apiKey, system: system, user: user,
                                                  maxTokens: maxTokens, temperature: temperature, json: json,
                                                  images: images)
                    // Remember whichever model actually answered — under load that's
                    // often an older, less-contended one, which is a fine default.
                    UserDefaults.standard.set(model, forKey: Self.modelKey)
                    return text
                } catch let error as URLError where error.code == .timedOut {
                    timeoutCount += 1
                    if timeoutCount >= 2 { throw AIError.timedOut }
                    break
                } catch ModelProblem.busy {
                    if timeoutCount > 0 { throw AIError.overloaded }
                    sawBusyModel = true
                    if attempt == 0 {
                        try await Task.sleep(for: .seconds(2))
                        continue
                    }
                } catch ModelProblem.unavailable {
                    if timeoutCount > 0 { throw AIError.timedOut }
                    UserDefaults.standard.removeObject(forKey: Self.modelKey)
                }
                break
            }
        }

        if timeoutCount > 0 { throw AIError.timedOut }
        throw sawBusyModel ? AIError.overloaded : AIError.noModelAvailable
    }

    // MARK: - On-device

    /// Tries the small model on the phone, then Apple's larger cloud model (iOS 27).
    /// Nil when neither can take it or the answer isn't usable.
    private func onDevice(system: String, user: String, maxTokens: Int, temperature: Double,
                          json: Bool, images: [Data], accepts: ((String) -> Bool)?) async -> String? {
        func usable(_ raw: String?) -> String? {
            guard var text = raw else { return nil }
            if json { text = Self.jsonBody(text) }
            guard !text.isEmpty else { return nil }
            if json, (try? JSONSerialization.jsonObject(with: Data(text.utf8))) == nil { return nil }
            if let accepts, !accepts(text) { return nil }
            return text
        }

        if OnDeviceAI.isOnPhoneAvailable {
            if !images.isEmpty {
                let raw = try? await OnDeviceAI.respondWithImages(instructions: system, prompt: user, images: images,
                                                                  temperature: temperature, maxTokens: min(maxTokens, 1800))
                if let text = usable(raw) { return text }
            } else if (system.count + user.count) / 3 <= 2200 {
                // The small model's window is about 4,000 tokens shared by prompt and reply.
                let raw = try? await OnDeviceAI.respond(instructions: system, prompt: user,
                                                        temperature: temperature, maxTokens: min(maxTokens, 1800))
                if let text = usable(raw) { return text }
            }
        }
        guard OnDeviceAI.isCloudAvailable else { return nil }
        let raw = try? await OnDeviceAI.respondInCloud(instructions: system, prompt: user, images: images,
                                                       temperature: temperature, maxTokens: maxTokens)
        return usable(raw)
    }

    /// Drops code fences and chatter around the outermost JSON object or array.
    private static func jsonBody(_ text: String) -> String {
        guard let start = text.firstIndex(where: { $0 == "{" || $0 == "[" }),
              let end = text.lastIndex(where: { $0 == "}" || $0 == "]" }), start <= end else { return "" }
        return String(text[start...end])
    }

    // MARK: - Model selection

    private enum ModelProblem: Error {
        /// Retired or not available to this key — skip it for good.
        case unavailable
        /// Overloaded right now (503 and friends) — skip it for this request only.
        case busy
    }

    private func nextModel(apiKey: String, excluding tried: Set<String>) async throws -> String? {
        if let cached = UserDefaults.standard.string(forKey: Self.modelKey), !tried.contains(cached) {
            return cached
        }
        if let discovered = try await discoverModel(apiKey: apiKey, excluding: tried) {
            return discovered
        }
        return Self.fallbackModels.first { !tried.contains($0) }
    }

    /// Picks the newest stable, text-capable Flash model the key can use.
    private func discoverModel(apiKey: String, excluding tried: Set<String>) async throws -> String? {
        var request = URLRequest(url: URL(string: "\(Self.baseURL)/models?pageSize=1000")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.timeoutInterval = 30

        guard let (data, response) = try? await URLSession.shared.data(for: request) else { return nil }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 400 || status == 401 || status == 403 {
            let text = String(data: data, encoding: .utf8)?.lowercased() ?? ""
            if text.contains("api_key") || text.contains("api key") { throw AIError.invalidAPIKey }
        }
        guard (200..<300).contains(status),
              let list = try? JSONDecoder().decode(ModelList.self, from: data) else { return nil }

        let excludedWords = ["image", "tts", "audio", "live", "transcribe", "embedding", "preview",
                             "exp", "vision", "robotics", "computer-use", "native", "thinking"]

        let candidates = list.models.compactMap { model -> (id: String, version: [Int], lite: Bool)? in
            let id = model.name.replacingOccurrences(of: "models/", with: "")
            let lowered = id.lowercased()
            guard lowered.hasPrefix("gemini"), lowered.contains("flash"),
                  model.supportedGenerationMethods?.contains("generateContent") == true,
                  !excludedWords.contains(where: lowered.contains),
                  !tried.contains(id) else { return nil }
            return (id, versionNumbers(in: lowered), lowered.contains("lite"))
        }

        // Full Flash over Lite, then highest version number.
        return candidates.sorted { a, b in
            if a.lite != b.lite { return !a.lite }
            return b.version.lexicographicallyPrecedes(a.version)
        }.first?.id
    }

    /// "gemini-3.8-flash-002" → [3, 8, 2]; used to rank model generations.
    private func versionNumbers(in id: String) -> [Int] {
        id.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }
    }

    private struct ModelList: Decodable {
        struct Model: Decodable {
            let name: String
            let supportedGenerationMethods: [String]?
        }
        let models: [Model]
    }

    // MARK: - Generation

    private func generate(model: String, apiKey: String, system: String, user: String,
                          maxTokens: Int, temperature: Double, json: Bool, images: [Data]) async throws -> String {
        var generationConfig: [String: Any] = [
            // Newer Flash models think before answering and those tokens count
            // against the output limit, so leave generous headroom.
            "maxOutputTokens": max(maxTokens * 4, 8192),
            "temperature": temperature
        ]
        if json { generationConfig["responseMimeType"] = "application/json" }

        let body: [String: Any] = [
            "systemInstruction": ["parts": [["text": system]]],
            "contents": [["role": "user", "parts": userParts(text: user, images: images)]],
            "generationConfig": generationConfig
        ]

        var request = URLRequest(url: URL(string: "\(Self.baseURL)/models/\(model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0

        guard (200..<300).contains(status) else {
            let errorText = String(data: data, encoding: .utf8) ?? "unknown error"
            let lowered = errorText.lowercased()
            if lowered.contains("api_key_invalid") || lowered.contains("api key not valid") || status == 401 {
                throw AIError.invalidAPIKey
            }
            if status == 429 {
                throw AIError.requestFailed("Gemini's free-tier limit was hit. Wait a minute and try again.")
            }
            // "This model is currently experiencing high demand" and other
            // temporary server-side failures.
            if [500, 502, 503, 504].contains(status) || lowered.contains("high demand")
                || lowered.contains("overloaded") || lowered.contains("\"unavailable\"") {
                throw ModelProblem.busy
            }
            if status == 404 || lowered.contains("is not found") || lowered.contains("not supported for generatecontent") {
                throw ModelProblem.unavailable
            }
            throw AIError.requestFailed("Gemini API returned an error (\(status)): \(errorText)")
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        if decoded.promptFeedback?.blockReason != nil { throw AIError.blocked }
        guard let candidate = decoded.candidates?.first else { throw AIError.emptyResponse }
        if candidate.finishReason == "SAFETY" || candidate.finishReason == "PROHIBITED_CONTENT" { throw AIError.blocked }

        // Skip any "thought" parts; only the final answer is shown.
        var text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if text.isEmpty {
            throw candidate.finishReason == "MAX_TOKENS" ? AIError.truncated : AIError.emptyResponse
        }
        if candidate.finishReason == "MAX_TOKENS" && json { throw AIError.truncated }

        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
                .replacingOccurrences(of: "```", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text
    }

    private func userParts(text: String, images: [Data]) -> [[String: Any]] {
        let imageParts: [[String: Any]] = images.map {
            ["inlineData": ["mimeType": "image/jpeg", "data": $0.base64EncodedString()]]
        }
        return imageParts + [["text": text]]
    }

    private struct GenerateResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                    let thought: Bool?
                }
                let parts: [Part]?
            }
            let content: Content?
            let finishReason: String?
        }
        struct PromptFeedback: Decodable { let blockReason: String? }

        let candidates: [Candidate]?
        let promptFeedback: PromptFeedback?
    }
}
