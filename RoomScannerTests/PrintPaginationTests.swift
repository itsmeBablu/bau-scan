#if os(macOS)
import XCTest
import AppKit
import CoreGraphics
@testable import RoomScanner

final class PrintPaginationTests: XCTestCase {
    @MainActor func testSingleAndThreePagePaginationAndInvalidNumbers() throws {
        for count in [1,3] {
            let bytes = NSMutableData(),consumer = try XCTUnwrap(CGDataConsumer(data:bytes as CFMutableData))
            var box = CGRect(x:0,y:0,width:842,height:595)
            let context = try XCTUnwrap(CGContext(consumer:consumer,mediaBox:&box,nil))
            for _ in 0..<count { context.beginPDFPage(nil); context.endPDFPage() }; context.closePDF()
            let pdf = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data:bytes as CFData))))
            let view = PrintController.PDFPageView(document:pdf,frame:box)
            var range = NSRange(); XCTAssertTrue(view.knowsPageRange(&range)); XCTAssertEqual(range.length,count)
            for page in 1...count { XCTAssertEqual(view.rectForPage(page).minY,CGFloat(page-1)*595) }
            XCTAssertEqual(view.rectForPage(0),.zero); XCTAssertEqual(view.rectForPage(count+1),.zero)
        }
    }
    @MainActor func testHousePDFPreservesEveryStoreyPage() throws {
        let house = try HouseBuilder().build(from:SyntheticRooms.twoStoryHouse(),name:"House")
        let bytes = PlanRenderer().pdfData(house,size:.init(width:842,height:595),title:"House")
        let pdf = try XCTUnwrap(CGPDFDocument(try XCTUnwrap(CGDataProvider(data:bytes as CFData))))
        let view = PrintController.PDFPageView(document:pdf,frame:.init(x:0,y:0,width:842,height:595))
        XCTAssertEqual(view.pageRects.count,pdf.numberOfPages); XCTAssertGreaterThanOrEqual(pdf.numberOfPages,2)
    }
}
#endif
