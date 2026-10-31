import UIKit
import CryptoKit

// MARK: - Claim PDF Generator
//
// Generates a structured PDF from a ClaimMaterialExport.
// The PDF is reference-only — disclaimers on every page.

enum ClaimPDFGenerator {

    private static func L(_ key: String) -> String { LanguageManager.shared.localized(key) }

    static func generate(
        export: ClaimMaterialExport,
        insuranceType: InsuranceType?,
        policyNumber: String?,
        userDescription: String?
    ) -> URL? {
        let pageWidth: CGFloat = 595.0  // A4
        let pageHeight: CGFloat = 842.0
        let margin: CGFloat = 50.0
        let contentWidth = pageWidth - margin * 2

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("shoudeng_claim_\(export.exportId).pdf")

        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        )

        let data = renderer.pdfData { context in
            var yOffset: CGFloat = 0

            func beginPageIfNeeded(need: CGFloat = 60) {
                if yOffset + need > pageHeight - margin {
                    drawFooter(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin, hash: export.contentHash)
                    context.beginPage()
                    yOffset = margin
                }
            }

            func drawText(_ text: String, font: UIFont, color: UIColor = .darkText) -> CGFloat {
                let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
                let rect = CGRect(x: margin, y: yOffset, width: contentWidth, height: 1000)
                let boundingRect = (text as NSString).boundingRect(
                    with: CGSize(width: contentWidth, height: 1000),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: attrs,
                    context: nil
                )
                (text as NSString).draw(in: rect, withAttributes: attrs)
                let h = ceil(boundingRect.height)
                yOffset += h
                return h
            }

            // Page 1
            context.beginPage()
            yOffset = margin

            // Title
            _ = drawText(L("claim.pdf.title"), font: .boldSystemFont(ofSize: 22))
            yOffset += 4
            _ = drawText(ClaimDisclaimer.pdfHeader, font: .systemFont(ofSize: 9), color: .gray)
            yOffset += 16

            // Basic info
            _ = drawText(L("claim.pdf.basicInfo"), font: .boldSystemFont(ofSize: 14))
            yOffset += 6
            _ = drawText(String(format: L("claim.pdf.exportId"), export.exportId), font: .systemFont(ofSize: 10))
            yOffset += 2
            _ = drawText(String(format: L("claim.pdf.person"), export.personName), font: .systemFont(ofSize: 10))
            yOffset += 2

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            _ = drawText(String(format: L("claim.pdf.incidentDate"), df.string(from: export.incidentDate)), font: .systemFont(ofSize: 10))
            yOffset += 2
            _ = drawText(String(format: L("claim.pdf.exportedAt"), df.string(from: export.exportedAt)), font: .systemFont(ofSize: 10))
            yOffset += 2
            _ = drawText(String(format: L("claim.pdf.window"), df.string(from: export.window.start), df.string(from: export.window.end)), font: .systemFont(ofSize: 10))
            yOffset += 2

            if let policy = policyNumber, !policy.isEmpty {
                _ = drawText(String(format: L("claim.pdf.policy"), policy), font: .systemFont(ofSize: 10))
                yOffset += 2
            }
            if let desc = userDescription, !desc.isEmpty {
                _ = drawText(String(format: L("claim.pdf.note"), desc), font: .systemFont(ofSize: 10))
                yOffset += 2
            }
            yOffset += 12

            // SOS Events
            if let sos = export.sosEvents, !sos.isEmpty {
                beginPageIfNeeded()
                _ = drawText(String(format: L("claim.pdf.sos"), sos.count), font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                for event in sos {
                    beginPageIfNeeded(need: 20)
                    var line = event.triggeredAt
                    if let method = event.triggerMethod { line += String(format: L("claim.pdf.method"), method) }
                    if let res = event.resolution { line += String(format: L("claim.pdf.resolution"), res) }
                    if let lat = event.latitude, let lng = event.longitude {
                        line += String(format: L("claim.pdf.location"), lat, lng)
                    }
                    _ = drawText(line, font: .monospacedSystemFont(ofSize: 9, weight: .regular))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Check-ins
            if let checkIns = export.checkIns, !checkIns.isEmpty {
                beginPageIfNeeded()
                _ = drawText(String(format: L("claim.pdf.checkIns"), checkIns.count), font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                for ci in checkIns {
                    beginPageIfNeeded(need: 20)
                    var line = ci.timestamp
                    if let lat = ci.latitude, let lng = ci.longitude {
                        line += String(format: L("claim.pdf.location"), lat, lng)
                    }
                    if let note = ci.note, !note.isEmpty { line += "  " + String(format: L("claim.pdf.note"), note) }
                    _ = drawText(line, font: .monospacedSystemFont(ofSize: 9, weight: .regular))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Timeline
            if let timeline = export.timeline, !timeline.isEmpty {
                beginPageIfNeeded()
                _ = drawText(String(format: L("claim.pdf.timeline"), timeline.count), font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                for entry in timeline {
                    beginPageIfNeeded(need: 20)
                    let desc = entry.description ?? entry.type ?? L("claim.pdf.event")
                    _ = drawText("\(entry.timestamp)  \(desc)", font: .monospacedSystemFont(ofSize: 9, weight: .regular))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Medical snapshot
            if let med = export.medicalSnapshot {
                beginPageIfNeeded()
                _ = drawText(L("claim.pdf.medical"), font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                if let bt = med.bloodType, !bt.isEmpty {
                    _ = drawText(String(format: L("claim.pdf.bloodType"), bt), font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let a = med.allergies, !a.isEmpty {
                    _ = drawText(String(format: L("claim.pdf.allergies"), a.joined(separator: L("claim.pdf.listSeparator"))), font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let c = med.conditions, !c.isEmpty {
                    _ = drawText(String(format: L("claim.pdf.conditions"), c.joined(separator: L("claim.pdf.listSeparator"))), font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let p = med.insuranceProvider, !p.isEmpty {
                    _ = drawText(String(format: L("claim.pdf.insurer"), p), font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let pn = med.policyNumber, !pn.isEmpty {
                    _ = drawText(String(format: L("claim.pdf.policy"), pn), font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Reference checklist
            if let type = insuranceType {
                beginPageIfNeeded(need: 100)
                _ = drawText(String(format: L("claim.pdf.checklist"), type.displayName), font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                _ = drawText(L("claim.pdf.insurerRequires"), font: .boldSystemFont(ofSize: 10))
                yOffset += 4
                for item in type.insurerRequires {
                    beginPageIfNeeded(need: 16)
                    _ = drawText("  [ ]  \(item)", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                yOffset += 6
                _ = drawText(L("claim.pdf.deviceHas"), font: .boldSystemFont(ofSize: 10))
                yOffset += 4
                for item in type.velaCanProvide {
                    beginPageIfNeeded(need: 16)
                    _ = drawText("  [x]  \(item)", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                yOffset += 4
                _ = drawText(ClaimDisclaimer.checklistNote, font: .italicSystemFont(ofSize: 9), color: .gray)
                yOffset += 10
            }

            // Disclaimer block
            beginPageIfNeeded(need: 100)
            _ = drawText(L("claim.pdf.dataNotes"), font: .boldSystemFont(ofSize: 14))
            yOffset += 6
            for line in ClaimDisclaimer.limitations {
                beginPageIfNeeded(need: 16)
                _ = drawText("· \(line)", font: .systemFont(ofSize: 9), color: .gray)
                yOffset += 2
            }
            yOffset += 8
            _ = drawText(ClaimDisclaimer.full, font: .systemFont(ofSize: 8), color: .gray)

            // Final footer
            drawFooter(context: context, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin, hash: export.contentHash)
        }

        do {
            try data.write(to: url)
            return url
        } catch {
            print("[ClaimPDF] write error: \(error)")
            return nil
        }
    }

    private static func drawFooter(context: UIGraphicsPDFRendererContext, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat, hash: String) {
        let footerY = pageHeight - 30
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedSystemFont(ofSize: 7, weight: .regular),
            .foregroundColor: UIColor.lightGray
        ]
        let text = "SHA-256: \(hash)  |  " + L("claim.pdf.footer")
        (text as NSString).draw(at: CGPoint(x: margin, y: footerY), withAttributes: attrs)
    }
}
