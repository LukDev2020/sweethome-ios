import Foundation
import Speech
import AVFoundation

// MARK: - Voice Command Service
//
// On-device speech recognition for hands-free SOS triggering.
// Listens for trigger phrases like "help", "SOS", "救命", "帮帮我".
// All processing happens on-device (iOS 17+ offline recognition).

final class VoiceCommandService: ObservableObject {

    // MARK: - State

    enum ServiceState {
        case stopped
        case listening
        case unavailable
    }

    @Published private(set) var state: ServiceState = .stopped

    // Callback when a trigger phrase is recognized
    var onSOSCommand: ((String) -> Void)?

    static func recognitionLocale(for language: AppLanguage) -> Locale {
        switch language {
        case .english: return Locale(identifier: "en-US")
        case .chinese: return Locale(identifier: "zh-CN")
        case .traditionalChinese: return Locale(identifier: "zh-TW")
        case .french: return Locale(identifier: "fr-FR")
        case .japanese: return Locale(identifier: "ja-JP")
        }
    }

    // MARK: - Configuration

    struct Config {
        var triggerPhrases: Set<String> = [
            "help", "help me", "sos",
            "救命", "帮帮我", "救我", "紧急求助",
            "幫幫我", "緊急求助", // Traditional, in case a zh-Hant / zh-HK recognizer is used
            "au secours", "aidez-moi",
            "助けて", "たすけて", "助けてください",
        ]
        var confidenceThreshold: Double = 0.5
    }

    // MARK: - Properties

    private let config: Config
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioEngine: AVAudioEngine?

    // Cooldown to prevent rapid-fire triggers
    private var lastTriggerTime: Date?
    private let cooldownInterval: TimeInterval = 60

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Authorization

    static func requestAuthorization(completion: @escaping (Bool) -> Void) {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                completion(status == .authorized)
            }
        }
    }

    // MARK: - Start / Stop

    func start() {
        guard !ExploreMode.blocks("microphone") else { return }
        guard state == .stopped else { return }

        #if targetEnvironment(simulator)
        #if DEBUG
        print("[VoiceCommand] Skipping — running on simulator")
        #endif
        state = .unavailable
        return
        #else

        guard SFSpeechRecognizer.authorizationStatus() == .authorized else {
            state = .unavailable
            return
        }

        // Recognize in the app's language (trigger phrases cover all of them)
        recognizer = SFSpeechRecognizer(locale: Self.recognitionLocale(for: LanguageManager.shared.current))

        // Fall back to English if that recognizer isn't available
        if recognizer?.isAvailable != true {
            recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
        }

        guard let recognizer, recognizer.isAvailable else {
            state = .unavailable
            return
        }

        // Request on-device recognition if available
        if recognizer.supportsOnDeviceRecognition {
            startListening(recognizer: recognizer, onDevice: true)
        } else {
            startListening(recognizer: recognizer, onDevice: false)
        }
        #endif
    }

    private func startListening(recognizer: SFSpeechRecognizer, onDevice: Bool) {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .mixWithOthers)
            try audioSession.setActive(true)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if onDevice {
                request.requiresOnDeviceRecognition = true
            }

            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
                request.append(buffer)
            }

            try engine.start()
            self.audioEngine = engine
            self.recognitionRequest = request

            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                if let result {
                    let text = result.bestTranscription.formattedString.lowercased()
                    self.checkForTriggerPhrase(in: text)
                }

                if error != nil || (result?.isFinal == true) {
                    // Restart recognition to keep listening
                    self.restartRecognition()
                }
            }

            state = .listening

            #if DEBUG
            print("[VoiceCommand] Started listening (onDevice: \(onDevice))")
            #endif
        } catch {
            #if DEBUG
            print("[VoiceCommand] Failed to start: \(error)")
            #endif
            state = .unavailable
        }
    }

    private func restartRecognition() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil

        // Small delay before restarting
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, self.state == .listening else { return }
            self.state = .stopped
            self.start()
        }
    }

    func stop() {
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        state = .stopped
    }

    // MARK: - Phrase Matching

    private func checkForTriggerPhrase(in text: String) {
        for phrase in config.triggerPhrases {
            if text.contains(phrase) {
                triggerSOS(matchedPhrase: phrase)
                return
            }
        }
    }

    private func triggerSOS(matchedPhrase: String) {
        // Cooldown check
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < cooldownInterval {
            return
        }

        lastTriggerTime = Date()

        #if DEBUG
        print("[VoiceCommand] Trigger phrase detected: \"\(matchedPhrase)\"")
        #endif

        DispatchQueue.main.async { [weak self] in
            self?.onSOSCommand?(matchedPhrase)
        }
    }

    deinit {
        stop()
    }
}
