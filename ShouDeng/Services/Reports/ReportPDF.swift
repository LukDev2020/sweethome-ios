import UIKit

// MARK: - Incident report PDF (A4)
//
// Cover → summary → maps → key events → activity → falls → SOS → locations → integrity.
// Every page carries the report id, the verify code and the data hash.

struct ReportPDF {
    let data: IncidentReportData
    let maps: [ReportMap]
    let verifyUrl: String?
    let dataSha256: String

    private let page = CGRect(x: 0, y: 0, width: 595, height: 842)
    private let margin: CGFloat = 44
    private var width: CGFloat { page.width - margin * 2 }
    private let ink = UIColor(red: 0.07, green: 0.13, blue: 0.23, alpha: 1)
    private let accent = UIColor(red: 0.77, green: 0.27, blue: 0.24, alpha: 1)
    private let muted = UIColor(white: 0.42, alpha: 1)

    private func L(_ key: String) -> String { LanguageManager.shared.localized(key) }

    func render() -> Data {
        let fmt = ReportFormat(data)
        let renderer = UIGraphicsPDFRenderer(bounds: page, format: {
            let f = UIGraphicsPDFRendererFormat()
            f.documentInfo = [
                kCGPDFContextTitle as String: "\(L("report.title")) \(data.reportId)",
                kCGPDFContextCreator as String: "Lantern Care",
            ]
            return f
        }())
        return renderer.pdfData { ctx in
            var w = Writer(ctx: ctx, page: page, margin: margin, footer: footer)
            w.newPage()
            cover(&w, fmt)
            summary(&w, fmt)
            mapsSection(&w)
            eventsSection(&w, fmt)
            activitySection(&w, fmt)
            fallsSection(&w, fmt)
            sosSection(&w, fmt)
            locationsSection(&w, fmt)
            integrity(&w)
            w.finish()
        }
    }

    private var footer: String {
        "\(L("report.title")) \(data.reportId) · \(L("report.verifyCode")) \(data.verifyCode) · SHA-256 \(dataSha256.prefix(16))…"
    }

    // MARK: Sections

    private func cover(_ w: inout Writer, _ fmt: ReportFormat) {
        w.text(L("report.title").uppercased(), size: 11, weight: .bold, color: accent)
        w.text(data.person.name ?? "—", size: 26, weight: .bold, color: ink)
        w.space(4)
        w.text("\(fmt.full(data.window.start)) – \(fmt.full(data.window.end))", size: 13, color: ink)
        w.space(10)
        w.keyValues([
            (L("report.field.reportId"), data.reportId),
            (L("report.verifyCode"), data.verifyCode),
            (L("report.field.purpose"), L("report.purpose.\(data.purpose)")),
            (L("report.field.caseNumber"), data.caseNumber ?? "—"),
            (L("report.field.person"), [data.person.name, data.person.phone].compactMap { $0 }.joined(separator: " · ")),
            (L("report.field.reporter"), "\(data.reporter.name ?? "—") (\(L(data.reporter.role == "self" ? "report.reporter.self" : "report.reporter.guardian")))"),
            (L("report.field.generated"), fmt.full(data.generatedAt)),
            (L("report.field.timeZone"), fmt.timeZone.identifier),
        ])
        w.space(8)
        w.box(L("report.cover.notice"), color: accent)
    }

    private func summary(_ w: inout Writer, _ fmt: ReportFormat) {
        w.heading(L("report.h.summary"))
        if let last = data.summary.lastKnown {
            var line = "\(fmt.full(last.at)) · \(ReportFormat.coord(last.latitude, last.longitude))"
            if let acc = last.accuracy { line += " · ±\(Int(acc)) m" }
            w.keyValues([(L("report.field.lastKnown"), line)])
        } else {
            w.keyValues([(L("report.field.lastKnown"), L("report.none"))])
        }
        if let c = data.summary.lastCheckIn {
            w.keyValues([(L("report.field.lastCheckIn"), "\(fmt.full(c.at))\(c.note.map { " · “\($0)”" } ?? "")")])
        }
        if let b = data.summary.lastBattery, let level = b.level {
            w.keyValues([(L("report.field.battery"), "\(Int(level * 100))% · \(fmt.full(b.at))")])
        }
        let c = data.summary.counts
        w.keyValues([(L("report.field.counts"), String(format: L("report.counts"), c.points, c.sos, c.falls, c.checkins, data.gaps.count))])
        let down = data.sources.filter { $0.value == "unavailable" }.map(\.key).sorted()
        if !down.isEmpty {
            w.box(String(format: L("report.sourcesDown"), down.joined(separator: ", ")), color: .systemOrange)
        }
        if data.summary.thinned == true { w.small(L("report.thinned")) }
        if !data.gaps.isEmpty {
            w.subheading(L("report.h.gaps"))
            for g in data.gaps { w.bullet("\(fmt.short(g.from)) – \(fmt.short(g.to)) (\(minutes(g.minutes)))") }
        }
    }

    private func mapsSection(_ w: inout Writer) {
        guard !maps.isEmpty else {
            if !data.locations.isEmpty { w.small(L("report.map.unavailable")) }
            return
        }
        // Keep the heading with the first map
        w.heading(L("report.h.maps"), keepWith: w.width * 440 / 640 + 24)
        for m in maps {
            w.image(m.image, caption: m.title)
        }
        w.small(L("report.map.legend"))
    }

    private func eventsSection(_ w: inout Writer, _ fmt: ReportFormat) {
        var rows: [(String, String, String)] = []
        for s in data.sos { rows.append((s.triggeredAt ?? "", "SOS", L("sos.method.\(s.triggerMethod ?? "longPress")").capitalizedFirst)) }
        for f in data.falls { rows.append((f.detectedAt ?? "", L("report.event.fall"), L("report.fall.outcome.\(f.outcome ?? "pending")"))) }
        for c in data.checkins { rows.append((c.at ?? "", L("report.event.checkIn"), c.note ?? "")) }
        for e in data.events where e.type != "checkIn" && e.type != "sosTriggered" && e.type != "fallDetected" {
            rows.append((e.at ?? "", L("report.event.\(e.type)"), e.description))
        }
        guard !rows.isEmpty else { return }
        w.heading(L("report.h.events"))
        w.table(header: [L("report.col.time"), L("report.col.event"), L("report.col.detail")], widths: [0.26, 0.24, 0.5],
                rows: rows.sorted { $0.0 < $1.0 }.map { [fmt.short($0.0), $0.1, $0.2] })
    }

    private func activitySection(_ w: inout Writer, _ fmt: ReportFormat) {
        guard !data.activity.isEmpty else { return }
        w.heading(L("report.h.activity"))
        w.table(header: [L("report.col.from"), L("report.col.to"), L("report.col.activity"), L("report.col.distance")], widths: [0.27, 0.27, 0.26, 0.2],
                rows: data.activity.map { [fmt.short($0.start), fmt.short($0.end), L("report.activity.\($0.activity)"), ReportFormat.distance($0.distanceMeters)] })
        w.small(L("report.activity.note"))
    }

    private func fallsSection(_ w: inout Writer, _ fmt: ReportFormat) {
        guard !data.falls.isEmpty else { return }
        w.heading(L("report.h.falls"))
        for f in data.falls {
            w.subheading("\(fmt.full(f.detectedAt)) · \(ReportFormat.coord(f.latitude, f.longitude))")
            var pairs: [(String, String)] = [(L("report.fall.outcome"), L("report.fall.outcome.\(f.outcome ?? "pending")"))]
            if let s = f.respondedAfterSec {
                let escalated = f.outcome != "dismissed" && f.outcome != "pending"
                pairs.append((L(escalated ? "report.fall.sentAfter" : "report.fall.responded"), "\(Int(s.rounded())) s"))
            }
            if let m = f.metrics {
                let parts = [
                    m.peakImpactG.map { String(format: L("report.fall.impact"), $0) },
                    m.freeFallMs.map { String(format: L("report.fall.freeFall"), Int($0)) },
                    m.orientationChangeDeg.map { String(format: L("report.fall.turn"), Int($0)) },
                ].compactMap { $0 }
                if !parts.isEmpty { pairs.append((L("report.fall.sensors"), parts.joined(separator: " · "))) }
            }
            if let b = f.batteryLevel { pairs.append((L("report.field.battery"), "\(Int(b * 100))%")) }
            w.keyValues(pairs)
        }
        w.small(L("report.fall.note"))
    }

    private func sosSection(_ w: inout Writer, _ fmt: ReportFormat) {
        guard !data.sos.isEmpty else { return }
        w.heading(L("report.h.sos"))
        for s in data.sos {
            w.subheading("\(fmt.full(s.triggeredAt)) · \(L("sos.method.\(s.triggerMethod ?? "longPress")").capitalizedFirst)")
            var pairs: [(String, String)] = [(L("report.sos.place"), ReportFormat.coord(s.latitude, s.longitude))]
            if let who = s.acknowledgedBy { pairs.append((L("report.sos.ack"), "\(who) · \(fmt.short(s.acknowledgedAt))")) }
            pairs.append((L("report.sos.ended"), s.resolvedAt.map { "\(fmt.short($0)) · \(s.resolution ?? "")" } ?? L("report.sos.open")))
            if let trail = s.trail, !trail.isEmpty { pairs.append((L("report.sos.trail"), String(format: L("report.sos.trailPoints"), trail.count))) }
            w.keyValues(pairs)
        }
    }

    private func locationsSection(_ w: inout Writer, _ fmt: ReportFormat) {
        guard !data.locations.isEmpty else { return }
        w.heading(L("report.h.locations"))
        // The PDF lists up to 400 rows; every point is in locations.csv / track.gpx
        let step = max(1, data.locations.count / 400)
        let shown = stride(from: 0, to: data.locations.count, by: step).map { data.locations[$0] }
        w.table(header: [L("report.col.time"), L("report.col.position"), "±m", L("report.col.activity"), L("report.col.source")],
                widths: [0.24, 0.32, 0.1, 0.17, 0.17],
                rows: shown.map { p in
                    [fmt.short(p.at), ReportFormat.coord(p.latitude, p.longitude), p.accuracy.map { "\(Int($0))" } ?? "—",
                     L("report.activity.\(p.activity.map { $0 == "automotive" ? "driving" : $0 } ?? "unknown")"), L("report.source.\(p.source)")]
                }, size: 7.5)
        if step > 1 { w.small(String(format: L("report.locations.sampled"), shown.count, data.locations.count)) }
    }

    private func integrity(_ w: inout Writer) {
        w.heading(L("report.h.integrity"))
        w.text(L("report.integrity.body"), size: 10, color: ink)
        w.space(4)
        w.keyValues([
            (L("report.verifyCode"), data.verifyCode),
            (L("report.integrity.url"), verifyUrl ?? "—"),
            ("data.json SHA-256", dataSha256),
        ], size: 9)
        w.subheading(L("report.h.limits"))
        for key in ["report.limit.accuracy", "report.limit.phone", "report.limit.fall", "report.limit.gaps"] { w.bullet(L(key)) }
        w.space(6)
        w.small(L("report.disclaimer"))
    }

    private func minutes(_ m: Int) -> String {
        m >= 120 ? String(format: L("report.hours"), Double(m) / 60) : String(format: L("report.minutes"), m)
    }
}

private extension String {
    /// "fall detected" → "Fall detected" (no change for Chinese / Japanese)
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}

// MARK: - Page writer

private struct Writer {
    let ctx: UIGraphicsPDFRendererContext
    let page: CGRect
    let margin: CGFloat
    let footer: String
    var y: CGFloat = 0
    var pageNo = 0
    var width: CGFloat { page.width - margin * 2 }
    private let ink = UIColor(red: 0.07, green: 0.13, blue: 0.23, alpha: 1)

    init(ctx: UIGraphicsPDFRendererContext, page: CGRect, margin: CGFloat, footer: String) {
        self.ctx = ctx; self.page = page; self.margin = margin; self.footer = footer
    }

    mutating func newPage() {
        if pageNo > 0 { drawFooter() }
        ctx.beginPage()
        pageNo += 1
        y = margin
    }

    mutating func finish() { drawFooter() }

    private func drawFooter() {
        let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: 7.5), .foregroundColor: UIColor(white: 0.45, alpha: 1)]
        (footer as NSString).draw(in: CGRect(x: margin, y: page.height - margin + 14, width: width - 40, height: 12), withAttributes: attrs)
        ("\(pageNo)" as NSString).draw(in: CGRect(x: page.width - margin - 30, y: page.height - margin + 14, width: 30, height: 12),
                                       withAttributes: attrs.merging([.paragraphStyle: { let p = NSMutableParagraphStyle(); p.alignment = .right; return p }()]) { $1 })
    }

    private mutating func ensure(_ h: CGFloat) {
        if y + h > page.height - margin { newPage() }
    }

    private func measure(_ s: NSAttributedString, width: CGFloat) -> CGFloat {
        ceil(s.boundingRect(with: CGSize(width: width, height: 10_000), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height)
    }

    mutating func space(_ h: CGFloat) { y += h }

    mutating func text(_ s: String, size: CGFloat, weight: UIFont.Weight = .regular, color: UIColor) {
        let a = NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        let h = measure(a, width: width)
        ensure(h)
        a.draw(with: CGRect(x: margin, y: y, width: width, height: h), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + 2
    }

    mutating func heading(_ s: String, keepWith: CGFloat = 0) {
        ensure(60 + keepWith)
        y += 14
        text(s, size: 15, weight: .bold, color: ink)
        let cg = ctx.cgContext
        cg.setFillColor(UIColor(white: 0.85, alpha: 1).cgColor)
        cg.fill(CGRect(x: margin, y: y, width: width, height: 0.7))
        y += 6
    }

    mutating func subheading(_ s: String) {
        ensure(40)
        y += 4
        text(s, size: 11, weight: .semibold, color: ink)
    }

    mutating func small(_ s: String) { text(s, size: 8.5, color: UIColor(white: 0.42, alpha: 1)) }

    mutating func bullet(_ s: String) { text("•  " + s, size: 10, color: ink) }

    mutating func box(_ s: String, color: UIColor) {
        let a = NSAttributedString(string: s, attributes: [.font: UIFont.systemFont(ofSize: 9.5), .foregroundColor: ink])
        let h = measure(a, width: width - 20) + 14
        ensure(h)
        let rect = CGRect(x: margin, y: y, width: width, height: h)
        let cg = ctx.cgContext
        cg.setFillColor(color.withAlphaComponent(0.08).cgColor)
        cg.fill(rect)
        cg.setFillColor(color.cgColor)
        cg.fill(CGRect(x: margin, y: y, width: 3, height: h))
        a.draw(with: rect.insetBy(dx: 12, dy: 7), options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil)
        y += h + 6
    }

    mutating func keyValues(_ pairs: [(String, String)], size: CGFloat = 10) {
        let keyW: CGFloat = 130
        for (k, v) in pairs {
            let ka = NSAttributedString(string: k, attributes: [.font: UIFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: UIColor(white: 0.42, alpha: 1)])
            let va = NSAttributedString(string: v, attributes: [.font: UIFont.systemFont(ofSize: size), .foregroundColor: ink])
            let h = max(measure(ka, width: keyW - 8), measure(va, width: width - keyW))
            ensure(h)
            ka.draw(with: CGRect(x: margin, y: y, width: keyW - 8, height: h), options: [.usesLineFragmentOrigin], context: nil)
            va.draw(with: CGRect(x: margin + keyW, y: y, width: width - keyW, height: h), options: [.usesLineFragmentOrigin], context: nil)
            y += h + 3
        }
    }

    mutating func image(_ img: UIImage, caption: String) {
        let h = width * img.size.height / max(img.size.width, 1)
        ensure(h + 24)
        img.draw(in: CGRect(x: margin, y: y, width: width, height: h))
        ctx.cgContext.setStrokeColor(UIColor(white: 0.8, alpha: 1).cgColor)
        ctx.cgContext.stroke(CGRect(x: margin, y: y, width: width, height: h))
        y += h + 3
        text(caption, size: 9, weight: .medium, color: ink)
        y += 6
    }

    mutating func table(header: [String], widths: [CGFloat], rows: [[String]], size: CGFloat = 8.5) {
        let cols = widths.map { $0 * width }
        func row(_ cells: [String], bold: Bool, shade: Bool) {
            let attrs: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular), .foregroundColor: ink]
            let strings = cells.map { NSAttributedString(string: $0, attributes: attrs) }
            let h = zip(strings, cols).map { measure($0, width: $1 - 6) }.max() ?? 10
            if y + h + 4 > page.height - margin {
                newPage()
                if !bold { row(header, bold: true, shade: true) }
            }
            if shade {
                ctx.cgContext.setFillColor(UIColor(white: 0.95, alpha: 1).cgColor)
                ctx.cgContext.fill(CGRect(x: margin, y: y, width: width, height: h + 4))
            }
            var x = margin
            for (s, w) in zip(strings, cols) {
                s.draw(with: CGRect(x: x + 3, y: y + 2, width: w - 6, height: h), options: [.usesLineFragmentOrigin], context: nil)
                x += w
            }
            y += h + 4
        }
        row(header, bold: true, shade: true)
        for (i, r) in rows.enumerated() { row(r, bold: false, shade: i % 2 == 1) }
        y += 4
    }
}
