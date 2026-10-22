import Foundation
import AVFoundation

// MARK: - Audio Session Coordinator
//
// Manages shared microphone access between DistressDetectionService
// and VoiceCommandService. Only one can use the mic at a time.

final class AudioSessionCoordinator: ObservableObject {

    enum ActiveService: String {
        case none
        case distressDetection
        case voiceCommand
    }

    @Published private(set) var activeService: ActiveService = .none

    weak var distressService: DistressDetectionService?
    weak var voiceService: VoiceCommandService?

    // User preferences
    @Published var distressDetectionEnabled: Bool = false {
        didSet { reconcile() }
    }

    @Published var voiceCommandEnabled: Bool = false {
        didSet { reconcile() }
    }

    func reconcile() {
        // Priority: voice command > distress detection (voice needs cleaner audio)
        if voiceCommandEnabled {
            distressService?.stop()
            voiceService?.start()
            activeService = .voiceCommand
        } else if distressDetectionEnabled {
            voiceService?.stop()
            distressService?.start()
            activeService = .distressDetection
        } else {
            voiceService?.stop()
            distressService?.stop()
            activeService = .none
        }
    }

    func stopAll() {
        voiceService?.stop()
        distressService?.stop()
        activeService = .none
    }
}
