import Foundation

enum RevitIFCExporter {
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            switch self { case .invalid(let reason): return "IFC export: "+reason }
        }
    }
    static func export(house: House?, technicalRooms: [RevitTechnicalRoomInput] = [],
                       options: RevitExportOptions = .init()) throws -> Data {
        guard options.includeArchitecture || options.includeMEP else { throw Failure.invalid("Select architecture or MEP") }
        guard house != nil || (options.includeMEP && !technicalRooms.isEmpty) else { throw Failure.invalid("No survey selected") }
        // JSONEncoder rejects NaN and infinity before STEP number serialization.
        let encoder = JSONEncoder()
        if let house {
            _ = try encoder.encode(house)
            let ids = house.allRooms.map(\.id)
            guard Set(ids).count == ids.count else { throw Failure.invalid("Duplicate room identity") }
            for room in house.allRooms {
                let points = room.floorPolygon + room.walls.flatMap { [$0.start,$0.end] } + room.openings.map(\.center) + [room.transform.translation]
                guard points.allSatisfy({ abs($0.x) < 100_000 && abs($0.y) < 100_000 }),
                      room.walls.allSatisfy({ $0.height < 100_000 && $0.thickness < 100_000 }),
                      Set(room.walls.map(\.id)).count == room.walls.count,
                      Set(room.openings.map(\.id)).count == room.openings.count else {
                    throw Failure.invalid("Invalid or duplicate room geometry")
                }
            }
        }
        for input in technicalRooms {
            _ = try encoder.encode(input.document)
            try TechnicalAnnotationHistory.validate(input.document)
        }
        guard options.storeyElevations.values.allSatisfy(\.isFinite) else { throw Failure.invalid("Invalid storey elevation") }
        let keys = technicalRooms.map { $0.document.room.id.uuidString }.sorted()
        guard Set(keys).count == keys.count else { throw Failure.invalid("Duplicate technical room") }
        let model = IFCModel(options:options,key:house?.id.uuidString ?? keys.joined(separator:"/"),name:house?.name ?? "Technical room survey")
        if let house { try RevitHouseMapper.map(house,model:model,options:options) }
        if options.includeMEP {
            for input in technicalRooms.sorted(by: { $0.document.room.id.uuidString < $1.document.room.id.uuidString }) {
                try RevitTechnicalMapper.map(input,house:house,model:model,options:options)
            }
        }
        model.finish()
        return model.writer.data(timestamp:options.timestamp)
    }
}
