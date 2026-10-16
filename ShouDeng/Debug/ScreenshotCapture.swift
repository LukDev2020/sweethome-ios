#if DEBUG
import SwiftUI
import UIKit
import PDFKit

// MARK: - Auto Screenshot Capture
//
// When launched with -screenshot argument, the app:
// 1. Cycles through all tabs automatically
// 2. Captures each screen to PNG
// 3. Generates a combined PDF with labels
// 4. Saves to the simulator's Documents folder

final class ScreenshotCapture: ObservableObject {
    static let shared = ScreenshotCapture()

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-screenshot")
    }

    @Published var capturedCount = 0
    private var images: [(name: String, path: String, image: UIImage)] = []
    private let outDir: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        outDir = docs.appendingPathComponent("screenshots")
        try? FileManager.default.removeItem(at: outDir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
    }

    func capture(name: String, filePath: String) {
        guard let window = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first?.windows.first else { return }

        let renderer = UIGraphicsImageRenderer(size: window.bounds.size)
        let image = renderer.image { ctx in
            window.layer.render(in: ctx.cgContext)
        }

        let pngPath = outDir.appendingPathComponent("\(name).png")
        if let data = image.pngData() {
            try? data.write(to: pngPath)
        }
        images.append((name: name, path: filePath, image: image))
        capturedCount += 1
        print("[Screenshot] Captured \(name) -> \(pngPath.lastPathComponent)")
    }

    func generatePDF() {
        guard !images.isEmpty else { return }

        let pageWidth: CGFloat = 390 * 2  // iPhone 16 Pro width @2x
        let pageHeight: CGFloat = 844 * 2 // iPhone 16 Pro height @2x
        let labelHeight: CGFloat = 80
        let fullHeight = pageHeight + labelHeight

        let pdfData = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: fullHeight)

        guard let consumer = CGDataConsumer(data: pdfData as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return }

        for item in images {
            context.beginPage(mediaBox: &mediaBox)

            // Draw label background
            context.setFillColor(UIColor.black.cgColor)
            context.fill(CGRect(x: 0, y: pageHeight, width: pageWidth, height: labelHeight))

            // Draw label text
            let label = "\(item.name)\n\(item.path)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 22, weight: .medium),
                .foregroundColor: UIColor.white
            ]
            let textRect = CGRect(x: 20, y: pageHeight + 10, width: pageWidth - 40, height: labelHeight - 20)

            UIGraphicsPushContext(context)
            // Flip for text drawing
            context.saveGState()
            context.translateBy(x: 0, y: fullHeight)
            context.scaleBy(x: 1, y: -1)
            let flippedRect = CGRect(x: 20, y: 10, width: pageWidth - 40, height: labelHeight - 20)
            label.draw(in: flippedRect, withAttributes: attrs)
            context.restoreGState()

            // Draw screenshot image
            if let cgImage = item.image.cgImage {
                context.draw(cgImage, in: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight))
            }
            UIGraphicsPopContext()

            context.endPage()
        }

        context.closePDF()

        let pdfPath = outDir.appendingPathComponent("ShouDeng_All_Screens.pdf")
        pdfData.write(to: pdfPath, atomically: true)
        print("[Screenshot] PDF saved to: \(pdfPath.path)")
        print("[Screenshot] Total pages: \(images.count)")
    }
}
#endif
