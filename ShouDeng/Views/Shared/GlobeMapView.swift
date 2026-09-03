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

    private let tilt: Double = 20
    private let speed: Double = 6

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: false)) { timeline in
            Canvas { ctx, size in
                draw(ctx: &ctx, size: size, time: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
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
            let glowR: CGFloat = pin.isMe ? 12 : 8
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - glowR, y: pt.y - glowR, width: glowR * 2, height: glowR * 2)),
                with: .color(pin.color.opacity(0.18 * alpha))
            )

            // Inner glow
            let innerR: CGFloat = pin.isMe ? 7 : 5
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - innerR, y: pt.y - innerR, width: innerR * 2, height: innerR * 2)),
                with: .color(pin.color.opacity(0.35 * alpha))
            )

            // Core dot
            let coreR: CGFloat = pin.isMe ? 4.5 : 3
            ctx.fill(
                Path(ellipseIn: CGRect(x: pt.x - coreR, y: pt.y - coreR, width: coreR * 2, height: coreR * 2)),
                with: .color(pin.color.opacity(alpha))
            )

            // City label (only when facing forward enough)
            if pt.z > 0.4 {
                let resolved = ctx.resolve(
                    Text(pin.label)
                        .font(.system(size: pin.isMe ? 9.5 : 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.8 * alpha))
                )
                ctx.draw(resolved, at: CGPoint(x: pt.x, y: pt.y - glowR - 5), anchor: .bottom)
            }
        }
    }
}

// MARK: - Pin Presets

extension GlobeMapView {

    private static let lamp = Color(red: 232/255, green: 163/255, blue: 61/255)
    private static let safe = Color(red: 63/255, green: 143/255, blue: 110/255)
    private static let pro  = Color(red: 107/255, green: 92/255, blue: 165/255)

    /// Protected Person portal (A1) — "me" is 小雨 in Kyiv
    static let protectedPersonPins: [Pin] = [
        Pin(label: "我 · 基辅",   latitude: 50.45,  longitude: 30.52,  color: lamp, isMe: true),
        Pin(label: "妈妈",        latitude: 43.65,  longitude: -79.38, color: safe, isMe: false),
        Pin(label: "姑姑",        latitude: -33.87, longitude: 151.21, color: safe, isMe: false),
        Pin(label: "爸爸",        latitude: 44.15,  longitude: -79.88, color: safe, isMe: false),
        Pin(label: "响应中心",     latitude: 25.20,  longitude: 55.27,  color: pro,  isMe: false),
        Pin(label: "响应中心",     latitude: 50.11,  longitude: 8.68,   color: pro,  isMe: false),
    ]

    static let protectedPersonLinks: [Link] = [
        Link(from: 1, to: 0), // 妈妈 → 我
        Link(from: 2, to: 0), // 姑姑 → 我
        Link(from: 3, to: 0), // 爸爸 → 我
        Link(from: 4, to: 0), // 响应中心 Dubai → 我
        Link(from: 5, to: 0), // 响应中心 Frankfurt → 我
    ]

    /// Guardian portal (B1) — "me" is 妈妈 in Toronto
    static let guardianPins: [Pin] = [
        Pin(label: "小雨 · 基辅",  latitude: 50.45,  longitude: 30.52,  color: lamp, isMe: false),
        Pin(label: "奶奶 · 上海",  latitude: 31.23,  longitude: 121.47, color: lamp, isMe: false),
        Pin(label: "弟弟 · 伦敦",  latitude: 51.50,  longitude: -0.12,  color: lamp, isMe: false),
        Pin(label: "你 · 多伦多",  latitude: 43.65,  longitude: -79.38, color: safe, isMe: true),
        Pin(label: "姑姑 · 悉尼",  latitude: -33.87, longitude: 151.21, color: safe, isMe: false),
        Pin(label: "响应中心",     latitude: 25.20,  longitude: 55.27,  color: pro,  isMe: false),
        Pin(label: "响应中心",     latitude: 1.35,   longitude: 103.82, color: pro,  isMe: false),
    ]

    static let guardianLinks: [Link] = [
        Link(from: 3, to: 0), // 你 → 小雨
        Link(from: 3, to: 1), // 你 → 奶奶
        Link(from: 3, to: 2), // 你 → 弟弟
        Link(from: 4, to: 0), // 姑姑 → 小雨
        Link(from: 5, to: 0), // 响应中心 → 小雨
        Link(from: 6, to: 1), // 响应中心 → 奶奶
    ]
}
