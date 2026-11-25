import Foundation

/// An additive catalogue. References never own, move or rewrite scan packages.
struct ProjectReference: Codable, Hashable, Identifiable {
    enum Kind: String, Codable, CaseIterable { case room, house, technicalRoom, designRoom, designHouse, designTechnical }
    var kind: Kind
    var itemID: UUID
    var library: String // "local" or "icloud"; no absolute paths in the index
    var id: String { library + ":" + kind.rawValue + ":" + itemID.uuidString }
}

struct RenovationProject: Codable, Equatable, Identifiable {
    var id: UUID
    var name: String
    var createdAt: Date
    var modifiedAt: Date
    var references: [ProjectReference]
    var notes: String
    var details:ProjectDetails? = nil
    var isUnsorted: Bool
    init(id: UUID = UUID(), name: String, date: Date = Date(), references: [ProjectReference] = [], isUnsorted: Bool = false) {
        self.id = id; self.name = name; createdAt = date; modifiedAt = date
        self.references = references; notes = ""; self.isUnsorted = isUnsorted
    }
}

struct ProjectIndex: Codable, Equatable {
    var schemaVersion = 1
    var projects: [RenovationProject] = []
    var displayNames: [String: String]? = nil
    var pins: [ProjectPin]? = nil
    var distanceChecks: [ProjectDistanceCheck]? = nil
    static let unsortedID = UUID(uuidString: "95B5DAB3-9B80-49D7-945B-C9B6B4B18791")!
    mutating func voiceNotesProject(for reference: ProjectReference,preferredProjectID: UUID? = nil) throws -> UUID {
        guard [.house,.room,.technicalRoom].contains(reference.kind),["local","icloud"].contains(reference.library) else { throw CocoaError(.fileReadCorruptFile) }
        if !projects.contains(where: { $0.references.contains(reference) }),let preferredProjectID {
            try assign(reference,to:preferredProjectID)
        }
        reconcile([reference])
        guard let owner = projects.first(where: { $0.references.contains(reference) }) else { throw CocoaError(.fileNoSuchFile) }
        return owner.id
    }

    /// Idempotent discovery preserves missing references for offline/cloud recovery.
    mutating func reconcile(_ discovered: [ProjectReference], now: Date = Date()) {
        let known = Set(projects.flatMap(\.references))
        let additions = Set(discovered).subtracting(known).sorted { $0.id < $1.id }
        guard !additions.isEmpty else { return }
        if let index = projects.firstIndex(where: \.isUnsorted) {
            projects[index].references += additions; projects[index].modifiedAt = now
        } else {
            projects.append(.init(id: Self.unsortedID, name: "Unsorted", date: now, references: additions, isUnsorted: true))
        }
    }

    mutating func assign(_ reference: ProjectReference, to projectID: UUID, now: Date = Date()) throws {
        guard projects.contains(where: { $0.id == projectID }) else { throw CocoaError(.fileNoSuchFile) }
        if let currentPins = pins {
            pins = currentPins.map { value in var pin = value; if pin.reference == reference { pin.projectID = projectID }; return pin }
        }
        if let checks = distanceChecks { distanceChecks = checks.map { value in var check = value; if check.reference == reference { check.projectID = projectID }; return check } }
        for index in projects.indices {
            let old = projects[index].references
            projects[index].references.removeAll { $0 == reference }
            if projects[index].id == projectID { projects[index].references.append(reference) }
            if projects[index].references != old { projects[index].modifiedAt = now }
        }
    }

    func validate() throws {
        for check in distanceChecks ?? [] {
            try check.validate()
            guard projects.contains(where:{ $0.id == check.projectID && $0.references.contains(check.reference) }) else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard (distanceChecks ?? []).count <= 100_000,Set((distanceChecks ?? []).map(\.id)).count == (distanceChecks ?? []).count else { throw CocoaError(.fileReadCorruptFile) }
        for pin in pins ?? [] {
            try pin.validate()
            guard projects.contains(where:{ $0.id == pin.projectID && $0.references.contains(pin.reference) }) else { throw CocoaError(.fileReadCorruptFile) }
        }
        guard (pins ?? []).count <= 100_000,Set((pins ?? []).map(\.id)).count == (pins ?? []).count else { throw CocoaError(.fileReadCorruptFile) }
        let refs = projects.flatMap(\.references)
        guard schemaVersion == 1, projects.count <= 10_000,
              Set(projects.map(\.id)).count == projects.count,
              projects.filter(\.isUnsorted).count <= 1,
              refs.count <= 100_000, Set(refs).count == refs.count,
              refs.allSatisfy({ ["local", "icloud"].contains($0.library) }),
              (displayNames ?? [:]).count <= 100_000,
              (displayNames ?? [:]).allSatisfy({ $0.key.count <= 150 && !$0.value.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && $0.value.count <= 240 }),
              projects.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.name.count <= 240 && $0.notes.count <= 50_000 && ($0.details?.valid ?? true) && $0.createdAt.timeIntervalSince1970.isFinite && $0.modifiedAt.timeIntervalSince1970.isFinite })
        else { throw CocoaError(.fileReadCorruptFile) }
    }
}
