import Foundation
import CoreMotion
import CoreBluetooth
import CoreLocation
import Accelerate
import simd

// MARK: - IndoorPositioningService
//
// BLE + motion fusion indoor positioning using an Extended Kalman Filter (EKF).
//
// Architecture:
//   - State vector x = [x, y, vx, vy] in meters relative to a GPS-fixed origin
//   - Prediction: dead reckoning from CMPedometer steps × stride length × CMDeviceMotion yaw
//   - Update: BLE RSSI triangulation from known BLEAnchors (min 3 anchors)
//   - RSSI→distance: path-loss model  d = 10^((txPower - rssi) / (10 × n)),  n = 2.5 indoor
//   - Mode switching: GPS (<15 m) → fusion → dead reckoning (no anchors)
//   - Floor detection: CMAltimeter relative altitude change > 2.5 m triggers floor event
//   - All heavy matrix math uses Accelerate vDSP / simd for performance

final class IndoorPositioningService: NSObject, ObservableObject {

    // MARK: - Published State

    @Published private(set) var estimatedPosition: CLLocationCoordinate2D = .init(latitude: 0, longitude: 0)
    @Published private(set) var accuracy: Double = 999          // metres
    @Published private(set) var isActive: Bool = false
    @Published private(set) var positionSource: PositionSource = .gps
    @Published private(set) var currentFloor: Int = 0
    @Published private(set) var floorChangedAt: Date?

    // MARK: - Public Types

    enum PositionSource: String {
        case gps
        case ble
        case fusion
        case deadReckoning
    }

    /// A fixed BLE anchor at a known coordinate whose RSSI we use for ranging.
    struct BLEAnchor: Identifiable {
        let id: UUID
        let coordinate: CLLocationCoordinate2D
        let txPower: Int8               // calibrated Tx power at 1 m (dBm)
        var smoothedRSSI: Double?       // EMA-smoothed RSSI
        var rssiVariance: Double = 25   // running variance estimate (dBm²)
        var lastSeen: Date?
    }

    // MARK: - Configuration

    struct Configuration {
        /// User height in metres — used to estimate stride length.
        var userHeightMetres: Double = 1.70
        /// Override stride length; nil = derive from height or GPS calibration.
        var manualStrideLengthMetres: Double? = nil
        /// Path-loss exponent n for indoor RSSI→distance model.
        var pathLossExponent: Double = 2.5
        /// EMA alpha for RSSI smoothing (0 = no change, 1 = instant).
        var rssiEMAAlpha: Double = 0.3
        /// Min anchors required for trilateration.
        var minAnchorsForTrilateration: Int = 3
        /// GPS accuracy threshold (m) below which GPS is used directly.
        var gpsPrecisionThreshold: Double = 15
        /// GPS accuracy threshold (m) above which fusion takes over.
        var gpsUncertaintyThreshold: Double = 30
        /// Altitude delta (m) that constitutes a floor change.
        var floorAltitudeThreshold: Double = 2.5
    }

    var configuration = Configuration()

    // MARK: - Private State

    // Registered BLE anchors (keyed by peripheral UUID string)
    private var anchors: [String: BLEAnchor] = [:]

    // GPS origin used for local-frame conversions
    private var gpsOrigin: CLLocation?
    private var lastGPSLocation: CLLocation?

    // Adaptive stride length (updated from GPS calibration)
    private var calibratedStrideLength: Double?

    // Pedometer baseline
    private var pedometerStepBaseline: Int = 0
    private var lastPedometerUpdate: Date?

    // Altimeter
    private var altitudeOrigin: Double?       // relative metres at session start
    private var lastRelativeAltitude: Double = 0

    // Dead-reckoning heading (radians, east = 0)
    private var currentHeadingRadians: Double = 0

    // EKF matrices stored column-major for Accelerate (4×4 = 16 doubles)
    private var ekfX = simd_double4(0, 0, 0, 0)    // state [x, y, vx, vy]
    private var ekfP = matrix_identity_double4x4    // covariance

    private var ekfInitialized: Bool = false

    // CoreMotion
    private let motionManager = CMMotionManager()
    private let pedometer = CMPedometer()
    private let altimeter = CMAltimeter()
    private let activityManager = CMMotionActivityManager()
    private let motionQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.shoudeng.indoorPositioning.motion"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    // CoreBluetooth
    private var centralManager: CBCentralManager?
    private let bleQueue = DispatchQueue(label: "com.shoudeng.indoorPositioning.ble", qos: .userInitiated)

    // Anchor scan service UUID (anchors advertise this)
    static let anchorServiceUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")

    // EKF update timer
    private var ekfTimer: Timer?
    private let ekfHz: Double = 10      // 10 Hz prediction loop

    // Floor tracking
    private var floorEventCallbacks: [(Int) -> Void] = []

    // MARK: - Initialisation

    override init() {
        super.init()
    }

    // MARK: - Lifecycle

    func start(withGPSLocation initialGPS: CLLocation? = nil) {
        guard !isActive else { return }

        if let gps = initialGPS {
            setGPSOrigin(gps)
        }

        startBLEScanning()
        startMotionSensors()
        startAltimeter()

        ekfTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / ekfHz, repeats: true) { [weak self] _ in
            self?.ekfPredictionTick()
        }

        DispatchQueue.main.async {
            self.isActive = true
        }
    }

    func stop() {
        ekfTimer?.invalidate()
        ekfTimer = nil
        centralManager?.stopScan()
        motionManager.stopDeviceMotionUpdates()
        pedometer.stopUpdates()
        altimeter.stopRelativeAltitudeUpdates()

        DispatchQueue.main.async {
            self.isActive = false
        }
    }

    // MARK: - Anchor Registration

    /// Register a known BLE anchor at a fixed real-world coordinate.
    /// Call this for each anchor installed in the building.
    func registerAnchor(_ anchor: BLEAnchor) {
        anchors[anchor.id.uuidString] = anchor
    }

    func removeAnchor(id: UUID) {
        anchors.removeValue(forKey: id.uuidString)
    }

    func registerAnchors(_ list: [BLEAnchor]) {
        list.forEach { registerAnchor($0) }
    }

    /// Update anchor list from server payload (decode and replace).
    func loadAnchorsFromServer(_ list: [BLEAnchor]) {
        anchors.removeAll()
        list.forEach { registerAnchor($0) }
    }

    // MARK: - GPS Feed (call from ReactiveLocationService / AdaptiveLocationManager)

    func updateGPSLocation(_ location: CLLocation) {
        lastGPSLocation = location

        let accuracy = location.horizontalAccuracy

        if gpsOrigin == nil {
            setGPSOrigin(location)
        }

        // GPS calibration of stride length
        calibrateStrideLength(with: location)

        // Mode selection
        if accuracy > 0 && accuracy < configuration.gpsPrecisionThreshold {
            // GPS is good — snap EKF state to GPS measurement
            if let local = localPoint(from: location.coordinate) {
                ekfX = simd_double4(local.x, local.y, ekfX.z, ekfX.w)
                // Reset covariance to GPS accuracy
                let gpsCov = accuracy * accuracy
                ekfP = matrix_double4x4(diagonal: simd_double4(gpsCov, gpsCov, 1.0, 1.0))
                ekfInitialized = true
            }
            updateOutput(source: .gps, accuracy: accuracy)
        } else if accuracy > configuration.gpsUncertaintyThreshold {
            // GPS too noisy — switch to fusion / dead reckoning
            selectFusionMode()
        }
    }

    // MARK: - Floor Change Observation

    func onFloorChange(_ callback: @escaping (Int) -> Void) {
        floorEventCallbacks.append(callback)
    }

    // MARK: - Private: GPS Origin & Coordinate Conversion

    private func setGPSOrigin(_ location: CLLocation) {
        gpsOrigin = location
        // Reset EKF to origin
        ekfX = simd_double4(0, 0, 0, 0)
        let initialCov = (location.horizontalAccuracy > 0 ? location.horizontalAccuracy : 50.0)
        ekfP = matrix_double4x4(diagonal: simd_double4(initialCov * initialCov,
                                                        initialCov * initialCov,
                                                        1.0, 1.0))
        ekfInitialized = true
    }

    /// Convert WGS84 coordinate to local Cartesian (metres from origin).
    private func localPoint(from coord: CLLocationCoordinate2D) -> simd_double2? {
        guard let origin = gpsOrigin else { return nil }
        let lat0 = origin.coordinate.latitude * .pi / 180
        let metersPerDegLat = 111_132.92
        let metersPerDegLon = 111_132.92 * cos(lat0)
        let dx = (coord.longitude - origin.coordinate.longitude) * metersPerDegLon
        let dy = (coord.latitude  - origin.coordinate.latitude)  * metersPerDegLat
        return simd_double2(dx, dy)
    }

    /// Convert local Cartesian (metres from origin) back to WGS84.
    private func wgs84(from local: simd_double2) -> CLLocationCoordinate2D {
        guard let origin = gpsOrigin else { return estimatedPosition }
        let lat0 = origin.coordinate.latitude * .pi / 180
        let metersPerDegLat = 111_132.92
        let metersPerDegLon = 111_132.92 * cos(lat0)
        let lat = origin.coordinate.latitude  + local.y / metersPerDegLat
        let lon = origin.coordinate.longitude + local.x / metersPerDegLon
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    // MARK: - Private: EKF Prediction Step (Dead Reckoning)

    private var pendingStepDistance: Double = 0     // metres accumulated since last tick
    private var stepDetectionConfidence: Double = 0.8

    private func ekfPredictionTick() {
        guard ekfInitialized else { return }

        let dt = 1.0 / ekfHz

        // --- State transition matrix F (constant-velocity model) ---
        // x_new = F * x_old + B * u
        //
        //   [ 1  0  dt  0 ]
        //   [ 0  1   0 dt ]
        //   [ 0  0   1  0 ]
        //   [ 0  0   0  1 ]
        let F = matrix_double4x4(columns: (
            simd_double4(1,  0,  0, 0),
            simd_double4(0,  1,  0, 0),
            simd_double4(dt, 0,  1, 0),
            simd_double4(0, dt,  0, 1)
        ))

        // --- Control input from pedometer ---
        // Motion update: Δposition in heading direction
        let stepDist = pendingStepDistance
        pendingStepDistance = 0

        let dx = stepDist * cos(currentHeadingRadians)
        let dy = stepDist * sin(currentHeadingRadians)
        let vx = stepDist > 0 ? dx / dt : ekfX.z
        let vy = stepDist > 0 ? dy / dt : ekfX.w

        let xPred = simd_double4(
            ekfX.x + dx,
            ekfX.y + dy,
            vx,
            vy
        )

        // --- Process noise Q ---
        // Scaled by step detection confidence: less confidence → more noise
        let posNoise = (1.0 - stepDetectionConfidence) * 0.5 + 0.05   // metres²
        let velNoise = 0.1
        let Q = matrix_double4x4(diagonal: simd_double4(posNoise, posNoise, velNoise, velNoise))

        // --- Covariance prediction: P = F*P*F' + Q ---
        let FP   = matMul4x4(F, ekfP)
        let FPFt = matMul4x4(FP, matTranspose4x4(F))
        var PPred = matAdd4x4(FPFt, Q)

        // --- BLE Update Step ---
        let visibleAnchors = anchors.values.filter {
            guard let seen = $0.lastSeen else { return false }
            return Date().timeIntervalSince(seen) < 5.0  // seen within 5 s
        }

        if visibleAnchors.count >= configuration.minAnchorsForTrilateration {
            (ekfX, PPred) = ekfBLEUpdate(xPred: xPred, PPred: PPred, anchors: Array(visibleAnchors))
            updateOutput(source: anchors.count >= configuration.minAnchorsForTrilateration ? .fusion : .ble,
                         accuracy: sqrt(PPred.columns.0.x + PPred.columns.1.y))
        } else {
            // No BLE update available — pure dead reckoning
            ekfX = xPred
            updateOutput(source: .deadReckoning,
                         accuracy: sqrt(PPred.columns.0.x + PPred.columns.1.y))
        }

        ekfP = PPred
    }

    // MARK: - Private: EKF BLE Update Step

    private func ekfBLEUpdate(xPred: simd_double4,
                               PPred: matrix_double4x4,
                               anchors: [BLEAnchor]) -> (simd_double4, matrix_double4x4) {
        var x = xPred
        var P = PPred

        for anchor in anchors {
            guard let rssi = anchor.smoothedRSSI,
                  let anchorLocal = localPoint(from: anchor.coordinate) else { continue }

            // RSSI → distance estimate
            let distMeasured = rssiToDistance(rssi: rssi, txPower: anchor.txPower)

            // Predicted distance from current state
            let dx = x.x - anchorLocal.x
            let dy = x.y - anchorLocal.y
            let distPredicted = max(sqrt(dx * dx + dy * dy), 0.01)

            // Innovation: scalar measurement residual
            let y_innov = distMeasured - distPredicted

            // Jacobian H = dh/dx = [(x-ax)/d, (y-ay)/d, 0, 0]
            let H = simd_double4(dx / distPredicted, dy / distPredicted, 0, 0)

            // Measurement noise R based on RSSI variance
            let R = anchor.rssiVariance * 2.0   // propagated distance noise (m²)

            // Innovation covariance S = H*P*H' + R
            let PH = matVecMul4x4(P, H)
            let S = dot(H, PH) + R

            guard S > 1e-9 else { continue }

            // Kalman gain K = P*H'/S
            let K = simd_double4(PH.x / S, PH.y / S, PH.z / S, PH.w / S)

            // State update: x = x + K * y
            x = x + K * y_innov

            // Covariance update: P = (I - K*H) * P   (Joseph form for stability)
            let KH = outerProduct4x4(K, H)
            let IminusKH = matSub4x4(matrix_identity_double4x4, KH)
            P = matMul4x4(IminusKH, P)
        }

        return (x, P)
    }

    // MARK: - Private: RSSI → Distance

    private func rssiToDistance(rssi: Double, txPower: Int8) -> Double {
        // Path-loss model: d = 10 ^ ((txPower - rssi) / (10 * n))
        let n = configuration.pathLossExponent
        let exponent = (Double(txPower) - rssi) / (10.0 * n)
        return pow(10.0, exponent)
    }

    // MARK: - Private: BLE Scanning

    private func startBLEScanning() {
        centralManager = CBCentralManager(delegate: self, queue: bleQueue)
    }

    private func resumeScanning() {
        guard let central = centralManager, central.state == .poweredOn else { return }
        central.scanForPeripherals(
            withServices: [IndoorPositioningService.anchorServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
        )
    }

    // MARK: - Private: Motion Sensors

    private func startMotionSensors() {
        // CMDeviceMotion — heading from attitude.yaw
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = 0.1  // 10 Hz
            motionManager.startDeviceMotionUpdates(
                using: .xMagneticNorthZVertical,
                to: motionQueue
            ) { [weak self] motion, error in
                guard let self, let motion, error == nil else { return }
                self.handleDeviceMotion(motion)
            }
        }

        // CMPedometer — step count + distance
        if CMPedometer.isStepCountingAvailable() {
            pedometer.startUpdates(from: Date()) { [weak self] data, error in
                guard let self, let data, error == nil else { return }
                self.handlePedometerData(data)
            }
        }

        // CMMotionActivityManager — confidence feed
        if CMMotionActivityManager.isActivityAvailable() {
            activityManager.startActivityUpdates(to: motionQueue) { [weak self] activity in
                guard let self, let activity else { return }
                self.handleMotionActivity(activity)
            }
        }
    }

    private func handleDeviceMotion(_ motion: CMDeviceMotion) {
        // yaw: rotation around vertical axis, 0 = magnetic north, CCW positive
        // We use East = 0, North = π/2 convention for local frame
        let yaw = motion.attitude.yaw
        // Convert: local heading = π/2 - yaw  (north offset from east)
        currentHeadingRadians = (.pi / 2) - yaw
    }

    private func handlePedometerData(_ data: CMPedometerData) {
        guard let dist = data.distance?.doubleValue else {
            // Fallback: steps × stride length
            let steps = data.numberOfSteps.intValue
            let stride = effectiveStrideLengthMetres()
            let totalDist = Double(steps) * stride
            pendingStepDistance += max(totalDist - (data.numberOfSteps.intValue == 0 ? 0 : 0), 0)
            return
        }
        // CMPedometer gives cumulative distance since start — take delta
        pendingStepDistance += dist
    }

    private func handleMotionActivity(_ activity: CMMotionActivity) {
        if activity.walking || activity.running {
            stepDetectionConfidence = Double(activity.confidence.rawValue + 1) / 3.0
        } else if activity.stationary {
            stepDetectionConfidence = 0.95
            pendingStepDistance = 0     // confident we are not moving
        } else {
            stepDetectionConfidence = 0.5
        }
    }

    // MARK: - Private: Altimeter

    private func startAltimeter() {
        guard CMAltimeter.isRelativeAltitudeAvailable() else { return }
        altimeter.startRelativeAltitudeUpdates(to: motionQueue) { [weak self] data, error in
            guard let self, let data, error == nil else { return }
            self.handleAltimeterData(data)
        }
    }

    private func handleAltimeterData(_ data: CMAltitudeData) {
        let rel = data.relativeAltitude.doubleValue    // metres

        if altitudeOrigin == nil {
            altitudeOrigin = rel
        }

        let deltaFromLast = rel - lastRelativeAltitude
        lastRelativeAltitude = rel

        if abs(deltaFromLast) >= configuration.floorAltitudeThreshold {
            let floorDelta = deltaFromLast > 0 ? 1 : -1
            let newFloor = currentFloor + floorDelta
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.currentFloor = newFloor
                self.floorChangedAt = Date()
                self.floorEventCallbacks.forEach { $0(newFloor) }
            }
        }
    }

    // MARK: - Private: Stride Length

    private func effectiveStrideLengthMetres() -> Double {
        if let manual = configuration.manualStrideLengthMetres { return manual }
        if let calibrated = calibratedStrideLength { return calibrated }
        // Anthropometric estimate: 0.415 × height
        return 0.415 * configuration.userHeightMetres
    }

    /// Use GPS-derived ground truth to calibrate stride length when GPS is accurate.
    private func calibrateStrideLength(with location: CLLocation) {
        guard location.horizontalAccuracy > 0,
              location.horizontalAccuracy < configuration.gpsPrecisionThreshold,
              let last = lastGPSLocation,
              Date().timeIntervalSince(last.timestamp) < 10
        else { return }

        let gpsDist = location.distance(from: last)
        guard gpsDist > 2.0 else { return }     // need meaningful movement

        let stepsInWindow = pendingStepDistance / effectiveStrideLengthMetres()
        guard stepsInWindow > 2 else { return }

        let newStride = gpsDist / stepsInWindow
        // EMA blend new estimate with previous
        if let existing = calibratedStrideLength {
            calibratedStrideLength = 0.8 * existing + 0.2 * newStride
        } else {
            calibratedStrideLength = newStride
        }
    }

    // MARK: - Private: Mode Selection & Output

    private func selectFusionMode() {
        let visibleCount = anchors.values.filter {
            guard let seen = $0.lastSeen else { return false }
            return Date().timeIntervalSince(seen) < 5.0
        }.count

        let source: PositionSource = visibleCount >= configuration.minAnchorsForTrilateration
            ? .fusion
            : .deadReckoning

        DispatchQueue.main.async {
            self.positionSource = source
        }
    }

    private func updateOutput(source: PositionSource, accuracy: Double) {
        let coord = wgs84(from: simd_double2(ekfX.x, ekfX.y))
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.estimatedPosition = coord
            self.accuracy = max(accuracy, 0.5)
            self.positionSource = source
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension IndoorPositioningService: CBCentralManagerDelegate {

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            resumeScanning()
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any],
                        rssi RSSI: NSNumber) {
        let rssiValue = RSSI.doubleValue
        guard rssiValue < 0 else { return }     // ignore invalid readings

        let peripheralUUID = peripheral.identifier.uuidString

        // Match against known anchors by UUID
        if var anchor = anchors[peripheralUUID] {
            // RSSI smoothing: exponential moving average
            let alpha = configuration.rssiEMAAlpha
            if let prev = anchor.smoothedRSSI {
                let smoothed = alpha * rssiValue + (1 - alpha) * prev
                // Update running variance
                let diff = rssiValue - smoothed
                anchor.rssiVariance = (1 - alpha) * anchor.rssiVariance + alpha * diff * diff
                anchor.smoothedRSSI = smoothed
            } else {
                anchor.smoothedRSSI = rssiValue
            }
            anchor.lastSeen = Date()
            anchors[peripheralUUID] = anchor
        } else {
            // Unknown peripheral — check if advertised name/service hints at being an anchor
            // (In production: server push maps peripheral UUIDs → anchor metadata)
            // Silently skip unregistered peripherals.
        }
    }
}

// MARK: - Matrix Helpers (Accelerate-backed 4×4 double operations)
//
// simd_double4x4 is stored column-major. All ops below use simd intrinsics
// which compile to NEON/AVX instructions on Apple Silicon.

private func matMul4x4(_ A: matrix_double4x4, _ B: matrix_double4x4) -> matrix_double4x4 {
    return A * B   // simd operator* performs column-major multiply natively
}

private func matTranspose4x4(_ M: matrix_double4x4) -> matrix_double4x4 {
    return M.transpose
}

private func matAdd4x4(_ A: matrix_double4x4, _ B: matrix_double4x4) -> matrix_double4x4 {
    return matrix_double4x4(columns: (
        A.columns.0 + B.columns.0,
        A.columns.1 + B.columns.1,
        A.columns.2 + B.columns.2,
        A.columns.3 + B.columns.3
    ))
}

private func matSub4x4(_ A: matrix_double4x4, _ B: matrix_double4x4) -> matrix_double4x4 {
    return matrix_double4x4(columns: (
        A.columns.0 - B.columns.0,
        A.columns.1 - B.columns.1,
        A.columns.2 - B.columns.2,
        A.columns.3 - B.columns.3
    ))
}

/// Multiply 4×4 matrix by column vector → column vector.
private func matVecMul4x4(_ M: matrix_double4x4, _ v: simd_double4) -> simd_double4 {
    return M * v
}

/// Outer product: K ⊗ H^T → 4×4 matrix  (used for Kalman covariance update).
/// Result[i][j] = K[i] * H[j]
private func outerProduct4x4(_ K: simd_double4, _ H: simd_double4) -> matrix_double4x4 {
    return matrix_double4x4(columns: (
        K * H.x,
        K * H.y,
        K * H.z,
        K * H.w
    ))
}
