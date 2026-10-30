import SwiftUI

// MARK: - Interactive Globe (Canvas)
//
// Orthographic globe projection — a direct port of the HTML design's
// JavaScript canvas globe. Draws a rotating dark sphere with grid lines,
// great-circle connection arcs between family members, and glowing dots
// at each person's location.

struct GlobeMapView: View {

    struct Pin {
        let label: String
        let latitude: Double
        let longitude: Double
        let color: Color
        let isMe: Bool
    }

    struct Link {
        let from: Int
        let to: Int
    }

    let pins: [Pin]
    var links: [Link] = []
    var initialLongitude: Double = -40
    /// Bands at the top/bottom covered by overlay text (card header, legend);
    /// labels are never drawn there.
    var labelInsets: EdgeInsets = EdgeInsets()

    private let tilt: Double = 20
    private let speed: Double = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(globeAccessibilityLabel)
    }

    private var globeAccessibilityLabel: String {
        let lm = LanguageManager.shared
        if pins.isEmpty { return lm.localized("globe.a11y.empty") }
        let names = Self.labelGroups(pins).map(\.label).joined(separator: "; ")
        return String(format: lm.localized("globe.a11y.members"), pins.count, names)
    }

    // MARK: - Label grouping

    /// One label per place: people closer than `mergeKm` share a single dot label
    /// ("Xiulan Chen, Jianguo Chen · Chengdu") instead of drawing overlapping text.
    struct LabelGroup: Equatable {
        let label: String
        let latitude: Double
        let longitude: Double
        let pinIndices: [Int]
    }

    static let mergeKm: Double = 40

    static func labelGroups(_ pins: [Pin]) -> [LabelGroup] {
        var groups: [[Int]] = []
        for (i, pin) in pins.enumerated() {
            if let g = groups.firstIndex(where: { group in
                group.contains { distanceKm(pins[$0], pin) < mergeKm }
            }) {
                groups[g].append(i)
            } else {
                groups.append([i])
            }
        }
        return groups.map { idx in
            let members = idx.map { pins[$0] }
            return LabelGroup(
                label: mergedLabel(members.map(\.label)),
                latitude: members[0].latitude,
                longitude: members[0].longitude,
                pinIndices: idx
            )
        }
    }

    /// "A · City" + "B · City" → "A, B · City"; 3+ names → "A +2 · City".
    static func mergedLabel(_ labels: [String]) -> String {
        guard labels.count > 1 else { return labels.first ?? "" }
        let parts = labels.map { $0.components(separatedBy: " · ") }
        let names = parts.map { $0[0] }
        let suffixes = Set(parts.map { $0.count > 1 ? $0.dropFirst().joined(separator: " · ") : "" })
        let who = names.count > 2 ? "\(names[0]) +\(names.count - 1)" : names.joined(separator: ", ")
        if suffixes.count == 1, let suffix = suffixes.first, !suffix.isEmpty {
            return "\(who) · \(suffix)"
        }
        return who
    }

    private static func distanceKm(_ a: Pin, _ b: Pin) -> Double {
        let rad = Double.pi / 180
        let dLat = (b.latitude - a.latitude) * rad
        let dLon = (b.longitude - a.longitude) * rad
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(a.latitude * rad) * cos(b.latitude * rad) * sin(dLon / 2) * sin(dLon / 2)
        return 6371 * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    // MARK: - Rendering

    private func draw(ctx: inout GraphicsContext, size: CGSize, time: TimeInterval) {
        let cx = size.width / 2
        let cy = size.height / 2
        let R = min(size.width, size.height) * 0.42
        let RAD = Double.pi / 180
        let phi = tilt * RAD
        let lam = (initialLongitude + time * speed) * RAD

        // Orthographic projection (matches HTML proj() function)
        func proj(_ lo: Double, _ la: Double) -> (x: Double, y: Double, z: Double) {
            let l = lo * RAD + lam
            let p = la * RAD
            let cp = cos(p), sp = sin(p), cl = cos(l), sl = sin(l)
            return (
                x: cx + R * cp * sl,
                y: cy - R * (cos(phi) * sp - sin(phi) * cp * cl),
                z: sin(phi) * sp + cos(phi) * cp * cl
            )
        }

        // --- Globe body ---
        let globe = CGRect(x: cx - R, y: cy - R, width: R * 2, height: R * 2)
        ctx.fill(Path(ellipseIn: globe), with: .color(Color(red: 44/255, green: 70/255, blue: 112/255).opacity(0.2)))
        ctx.stroke(Path(ellipseIn: globe), with: .color(.white.opacity(0.22)), lineWidth: 0.8)

        // --- Grid lines ---
        let gridColor: GraphicsContext.Shading = .color(.white.opacity(0.09))
        for i in stride(from: -180, to: 180, by: 24) {
            var p = Path(); var on = false
            for j in stride(from: -90, through: 90, by: 4) {
                let pt = proj(Double(i), Double(j))
                if pt.z > 0 { if !on { p.move(to: CGPoint(x: pt.x, y: pt.y)); on = true } else { p.addLine(to: CGPoint(x: pt.x, y: pt.y)) } } else { on = false }
            }
            ctx.stroke(p, with: gridColor, lineWidth: 0.5)
        }
        for i in stride(from: -60, through: 60, by: 24) {
            var p = Path(); var on = false
            for j in stride(from: -180, through: 180, by: 4) {
                let pt = proj(Double(j), Double(i))
                if pt.z > 0 { if !on { p.move(to: CGPoint(x: pt.x, y: pt.y)); on = true } else { p.addLine(to: CGPoint(x: pt.x, y: pt.y)) } } else { on = false }
            }
            ctx.stroke(p, with: gridColor, lineWidth: 0.5)
        }

        // --- Connection arcs (great circles via SLERP) ---
        func vec(_ lo: Double, _ la: Double) -> (Double, Double, Double) {
            let a = lo * RAD, b = la * RAD, cb = cos(b)
            return (cb * cos(a), cb * sin(a), sin(b))
        }
        func ll(_ v: (Double, Double, Double)) -> (Double, Double) {
            (atan2(v.1, v.0) / RAD, asin(max(-1, min(1, v.2))) / RAD)
        }
        func slerp(_ aPin: Pin, _ bPin: Pin, _ t: Double) -> (Double, Double) {
            let u = vec(aPin.longitude, aPin.latitude)
            let v = vec(bPin.longitude, bPin.latitude)
            let d = max(-1.0, min(1.0, u.0*v.0 + u.1*v.1 + u.2*v.2))
            let omega = acos(d)
            if omega < 1e-6 { return ll(u) }
            let so = sin(omega)
            let s1 = sin((1-t)*omega)/so, s2 = sin(t*omega)/so
            return ll((u.0*s1+v.0*s2, u.1*s1+v.1*s2, u.2*s1+v.2*s2))
        }

        let lampArc = Color(red: 232/255, green: 163/255, blue: 61/255).opacity(0.4)
        let proArc  = Color(red: 107/255, green: 92/255, blue: 165/255).opacity(0.45)

        for link in links {
            guard link.from < pins.count, link.to < pins.count else { continue }
            let a = pins[link.from], b = pins[link.to]
            var p = Path(); var on = false
            for step in stride(from: 0.0, through: 1.0, by: 0.025) {
                let (lo, la) = slerp(a, b, step)
                let pt = proj(lo, la)
                if pt.z > 0 { if !on { p.move(to: CGPoint(x: pt.x, y: pt.y)); on = true } else { p.addLine(to: CGPoint(x: pt.x, y: pt.y)) } } else { on = false }
            }
            let isHub = a.label.contains("响应") || b.label.contains("响应")
            ctx.stroke(p, with: .color(isHub ? proArc : lampArc), lineWidth: 1)
        }

        // --- Dots and labels ---
        for pin in pins {
            let pt = proj(pin.longitude, pin.latitude)
            guard pt.z > 0 else { continue }

            let alpha = min(1.0, 0.4 + pt.z)

            // Outer glow
            let glowR: CGFloat = pin.isMe ? 14 : 10
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - glowR, y: pt.y - glowR, width: glowR * 2, height: glowR * 2)),
                with: .color(pin.color.opacity(0.18 * alpha))
            )

            // Inner glow
            let innerR: CGFloat = pin.isMe ? 8 : 6
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - innerR, y: pt.y - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(pin.color.opacity(0.35 * alpha))
            )

            // Core dot
            let coreR: CGFloat = pin.isMe ? 5.5 : 4
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - coreR, y: pt.y - coreR, width: coreR * 2, height: coreR * 2)),
                with: .color(pin.color.opacity(alpha))
            )

        }

        // --- Labels: one per place, nudged apart if they still collide on screen ---
        var placed: [CGRect] = []
        for group in Self.labelGroups(pins) {
            let pt = proj(group.longitude, group.latitude)
            // City label (only when facing forward enough)
            guard pt.z > 0.2 else { continue }
            let alpha = min(1.0, 0.4 + pt.z)
            let isMe = group.pinIndices.contains { pins[$0].isMe }
            let glowR: CGFloat = isMe ? 14 : 10
            let resolved = ctx.resolve(
                Text(group.label)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.9 * alpha))
            )
            let textSize = resolved.measure(in: CGSize(width: size.width, height: 40))
            // Prefer above the dot; then below; then further up.
            let candidates: [CGFloat] = [
                pt.y - glowR - 6 - textSize.height,
                pt.y + glowR + 4,
                pt.y - glowR - 8 - textSize.height * 2,
            ]
            let allowed = CGRect(x: 0, y: labelInsets.top, width: size.width,
                                 height: size.height - labelInsets.top - labelInsets.bottom)
            var chosen: CGRect?
            for top in candidates {
                let r = CGRect(x: pt.x - textSize.width / 2, y: top, width: textSize.width, height: textSize.height)
                if allowed.contains(CGRect(x: allowed.minX, y: r.minY, width: 1, height: r.height)),
                   !placed.contains(where: { $0.insetBy(dx: -2, dy: -1).intersects(r) }) {
                    chosen = r
                    break
                }
            }
            // No free spot this frame (e.g. dot under the header): skip the label rather than overlap
            guard let rect = chosen else { continue }
            placed.append(rect)
            ctx.draw(resolved, at: CGPoint(x: rect.midX, y: rect.minY), anchor: .top)
        }
    }
}

// MARK: - Pin Presets

extension GlobeMapView {

    private static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private static let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private static let pro  = Color(red: 107/255, green: 92/255, blue: 165/255)

    // Pin presets removed — globe now uses dynamic pins from real data only
}
