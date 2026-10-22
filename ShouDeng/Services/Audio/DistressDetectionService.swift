import Foundation
import AVFoundation
import SoundAnalysis

// MARK: - Distress Sound Detection Service
//
// Uses Apple's Sound Classification API (SNClassifySoundRequest) to detect
// screams, cries for help, and other distress sounds on-device.
// No audio data leaves the device — all classification is local.

final class DistressDetectionService: ObservableObject {

    // MARK: - State

    enum ServiceState {
        case stopped
        case listening
        case paused
    }

    @Published private(set) var state: ServiceState = .stopped
    @Published private(set) var lastDetectedLabel: String?
    @Published private(set) var lastDetectedConfidence: Double = 0

    // Callback when distress sound is detected above threshold
    var onDistressDetected: ((String, Double) -> Void)?

    // MARK: - Configuration

    struct Config {
        var confidenceThreshold: Double = 0.7
        // Apple Sound Classification labels that indicate distress
        var distressLabels: Set<String> = [
            "scream", "screaming", "shout", "shouting",
            "crying", "cry", "yell", "yelling",
            "speech", // Only used with high confidence + specific context
        ]
        var windowDurationSec: Double = 1.5
    }

    // MARK: - Properties

    private let config: Config
    private var audioEngine: AVAudioEngine?
    private var analyzer: SNAudioStreamAnalyzer?
    private var resultsObserver: SoundResultsObserver?
    private let analysisQueue = DispatchQueue(label: "com.shoudeng.distress-detection")

    // Cooldown to prevent rapid-fire triggers
    private var lastTriggerTime: Date?
    private let cooldownInterval: TimeInterval = 30

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
    }

    // MARK: - Start / Stop

    func start() {
        guard state == .stopped else { return }

        #if targetEnvironment(simulator)
        // Sound analysis is not available on simulator
        #if DEBUG
        print("[DistressDetection] Skipping — running on simulator")
        #endif
        return
        #else

        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.record, mode: .measurement, options: .mixWithOthers)
            try audioSession.setActive(true)

            let engine = AVAudioEngine()
            let inputNode = engine.inputNode
            let format = inputNode.outputFormat(forBus: 0)

            let streamAnalyzer = SNAudioStreamAnalyzer(format: format)
            let request = try SNClassifySoundRequest(classifierIdentifier: .version1)
            request.windowDuration = CMTime(seconds: config.windowDurationSec, preferredTimescale: 1000)

            let observer = SoundResultsObserver { [weak self] label, confidence in
                self?.handleClassification(label: label, confidence: confidence)
            }

            try streamAnalyzer.add(request, withObserver: observer)

            inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak streamAnalyzer] buffer, time in
                streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
            }

            try engine.start()

            self.audioEngine = engine
            self.analyzer = streamAnalyzer
            self.resultsObserver = observer

            DispatchQueue.main.async {
                self.state = .listening
            }

            #if DEBUG
            print("[DistressDetection] Started listening for distress sounds")
            #endif
        } catch {
            #if DEBUG
            print("[DistressDetection] Failed to start: \(error)")
            #endif
        }
        #endif
    }

    func stop() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine = nil
        analyzer = nil
        resultsObserver = nil

        DispatchQueue.main.async {
            self.state = .stopped
        }
    }

    // MARK: - Classification Handler

    private func handleClassification(label: String, confidence: Double) {
        let lowered = label.lowercased()

        guard config.distressLabels.contains(lowered),
              confidence >= config.confidenceThreshold else { return }

        // Cooldown check
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < cooldownInterval {
            return
        }

        lastTriggerTime = Date()

        DispatchQueue.main.async { [weak self] in
            self?.lastDetectedLabel = label
            self?.lastDetectedConfidence = confidence
            self?.onDistressDetected?(label, confidence)
        }

        #if DEBUG
        print("[DistressDetection] Distress detected: \(label) (\(Int(confidence * 100))%)")
        #endif
    }

    deinit {
        stop()
    }
}

// MARK: - Sound Results Observer

private class SoundResultsObserver: NSObject, SNResultsObserving {
    private let handler: (String, Double) -> Void

    init(handler: @escaping (String, Double) -> Void) {
        self.handler = handler
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        guard let top = classification.classifications.first,
              top.confidence > 0.3 else { return }
        handler(top.identifier, Double(top.confidence))
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        #if DEBUG
        print("[DistressDetection] Analysis error: \(error)")
        #endif
    }
}
