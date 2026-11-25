import Foundation

/// Sidebar identity/metadata only; the mutable document is read when opened.
struct DesignRef: Hashable, Identifiable {
    let source: SceneEditDocument.Source
    let sourceID: UUID
    let title: String
    let modifiedAt: Date?
    var id: String { source.rawValue+"-"+sourceID.uuidString }
    init(_ document: SceneEditDocument, modifiedAt: Date? = nil) {
        source = document.source; sourceID = document.sourceID
        title = document.title; self.modifiedAt = document.modifiedAt ?? modifiedAt
    }
}
