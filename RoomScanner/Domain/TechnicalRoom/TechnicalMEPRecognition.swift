import Foundation

enum TechnicalMEPKind: String, Codable, CaseIterable {
    case pipe, roundDuct, rectangularDuct
    var title: String {
        switch self { case .pipe: "Pipe / cylindrical element"; case .roundDuct: "Round duct"; case .rectangularDuct: "Rectangular duct" }
    }
}
enum TechnicalMEPMaterial: String, Codable, CaseIterable { case captured, paintedMetal, bareMetal, plastic, insulation }

/// Suggestions use original AR session coordinates, independently of manual survey alignment.
/// Acceptance is a user review, not an accuracy certification or a live alignment check.
struct TechnicalMEPSuggestion: Codable, Equatable, Identifiable {
    enum Status: String, Codable { case proposed, accepted, rejected }
    var id = UUID()
    var kind: TechnicalMEPKind
    var start: TechnicalPoint3
    var end: TechnicalPoint3
    var width: Double
    var height: Double
    var crossAxis: TechnicalPoint3
    var color: TechnicalPoint3?
    var material = TechnicalMEPMaterial.captured
    var status = Status.proposed
    var method: String
    var supportCount: Int
    var residualMetres: Double
    var modelScore: Double?
    var evidenceIDs: [UUID] = []
    var geometrySource = TechnicalSource.estimated
    var length: Double { start.distance(to: end) }
    var accuracyMm: Double? { nil }
    func validate() throws {
        guard TechnicalPointEditing.valid(start), TechnicalPointEditing.valid(end),
              length >= 0.1, length <= 100, width.isFinite, height.isFinite,
              width > 0, width <= 3, height > 0, height <= 3,
              kind == .rectangularDuct || abs(width-height) < 1e-6,
              TechnicalPointEditing.valid(crossAxis), abs(crossAxis.distance(to: .init(x: 0, y: 0, z: 0)) - 1) < 0.001,
              abs(MEPVector.dot(MEPVector.unit(MEPVector.sub(end, start)), crossAxis)) < 0.001,
              supportCount >= 20, supportCount <= 250_000, residualMetres.isFinite, residualMetres >= 0,
              !method.isEmpty, method.count <= 200, evidenceIDs.count <= 32,
              modelScore == nil || (modelScore!.isFinite && (0...1).contains(modelScore!)),
              color == nil || [color!.x, color!.y, color!.z].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw TechnicalCaptureJournal.JournalError.invalidEvidence
        }
    }
}

struct TechnicalMEPReview: Codable, Equatable {
    var schemaVersion = 1
    var suggestions: [TechnicalMEPSuggestion] = []
    func validate() throws {
        guard schemaVersion == 1, suggestions.count <= 200, Set(suggestions.map(\.id)).count == suggestions.count else {
            throw TechnicalCaptureJournal.JournalError.invalidEvidence
        }
        for item in suggestions { try item.validate() }
    }
    mutating func merge(_ items: [TechnicalMEPSuggestion]) {
        for item in items where suggestions.count < 200 {
            // Do not recreate rejected/accepted objects on another analysis of the same evidence.
            let duplicate = suggestions.contains { old in
                guard old.kind == item.kind else { return false }
                let direct = old.start.distance(to: item.start) + old.end.distance(to: item.end)
                let reverse = old.start.distance(to: item.end) + old.end.distance(to: item.start)
                return min(direct, reverse) < 0.25 && abs(old.width - item.width) < 0.05
            }
            if !duplicate { suggestions.append(item) }
        }
    }
}

/// Foundation-only vector arithmetic keeps recognition and package tests platform independent.
enum MEPVector {
    static let zero = TechnicalPoint3(x: 0, y: 0, z: 0)
    static func add(_ a: TechnicalPoint3, _ b: TechnicalPoint3) -> TechnicalPoint3 { .init(x: a.x+b.x, y: a.y+b.y, z: a.z+b.z) }
    static func sub(_ a: TechnicalPoint3, _ b: TechnicalPoint3) -> TechnicalPoint3 { .init(x: a.x-b.x, y: a.y-b.y, z: a.z-b.z) }
    static func mul(_ a: TechnicalPoint3, _ s: Double) -> TechnicalPoint3 { .init(x: a.x*s, y: a.y*s, z: a.z*s) }
    static func dot(_ a: TechnicalPoint3, _ b: TechnicalPoint3) -> Double { a.x*b.x+a.y*b.y+a.z*b.z }
    static func cross(_ a: TechnicalPoint3, _ b: TechnicalPoint3) -> TechnicalPoint3 { .init(x: a.y*b.z-a.z*b.y, y: a.z*b.x-a.x*b.z, z: a.x*b.y-a.y*b.x) }
    static func unit(_ a: TechnicalPoint3) -> TechnicalPoint3 { let n = sqrt(dot(a,a)); return n > 1e-9 ? mul(a,1/n) : zero }
}
