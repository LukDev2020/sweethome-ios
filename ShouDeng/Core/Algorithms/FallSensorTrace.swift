import Foundation
import CoreMotion
import simd

// MARK: - Synthetic sensor traces for the fall detector
//
// 50 Hz device-motion samples (in g, like CoreMotion) for the situations the
// detector has to tell apart: a real fall, a fall down stairs, a dropped phone, sitting
// down hard, a jump, running. Used by the unit tests and by the debug "simulate a fall"
// action, which feeds a trace through the real detector so the whole chain runs —
// detector → "Are you OK?" countdown → SOS → guardians.
//
// The shapes follow the published fall datasets (SisFall, UMAFall): free fall dips the
// magnitude towards 0 g for 0.3–0.6 s from standing height, the impact peaks at 2.5–6 g,
// the body ends ~90° from upright, then lies still.

struct FallSensorTrace {
    struct Sample {
        let timestamp: TimeInterval
        let acceleration: CMAcceleration      // total (gravity + user), g
        let gravity: CMAcceleration
        let userAcceleration: CMAcceleration
    }

    static let rate: Double = 50

    private(set) var samples: [Sample] = []
    private var t: TimeInterval
    private var gravity: simd_double3
    private var rng: SeededRandom

    /// Phone upright in a trouser pocket: gravity along -y.
    static let upright = simd_double3(0, -1, 0)
    /// Lying on one side after a fall: rotated 90°.
    static let lyingOnSide = simd_double3(1, 0, 0)
    /// Phone flat on the floor, screen up.
    static let flat = simd_double3(0, 0, -1)

    init(start: TimeInterval = 1_000, orientation: simd_double3 = FallSensorTrace.upright, seed: UInt64 = 7) {
        t = start
        gravity = orientation
        rng = SeededRandom(seed: seed)
    }

    var duration: TimeInterval { (samples.last?.timestamp ?? t) - (samples.first?.timestamp ?? t) }

    // MARK: Building blocks

    /// Standing or sitting still (small sensor noise).
    mutating func still(_ seconds: Double, noise: Double = 0.01) -> Self {
        for _ in 0..<count(seconds) { add(user: jitter(noise)) }
        return self
    }

    /// Walking: ~1.8 steps/s, vertical bounce of `amplitude` g.
    mutating func walk(_ seconds: Double, amplitude: Double = 0.3) -> Self {
        periodic(seconds, hz: 1.8, amplitude: amplitude)
    }

    /// Running: ~2.8 steps/s with hard foot strikes (magnitude swings 0 g … 2.8 g: airborne, then the strike).
    mutating func run(_ seconds: Double) -> Self {
        periodic(seconds, hz: 2.8, amplitude: 1.8)
    }

    /// Falling freely: the phone measures close to 0 g.
    mutating func freeFall(_ seconds: Double, residual: Double = 0.15) -> Self {
        for _ in 0..<count(seconds) { add(user: -gravity * (1 - residual) + jitter(0.03)) }
        return self
    }

    /// A partial dip (stumbling, slumping, sitting down): magnitude drops to `to` g.
    mutating func dip(_ seconds: Double, to level: Double) -> Self {
        freeFall(seconds, residual: level)
    }

    /// Hitting the ground: a spike of `peak` g over ~100 ms while the body turns to
    /// `orientation` (the gravity estimate rotates through the impact).
    mutating func impact(peak: Double, orientation: simd_double3) -> Self {
        let n = 5   // odd, so the middle sample carries the full peak
        let from = gravity
        for i in 0..<n {
            let p = Double(i) / Double(max(n - 1, 1))
            gravity = simd_normalize(simd_mix(from, orientation, simd_double3(repeating: p)))
            // Triangle pulse: peak magnitude in the middle, along the new "down"
            let shape = 1 - abs(p * 2 - 1)
            add(user: gravity * (peak - 1) * shape + jitter(0.05))
        }
        gravity = orientation
        return self
    }

    /// Turning to a new orientation over `seconds` without a jolt (rolling over, picking up the phone).
    mutating func turn(to orientation: simd_double3, over seconds: Double) -> Self {
        let n = count(seconds)
        let from = gravity
        for i in 0..<n {
            let p = Double(i + 1) / Double(n)
            gravity = simd_normalize(simd_mix(from, orientation, simd_double3(repeating: p)))
            add(user: jitter(0.08))
        }
        return self
    }

    /// Moving about (getting up, picking the phone up): strong irregular movement.
    mutating func struggle(_ seconds: Double, amplitude: Double = 0.5) -> Self {
        for _ in 0..<count(seconds) { add(user: jitter(amplitude)) }
        return self
    }

    // MARK: Scenarios

    /// Walking, trip forward, ~0.45 s fall, 3.5 g impact, lies on their side without moving.
    static func forwardFall(stillFor seconds: Double = 20) -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(3)
        _ = t.walk(3)
        _ = t.freeFall(0.45)
        _ = t.impact(peak: 3.5, orientation: lyingOnSide)
        _ = t.struggle(0.6, amplitude: 0.25)   // bounce / settle after the impact
        _ = t.still(seconds, noise: 0.006)
        return t
    }

    /// Down a flight of stairs: ~0.9 s of falling before the impact.
    static func stairsFall() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.walk(3)
        _ = t.freeFall(0.9)
        _ = t.impact(peak: 4.5, orientation: lyingOnSide)
        _ = t.struggle(0.6, amplitude: 0.25)
        _ = t.still(20, noise: 0.006)
        return t
    }

    /// The fall happens, but they get up after a few seconds.
    static func fallThenGetUp() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.walk(3)
        _ = t.freeFall(0.45)
        _ = t.impact(peak: 3.5, orientation: lyingOnSide)
        _ = t.still(5, noise: 0.006)
        _ = t.struggle(3, amplitude: 0.6)
        _ = t.turn(to: upright, over: 1)
        _ = t.walk(10)
        return t
    }

    /// Phone slips out of the hand, hits the floor flat, is picked up again.
    static func phoneDroppedAndPickedUp() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(3)
        _ = t.freeFall(0.4, residual: 0.05)
        _ = t.impact(peak: 5, orientation: flat)
        _ = t.still(4, noise: 0.002)
        _ = t.struggle(2, amplitude: 0.5)
        _ = t.turn(to: upright, over: 1)
        _ = t.still(15)
        return t
    }

    /// Phone dropped and left on the floor — indistinguishable from a fall by the
    /// phone alone; the "Are you OK?" check is what stops a false alarm here.
    static func phoneDroppedAndLeft() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(3)
        _ = t.freeFall(0.4, residual: 0.05)
        _ = t.impact(peak: 5, orientation: flat)
        _ = t.still(20, noise: 0.002)
        return t
    }

    /// Dropping onto a chair: a short dip, a 2 g bump, ~30° lean back.
    static func sitDownHard() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(3)
        _ = t.dip(0.25, to: 0.7)
        _ = t.impact(peak: 2.0, orientation: simd_normalize(simd_double3(0, -0.87, -0.5)))
        _ = t.still(20)
        return t
    }

    /// A jump: airborne, lands hard, still upright.
    static func jump() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(3)
        _ = t.freeFall(0.35)
        _ = t.impact(peak: 3.2, orientation: upright)
        _ = t.still(20)
        return t
    }

    /// A 30-second run.
    static func running() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(2)
        _ = t.run(30)
        _ = t.still(20)
        return t
    }

    /// An older person slumping to the floor: no real free fall, a soft 2.2 g impact.
    static func slowSlump() -> FallSensorTrace {
        var t = FallSensorTrace()
        _ = t.still(3)
        _ = t.dip(0.5, to: 0.55)
        _ = t.impact(peak: 2.2, orientation: lyingOnSide)
        _ = t.still(20, noise: 0.006)
        return t
    }

    // MARK: Helpers

    private func count(_ seconds: Double) -> Int { max(1, Int((seconds * Self.rate).rounded())) }

    private mutating func periodic(_ seconds: Double, hz: Double, amplitude: Double) -> Self {
        for i in 0..<count(seconds) {
            let phase = Double(i) / Self.rate * hz * 2 * .pi
            add(user: -gravity * amplitude * sin(phase) + jitter(0.05))
        }
        return self
    }

    private mutating func jitter(_ amount: Double) -> simd_double3 {
        simd_double3(rng.next(amount), rng.next(amount), rng.next(amount))
    }

    private mutating func add(user: simd_double3) {
        let total = gravity + user
        samples.append(Sample(
            timestamp: t,
            acceleration: CMAcceleration(x: total.x, y: total.y, z: total.z),
            gravity: CMAcceleration(x: gravity.x, y: gravity.y, z: gravity.z),
            userAcceleration: CMAcceleration(x: user.x, y: user.y, z: user.z)
        ))
        t += 1 / Self.rate
    }
}

/// Deterministic noise so a scenario gives the same samples on every run.
struct SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
    /// Uniform in -amount…amount
    mutating func next(_ amount: Double) -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        let unit = Double(state >> 11) / Double(1 << 53)
        return (unit * 2 - 1) * amount
    }
}

extension FallDetector {
    /// Runs a trace through the detector (tests, debug simulation).
    func feed(_ trace: FallSensorTrace) {
        for s in trace.samples {
            feed(acceleration: s.acceleration, gravity: s.gravity, userAcceleration: s.userAcceleration, timestamp: s.timestamp)
        }
    }
}
