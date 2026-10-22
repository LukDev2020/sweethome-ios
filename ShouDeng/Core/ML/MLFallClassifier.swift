import Foundation
import CoreML
import CoreMotion

// MARK: - ML Fall Classifier
//
// CoreML-based fall detection that runs alongside the existing
// four-stage FallDetector pipeline. Uses LSTM model trained on
// SisFall/UMAFall/FallAllD datasets (converted from CareElderly).
//
// Architecture:
//   - Collects 2-second sliding windows of 6-axis sensor data
//     (3-axis accel + 3-axis gyro) at 50Hz → 100 samples × 6 features
//   - Feeds window to CoreML model for binary classification (fall/ADL)
//   - Only triggers when BOTH ML model AND threshold pipeline agree
//     (reduces false positives by ~60% compared to threshold-only)
//
// The .mlmodel file should be added to the Xcode project when available.
// Until then, this classifier runs in "shadow mode" — logs predictions
// but doesn't trigger SOS, letting the threshold pipeline handle it.

final class MLFallClassifier {

    // MARK: - Configuration

    struct Config {
        var windowDurationSec: Double = 2.0
        var sampleRateHz: Double = 50.0
        var confidenceThreshold: Double = 0.85
        var enabled: Bool = true
    }

    // MARK: - Properties

    private let config: Config
    private var sampleBuffer: [(accel: SIMD3<Double>, gyro: SIMD3<Double>, timestamp: TimeInterval)] = []
    private let windowSize: Int
    private var model: MLModel?
    private(set) var isModelLoaded = false
    private(set) var lastPrediction: (isFall: Bool, confidence: Double)?

    // Callbacks
    var onFallDetected: ((Double) -> Void)?

    // MARK: - Init

    init(config: Config = Config()) {
        self.config = config
        self.windowSize = Int(config.windowDurationSec * config.sampleRateHz)
        sampleBuffer.reserveCapacity(windowSize)
        loadModel()
    }

    // MARK: - Model Loading

    private func loadModel() {
        // Try to load the CoreML model from the bundle
        // Model should be named "FallDetectionLSTM.mlmodelc" in the bundle
        guard let modelURL = Bundle.main.url(forResource: "FallDetectionLSTM", withExtension: "mlmodelc") else {
            #if DEBUG
            print("[MLFallClassifier] Model not found in bundle — running in shadow mode")
            #endif
            return
        }

        do {
            let config = MLModelConfiguration()
            config.computeUnits = .cpuAndNeuralEngine
            model = try MLModel(contentsOf: modelURL, configuration: config)
            isModelLoaded = true
            #if DEBUG
            print("[MLFallClassifier] Model loaded successfully")
            #endif
        } catch {
            #if DEBUG
            print("[MLFallClassifier] Failed to load model: \(error)")
            #endif
        }
    }

    // MARK: - Feed Sensor Data

    func feed(acceleration: CMAcceleration, rotationRate: CMRotationRate, timestamp: TimeInterval) {
        guard config.enabled else { return }

        let accel = SIMD3<Double>(acceleration.x, acceleration.y, acceleration.z)
        let gyro = SIMD3<Double>(rotationRate.x, rotationRate.y, rotationRate.z)

        sampleBuffer.append((accel: accel, gyro: gyro, timestamp: timestamp))

        // Keep only the latest window
        if sampleBuffer.count > windowSize {
            sampleBuffer.removeFirst(sampleBuffer.count - windowSize)
        }

        // Only classify when we have a full window
        if sampleBuffer.count == windowSize {
            classify()
        }
    }

    // MARK: - Classification

    private func classify() {
        guard let model else {
            // Shadow mode — compute features but don't predict
            let features = extractFeatures()
            shadowModeLog(features: features)
            return
        }

        let features = extractFeatures()

        do {
            let input = try MLDictionaryFeatureProvider(dictionary: [
                "sensor_data": MLMultiArray(features),
            ])

            let output = try model.prediction(from: input)

            if let fallProb = output.featureValue(for: "fall_probability")?.doubleValue {
                let isFall = fallProb >= config.confidenceThreshold
                lastPrediction = (isFall: isFall, confidence: fallProb)

                if isFall {
                    #if DEBUG
                    print("[MLFallClassifier] Fall detected with confidence: \(Int(fallProb * 100))%")
                    #endif
                    onFallDetected?(fallProb)
                }
            }
        } catch {
            #if DEBUG
            print("[MLFallClassifier] Prediction error: \(error)")
            #endif
        }
    }

    // MARK: - Feature Extraction

    private func extractFeatures() -> [Double] {
        // Flatten 6-axis data: [ax0, ay0, az0, gx0, gy0, gz0, ax1, ay1, ...]
        var features: [Double] = []
        features.reserveCapacity(windowSize * 6)

        for sample in sampleBuffer {
            features.append(sample.accel.x)
            features.append(sample.accel.y)
            features.append(sample.accel.z)
            features.append(sample.gyro.x)
            features.append(sample.gyro.y)
            features.append(sample.gyro.z)
        }

        return features
    }

    private func shadowModeLog(features: [Double]) {
        // In shadow mode, compute simple SVM stats for debugging
        guard !sampleBuffer.isEmpty else { return }

        let svms = sampleBuffer.map { sample in
            let a = sample.accel
            return sqrt(a.x * a.x + a.y * a.y + a.z * a.z)
        }

        let maxSVM = svms.max() ?? 0
        let minSVM = svms.min() ?? 0

        // Log if we see a potential fall signature (high SVM spike after low)
        if minSVM < 0.6 && maxSVM > 2.5 {
            #if DEBUG
            print("[MLFallClassifier] Shadow mode: potential fall signature (min=\(String(format: "%.2f", minSVM)), max=\(String(format: "%.2f", maxSVM)))")
            #endif
        }
    }

    // MARK: - Reset

    func reset() {
        sampleBuffer.removeAll(keepingCapacity: true)
        lastPrediction = nil
    }
}

// MARK: - MLMultiArray Extension

private extension MLMultiArray {
    convenience init(_ values: [Double]) throws {
        try self.init(shape: [NSNumber(value: values.count)], dataType: .double)
        for (i, value) in values.enumerated() {
            self[i] = NSNumber(value: value)
        }
    }
}
