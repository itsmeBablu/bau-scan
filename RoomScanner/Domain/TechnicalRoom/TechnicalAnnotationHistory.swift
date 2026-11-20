import Foundation

/// Transactional, bounded history. Rejected edits never alter the document or undo stack.
struct TechnicalAnnotationHistory {
    enum EditError: LocalizedError {
        case alignmentRequired, invalidPipe, duplicateID, invalidGeometry, missingReference
        var errorDescription: String? {
            switch self {
            case .alignmentRequired: "Verify alignment before editing annotations."
            case .invalidPipe, .invalidGeometry: "Enter finite, positive dimensions and valid control points."
            case .duplicateID: "This annotation or connection already exists."
            case .missingReference: "The referenced annotation or port is missing."
            }
        }
    }
    private(set) var document: TechnicalAnnotationDocument
    var room: TechnicalRoom { document.room }
    private var undoStack: [TechnicalAnnotationDocument] = []
    private var redoStack: [TechnicalAnnotationDocument] = []
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    init(room: TechnicalRoom) { document = .init(room: room) }
    init(document: TechnicalAnnotationDocument) { self.document = document }

    mutating func edit(capture: TechnicalCaptureState, _ change: (inout TechnicalAnnotationDocument) throws -> Void) throws {
        guard capture.canAnnotate else { throw EditError.alignmentRequired }
        var candidate = document
        try change(&candidate)
        try Self.validate(candidate)
        guard candidate != document else { return }
        if undoStack.count >= 50 { undoStack.removeFirst() }
        undoStack.append(document); redoStack.removeAll(); document = candidate
    }
    mutating func addPipe(_ pipe: TechnicalPipeRun, capture: TechnicalCaptureState) throws {
        try edit(capture: capture) { $0.room.pipeRuns.append(pipe) }
    }
    mutating func deletePipe(_ id: UUID, capture: TechnicalCaptureState) throws {
        try edit(capture: capture) {
            $0.room.pipeRuns.removeAll { $0.id == id }; $0.room.fittings.removeAll { $0.hostPipeRunId == id }
            $0.connections.removeAll { $0.pipeID == id }; $0.pointOverrides.removeAll { $0.objectID == id }
        }
    }
    mutating func deleteEquipment(_ id: UUID, capture: TechnicalCaptureState) throws {
        try edit(capture: capture) { doc in
            let ports = Set(doc.room.equipment.first { $0.id == id }?.ports.map(\.id) ?? [])
            doc.room.equipment.removeAll { $0.id == id }; doc.connections.removeAll { ports.contains($0.portID) }
            for i in doc.room.pipeRuns.indices { doc.room.pipeRuns[i].connectedPorts.removeAll { ports.contains($0) } }
        }
    }
    mutating func connect(pipeID: UUID, endpoint: TechnicalPipeConnection.Endpoint, portID: UUID, capture: TechnicalCaptureState) throws {
        try edit(capture: capture) { doc in
            guard let i = doc.room.pipeRuns.firstIndex(where: { $0.id == pipeID }) else { throw EditError.missingReference }
            let old = doc.connections.filter { $0.pipeID == pipeID && $0.endpoint == endpoint }.map(\.portID)
            doc.connections.removeAll { $0.pipeID == pipeID && $0.endpoint == endpoint }
            doc.room.pipeRuns[i].connectedPorts.removeAll { old.contains($0) }
            doc.connections.append(.init(id: UUID(), pipeID: pipeID, endpoint: endpoint, portID: portID))
            if !doc.room.pipeRuns[i].connectedPorts.contains(portID) { doc.room.pipeRuns[i].connectedPorts.append(portID) }
        }
    }
    mutating func deletePort(_ id: UUID, capture: TechnicalCaptureState) throws {
        try edit(capture: capture) { doc in
            for i in doc.room.equipment.indices { doc.room.equipment[i].ports.removeAll { $0.id == id } }
            for i in doc.room.pipeRuns.indices { doc.room.pipeRuns[i].connectedPorts.removeAll { $0 == id } }
            doc.connections.removeAll { $0.portID == id }
        }
    }
    mutating func move(target: TechnicalAnnotationTarget, index: Int, to point: TechnicalPoint3,
                       observation: TechnicalSurfaceHit?, capture: TechnicalCaptureState) throws {
        let id: UUID
        switch target { case .pipe(let value), .duct(let value): id = value }
        try edit(capture: capture) {
            guard $0.points(for: target).indices.contains(index) else { throw EditError.missingReference }
            $0.pointOverrides.removeAll { $0.objectID == id && $0.pointIndex == index }
            $0.pointOverrides.append(.init(objectID: id, pointIndex: index,
                position: .init(value: point, unit: "m", source: .entered, method: "manualControlPointAdjustment", accuracyMm: nil), observation: observation))
        }
    }
    mutating func undo() { guard let value = undoStack.popLast() else { return }; redoStack.append(document); document = value }
    mutating func redo() { guard let value = redoStack.popLast() else { return }; undoStack.append(document); document = value }

    static func validate(_ doc: TechnicalAnnotationDocument) throws {
        let room = doc.room
        let ids = [room.id] + room.pipeRuns.map(\.id) + room.equipment.map(\.id) + room.equipment.flatMap { $0.ports.map(\.id) } +
            room.fittings.map(\.id) + room.photos.map(\.id) + doc.ducts.map(\.id) + doc.measurements.map(\.id) + doc.connections.map(\.id)
        guard Set(ids).count == ids.count else { throw EditError.duplicateID }
        func positive(_ value: Double) -> Bool { value.isFinite && value > 0 && value < 100_000 }
        func normal(_ value: TechnicalPoint3) -> Bool { TechnicalPointEditing.valid(value) && value.distance(to: .init(x: 0, y: 0, z: 0)) > 1e-9 }
        for pipe in room.pipeRuns + doc.effectiveRoom.pipeRuns {
            guard positive(pipe.outerDiameterMm.value), (pipe.insulationThicknessMm?.value ?? 0).isFinite,
                  (pipe.insulationThicknessMm?.value ?? 0) >= 0, pipe.surfaceHits.count >= 2,
                  pipe.surfaceHits.allSatisfy({ TechnicalPointEditing.valid($0.position.value) && normal($0.normal.value) }),
                  positive(pipe.length.value) else { throw EditError.invalidPipe }
        }
        let ports = Set(room.equipment.flatMap { $0.ports.map(\.id) }), pipes = Set(room.pipeRuns.map(\.id)), photos = Set(room.photos.map(\.id))
        guard room.pipeRuns.allSatisfy({ Set($0.connectedPorts).isSubset(of: ports) }),
              room.fittings.allSatisfy({ pipes.contains($0.hostPipeRunId) && TechnicalPointEditing.valid($0.position.value) }),
              room.equipment.allSatisfy({ Set($0.photoRefs).isSubset(of: photos) }) else { throw EditError.missingReference }
        for item in room.equipment {
            guard TechnicalPointEditing.valid(item.center.value), [item.size.value.x, item.size.value.y, item.size.value.z].allSatisfy(positive),
                  item.rotation.value.isFinite, item.ports.allSatisfy({ TechnicalPointEditing.valid($0.position.value) && normal($0.direction.value) }) else { throw EditError.invalidGeometry }
        }
        for duct in doc.ducts {
            guard positive(duct.width.value), positive(duct.height.value), duct.points.count >= 2,
                  doc.points(for: .duct(duct.id)).allSatisfy(TechnicalPointEditing.valid) else { throw EditError.invalidGeometry }
        }
        guard doc.measurements.allSatisfy({ TechnicalPointEditing.valid($0.start.value) && TechnicalPointEditing.valid($0.end.value) && positive($0.length) }) else { throw EditError.invalidGeometry }
        if let value = doc.calibration {
            guard let measurement = doc.measurements.first(where: { $0.id == value.measurementID }),
                  abs(measurement.length - value.observedLength.value) < 1e-9, positive(value.referenceLength.value),
                  positive(value.observedLength.value), positive(value.factor) else { throw EditError.invalidGeometry }
        }
        var usedPorts: Set<UUID> = [], endpoints: Set<String> = []
        for connection in doc.connections {
            guard pipes.contains(connection.pipeID), ports.contains(connection.portID),
                  room.pipeRuns.first(where: { $0.id == connection.pipeID })?.connectedPorts.contains(connection.portID) == true else { throw EditError.missingReference }
            guard usedPorts.insert(connection.portID).inserted, endpoints.insert("\(connection.pipeID)/\(connection.endpoint.rawValue)").inserted else { throw EditError.duplicateID }
        }
        var editedPoints: Set<String> = []
        for edit in doc.pointOverrides {
            let count = room.pipeRuns.first { $0.id == edit.objectID }?.surfaceHits.count ?? doc.ducts.first { $0.id == edit.objectID }?.points.count ?? 0
            guard edit.pointIndex >= 0, edit.pointIndex < count, TechnicalPointEditing.valid(edit.position.value) else { throw EditError.invalidGeometry }
            guard editedPoints.insert("\(edit.objectID)/\(edit.pointIndex)").inserted else { throw EditError.duplicateID }
            if let observation = edit.observation {
                guard TechnicalPointEditing.valid(observation.position.value), normal(observation.normal.value) else { throw EditError.invalidGeometry }
            }
        }
        guard Set(doc.photoAssets.map(\.id)).count == doc.photoAssets.count,
              doc.photoAssets.count <= 200, doc.photoAssets.reduce(0, { $0 + $1.jpegData.count }) <= 64 * 1_048_576,
              doc.photoAssets.allSatisfy({ photos.contains($0.id) && !$0.jpegData.isEmpty && $0.jpegData.count <= 10 * 1_048_576 }) else { throw EditError.invalidGeometry }
    }
}
