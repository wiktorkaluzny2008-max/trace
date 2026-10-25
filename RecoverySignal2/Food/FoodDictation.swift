import AVFoundation
import Speech
import Observation

@Observable
final class FoodDictation {
    var transcript = ""
    var recording = false
    var starting = false
    var error: String?
    private var engine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var generation = UUID()
    private var hasTap = false

    func supportsLocal(_ locale: String) -> Bool {
        SFSpeechRecognizer(locale: Locale(identifier: locale))?.supportsOnDeviceRecognition == true
    }

    func start(locale: String) async {
        guard !recording && !starting else { return }
        starting = true
        error = nil
        let token = UUID()
        generation = token
        defer { starting = false }
        let permission = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard generation == token else { return }
        guard permission == .authorized else {
            error = String(localized: "Allow speech recognition in Settings to dictate a meal."); return
        }
        let microphone = await AVAudioApplication.requestRecordPermission()
        guard generation == token else { return }
        guard microphone else {
            error = String(localized: "Allow microphone access in Settings to dictate a meal."); return
        }
        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: locale)), recognizer.isAvailable else {
            error = String(localized: "Dictation is unavailable for this language right now. You can still type."); return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true)
            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            self.engine = engine
            self.request = request
            transcript = ""
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 && format.channelCount > 0 else { throw DictationError.noInput }
            input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }
            hasTap = true
            task = recognizer.recognitionTask(with: request) { [weak self] result, failure in
                let text = result?.bestTranscription.formattedString
                let finished = result?.isFinal == true
                let message = failure?.localizedDescription
                Task { @MainActor in
                    guard let self, self.generation == token else { return }
                    if let text { self.transcript = text }
                    if finished || message != nil {
                        self.stop()
                        if let message, self.transcript.isEmpty { self.error = message }
                    }
                }
            }
            engine.prepare()
            try engine.start()
            recording = true
        } catch {
            stop()
            self.error = error.localizedDescription
        }
    }

    func stop() {
        generation = UUID()
        engine?.stop()
        if hasTap { engine?.inputNode.removeTap(onBus: 0); hasTap = false }
        request?.endAudio()
        task?.cancel()
        task = nil
        engine = nil
        request = nil
        recording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    enum DictationError: LocalizedError {
        case noInput
        var errorDescription: String? { String(localized: "No microphone input is available.") }
    }
}
