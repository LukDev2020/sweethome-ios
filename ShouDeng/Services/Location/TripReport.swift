import Foundation
import CoreLocation
import MapKit
import UIKit

// MARK: - Trip statistics
//
// Shared by the live track screen, the trip detail map and the PDF report.
// Pure functions of the recorded points, so they are unit-tested directly.

struct TripStats: Equatable {
    var distanceMeters: Double = 0
    var durationSeconds: TimeInterval = 0
    /// Time spent faster than a slow walk (stops and GPS jitter don't count)
    var movingSeconds: TimeInterval = 0
    /// Over the moving time, m/s
    var averageSpeed: Double = 0
    /// m/s; a single GPS jump can't set it (see `segmentSpeed`)
    var maxSpeed: Double = 0
    /// Metres climbed / descended, ignoring wobbles under `elevationNoise`
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var minAltitude: Double?
    var maxAltitude: Double?
    /// Median horizontal accuracy, metres
    var typicalAccuracy: Double?

    static let movingThreshold: Double = 0.5        // m/s
    static let elevationNoise: Double = 3           // m
    /// Faster than this between two fixes is a GPS jump, not travel
    static let implausibleSpeed: Double = 120       // m/s (≈ 430 km/h)

    static func compute(_ points: [TripPoint]) -> TripStats {
        var s = TripStats()
        guard let first = points.first, let last = points.last else { return s }
        s.durationSeconds = max(0, last.timestamp.timeIntervalSince(first.timestamp))

        for (a, b) in zip(points, points.dropFirst()) {
            let d = distance(a, b)
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            guard let v = segmentSpeed(a, b, distance: d, dt: dt) else { continue }
            s.distanceMeters += d
            if v > movingThreshold, dt > 0 { s.movingSeconds += dt }
            s.maxSpeed = max(s.maxSpeed, v)
        }
        s.averageSpeed = s.movingSeconds > 0 ? s.distanceMeters / s.movingSeconds : 0
        // The phone's speed readings lag distance / time a little: an average above
        // the top speed reads as a bug
        s.maxSpeed = max(s.maxSpeed, s.averageSpeed)

        // Climb with hysteresis: only count a change once it exceeds the noise
        let altitudes = points.compactMap(\.altitude)
        if let a0 = altitudes.first {
            s.minAltitude = altitudes.min()
            s.maxAltitude = altitudes.max()
            var anchor = a0
            for a in altitudes.dropFirst() {
                let delta = a - anchor
                if delta >= elevationNoise { s.elevationGain += delta; anchor = a }
                else if delta <= -elevationNoise { s.elevationLoss -= delta; anchor = a }
            }
        }

        let accuracies = points.map(\.accuracy).filter { $0 >= 0 }.sorted()
        if !accuracies.isEmpty { s.typicalAccuracy = accuracies[accuracies.count / 2] }
        return s
    }

    /// Speed between two fixes: the phone's own reading when it has one,
    /// else distance / time. nil for a GPS jump (implausibly fast).
    static func segmentSpeed(_ a: TripPoint, _ b: TripPoint, distance d: Double, dt: TimeInterval) -> Double? {
        let derived = dt > 0 ? d / dt : 0
        if dt > 0, derived > implausibleSpeed { return nil }
        if let reported = b.speed, reported >= 0 { return min(reported, implausibleSpeed) }
        return derived
    }

    static func distance(_ a: TripPoint, _ b: TripPoint) -> Double {
        CLLocation(latitude: a.latitude, longitude: a.longitude)
            .distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
    }

    /// Compass bearing a → b in degrees (0 = north)
    static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let rad = Double.pi / 180
        let la1 = a.latitude * rad, la2 = b.latitude * rad, dLon = (b.longitude - a.longitude) * rad
        let y = sin(dLon) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        let deg = atan2(y, x) / rad
        return deg < 0 ? deg + 360 : deg
    }

    /// Places the person stayed within `radius` metres for at least `minDuration`
    static func stops(_ points: [TripPoint], radius: Double = 50, minDuration: TimeInterval = 180) -> [TripStop] {
        var stops: [TripStop] = []
        var i = 0
        while i < points.count {
            let anchor = points[i]
            var j = i + 1
            while j < points.count, distance(anchor, points[j]) <= radius { j += 1 }
            let end = points[j - 1]
            let duration = end.timestamp.timeIntervalSince(anchor.timestamp)
            if duration >= minDuration {
                stops.append(TripStop(latitude: anchor.latitude, longitude: anchor.longitude,
                                      start: anchor.timestamp, end: end.timestamp))
                i = j
            } else {
                i += 1
            }
        }
        return stops
    }
}

struct TripStop: Equatable {
    let latitude: Double
    let longitude: Double
    let start: Date
    let end: Date
    var duration: TimeInterval { end.timeIntervalSince(start) }
}

// MARK: - Speed colours (Garmin-style track)

enum TrackSpeedBand: Int, CaseIterable {
    case slow, moderate, fast, veryFast

    /// < 5 km/h walking · < 20 km/h running / cycling · < 60 km/h town driving · faster
    static func band(for speed: Double) -> TrackSpeedBand {
        switch speed * 3.6 {
        case ..<5: return .slow
        case ..<20: return .moderate
        case ..<60: return .fast
        default: return .veryFast
        }
    }

    var uiColor: UIColor {
        switch self {
        case .slow: return UIColor(red: 63/255, green: 143/255, blue: 110/255, alpha: 1)    // green
        case .moderate: return UIColor(red: 61/255, green: 154/255, blue: 192/255, alpha: 1) // blue
        case .fast: return UIColor(red: 232/255, green: 163/255, blue: 61/255, alpha: 1)     // amber
        case .veryFast: return UIColor(red: 214/255, green: 69/255, blue: 65/255, alpha: 1)  // red
        }
    }

    var rangeLabel: String {
        switch self {
        case .slow: return "< 5 km/h"
        case .moderate: return "5–20 km/h"
        case .fast: return "20–60 km/h"
        case .veryFast: return "> 60 km/h"
        }
    }
}

/// A run of consecutive points in one speed band (the line is drawn as a few
/// coloured polylines, not one per point).
struct TrackRun: Equatable {
    let band: TrackSpeedBand
    let coordinates: [CLLocationCoordinate2D]

    static func == (l: TrackRun, r: TrackRun) -> Bool {
        l.band == r.band && l.coordinates.count == r.coordinates.count
            && zip(l.coordinates, r.coordinates).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
    }

    static func runs(_ points: [TripPoint]) -> [TrackRun] {
        guard points.count > 1 else { return [] }
        var runs: [TrackRun] = []
        var band: TrackSpeedBand?
        var coords: [CLLocationCoordinate2D] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let d = TripStats.distance(a, b)
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            let v = TripStats.segmentSpeed(a, b, distance: d, dt: dt) ?? 0
            let next = TrackSpeedBand.band(for: v)
            let ca = CLLocationCoordinate2D(latitude: a.latitude, longitude: a.longitude)
            let cb = CLLocationCoordinate2D(latitude: b.latitude, longitude: b.longitude)
            if next == band {
                coords.append(cb)
            } else {
                if let band, coords.count > 1 { runs.append(TrackRun(band: band, coordinates: coords)) }
                band = next
                coords = [ca, cb]   // shares the joint with the previous run: no gaps
            }
        }
        if let band, coords.count > 1 { runs.append(TrackRun(band: band, coordinates: coords)) }
        return runs
    }
}

// MARK: - Formatting

enum TripFormat {
    static func distance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.2f km", m / 1000) : String(format: "%.0f m", m)
    }

    static func speed(_ mps: Double) -> String {
        String(format: "%.1f km/h", mps * 3.6)
    }

    static func duration(_ s: TimeInterval) -> String {
        let t = Int(max(0, s))
        return t >= 3600
            ? String(format: "%d:%02d:%02d", t / 3600, (t % 3600) / 60, t % 60)
            : String(format: "%02d:%02d", t / 60, t % 60)
    }

    static func metres(_ m: Double?) -> String {
        guard let m else { return "—" }
        return String(format: "%.0f m", m)
    }
}

// MARK: - PDF report

struct TripReportInput {
    var personName: String
    var points: [TripPoint]
    /// Still being recorded (live track export)
    var inProgress: Bool = false
    var generatedAt: Date = Date()
}

enum TripReportPDF {

    static let pageSize = CGSize(width: 595, height: 842)   // A4 at 72 dpi
    static let margin: CGFloat = 40
    static let maxLogRows = 300

    private static let navy = UIColor(red: 1/255, green: 69/255, blue: 129/255, alpha: 1)
    private static let ink = UIColor(red: 14/255, green: 43/255, blue: 74/255, alpha: 1)
    private static let muted = UIColor(red: 14/255, green: 43/255, blue: 74/255, alpha: 0.55)
    private static let rule = UIColor(red: 1/255, green: 69/255, blue: 129/255, alpha: 0.15)

    /// The PDF, with an Apple Maps picture of the route (`includeMap`; falls back
    /// to a plain drawing of the line when the map can't be loaded, e.g. offline).
    static func render(_ input: TripReportInput, includeMap: Bool = true) async -> Data {
        var mapImage: UIImage?
        if includeMap, input.points.count > 1 {
            mapImage = await snapshot(input.points, size: CGSize(width: pageSize.width - 2 * margin, height: 330))
        }
        return draw(input, mapImage: mapImage)
    }

    /// Writes the report to a file named after the person and date (for sharing).
    static func write(_ data: Data, input: TripReportInput) throws -> URL {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HHmm"
        let stamp = df.string(from: input.points.first?.timestamp ?? input.generatedAt)
        let name = input.personName.isEmpty ? LanguageManager.shared.current.brandName : input.personName
        let safe = name.components(separatedBy: CharacterSet(charactersIn: "/\\:?%*|\"<>")).joined()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(safe)_trip_\(stamp).pdf")
        try data.write(to: url, options: .atomic)
        #if DEBUG
        // Simulator runs: keep a copy where `simctl get_app_container … data` finds it
        if let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let dir = docs.appendingPathComponent("TripReports")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: dir.appendingPathComponent(url.lastPathComponent), options: .atomic)
        }
        #endif
        return url
    }

    // MARK: Drawing

    private static func L(_ key: String) -> String { LanguageManager.shared.localized(key) }

    private static func draw(_ input: TripReportInput, mapImage: UIImage?) -> Data {
        let stats = TripStats.compute(input.points)
        let stops = TripStats.stops(input.points)
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(origin: .zero, size: pageSize),
                                             format: pdfFormat(input))
        var pageNumber = 0
        return renderer.pdfData { ctx in
            func newPage() -> CGFloat {
                ctx.beginPage()
                pageNumber += 1
                footer(input, page: pageNumber)
                return margin
            }

            // Page 1: header, summary, map
            var y = newPage()
            y = header(input, y: y)
            y = section(L("report.trip.summary"), y: y + 14)
            y = statGrid(stats, pointCount: input.points.count, y: y + 6)
            y = section(L("report.trip.route"), y: y + 18)
            let mapRect = CGRect(x: margin, y: y + 6, width: pageSize.width - 2 * margin, height: 330)
            if let mapImage {
                mapImage.draw(in: mapRect)
            } else {
                drawPlainTrack(input.points, in: mapRect)
            }
            UIColor.clear.setFill()
            rule.setStroke()
            UIBezierPath(roundedRect: mapRect, cornerRadius: 6).stroke()
            y = legend(y: mapRect.maxY + 8)

            // Page 2: charts and stops
            y = newPage()
            y = section(L("report.trip.speedChart"), y: y)
            y = chart(input.points, value: { $0.speed.map { max(0, $0) * 3.6 } }, unit: "km/h",
                      color: TrackSpeedBand.moderate.uiColor, y: y + 6)
            if let lo = stats.minAltitude, let hi = stats.maxAltitude, hi - lo >= 1 {
                y = section(L("report.trip.elevChart"), y: y + 18)
                y = chart(input.points, value: \.altitude, unit: "m",
                          color: TrackSpeedBand.slow.uiColor, y: y + 6)
            }
            y = section(L("report.trip.stops"), y: y + 18)
            y = stopsTable(stops, y: y + 6) { newPage() }

            // GPS log (sampled), on as many pages as it needs
            y = newPage()
            y = section(L("report.trip.log"), y: y)
            let sampled = sample(input.points, max: maxLogRows)
            let note = String(format: L("report.trip.log.note"), sampled.count, input.points.count)
            y = text(note, at: CGPoint(x: margin, y: y + 4), font: .systemFont(ofSize: 9), color: muted) + 6
            y = logTable(sampled, y: y) { newPage() }
        }
    }

    private static func pdfFormat(_ input: TripReportInput) -> UIGraphicsPDFRendererFormat {
        let f = UIGraphicsPDFRendererFormat()
        f.documentInfo = [
            kCGPDFContextTitle as String: L("report.trip.title"),
            kCGPDFContextAuthor as String: input.personName,
            kCGPDFContextCreator as String: "Beaconify",
        ]
        return f
    }

    @discardableResult
    private static func text(_ s: String, at p: CGPoint, font: UIFont, color: UIColor = ink,
                             width: CGFloat? = nil, alignment: NSTextAlignment = .left) -> CGFloat {
        let style = NSMutableParagraphStyle()
        style.alignment = alignment
        style.lineBreakMode = .byWordWrapping
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: style]
        let w = width ?? (pageSize.width - margin - p.x)
        let rect = (s as NSString).boundingRect(with: CGSize(width: w, height: .greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        (s as NSString).draw(with: CGRect(x: p.x, y: p.y, width: w, height: ceil(rect.height)),
                             options: [.usesLineFragmentOrigin], attributes: attrs, context: nil)
        return p.y + ceil(rect.height)
    }

    private static func header(_ input: TripReportInput, y: CGFloat) -> CGFloat {
        let band = CGRect(x: 0, y: 0, width: pageSize.width, height: 86)
        navy.setFill()
        UIRectFill(band)
        text(LanguageManager.shared.current.brandName, at: CGPoint(x: margin, y: 20), font: .boldSystemFont(ofSize: 13),
             color: UIColor.white.withAlphaComponent(0.8))
        text(L("report.trip.title"), at: CGPoint(x: margin, y: 38), font: .boldSystemFont(ofSize: 22), color: .white)

        var y = band.maxY + 16
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale(identifier: LanguageManager.shared.current.rawValue)
        let from = input.points.first.map { df.string(from: $0.timestamp) } ?? "—"
        var to = input.points.last.map { df.string(from: $0.timestamp) } ?? "—"
        if input.inProgress { to += " (\(L("report.trip.inProgress")))" }
        if !input.personName.isEmpty {
            y = row(L("report.trip.person"), input.personName, y: y)
        }
        y = row(L("report.trip.period"), "\(from) → \(to)", y: y + 2)
        return y
    }

    private static func row(_ label: String, _ value: String, y: CGFloat) -> CGFloat {
        text(label, at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), color: muted, width: 110)
        return text(value, at: CGPoint(x: margin + 115, y: y), font: .systemFont(ofSize: 11, weight: .medium))
    }

    private static func section(_ title: String, y: CGFloat) -> CGFloat {
        let bottom = text(title.uppercased(), at: CGPoint(x: margin, y: y), font: .boldSystemFont(ofSize: 10), color: navy)
        rule.setFill()
        UIRectFill(CGRect(x: margin, y: bottom + 3, width: pageSize.width - 2 * margin, height: 0.75))
        return bottom + 4
    }

    private static func statGrid(_ s: TripStats, pointCount: Int, y: CGFloat) -> CGFloat {
        let items: [(String, String)] = [
            (L("report.trip.distance"), TripFormat.distance(s.distanceMeters)),
            (L("report.trip.duration"), TripFormat.duration(s.durationSeconds)),
            (L("report.trip.moving"), TripFormat.duration(s.movingSeconds)),
            (L("report.trip.avgSpeed"), TripFormat.speed(s.averageSpeed)),
            (L("report.trip.maxSpeed"), TripFormat.speed(s.maxSpeed)),
            (L("report.trip.elevGain"), TripFormat.metres(s.elevationGain)),
            (L("report.trip.points"), "\(pointCount)"),
            (L("report.trip.accuracy"), s.typicalAccuracy.map { String(format: "± %.0f m", $0) } ?? "—"),
        ]
        let cols = 4
        let w = (pageSize.width - 2 * margin) / CGFloat(cols)
        var bottom = y
        for (i, item) in items.enumerated() {
            let x = margin + CGFloat(i % cols) * w
            let top = y + CGFloat(i / cols) * 44
            let value = item.1
            text(item.0, at: CGPoint(x: x, y: top), font: .systemFont(ofSize: 9), color: muted, width: w - 8)
            bottom = max(bottom, text(value, at: CGPoint(x: x, y: top + 13), font: .boldSystemFont(ofSize: 15), width: w - 8))
        }
        return bottom
    }

    private static func legend(y: CGFloat) -> CGFloat {
        var x = margin
        let title = L("report.trip.speed") + ":"
        text(title, at: CGPoint(x: x, y: y), font: .systemFont(ofSize: 9), color: muted, width: 80)
        x += (title as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 9)]).width + 8
        for band in TrackSpeedBand.allCases {
            band.uiColor.setFill()
            UIBezierPath(roundedRect: CGRect(x: x, y: y + 3, width: 16, height: 5), cornerRadius: 2.5).fill()
            x += 20
            text(band.rangeLabel, at: CGPoint(x: x, y: y), font: .systemFont(ofSize: 9), color: ink, width: 70)
            x += (band.rangeLabel as NSString).size(withAttributes: [.font: UIFont.systemFont(ofSize: 9)]).width + 14
        }
        return y + 14
    }

    private static func chart(_ points: [TripPoint], value: (TripPoint) -> Double?, unit: String,
                              color: UIColor, y: CGFloat) -> CGFloat {
        let rect = CGRect(x: margin + 34, y: y + 4, width: pageSize.width - 2 * margin - 34, height: 150)
        let samples: [(TimeInterval, Double)] = points.compactMap { p in
            value(p).map { (p.timestamp.timeIntervalSince(points[0].timestamp), $0) }
        }
        rule.setStroke()
        UIBezierPath(rect: rect).stroke()
        guard samples.count > 1, let tMax = samples.last?.0, tMax > 0 else {
            text("—", at: CGPoint(x: rect.midX, y: rect.midY - 6), font: .systemFont(ofSize: 10), color: muted)
            return rect.maxY + 16
        }
        let vMin = min(0, samples.map(\.1).min() ?? 0)
        let vMax = max(samples.map(\.1).max() ?? 1, vMin + 4)
        let grid = 4
        for i in 0...grid {
            let gy = rect.maxY - CGFloat(i) / CGFloat(grid) * rect.height
            rule.setFill()
            UIRectFill(CGRect(x: rect.minX, y: gy, width: rect.width, height: 0.5))
            let v = vMin + (vMax - vMin) * Double(i) / Double(grid)
            text(String(format: "%.0f", v), at: CGPoint(x: margin, y: gy - 6), font: .systemFont(ofSize: 8),
                 color: muted, width: 30, alignment: .right)
        }
        text(unit, at: CGPoint(x: rect.minX + 5, y: rect.minY + 3), font: .systemFont(ofSize: 8), color: muted, width: 40)
        let path = UIBezierPath()
        for (i, s) in samples.enumerated() {
            let p = CGPoint(x: rect.minX + CGFloat(s.0 / tMax) * rect.width,
                            y: rect.maxY - CGFloat((s.1 - vMin) / (vMax - vMin)) * rect.height)
            i == 0 ? path.move(to: p) : path.addLine(to: p)
        }
        color.setStroke()
        path.lineWidth = 1.5
        path.lineJoinStyle = .round
        path.stroke()
        text(TripFormat.duration(tMax), at: CGPoint(x: rect.maxX - 80, y: rect.maxY + 3), font: .systemFont(ofSize: 8),
             color: muted, width: 80, alignment: .right)
        text("0:00", at: CGPoint(x: rect.minX, y: rect.maxY + 3), font: .systemFont(ofSize: 8), color: muted, width: 40)
        return rect.maxY + 16
    }

    private static func stopsTable(_ stops: [TripStop], y: CGFloat, newPage: () -> CGFloat) -> CGFloat {
        guard !stops.isEmpty else {
            return text(L("report.trip.noStops"), at: CGPoint(x: margin, y: y), font: .systemFont(ofSize: 10), color: muted)
        }
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm"
        var y = y
        for (i, stop) in stops.enumerated() {
            if y > pageSize.height - 90 { y = newPage() }
            let line = String(format: "%d.  %@–%@  ·  %@  ·  %.5f, %.5f", i + 1,
                              tf.string(from: stop.start), tf.string(from: stop.end),
                              TripFormat.duration(stop.duration), stop.latitude, stop.longitude)
            y = text(line, at: CGPoint(x: margin, y: y), font: .monospacedDigitSystemFont(ofSize: 9.5, weight: .regular)) + 3
        }
        return y
    }

    private static func logTable(_ points: [TripPoint], y: CGFloat, newPage: () -> CGFloat) -> CGFloat {
        let cols: [(String, CGFloat)] = [
            ("#", 30), (L("report.trip.col.time"), 70), (L("report.trip.col.lat"), 85),
            (L("report.trip.col.lon"), 90), (L("report.trip.col.acc"), 70),
            (L("report.trip.col.speed"), 80), (L("report.trip.col.alt"), 90),
        ]
        let tf = DateFormatter()
        tf.dateFormat = "HH:mm:ss"
        let mono = UIFont.monospacedDigitSystemFont(ofSize: 8.5, weight: .regular)
        func headerRow(_ y: CGFloat) -> CGFloat {
            var x = margin
            for (title, w) in cols {
                text(title, at: CGPoint(x: x, y: y), font: .boldSystemFont(ofSize: 8.5), color: navy, width: w - 4)
                x += w
            }
            rule.setFill()
            UIRectFill(CGRect(x: margin, y: y + 13, width: pageSize.width - 2 * margin, height: 0.5))
            return y + 16
        }
        var y = headerRow(y)
        for (i, p) in points.enumerated() {
            if y > pageSize.height - 80 { y = headerRow(newPage()) }
            let cells = [
                "\(i + 1)", tf.string(from: p.timestamp),
                String(format: "%.5f", p.latitude), String(format: "%.5f", p.longitude),
                p.accuracy >= 0 ? String(format: "± %.0f m", p.accuracy) : "—",
                p.speed.map { $0 >= 0 ? TripFormat.speed($0) : "—" } ?? "—",
                TripFormat.metres(p.altitude),
            ]
            var x = margin
            for (cell, col) in zip(cells, cols) {
                text(cell, at: CGPoint(x: x, y: y), font: mono, width: col.1 - 4)
                x += col.1
            }
            y += 12.5
        }
        return y
    }

    private static func footer(_ input: TripReportInput, page: Int) {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        df.locale = Locale(identifier: LanguageManager.shared.current.rawValue)
        let y = pageSize.height - 50
        rule.setFill()
        UIRectFill(CGRect(x: margin, y: y, width: pageSize.width - 2 * margin, height: 0.5))
        let below = text(L("report.trip.disclaimer"), at: CGPoint(x: margin, y: y + 5), font: .systemFont(ofSize: 7.5),
                         color: muted, width: pageSize.width - 2 * margin)
        let right = String(format: L("report.trip.generated"), df.string(from: input.generatedAt))
            + " · " + String(format: L("report.trip.page"), page)
        text(right, at: CGPoint(x: margin, y: below + 2), font: .systemFont(ofSize: 7.5),
             color: muted, width: pageSize.width - 2 * margin, alignment: .right)
    }

    /// At most `max` points, evenly spread, always keeping the first and last
    static func sample(_ points: [TripPoint], max: Int) -> [TripPoint] {
        guard points.count > max, max > 1 else { return points }
        let step = Double(points.count - 1) / Double(max - 1)
        return (0..<max).map { points[Int((Double($0) * step).rounded())] }
    }

    // MARK: Map picture

    static func region(for points: [TripPoint]) -> MKCoordinateRegion {
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.35, 0.004),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.35, 0.004))
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func snapshot(_ points: [TripPoint], size: CGSize) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = region(for: points)
        options.size = size
        options.scale = 2
        options.pointOfInterestFilter = .excludingAll
        let snapshotter = MKMapSnapshotter(options: options)
        guard let snap = try? await snapshotter.start() else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            snap.image.draw(at: .zero)
            drawTrack(points) { snap.point(for: $0) }
        }
    }

    /// No map available: the line on a plain background, north up
    private static func drawPlainTrack(_ points: [TripPoint], in rect: CGRect) {
        UIColor(red: 0.95, green: 0.96, blue: 0.97, alpha: 1).setFill()
        UIBezierPath(roundedRect: rect, cornerRadius: 6).fill()
        guard points.count > 1 else { return }
        let r = region(for: points)
        let cosLat = cos(r.center.latitude * .pi / 180)
        let spanX = r.span.longitudeDelta * cosLat, spanY = r.span.latitudeDelta
        let scale = min(rect.width / CGFloat(spanX), rect.height / CGFloat(spanY))
        drawTrack(points) { c in
            CGPoint(x: rect.midX + CGFloat((c.longitude - r.center.longitude) * cosLat) * scale,
                    y: rect.midY - CGFloat(c.latitude - r.center.latitude) * scale)
        }
    }

    private static func drawTrack(_ points: [TripPoint], project: (CLLocationCoordinate2D) -> CGPoint) {
        for run in TrackRun.runs(points) {
            let path = UIBezierPath()
            for (i, c) in run.coordinates.enumerated() {
                i == 0 ? path.move(to: project(c)) : path.addLine(to: project(c))
            }
            path.lineWidth = 4
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            UIColor.white.withAlphaComponent(0.9).setStroke()
            let halo = path.copy() as! UIBezierPath
            halo.lineWidth = 6.5
            halo.stroke()
            run.band.uiColor.setStroke()
            path.stroke()
        }
        func dot(_ p: TripPoint, _ color: UIColor) {
            let c = project(CLLocationCoordinate2D(latitude: p.latitude, longitude: p.longitude))
            let r = CGRect(x: c.x - 6, y: c.y - 6, width: 12, height: 12)
            color.setFill()
            UIBezierPath(ovalIn: r).fill()
            UIColor.white.setStroke()
            let ring = UIBezierPath(ovalIn: r)
            ring.lineWidth = 2
            ring.stroke()
        }
        if let first = points.first { dot(first, UIColor(red: 63/255, green: 143/255, blue: 110/255, alpha: 1)) }
        if let last = points.last { dot(last, UIColor(red: 214/255, green: 69/255, blue: 65/255, alpha: 1)) }
    }
}
