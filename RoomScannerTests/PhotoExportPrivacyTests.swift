import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import RoomScanner

final class PhotoExportPrivacyTests: XCTestCase {
    func testRemovesGPSAndEXIFFromCopyWithoutChangingOriginal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        let context = try XCTUnwrap(CGContext(data:nil,width:4,height:2,bitsPerComponent:8,bytesPerRow:0,
            space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.noneSkipLast.rawValue))
        let image = try XCTUnwrap(context.makeImage())
        let original = root.appendingPathComponent("original.jpg"),copy = root.appendingPathComponent("export.jpg")
        let destination = try XCTUnwrap(CGImageDestinationCreateWithURL(original as CFURL,UTType.jpeg.identifier as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:52.0,kCGImagePropertyGPSLatitudeRef:"N"],
            kCGImagePropertyExifDictionary:[kCGImagePropertyExifUserComment:"Private survey note"],kCGImagePropertyOrientation:6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let originalBytes = try Data(contentsOf:original)
        try FileManager.default.copyItem(at:original,to:copy)
        XCTAssertGreaterThan(try PhotoExportPrivacy.removeMetadata(fromCopyAt:copy),0)
        XCTAssertEqual(try Data(contentsOf:original),originalBytes)
        let source = try XCTUnwrap(CGImageSourceCreateWithURL(copy as CFURL,nil))
        let props = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any])
        XCTAssertNil(props[kCGImagePropertyGPSDictionary])
        let exif = props[kCGImagePropertyExifDictionary] as? [CFString:Any]
        XCTAssertNil(exif?[kCGImagePropertyExifUserComment])
        XCTAssertEqual(props[kCGImagePropertyPixelWidth] as? Int,2)
        XCTAssertEqual(props[kCGImagePropertyPixelHeight] as? Int,4)
    }

    func testInvalidJPEGThrowsAndPreservesCopy() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString+".jpg")
        defer { try? FileManager.default.removeItem(at:file) }
        let bytes = Data("invalid".utf8)
        try bytes.write(to:file)
        XCTAssertThrowsError(try PhotoExportPrivacy.removeMetadata(fromCopyAt:file))
        XCTAssertEqual(try Data(contentsOf:file),bytes)
    }
}
