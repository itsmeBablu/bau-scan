import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Re-encodes only an export copy. Original survey assets remain unchanged.
enum PhotoExportPrivacy {
    static func removeMetadata(fromCopyAt url: URL) throws -> Int64 {
        guard let source = CGImageSourceCreateWithURL(url as CFURL,[kCGImageSourceShouldCache:false] as CFDictionary),
              CGImageSourceGetCount(source) == 1,
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [CFString:Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0,height > 0,width <= 8192,height <= 8192,width*height <= 16_777_216,
              let image = CGImageSourceCreateThumbnailAtIndex(source,0,[
                kCGImageSourceCreateThumbnailFromImageAlways:true,
                kCGImageSourceCreateThumbnailWithTransform:true,
                kCGImageSourceThumbnailMaxPixelSize:max(width,height)] as CFDictionary) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output,UTType.jpeg.identifier as CFString,1,nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        // Orientation is baked into pixels. No source EXIF/GPS/IPTC properties are copied.
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:1.0] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        try (output as Data).write(to:url,options:.atomic)
        return Int64(output.length)
    }
}
