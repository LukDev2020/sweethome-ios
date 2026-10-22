import Foundation
import Speech
import AVFoundation

// MARK: - Voice Note Service
//
// Records voice notes during SOS events and transcribes them on-device
// using Apple's Speech framework. Inspired by Huddle's AI voice analysis
// pattern but uses on-device processing for privacy.
//
// Flow:
//   1. Guardian or protected person taps "record voice note"
//   2. Audio recorded to temp file (m4a, 60 sec max)
//   3. On-device SFSpeechRecognizer transcribes audio
//   4. Transcript + metadata sent to server as text (no audio upload)
//   5. Server stores as actionable alert card on the SOS event

final class VoiceNoteService: NSObject, ObservableObject {

    // MARK: - State

    enum RecordingState: Equatable {
        case idle
        case recording
        case transcribing
        case done(VoiceNote)
        case error(String)

        static func == (lhs: RecordingState, rhs: RecordingState) -> Bool {
            switch (lhs, rhs) {
            case (.idle, .idle), (.recording, .recording), (.transcribing, .transcribing):
                return true
            case (.done(let a), .done(let b)):
                return a.id == b.id
            case (.error(let a), .error(let b)):
                return a == b
            default:
                return false
            }
        }
    }

    struct VoiceNote {
        let id: String
        let audioURL: URL
        let transcript: String
        let duration: TimeInterval
        let createdAt: Date
        let keywords: [String]
    }

    @Published var state: RecordingState = .idle
    @Published var recordingDuration: TimeInterval = 0

    // MARK: - Properties

    private var audioRecorder: AVAudioRecorder?
    private var recordingTimer: Timer?
    private let maxDuration: TimeInterval = 60
    private let speechRecognizer: SFSpeechRecognizer?
    private var currentFileURL: URL?
    private var recordingStartTime: Date?

    // Keywords that indicate urgency — extracted from transcript
    private let urgencyKeywords = [
        "help", "hurt", "pain", "bleeding", "fell", "fall", "accident", "emergency",
        "救命", "疼", "痛", "摔", "伤", "出血", "事故", "紧急", "危险", "被困",
        "au secours", "blessé", "douleur", "accident", "urgence"
    ]

    // MARK: - Init

    override init() {
        // Use device locale for speech recognition
        let locale = Locale.current
        speechRecognizer = SFSpeechRecognizer(locale: locale)
        super.init()
    }

    // MARK: - Recording

    func startRecording() {
        #if targetEnvironment(simulator)
        state = .error("Recording not available in simulator")
        return
        #endif

        guard audioRecorder == nil else { return }

        // Request mic permission
        AVAudioSession.sharedInstance().requestRecordPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard granted else {
                    self?.state = .error("Microphone access denied")
                    return
                }
                self?.beginRecording()
            }
        }
    }

    func stopRecording() {
        guard audioRecorder?.isRecording == true else { return }
        audioRecorder?.stop()
        recordingTimer?.invalidate()
        recordingTimer = nil

        let duration = Date().timeIntervalSince(recordingStartTime ?? Date())
        recordingDuration = duration

        guard let fileURL = currentFileURL else {
            state = .error("No recording file")
            return
        }

        state = .transcribing
        transcribe(fileURL: fileURL, duration: duration)
    }

    func cancelRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        recordingTimer?.invalidate()
        recordingTimer = nil
        recordingDuration = 0
        if let url = currentFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentFileURL = nil
        state = .idle
    }

    // MARK: - Private

    private func beginRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "voice_note_\(UUID().uuidString).m4a"
        let fileURL = tempDir.appendingPathComponent(fileName)
        currentFileURL = fileURL

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .default)
            try session.setActive(true)

            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.delegate = self
            audioRecorder?.record(forDuration: maxDuration)
            recordingStartTime = Date()
            state = .recording
            recordingDuration = 0

            recordingTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                guard let self, let start = self.recordingStartTime else { return }
                self.recordingDuration = Date().timeIntervalSince(start)
            }
        } catch {
            state = .error("Failed to start recording: \(error.localizedDescription)")
        }
    }

    private func transcribe(fileURL: URL, duration: TimeInterval) {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            // If speech recognition unavailable, create note without transcript
            let note = VoiceNote(
                id: UUID().uuidString,
                audioURL: fileURL,
                transcript: "",
                duration: duration,
                createdAt: Date(),
                keywords: []
            )
            DispatchQueue.main.async { self.state = .done(note) }
            return
        }

        SFSpeechRecognizer.requestAuthorization { [weak self] authStatus in
            guard let self else { return }

            guard authStatus == .authorized else {
                let note = VoiceNote(
                    id: UUID().uuidString,
                    audioURL: fileURL,
                    transcript: "",
                    duration: duration,
                    createdAt: Date(),
                    keywords: []
                )
                DispatchQueue.main.async { self.state = .done(note) }
                return
            }

            let request = SFSpeechURLRecognitionRequest(url: fileURL)
            request.shouldReportPartialResults = false
            if #available(iOS 16, *) {
                request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
            }

            recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }

                let transcript = result?.bestTranscription.formattedString ?? ""
                let keywords = self.extractKeywords(from: transcript)

                let note = VoiceNote(
                    id: UUID().uuidString,
                    audioURL: fileURL,
                    transcript: transcript,
                    duration: duration,
                    createdAt: Date(),
                    keywords: keywords
                )

                DispatchQueue.main.async { self.state = .done(note) }
            }
        }
    }

    private func extractKeywords(from transcript: String) -> [String] {
        let lower = transcript.lowercased()
        return urgencyKeywords.filter { lower.contains($0.lowercased()) }
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceNoteService: AVAudioRecorderDelegate {

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        if flag && state == .recording {
            // Auto-stop after max duration — trigger transcription
            stopRecording()
        }
    }

    func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        DispatchQueue.main.async {
            self.state = .error("Recording failed: \(error?.localizedDescription ?? "unknown")")
        }
    }
}
