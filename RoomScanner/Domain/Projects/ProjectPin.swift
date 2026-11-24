import Foundation

struct ProjectPin: Codable, Equatable, Identifiable {
    enum Status: String, Codable, CaseIterable { case open, inProgress, resolved }
    var id: UUID = UUID()
    var projectID: UUID
    var reference: ProjectReference
    var story: Int
    var position: Point2D // source plan coordinates, metres, Y = -room Z
    var text: String = ""
    var status: Status = .open
    var photoID: UUID?
    var elementID: UUID?
    func validate() throws {
        guard position.x.isFinite,position.y.isFinite,abs(position.x) <= 100_000,abs(position.y) <= 100_000,
              text.count <= 4000,reference.kind == .house || reference.kind == .room else { throw CocoaError(.fileReadCorruptFile) }
    }
}
