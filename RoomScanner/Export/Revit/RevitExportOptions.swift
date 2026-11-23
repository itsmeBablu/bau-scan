import Foundation

struct RevitExportOptions {
    enum Schema: String, CaseIterable { case ifc4 = "IFC4", ifc2x3 = "IFC2X3" }
    var schema = Schema.ifc4
    var includeArchitecture = true
    var includeMEP = true
    /// Absolute elevations supplied from scan floor evidence, in metres.
    var storeyElevations: [Int: Double] = [:]
    /// Original shell coordinates to house coordinates. Required for registered MEP.
    var shellPlacements: [UUID: TechnicalTransform] = [:]
    /// A fixed timestamp makes repeated exports byte-identical.
    var timestamp = "2000-01-01T00:00:00"
}

struct RevitTechnicalRoomInput {
    var name: String
    var document: TechnicalAnnotationDocument
}
