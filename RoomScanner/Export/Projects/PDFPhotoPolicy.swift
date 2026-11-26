import Foundation

/// A device preference/export option, never a native scan-package field.
enum PDFPhotoPolicy {
    static let preferenceKey = "export.pdf.includePhotos"
    static let defaultValue = true // preserve previously included report photographs
}
