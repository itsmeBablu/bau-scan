import Foundation

/// Shared disposable cache identity. No content, hashes or persistent schema.
/// Callers still own containment checks, file budgets and coordinated reads.
struct SavedFileRevision: Equatable {
    let path:String
    let modified:Date?
    let bytes:Int
    let fileID:String

    init(_ file:URL) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath:file.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber,size.int64Value >= 0,
              size.uint64Value <= UInt64(Int.max) else { throw CocoaError(.fileReadCorruptFile) }
        path = file.standardizedFileURL.path
        modified = attributes[.modificationDate] as? Date
        bytes = size.intValue
        fileID = String(describing:attributes[.systemFileNumber])
    }
}
