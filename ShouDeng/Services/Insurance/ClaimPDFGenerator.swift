import UIKit
import CryptoKit

// MARK: - Claim PDF Generator
//
// Generates a structured PDF from a ClaimMaterialExport.
// The PDF is reference-only — disclaimers on every page.

enum ClaimPDFGenerator {

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
            _ = drawText("理赔材料参考", font: .boldSystemFont(ofSize: 22))
            yOffset += 4
            _ = drawText(ClaimDisclaimer.pdfHeader, font: .systemFont(ofSize: 9), color: .gray)
            yOffset += 16

            // Basic info
            _ = drawText("基本信息", font: .boldSystemFont(ofSize: 14))
            yOffset += 6
            _ = drawText("导出编号: \(export.exportId)", font: .systemFont(ofSize: 10))
            yOffset += 2
            _ = drawText("当事人: \(export.personName)", font: .systemFont(ofSize: 10))
            yOffset += 2

            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm"
            _ = drawText("事件日期: \(df.string(from: export.incidentDate))", font: .systemFont(ofSize: 10))
            yOffset += 2
            _ = drawText("导出时间: \(df.string(from: export.exportedAt))", font: .systemFont(ofSize: 10))
            yOffset += 2
            _ = drawText("时间范围: \(df.string(from: export.window.start)) ~ \(df.string(from: export.window.end))", font: .systemFont(ofSize: 10))
            yOffset += 2

            if let policy = policyNumber, !policy.isEmpty {
                _ = drawText("保单号: \(policy)", font: .systemFont(ofSize: 10))
                yOffset += 2
            }
            if let desc = userDescription, !desc.isEmpty {
                _ = drawText("备注: \(desc)", font: .systemFont(ofSize: 10))
                yOffset += 2
            }
            yOffset += 12

            // SOS Events
            if let sos = export.sosEvents, !sos.isEmpty {
                beginPageIfNeeded()
                _ = drawText("SOS 求助记录 (\(sos.count) 条)", font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                for event in sos {
                    beginPageIfNeeded(need: 20)
                    var line = event.triggeredAt
                    if let method = event.triggerMethod { line += "  触发方式: \(method)" }
                    if let res = event.resolution { line += "  处理: \(res)" }
                    if let lat = event.latitude, let lng = event.longitude {
                        line += String(format: "  位置: %.4f, %.4f", lat, lng)
                    }
                    _ = drawText(line, font: .monospacedSystemFont(ofSize: 9, weight: .regular))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Check-ins
            if let checkIns = export.checkIns, !checkIns.isEmpty {
                beginPageIfNeeded()
                _ = drawText("签到记录 (\(checkIns.count) 条)", font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                for ci in checkIns {
                    beginPageIfNeeded(need: 20)
                    var line = ci.timestamp
                    if let lat = ci.latitude, let lng = ci.longitude {
                        line += String(format: "  位置: %.4f, %.4f", lat, lng)
                    }
                    if let note = ci.note, !note.isEmpty { line += "  备注: \(note)" }
                    _ = drawText(line, font: .monospacedSystemFont(ofSize: 9, weight: .regular))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Timeline
            if let timeline = export.timeline, !timeline.isEmpty {
                beginPageIfNeeded()
                _ = drawText("时间线事件 (\(timeline.count) 条)", font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                for entry in timeline {
                    beginPageIfNeeded(need: 20)
                    let desc = entry.description ?? entry.type ?? "事件"
                    _ = drawText("\(entry.timestamp)  \(desc)", font: .monospacedSystemFont(ofSize: 9, weight: .regular))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Medical snapshot
            if let med = export.medicalSnapshot {
                beginPageIfNeeded()
                _ = drawText("医疗卡快照", font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                if let bt = med.bloodType, !bt.isEmpty {
                    _ = drawText("血型: \(bt)", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let a = med.allergies, !a.isEmpty {
                    _ = drawText("过敏: \(a.joined(separator: "、"))", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let c = med.conditions, !c.isEmpty {
                    _ = drawText("病史: \(c.joined(separator: "、"))", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let p = med.insuranceProvider, !p.isEmpty {
                    _ = drawText("保险公司: \(p)", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                if let pn = med.policyNumber, !pn.isEmpty {
                    _ = drawText("保单号: \(pn)", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                yOffset += 10
            }

            // Reference checklist
            if let type = insuranceType {
                beginPageIfNeeded(need: 100)
                _ = drawText("材料参考清单 · \(type.displayName)", font: .boldSystemFont(ofSize: 14))
                yOffset += 6
                _ = drawText("保险公司通常要求 (需您自行获取):", font: .boldSystemFont(ofSize: 10))
                yOffset += 4
                for item in type.insurerRequires {
                    beginPageIfNeeded(need: 16)
                    _ = drawText("  [ ]  \(item)", font: .systemFont(ofSize: 10))
                    yOffset += 2
                }
                yOffset += 6
                _ = drawText("您的设备记录中包含:", font: .boldSystemFont(ofSize: 10))
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
            _ = drawText("数据说明", font: .boldSystemFont(ofSize: 14))
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
        let text = "SHA-256: \(hash)  |  守灯 App 导出 · 仅供参考"
        (text as NSString).draw(at: CGPoint(x: margin, y: footerY), withAttributes: attrs)
    }
}
