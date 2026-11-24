import Foundation
import CoreGraphics
import CoreText
import ImageIO

/// A report assembles independent surveys; it does not infer that repeated scans are disjoint.
enum ProjectReportRenderer {
    static func pdf(_ report: ProjectReport, locale: Locale) throws -> Data {
        let data = NSMutableData(); var box = CGRect(x:0,y:0,width:595,height:842)
        guard let consumer = CGDataConsumer(data:data as CFMutableData),
              let ctx = CGContext(consumer:consumer,mediaBox:&box,[kCGPDFContextTitle:report.name,kCGPDFContextCreator:"dWalkScan"] as CFDictionary) else { throw CocoaError(.fileWriteUnknown) }
        func text(_ value: String, y: CGFloat, size: CGFloat = 12, height: CGFloat = 60) {
            let attributed = NSAttributedString(string:value,attributes:[
                NSAttributedString.Key(kCTFontAttributeName as String):CTFontCreateWithName("Helvetica" as CFString,size,nil),
                NSAttributedString.Key(kCTForegroundColorAttributeName as String):CGColor(gray:0,alpha:1)])
            let path = CGPath(rect:CGRect(x:36,y:y-height,width:523,height:height),transform:nil)
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),CFRange(location:0,length:0),path,nil)
            CTFrameDraw(frame,ctx)
        }
        let warning = AppLanguage.text("Measured with iPhone LiDAR; device validation pending. Verify critical dimensions independently.",locale:locale)
        var pageNumber = 0
        func begin(_ title: String) { ctx.beginPDFPage(nil); pageNumber += 1; text(title,y:806,size:20,height:55) }
        func end() { text(warning,y:57,size:9,height:35); text("\(pageNumber)",y:25,size:9,height:15); ctx.endPDFPage() }
        func lines(_ title: String,_ values: [String]) {
            begin(title); var y: CGFloat = 735
            for line in values {
                if y < 115 { end(); begin(title); y = 735 }
                let count = max(1,Int(ceil(Double(line.count)/70)))
                let height = CGFloat(min(12,count))*17
                if y-height < 95 { end(); begin(title); y = 735 }
                text(line,y:y,height:height); y -= height+9
            }
            end()
        }
        let date = DateFormatter(); date.locale = locale; date.dateStyle = .long
        lines(report.name,[AppLanguage.text("Renovation survey",locale:locale),date.string(from:report.generatedAt),warning,
                          AppLanguage.text("Each scan is an independent survey. Repeated or overlapping scans must not be added as building totals.",locale:locale)])
        if !report.notes.isEmpty {
            let paragraphs = report.notes.split(separator:"\n",omittingEmptySubsequences:false).flatMap { paragraph -> [String] in
                let chars = Array(paragraph)
                if chars.isEmpty { return [""] }
                return stride(from:0,to:chars.count,by:500).map { String(chars[$0..<min(chars.count,$0+500)]) }
            }
            lines(AppLanguage.text("Photos & notes",locale:locale),paragraphs)
        }
        for scan in report.scans {
            if let house = scan.house {
                var renderer = PlanRenderer(); renderer.options.locale = locale
                let pdf = renderer.pdfData(house,title:scan.title)
                if let provider = CGDataProvider(data:pdf as CFData),let source = CGPDFDocument(provider) {
                    for i in 1...max(1,source.numberOfPages) {
                        guard let page = source.page(at:i) else { continue }
                        begin(scan.title)
                        ctx.saveGState()
                        ctx.concatenate(page.getDrawingTransform(.mediaBox,rect:CGRect(x:24,y:160,width:547,height:560),rotate:0,preserveAspectRatio:true))
                        ctx.drawPDFPage(page); ctx.restoreGState(); end()
                    }
                }
                let rows = house.allRooms.map { room in
                    let m = RoomMeasurements(plan:room)
                    return room.name+" · "+MeasurementFormat.squareMeters(m.floorArea,locale:locale)+" · "+AppLanguage.text("Perimeter",locale:locale)+" "+MeasurementFormat.meters(m.perimeter,locale:locale)
                }
                lines(scan.title+" — "+AppLanguage.text("Rooms",locale:locale),rows)
            }
            if !scan.detailLines.isEmpty { lines(scan.title,scan.detailLines) }
        }
        for photo in report.photos {
            begin(photo.room+" — "+AppLanguage.text("Photo",locale:locale)+" \(photo.number)")
            if let source = CGImageSourceCreateWithData(photo.jpeg as CFData,nil),let image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways:true,kCGImageSourceCreateThumbnailWithTransform:true,kCGImageSourceThumbnailMaxPixelSize:2400] as CFDictionary) {
                let scale = min(523/CGFloat(image.width),620/CGFloat(image.height))
                let size = CGSize(width:CGFloat(image.width)*scale,height:CGFloat(image.height)*scale)
                ctx.draw(image,in:CGRect(x:(595-size.width)/2,y:110+(620-size.height)/2,width:size.width,height:size.height))
            } else { text(AppLanguage.text("Photo unavailable",locale:locale),y:700) }
            end()
        }
        if !report.unresolved.isEmpty { lines(AppLanguage.text("Unresolved items",locale:locale),report.unresolved) }
        ctx.closePDF(); return data as Data
    }
}
