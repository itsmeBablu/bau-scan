import AppKit
import CoreGraphics

/// Plan printing: vector PDF from `PlanRenderer` (A4 landscape) is drawn
/// via dedicated `NSView` and passed to `NSPrintOperation`.
@MainActor
enum PrintController {
    static func printPlan(_ house: House, title: String, locale: Locale = AppLanguage.locale, window: NSWindow?) throws {
        var renderer = PlanRenderer(); renderer.options.locale = locale
        renderer.options.unit = ExportService().unit
        let pageSize = CGSize(width: 842, height: 595)
        let data = renderer.pdfData(house, size: pageSize, title: title)
        guard let provider = CGDataProvider(data:data as CFData),let pdf = CGPDFDocument(provider) else { throw CocoaError(.fileReadCorruptFile) }
        let view = PDFPageView(document: pdf, frame: NSRect(origin: .zero, size: pageSize))
        guard let info = NSPrintInfo.shared.copy() as? NSPrintInfo else { throw CocoaError(.fileReadUnknown) }
        info.orientation = .landscape
        info.paperSize = NSSize(width: 842, height: 595)
        info.horizontalPagination = .fit; info.verticalPagination = .fit
        info.isHorizontallyCentered = true; info.isVerticallyCentered = true
        info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = title
        op.showsPrintPanel = true; op.showsProgressPanel = true
        if let window { op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil) } else { op.run() }
    }

    /// Each PDF page occupies a separate printable rectangle in document order.
    final class PDFPageView: NSView {
        let document: CGPDFDocument
        let pageRects: [NSRect]
        init(document: CGPDFDocument, frame: NSRect) {
            self.document = document
            var y: CGFloat = 0,rects: [NSRect] = []
            for number in 1...max(1,document.numberOfPages) {
                guard let page = document.page(at:number) else { continue }
                let size = page.getBoxRect(.mediaBox).size
                rects.append(NSRect(x:0,y:y,width:size.width,height:size.height)); y += size.height
            }
            pageRects = rects
            super.init(frame:NSRect(x:frame.minX,y:frame.minY,width:rects.map(\.width).max() ?? frame.width,height:y))
        }
        required init?(coder: NSCoder) { nil }
        override var isFlipped: Bool { false }
        override func draw(_ dirtyRect: NSRect) {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            for (index,rect) in pageRects.enumerated() where rect.intersects(dirtyRect) {
                guard let page = document.page(at:index+1) else { continue }
                ctx.saveGState(); ctx.clip(to:rect)
                ctx.concatenate(page.getDrawingTransform(.mediaBox,rect:rect,rotate:0,preserveAspectRatio:true))
                ctx.drawPDFPage(page); ctx.restoreGState()
            }
        }
        override func knowsPageRange(_ range: NSRangePointer) -> Bool { range.pointee = NSRange(location:1,length:pageRects.count); return true }
        override func rectForPage(_ page: Int) -> NSRect { page > 0 && page <= pageRects.count ? pageRects[page-1] : .zero }
    }
}
