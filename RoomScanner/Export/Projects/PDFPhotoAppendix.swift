import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// A PDF-only appendix. Original pages keep their media boxes; source photos are
/// read one at a time and never rewritten. No UIKit/AppKit/PDFKit dependency.
enum PDFPhotoAppendix {
    static func append(to original: Data, sources: [SurveyPhotoExportSource], locale: Locale) throws -> Data {
        guard !sources.isEmpty else { return original }
        guard let provider = CGDataProvider(data: original as CFData), let pdf = CGPDFDocument(provider)
        else { throw CocoaError(.fileReadCorruptFile) }
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: nil, nil) else { throw CocoaError(.fileWriteUnknown) }
        for index in 1...pdf.numberOfPages {
            try Task.checkCancellation()
            guard let page = pdf.page(at: index) else { throw CocoaError(.fileReadCorruptFile) }
            var box = page.getBoxRect(.mediaBox)
            let boxData = NSData(bytes: &box, length: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox: boxData] as CFDictionary)
            context.drawPDFPage(page); context.endPDFPage()
        }
        for source in sources.prefix(100) {
            try Task.checkCancellation()
            try autoreleasepool {
                let bytes = try RoomPackage.coordinatedRead(at: source.root) { root in
                    try SafePackageRead.data(root.appendingPathComponent(source.photo.jpegPath),root:root,maximum:4*1_048_576,preflight:false)
                }
                let label = source.roomName + " — " + AppLanguage.text("Photo",locale:locale) + " \(source.photo.number)"
                drawPage(in: context, jpeg: bytes, label: label, locale: locale)
            }
        }
        if sources.count > 100 {
            drawPage(in: context,jpeg:nil,label:AppLanguage.text("PDF photo budget reached. The complete ZIP photo folders retain all available photos.",locale:locale),locale:locale)
        }
        context.closePDF()
        return output as Data
    }

    static func drawPage(in context: CGContext, jpeg: Data?, label: String, locale: Locale) {
        var box = CGRect(x:0,y:0,width:595,height:842)
        let boxData = NSData(bytes:&box,length:MemoryLayout<CGRect>.size)
        context.beginPDFPage([kCGPDFContextMediaBox:boxData] as CFDictionary)
        func text(_ value: String, y: CGFloat) {
            let attributes: [NSAttributedString.Key:Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString,12,nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray:0.12,alpha:1)]
            let framesetter = CTFramesetterCreateWithAttributedString(NSAttributedString(string:value,attributes:attributes))
            let path = CGPath(rect:CGRect(x:36,y:y,width:523,height:72),transform:nil)
            CTFrameDraw(CTFramesetterCreateFrame(framesetter,CFRange(location:0,length:0),path,nil),context)
        }
        text(label,y:740)
        if let jpeg,let source = CGImageSourceCreateWithData(jpeg as CFData,nil),
           let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2400] as CFDictionary) {
            let scale = min(523/CGFloat(image.width),620/CGFloat(image.height))
            let size = CGSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
            context.draw(image,in:CGRect(x:(595-size.width)/2,y:110+(620-size.height)/2,width:size.width,height:size.height))
        } else if jpeg != nil { text(AppLanguage.text("Photo unavailable",locale:locale),y:650) }
        context.endPDFPage()
    }
}
