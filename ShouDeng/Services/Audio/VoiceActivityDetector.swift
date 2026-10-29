import Foundation
import AVFoundation
import Accelerate

// MARK: - Voice Activity Detector (VAD)
//
// Energy-based voice activity detection to reduce false triggers in
// VoiceCommandService. Only activates speech recognition when human
// voice is likely present, saving battery and reducing false positives.
//
// Algorithm: Frame-level energy + zero-crossing rate + spectral flatness
// Inspired by Silero VAD but implemented as lightweight signal processing
// (no CoreML dependency — runs on any device).

final class VoiceActivityDetector: ObservableObject {
    static let shared = VoiceActivityDetector()

    @Published var isVoiceDetected = false
    @Published var currentEnergy: Float = 0

    // Tunable thresholds
    var energyThreshold: Float = -35.0  // dBFS; speech typically -30 to -10
    var zeroCrossingMin: Float = 0.02   // Minimum ZCR for voice (vs silence)
    var zeroCrossingMax: Float = 0.35   // Maximum ZCR for voice (vs noise)
    var spectralFlatnessMax: Float = 0.5 // Voice has low flatness (tonal); noise is flat
    var hangoverFrames: Int = 8         // Keep "voice detected" for N frames after last detection
    var smoothingAlpha: Float = 0.3     // EMA smoothing for energy

    private var audioEngine: AVAudioEngine?
    private var isRunning = false
    private var consecutiveSpeechFrames = 0
    private var hangoverCounter = 0
    private var smoothedEnergy: Float = -60.0

    private let analysisQueue = DispatchQueue(label: "com.shoudeng.vad", qos: .userInteractive)
    private let frameSize = 512 // ~11.6ms at 44.1kHz
    private let sampleRate: Float = 44100.0

    private init() {}

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }

        #if targetEnvironment(simulator)
        // Simulator has no real mic — simulate periodic voice detection for testing
        isRunning = true
        return
        #endif

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: UInt32(frameSize), format: format) { [weak self] buffer, _ in
            self?.processBuffer(buffer)
        }

        do {
            try engine.start()
            audioEngine = engine
            isRunning = true
        } catch {
            #if DEBUG
            print("[VAD] Failed to start: \(error)")
            #endif
        }
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRunning = false
        DispatchQueue.main.async {
            self.isVoiceDetected = false
            self.currentEnergy = -60
        }
    }

    // MARK: - Frame Processing

    private func processBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameLength = Int(buffer.frameLength)
        guard frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channelData[0], count: frameLength))

        analysisQueue.async { [weak self] in
            guard let self else { return }

            let energy = self.computeEnergy(samples)
            let zcr = self.computeZeroCrossingRate(samples)
            let flatness = self.computeSpectralFlatness(samples)

            // Smooth energy
            self.smoothedEnergy = self.smoothingAlpha * energy + (1.0 - self.smoothingAlpha) * self.smoothedEnergy

            // Voice decision: energy above threshold AND ZCR in voice range AND non-flat spectrum
            let isVoice = self.smoothedEnergy > self.energyThreshold
                && zcr >= self.zeroCrossingMin
                && zcr <= self.zeroCrossingMax
                && flatness < self.spectralFlatnessMax

            if isVoice {
                self.consecutiveSpeechFrames += 1
                self.hangoverCounter = self.hangoverFrames
            } else {
                self.consecutiveSpeechFrames = 0
                self.hangoverCounter = max(0, self.hangoverCounter - 1)
            }

            // Require at least 3 consecutive speech frames to trigger (debounce)
            let detected = self.consecutiveSpeechFrames >= 3 || self.hangoverCounter > 0

            DispatchQueue.main.async {
                self.isVoiceDetected = detected
                self.currentEnergy = self.smoothedEnergy
            }
        }
    }

    // MARK: - Signal Analysis

    /// RMS energy in dBFS
    private func computeEnergy(_ samples: [Float]) -> Float {
        var rms: Float = 0
        vDSP_rmsqv(samples, 1, &rms, vDSP_Length(samples.count))
        guard rms > 0 else { return -60.0 }
        return 20.0 * log10f(rms)
    }

    /// Zero-crossing rate: fraction of sign changes in the frame
    private func computeZeroCrossingRate(_ samples: [Float]) -> Float {
        guard samples.count > 1 else { return 0 }
        var crossings = 0
        for i in 1..<samples.count {
            if (samples[i] >= 0 && samples[i-1] < 0) || (samples[i] < 0 && samples[i-1] >= 0) {
                crossings += 1
            }
        }
        return Float(crossings) / Float(samples.count - 1)
    }

    /// Spectral flatness: geometric mean / arithmetic mean of magnitude spectrum
    /// Voice (tonal) has low flatness (~0.1-0.3); noise has high flatness (~0.7-1.0)
    private func computeSpectralFlatness(_ samples: [Float]) -> Float {
        let n = samples.count
        guard n >= 2 else { return 1.0 }

        // Simple DFT magnitude via vDSP
        let halfN = n / 2
        var realPart = [Float](repeating: 0, count: halfN)
        var imagPart = [Float](repeating: 0, count: halfN)

        // Compute magnitude spectrum manually (lightweight, no FFT setup needed for small frames)
        for k in 0..<halfN {
            var re: Float = 0
            var im: Float = 0
            for i in 0..<n {
                let angle = -2.0 * Float.pi * Float(k) * Float(i) / Float(n)
                re += samples[i] * cosf(angle)
                im += samples[i] * sinf(angle)
            }
            realPart[k] = sqrtf(re * re + im * im) + 1e-10
            imagPart[k] = realPart[k] // reuse for log computation
        }

        // Geometric mean = exp(mean(log(magnitudes)))
        var logMagnitudes = [Float](repeating: 0, count: halfN)
        var count = Int32(halfN)
        vvlogf(&logMagnitudes, &realPart, &count)

        var logMean: Float = 0
        vDSP_meanv(logMagnitudes, 1, &logMean, vDSP_Length(halfN))
        let geometricMean = expf(logMean)

        // Arithmetic mean
        var arithmeticMean: Float = 0
        vDSP_meanv(realPart, 1, &arithmeticMean, vDSP_Length(halfN))

        guard arithmeticMean > 0 else { return 1.0 }
        return min(1.0, geometricMean / arithmeticMean)
    }
}
