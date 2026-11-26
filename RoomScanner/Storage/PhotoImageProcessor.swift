import Foundation
import ImageIO

/// Shared bounded image decoding/encoding, with no UI or AR dependency. Call
/// from the thumbnail actor or an explicitly owned background worker.
enum PhotoImageProcessor {
    static func thumbnail(_ data:Data,maximumPixelSize:Int) throws -> CGImage {
        try Task.checkCancellation()
        guard (1...2400).contains(maximumPixelSize),!data.isEmpty,data.count <= 20*1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        guard let source = CGImageSourceCreateWithData(data as CFData,[kCGImageSourceShouldCache:false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:maximumPixelSize] as CFDictionary)
        else { throw CocoaError(.fileReadCorruptFile) }
        try Task.checkCancellation()
        return image
    }

    /// Normalizes orientation and writes a fresh JPEG without copying GPS/EXIF.
    /// Source bytes and the selected original file remain unchanged.
    static func jpeg(_ data:Data,maximumPixelSize:Int = 1600,quality:Double = 0.8) throws -> Data {
        guard quality.isFinite,(0...1).contains(quality) else { throw CocoaError(.coderInvalidValue) }
        let image = try thumbnail(data,maximumPixelSize:maximumPixelSize),output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,"public.jpeg" as CFString,1,nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try Task.checkCancellation()
        guard output.length <= 4*1_048_576 else { throw CocoaError(.fileWriteOutOfSpace) }
        return output as Data
    }
}
