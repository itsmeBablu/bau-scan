import Foundation

struct ProjectDistanceCheck: Codable, Equatable, Identifiable {
    var id = UUID()
    var projectID: UUID
    var reference: ProjectReference
    var elementID: UUID
    var label: String
    var referenceMeters: Double
    var observedMeters: Double
    var method: String
    var date = Date()
    var deviceValidationPending = true
    var signedErrorMeters: Double { observedMeters-referenceMeters }
    var absoluteErrorMeters: Double { abs(signedErrorMeters) }
    var relativeErrorPercent: Double { 100*signedErrorMeters/referenceMeters }
    func validate() throws {
        guard referenceMeters.isFinite,referenceMeters > 0,referenceMeters <= 100_000,
              observedMeters.isFinite,observedMeters > 0,observedMeters <= 100_000,
              !method.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty,method.count <= 1000,label.count <= 500,
              date.timeIntervalSince1970.isFinite else { throw CocoaError(.fileReadCorruptFile) }
    }
}
