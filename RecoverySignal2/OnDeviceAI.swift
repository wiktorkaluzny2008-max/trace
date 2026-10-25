//
//  OnDeviceAI.swift
//  RecoverySignal2
//
//  Apple Intelligence's on-device language model (Foundation Models framework).
//  Free, works offline, no API key or rate limits, and nothing leaves the phone —
//  so it's tried first for everything it can do. Needs an Apple Intelligence
//  iPhone (15 Pro or later) with Apple Intelligence switched on; everything else
//  falls back to Gemini.
//
//  On iOS 26 the on-device model reads text only and has a small context window,
//  so photos and screenshots are first turned into text with Vision (image
//  classification and text recognition), and requests that clearly won't fit go
//  to Gemini. iOS 27 adds two things, used when present: image input, so the
//  model looks at the photo itself, and Apple's Private Cloud Compute model, a
//  larger one that runs on Apple's servers (with Apple's privacy guarantees, but
//  not on the phone) for requests the small model can't take.
//

import Foundation
import FoundationModels
import UIKit
import Vision

enum OnDeviceAI {

    /// The small model on this iPhone.
    static var isOnPhoneAvailable: Bool {
        SystemLanguageModel.default.isAvailable
    }

    /// Apple's larger Private Cloud Compute model (iOS 27), when there's quota left.
    static var isCloudAvailable: Bool {
        guard #available(iOS 27.0, *) else { return false }
        let model = PrivateCloudComputeLanguageModel()
        guard model.isAvailable else { return false }
        if case .limitReached = model.quotaUsage.status { return false }
        return true
    }

    /// Apple Intelligence can answer, on the phone or in Apple's private cloud.
    static var isAvailable: Bool { isOnPhoneAvailable || isCloudAvailable }

    /// True when a model that can look at photos is available (iOS 27).
    static var canSeeImages: Bool {
        guard #available(iOS 27.0, *) else { return false }
        if SystemLanguageModel.default.isAvailable, SystemLanguageModel.default.capabilities.contains(.vision) { return true }
        return isCloudAvailable && PrivateCloudComputeLanguageModel().capabilities.contains(.vision)
    }

    /// Available, and AI features are switched on in Settings.
    static var isUsable: Bool { AppPrefs.aiEnabled && isAvailable }

    /// True when Apple Intelligence is doing the work because there's no Gemini key.
    static var standsInForGemini: Bool {
        isUsable && (KeychainStore.get(APIKeyName.gemini) ?? "").isEmpty
    }

    /// A short, human explanation for Settings.
    static var statusText: String {
        switch SystemLanguageModel.default.availability {
        case .available:
            return isCloudAvailable ? "On your iPhone, and Apple's private cloud for big requests" : "On your iPhone, used first"
        case .unavailable(.deviceNotEligible):
            return "This iPhone doesn't support Apple Intelligence"
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in the iPhone's Settings"
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading"
        case .unavailable:
            return "On-device model unavailable"
        }
    }

    static func respond(instructions: String, prompt: String,
                        temperature: Double = 0.7, maxTokens: Int? = nil) async throws -> String {
        // A phone whose own model isn't available can still use Apple's cloud model (iOS 27).
        if !isOnPhoneAvailable {
            return try await respondInCloud(instructions: instructions, prompt: prompt,
                                            temperature: temperature, maxTokens: maxTokens)
        }
        let session = LanguageModelSession(instructions: instructions)
        var options = GenerationOptions(temperature: temperature)
        if let maxTokens { options.maximumResponseTokens = maxTokens }
        let response = try await session.respond(to: prompt, options: options)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the request on Apple's Private Cloud Compute model instead (iOS 27), optionally
    /// with photos. Larger context than the on-device model; needs a network connection.
    static func respondInCloud(instructions: String, prompt: String, images: [Data] = [],
                               temperature: Double = 0.7, maxTokens: Int? = nil) async throws -> String {
        guard #available(iOS 27.0, *), isCloudAvailable else { throw CocoaError(.featureUnsupported) }
        return try await run(model: PrivateCloudComputeLanguageModel(), instructions: instructions,
                             prompt: prompt, images: images, temperature: temperature, maxTokens: maxTokens)
    }

    /// Runs the request with photos on the on-device model, if it can see them (iOS 27).
    static func respondWithImages(instructions: String, prompt: String, images: [Data],
                                  temperature: Double = 0.7, maxTokens: Int? = nil) async throws -> String {
        guard #available(iOS 27.0, *), SystemLanguageModel.default.isAvailable,
              SystemLanguageModel.default.capabilities.contains(.vision) else { throw CocoaError(.featureUnsupported) }
        return try await run(model: SystemLanguageModel.default, instructions: instructions,
                             prompt: prompt, images: images, temperature: temperature, maxTokens: maxTokens)
    }

    @available(iOS 27.0, *)
    private static func run(model: some LanguageModel, instructions: String, prompt: String, images: [Data],
                            temperature: Double, maxTokens: Int?) async throws -> String {
        let session = LanguageModelSession(model: model, instructions: instructions)
        var options = GenerationOptions(temperature: temperature)
        if let maxTokens { options.maximumResponseTokens = maxTokens }
        let photos = images.compactMap { UIImage(data: $0)?.cgImage }.map { Attachment<ImageAttachmentContent>($0) }
        let response = try await session.respond(options: options) {
            prompt
            photos
        }
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Reading images on the phone

    /// Text in the screenshots, top to bottom, for the model to parse.
    static func screenText(_ jpegs: [Data]) async -> String {
        let pages = await Task.detached { jpegs.map(recognizeText) }.value
        let body = pages.enumerated().map { "--- screenshot \($0.offset + 1) ---\n\($0.element)" }.joined(separator: "\n")
        return "The screenshots were read on the phone as text (top to bottom). Use this text; there are no images:\n" + body
    }

    /// What the photo probably shows, from Apple's image classifier.
    static func foodContext(_ jpegs: [Data]) async -> String {
        let labels = await Task.detached { jpegs.flatMap(classify) }.value
        guard !labels.isEmpty else { return "No photo details are available; estimate from the description alone." }
        return "The photo can't be shown to you. An on-device classifier says it probably shows: "
            + labels.joined(separator: ", ")
            + ". Treat that as a rough hint, use typical portions, and set confidence to \"low\"."
    }

    private nonisolated static func recognizeText(_ jpeg: Data) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        guard (try? VNImageRequestHandler(data: jpeg).perform([request])) != nil else { return "" }
        let lines = (request.results ?? []).sorted { $0.boundingBox.midY > $1.boundingBox.midY }
        return lines.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    private nonisolated static func classify(_ jpeg: Data) -> [String] {
        let request = VNClassifyImageRequest()
        guard (try? VNImageRequestHandler(data: jpeg).perform([request])) != nil else { return [] }
        return (request.results ?? [])
            .filter { $0.confidence >= 0.12 }
            .prefix(8)
            .map { "\($0.identifier.replacingOccurrences(of: "_", with: " ")) (\(Int($0.confidence * 100))%)" }
    }
}
