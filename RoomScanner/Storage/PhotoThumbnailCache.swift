import Foundation
import ImageIO
import CryptoKit

/// One bounded decoder for saved photo previews. The actor owns decoding away
/// from view bodies; the cache retains decoded thumbnails, never source JPEGs.
actor PhotoThumbnailCache {
    static let shared = PhotoThumbnailCache()
    private let cache = NSCache<NSString, CGImage>()
    init() { cache.countLimit = 48; cache.totalCostLimit = 12 * 1_048_576 }

    func image(_ asset: ProjectPhotoAsset, maximumPixelSize: Int = 400) throws -> CGImage {
        try Task.checkCancellation()
        let file = try SafePackageRead.fileURL(asset.url,root:asset.root)
        let revision = try SavedFileRevision(file)
        guard revision.bytes <= 4*1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        let key = "file|\(revision.path)|\(String(describing:revision.modified))|\(revision.bytes)|\(revision.fileID)|\(maximumPixelSize)" as NSString
        try validateSize(maximumPixelSize)
        if let image = cache.object(forKey: key) { return image }
        return try decode(asset.image().jpegData, maximumPixelSize: maximumPixelSize, key: key)
    }

    func image(data: Data, maximumPixelSize: Int = 400) throws -> CGImage {
        try Task.checkCancellation()
        try validateSize(maximumPixelSize)
        guard !data.isEmpty, data.count <= 20 * 1_048_576 else { throw CocoaError(.fileReadTooLarge) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let key = "bytes|\(digest)|\(maximumPixelSize)" as NSString
        if let image = cache.object(forKey: key) { return image }
        return try decode(data, maximumPixelSize: maximumPixelSize, key: key)
    }

    private func validateSize(_ size: Int) throws {
        guard (1...2400).contains(size) else { throw CocoaError(.fileReadTooLarge) }
    }
    private func decode(_ data: Data, maximumPixelSize: Int, key: NSString) throws -> CGImage {
        try Task.checkCancellation()
        let image = try PhotoImageProcessor.thumbnail(data,maximumPixelSize:maximumPixelSize)
        try Task.checkCancellation()
        cache.setObject(image, forKey: key, cost: image.bytesPerRow * image.height)
        return image
    }
}
