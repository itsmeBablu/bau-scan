import XCTest
import ImageIO
@testable import RoomScanner

final class PhotoImageProcessorTests: XCTestCase {
    func testFreshJPEGIsBoundedAndDoesNotMutateInputOrCopyLocationMetadata() throws {
        let clean = try SyntheticWorkload.jpeg()
        let source = try XCTUnwrap(CGImageSourceCreateWithData(clean as CFData,nil))
        let image = try XCTUnwrap(CGImageSourceCreateImageAtIndex(source,0,nil))
        let privateInput = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(privateInput,"public.jpeg" as CFString,1,nil))
        CGImageDestinationAddImage(destination,image,[kCGImagePropertyGPSDictionary:[kCGImagePropertyGPSLatitude:52.5,kCGImagePropertyGPSLongitude:13.4,kCGImagePropertyGPSLatitudeRef:"N",kCGImagePropertyGPSLongitudeRef:"E"]] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let original = privateInput as Data
        let withGPS = try XCTUnwrap(CGImageSourceCreateWithData(original as CFData,nil))
        let originalProperties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(withGPS,0,nil) as? [CFString:Any])
        XCTAssertNotNil(originalProperties[kCGImagePropertyGPSDictionary],"The input must actually contain location metadata")
        let result = try PhotoImageProcessor.jpeg(original,maximumPixelSize:160,quality:0.7)
        let output = try XCTUnwrap(CGImageSourceCreateWithData(result as CFData,nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(output,0,nil) as? [CFString:Any])
        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
        let decoded = try XCTUnwrap(CGImageSourceCreateImageAtIndex(output,0,nil))
        XCTAssertEqual(max(decoded.width,decoded.height),160)
        XCTAssertLessThanOrEqual(result.count,4*1_048_576)
        XCTAssertEqual(original,privateInput as Data)
    }

    func testCorruptImageAndInvalidQualityNeverProduceAReplacement() throws {
        XCTAssertThrowsError(try PhotoImageProcessor.jpeg(Data("invalid image".utf8)))
        for quality in [-0.1,1.1,Double.nan] {
            XCTAssertThrowsError(try PhotoImageProcessor.jpeg(Data([1]),quality:quality))
        }
    }
}
