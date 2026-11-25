import Foundation

struct ProjectLibraryEntry: Identifiable {
    let reference: ProjectReference
    let title: String
    let date: Date
    let area: Double?
    let roomCount: Int
    let root: URL
    let url: URL
    var id: String { reference.id }
    var isDesign: Bool { reference.kind.rawValue.hasPrefix("design") }
}
