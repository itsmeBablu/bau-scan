import Foundation

enum TechnicalRoomJSONExporter {
    enum ExportError: Error { case invalidGeometry, duplicateID, missingReference }

    /// Standalone engineering handoff. Package readers continue to use the original v1 document.
    static func handoff(for package: TechnicalRoomPackage) throws -> Data {
        let document = package.document
        var object = try JSONSerialization.jsonObject(with: data(for: document.effectiveRoom)) as? [String: Any] ?? [:]
        let encoder = JSONEncoder()
        func json<T: Encodable>(_ value: T) throws -> Any {
            try JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        let ducts = document.ducts.map { original in
            var duct = original
            for edit in document.pointOverrides where edit.objectID == duct.id && duct.points.indices.contains(edit.pointIndex) {
                duct.points[edit.pointIndex] = edit.position
            }
            return duct
        }
        object["format"] = "dWalkScan.technicalSurvey"
        object["handoffSchemaVersion"] = 1
        object["captureValidationStatus"] = "device validation pending"
        object["name"] = package.manifest.name
        object["ducts"] = try json(ducts)
        object["connections"] = try json(document.connections)
        object["measurements"] = try json(document.measurements)
        if let calibration = document.calibration { object["calibration"] = try json(calibration) }
        object["acceptedDetectionsInSessionCoordinates"] = try json(package.recognition.suggestions.filter { $0.status == .accepted })
        if let frame = package.alignment.referenceFrame { object["sessionToRoom"] = try json(frame) }
        object["originalPipeRuns"] = try json(document.room.pipeRuns)
        let output = try JSONSerialization.data(withJSONObject: object,options: [.sortedKeys,.prettyPrinted])
        try TechnicalJSONSchema.validateHandoff(output)
        return output
    }

    static func data(for room: TechnicalRoom) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try encoder.encode(room)
        let transform = room.shellToRoom.value
        let basis = [transform.xAxis, transform.yAxis, transform.zAxis]
        func dot(_ a: TechnicalPoint3, _ b: TechnicalPoint3) -> Double { a.x * b.x + a.y * b.y + a.z * b.z }
        guard basis.allSatisfy({ abs(dot($0, $0) - 1) < 1e-6 }),
              abs(dot(basis[0], basis[1])) < 1e-6,
              abs(dot(basis[0], basis[2])) < 1e-6,
              abs(dot(basis[1], basis[2])) < 1e-6 else { throw ExportError.invalidGeometry }
        let cross = TechnicalPoint3(x: basis[0].y * basis[1].z - basis[0].z * basis[1].y,
                                    y: basis[0].z * basis[1].x - basis[0].x * basis[1].z,
                                    z: basis[0].x * basis[1].y - basis[0].y * basis[1].x)
        guard dot(cross, basis[2]) > 0.999999 else { throw ExportError.invalidGeometry }
        guard var object = try JSONSerialization.jsonObject(with: encoded) as? [String: Any] else { throw ExportError.invalidGeometry }
        var ids: Set<UUID> = []
        let allIDs = [room.id] + room.pipeRuns.map(\.id) + room.equipment.map(\.id) +
            room.equipment.flatMap { $0.ports.map(\.id) } + room.fittings.map(\.id) + room.photos.map(\.id)
        for id in allIDs { guard ids.insert(id).inserted else { throw ExportError.duplicateID } }
        let ports = Set(room.equipment.flatMap { $0.ports.map(\.id) })
        let pipes = Set(room.pipeRuns.map(\.id))
        let photos = Set(room.photos.map(\.id))
        guard room.pipeRuns.allSatisfy({ Set($0.connectedPorts).isSubset(of: ports) }),
              room.fittings.allSatisfy({ pipes.contains($0.hostPipeRunId) }),
              room.equipment.allSatisfy({ Set($0.photoRefs).isSubset(of: photos) }) else { throw ExportError.missingReference }
        var runs = object["pipeRuns"] as? [[String: Any]] ?? []
        var mediumTotals: [String: Double] = [:]
        var dnTotals: [String: Double] = [:]
        func json<T: Codable & Equatable>(_ value: TechnicalValue<T>) throws -> Any {
            try JSONSerialization.jsonObject(with: encoder.encode(value))
        }
        for (index, run) in room.pipeRuns.enumerated() {
            guard run.surfaceHits.count >= 2, run.outerDiameterMm.value > 0,
                  (run.insulationThicknessMm?.value ?? 0) >= 0,
                  run.surfaceHits.allSatisfy({
                      let n = $0.normal.value
                      return n.x.isFinite && n.y.isFinite && n.z.isFinite &&
                          n.x * n.x + n.y * n.y + n.z * n.z > 1e-12
                  }) else { throw ExportError.invalidGeometry }
            runs[index]["centerline"] = try json(run.centerline)
            runs[index]["length"] = try json(run.length)
            runs[index]["elevationMin"] = try json(run.elevationMin)
            runs[index]["elevationMax"] = try json(run.elevationMax)
            mediumTotals[run.medium.value.rawValue, default: 0] += run.length.value
            dnTotals[run.nominalDN?.value ?? "unspecified", default: 0] += run.length.value
        }
        object["pipeRuns"] = runs
        object["schemaVersion"] = 1
        object["coordinateSystem"] = "rightHandedYUp"
        object["units"] = "m"
        object["totalsByMedium"] = try mediumTotals.mapValues {
            try json(TechnicalValue(value: $0, unit: "m", source: .estimated, method: "sumOfRunLengths", accuracyMm: nil))
        }
        object["totalsByDN"] = try dnTotals.mapValues {
            try json(TechnicalValue(value: $0, unit: "m", source: .estimated, method: "sumOfRunLengths", accuracyMm: nil))
        }
        let output = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        try TechnicalJSONSchema.validate(output)
        return output
    }
}
