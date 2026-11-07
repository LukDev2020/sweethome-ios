import UIKit
import MapKit
import CryptoKit

// MARK: - Incident report for police: the package (docs/police-incident-report.md)
//
//   report.pdf · map-*.png · track.gpx · locations.csv · data.json · manifest.json
//
// The server sends the data already hashed; data.json is that string byte for byte
// (checked here before anything is drawn). Everything else is drawn from it, hashed,
// and sealed on the server once, so police can verify any file with the code.
// Maps come from MKMapSnapshotter: no API key, the same maps the family sees.

@MainActor
final class IncidentReportBuilder {

    struct Package {
        let folder: URL
        let files: [URL]
        let data: IncidentReportData
        let verifyUrl: String?
        let sealed: Bool
        var pdf: URL { folder.appendingPathComponent("report.pdf") }
        var reportId: String { data.reportId }
        var verifyCode: String { data.verifyCode }
    }

    enum BuildError: LocalizedError {
        case hashMismatch
        var errorDescription: String? { LanguageManager.shared.localized("report.error.hash") }
    }

    enum Step { case gathering, maps, document, sealing }

    private let api: APIClient

    init(api: APIClient) { self.api = api }

    func build(_ request: IncidentReportRequest, progress: @escaping (Step) -> Void = { _ in }) async throws -> Package {
        progress(.gathering)
        let created: IncidentReportCreated = try await api.post("/v1/incident-reports", body: request)
        let raw = Data(created.canonical.utf8)
        // What we save must be exactly what the server registered
        guard Self.sha256(raw) == created.dataSha256 else { throw BuildError.hashMismatch }
        let data = try JSONDecoder().decode(IncidentReportData.self, from: raw)

        let folder = try Self.makeFolder(for: data)
        var files: [URL] = []
        func write(_ name: String, _ bytes: Data) throws {
            let url = folder.appendingPathComponent(name)
            try bytes.write(to: url, options: .atomic)
            files.append(url)
        }

        progress(.maps)
        let maps = await ReportMaps.render(data)

        progress(.document)
        let pdf = ReportPDF(data: data, maps: maps, verifyUrl: created.verifyUrl, dataSha256: created.dataSha256).render()
        try write("report.pdf", pdf)
        for map in maps {
            if let png = map.image.pngData() { try write(map.fileName, png) }
        }
        try write("track.gpx", Data(ReportExports.gpx(data).utf8))
        try write("locations.csv", Data(ReportExports.csv(data).utf8))
        try write("data.json", raw)

        var hashes: [String: String] = [:]
        for url in files { hashes[url.lastPathComponent] = Self.sha256(try Data(contentsOf: url)) }
        let manifest = ReportExports.manifest(data, files: hashes, verifyUrl: created.verifyUrl)
        try write("manifest.json", manifest)
        hashes["manifest.json"] = Self.sha256(manifest)

        progress(.sealing)
        var sealed = false
        do {
            let _: EmptyResponse = try await api.post("/v1/incident-reports/\(data.reportId)/seal", body: IncidentReportSealRequest(files: hashes))
            sealed = true
        } catch {
            // data.json can still be verified; the files stay usable
            #if DEBUG
            print("[IncidentReport] seal failed: \(error)")
            #endif
        }
        return Package(folder: folder, files: files, data: data, verifyUrl: created.verifyUrl, sealed: sealed)
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func makeFolder(for data: IncidentReportData) throws -> URL {
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmm"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let name = (data.person.name ?? "person").components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("IncidentReports", isDirectory: true)
        let folder = base.appendingPathComponent("LanternCare_\(data.reportId)_\(name.isEmpty ? "person" : name)_\(stamp.string(from: Date()))", isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }
}

// MARK: - Formatting in the person's time zone

struct ReportFormat {
    let timeZone: TimeZone
    private let full: DateFormatter
    private let time: DateFormatter

    init(_ data: IncidentReportData) {
        timeZone = data.person.timeZone.flatMap(TimeZone.init(identifier:)) ?? .current
        let locale = Locale(identifier: LanguageManager.shared.current.rawValue)
        full = DateFormatter()
        full.locale = locale
        full.timeZone = timeZone
        full.setLocalizedDateFormatFromTemplate("yMMMdHHmmz")
        time = DateFormatter()
        time.locale = locale
        time.timeZone = timeZone
        time.setLocalizedDateFormatFromTemplate("MMMdHHmm")
    }

    func full(_ iso: String?) -> String { ReportTime.date(iso).map(full.string(from:)) ?? "—" }
    func short(_ iso: String?) -> String { ReportTime.date(iso).map(time.string(from:)) ?? "—" }

    static func coord(_ lat: Double?, _ lon: Double?) -> String {
        guard let lat, let lon else { return "—" }
        return String(format: "%.5f, %.5f", lat, lon)
    }

    static func distance(_ m: Double) -> String {
        m >= 1000 ? String(format: "%.1f km", m / 1000) : "\(Int(m.rounded())) m"
    }
}

// MARK: - Maps

struct ReportMap {
    let fileName: String
    let title: String
    let image: UIImage
}

enum ReportMaps {
    private static let size = CGSize(width: 640, height: 440)

    static func render(_ data: IncidentReportData) async -> [ReportMap] {
        let L: (String) -> String = { LanguageManager.shared.localized($0) }
        let fmt = ReportFormat(data)
        var trail = data.locations.map(\.coordinate)
        for s in data.sos { trail += (s.trail ?? []).map { .init(latitude: $0.latitude, longitude: $0.longitude) } }
        let markers = eventMarkers(data)
        var maps: [ReportMap] = []

        if !trail.isEmpty || !markers.isEmpty {
            let all = trail + markers.map(\.coordinate)
            if let image = await snapshot(region: region(fitting: all), trail: trail, markers: markers) {
                maps.append(ReportMap(fileName: "map-overview.png", title: L("report.map.overview"), image: image))
            }
        }
        if let last = data.summary.lastKnown {
            let region = MKCoordinateRegion(center: last.coordinate, latitudinalMeters: 600, longitudinalMeters: 600)
            let withLast = markers + [Marker(coordinate: last.coordinate, kind: .lastKnown)]
            if let image = await snapshot(region: region, trail: trail, markers: withLast, accuracy: last.accuracy) {
                maps.append(ReportMap(fileName: "map-last-known.png",
                                      title: String(format: L("report.map.lastKnown"), fmt.full(last.at)), image: image))
            }
        }
        // One close-up per place: a fall and the SOS it led to share a map
        var places: [(coordinate: CLLocationCoordinate2D, titles: [String])] = []
        for m in markers where m.kind == .sos || m.kind == .fall {
            let title = "\(L(m.kind == .sos ? "report.map.sos" : "report.map.fall")) · \(fmt.full(m.at))"
            let here = CLLocation(latitude: m.coordinate.latitude, longitude: m.coordinate.longitude)
            if let i = places.firstIndex(where: { CLLocation(latitude: $0.coordinate.latitude, longitude: $0.coordinate.longitude).distance(from: here) < 50 }) {
                places[i].titles.append(title)
            } else {
                places.append((m.coordinate, [title]))
            }
        }
        for (i, place) in places.prefix(4).enumerated() {
            let region = MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
            if let image = await snapshot(region: region, trail: trail, markers: markers) {
                maps.append(ReportMap(fileName: "map-event-\(i + 1).png", title: place.titles.joined(separator: " → "), image: image))
            }
        }
        return maps
    }

    struct Marker {
        enum Kind { case start, lastKnown, sos, fall, checkIn }
        let coordinate: CLLocationCoordinate2D
        let kind: Kind
        var at: String? = nil
    }

    private static func eventMarkers(_ data: IncidentReportData) -> [Marker] {
        var out: [Marker] = []
        if let first = data.locations.first { out.append(Marker(coordinate: first.coordinate, kind: .start, at: first.at)) }
        for c in data.checkins { if let lat = c.latitude, let lon = c.longitude { out.append(Marker(coordinate: .init(latitude: lat, longitude: lon), kind: .checkIn, at: c.at)) } }
        for f in data.falls { if let lat = f.latitude, let lon = f.longitude { out.append(Marker(coordinate: .init(latitude: lat, longitude: lon), kind: .fall, at: f.detectedAt)) } }
        for s in data.sos { if let lat = s.latitude, let lon = s.longitude { out.append(Marker(coordinate: .init(latitude: lat, longitude: lon), kind: .sos, at: s.triggeredAt)) } }
        return out
    }

    private static func region(fitting coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion {
        let lats = coords.map(\.latitude), lons = coords.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2, longitude: (lons.min()! + lons.max()!) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((lats.max()! - lats.min()!) * 1.35, 0.006),
                                    longitudeDelta: max((lons.max()! - lons.min()!) * 1.35, 0.006))
        return MKCoordinateRegion(center: center, span: span)
    }

    private static func snapshot(region: MKCoordinateRegion, trail: [CLLocationCoordinate2D], markers: [Marker], accuracy: Double? = nil) async -> UIImage? {
        let options = MKMapSnapshotter.Options()
        options.region = region
        options.size = size
        options.scale = 2
        options.traitCollection = UITraitCollection(userInterfaceStyle: .light)
        options.pointOfInterestFilter = .includingAll
        guard let snap = try? await MKMapSnapshotter(options: options).start() else { return nil }

        return UIGraphicsImageRenderer(size: size, format: { let f = UIGraphicsImageRendererFormat(); f.scale = 2; return f }()).image { ctx in
            snap.image.draw(at: .zero)
            let cg = ctx.cgContext
            // Trail (at most ~2000 segments drawn)
            let step = max(1, trail.count / 2000)
            let pts = stride(from: 0, to: trail.count, by: step).map { snap.point(for: trail[$0]) }
            if pts.count > 1 {
                cg.setLineWidth(3.5)
                cg.setLineJoin(.round)
                cg.setLineCap(.round)
                cg.setStrokeColor(UIColor(red: 0.16, green: 0.42, blue: 0.86, alpha: 0.85).cgColor)
                cg.addLines(between: pts)
                cg.strokePath()
            }
            for m in markers {
                let p = snap.point(for: m.coordinate)
                guard CGRect(origin: .zero, size: size).insetBy(dx: -10, dy: -10).contains(p) else { continue }
                if m.kind == .lastKnown, let accuracy, accuracy > 0 {
                    // Accuracy radius around the last position
                    let edge = snap.point(for: CLLocationCoordinate2D(latitude: m.coordinate.latitude + accuracy / 111_000, longitude: m.coordinate.longitude))
                    let r = max(6, abs(p.y - edge.y))
                    cg.setFillColor(UIColor.systemRed.withAlphaComponent(0.15).cgColor)
                    cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                }
                let (color, r): (UIColor, CGFloat) = {
                    switch m.kind {
                    case .start: return (.systemGreen, 6)
                    case .lastKnown: return (.systemRed, 8)
                    case .sos: return (UIColor(red: 0.77, green: 0.27, blue: 0.24, alpha: 1), 9)
                    case .fall: return (.systemOrange, 8)
                    case .checkIn: return (.systemTeal, 5)
                    }
                }()
                cg.setFillColor(UIColor.white.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - r - 2, y: p.y - r - 2, width: (r + 2) * 2, height: (r + 2) * 2))
                cg.setFillColor(color.cgColor)
                cg.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                let label: String? = m.kind == .sos ? "SOS" : m.kind == .fall ? "!" : nil
                if let label {
                    let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: m.kind == .sos ? 7 : 11, weight: .heavy), .foregroundColor: UIColor.white]
                    let s = (label as NSString).size(withAttributes: attrs)
                    (label as NSString).draw(at: CGPoint(x: p.x - s.width / 2, y: p.y - s.height / 2), withAttributes: attrs)
                }
            }
        }
    }
}

// MARK: - GPX / CSV / manifest

enum ReportExports {
    static func gpx(_ d: IncidentReportData) -> String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
        }
        var wpts: [String] = []
        for s in d.sos { if let lat = s.latitude, let lon = s.longitude, let at = s.triggeredAt {
            wpts.append("  <wpt lat=\"\(lat)\" lon=\"\(lon)\"><time>\(at)</time><name>SOS</name><desc>\(esc(s.triggerMethod ?? ""))</desc><type>sos</type></wpt>")
        } }
        for f in d.falls { if let lat = f.latitude, let lon = f.longitude, let at = f.detectedAt {
            wpts.append("  <wpt lat=\"\(lat)\" lon=\"\(lon)\"><time>\(at)</time><name>Fall detected</name><desc>\(esc(f.outcome ?? ""))</desc><type>fall</type></wpt>")
        } }
        for c in d.checkins { if let lat = c.latitude, let lon = c.longitude, let at = c.at {
            wpts.append("  <wpt lat=\"\(lat)\" lon=\"\(lon)\"><time>\(at)</time><name>Check-in</name><desc>\(esc(c.note ?? ""))</desc><type>checkin</type></wpt>")
        } }
        let pts = d.locations.map { p -> String in
            var s = "      <trkpt lat=\"\(p.latitude)\" lon=\"\(p.longitude)\">"
            if let ele = p.altitude { s += "<ele>\(ele)</ele>" }
            s += "<time>\(p.at)</time>"
            if let acc = p.accuracy { s += "<hdop>\(String(format: "%.1f", acc / 5))</hdop>" }
            s += "<src>\(p.source)</src></trkpt>"
            return s
        }
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Lantern Care incident report" xmlns="http://www.topografix.com/GPX/1/1">
          <metadata><name>\(esc(d.person.name ?? "")) — \(d.reportId)</name><desc>Verify code \(d.verifyCode). Window \(d.window.start) – \(d.window.end)</desc><time>\(d.generatedAt)</time></metadata>
        \(wpts.joined(separator: "\n"))
          <trk><name>\(esc(d.person.name ?? ""))</name><trkseg>
        \(pts.joined(separator: "\n"))
          </trkseg></trk>
        </gpx>
        """
    }

    static func csv(_ d: IncidentReportData) -> String {
        let fmt = ReportFormat(d)
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.timeZone = fmt.timeZone
        local.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
        var rows = ["time_utc,time_local,latitude,longitude,accuracy_m,speed_mps,altitude_m,activity,source"]
        for p in d.locations {
            let localTime = ReportTime.date(p.at).map(local.string(from:)) ?? ""
            let cells: [String] = [p.at, localTime, String(p.latitude), String(p.longitude),
                                   p.accuracy.map { String(format: "%.0f", $0) } ?? "",
                                   p.speed.map { String(format: "%.1f", $0) } ?? "",
                                   p.altitude.map { String(format: "%.0f", $0) } ?? "",
                                   p.activity ?? "", p.source]
            rows.append(cells.joined(separator: ","))
        }
        return rows.joined(separator: "\n") + "\n"
    }

    static func manifest(_ d: IncidentReportData, files: [String: String], verifyUrl: String?) -> Data {
        let body: [String: Any] = [
            "reportId": d.reportId,
            "verifyCode": d.verifyCode,
            "verifyUrl": verifyUrl ?? "",
            "generatedAt": d.generatedAt,
            "window": ["start": d.window.start, "end": d.window.end],
            "algorithm": "SHA-256",
            "files": files,
            "howToVerify": "shasum -a 256 <file> (macOS/Linux) or certutil -hashfile <file> SHA256 (Windows), then compare at verifyUrl",
        ]
        return (try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])) ?? Data()
    }
}
