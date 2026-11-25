import Foundation

/// Additive handoff only; never writes a native package or changes legacy JSON.
enum ResolvedGeometryExporter {
    static func data(for house: House,sourceID: UUID? = nil,storeyElevations: [Int:Double] = [:]) throws -> Data {
        let null = NSNull()
        guard Set(house.allRooms.map(\.id)).count == house.allRooms.count,
              Set(house.stories.map(\.index)).count == house.stories.count,
              storeyElevations.values.allSatisfy(\.isFinite) else { throw CocoaError(.fileReadCorruptFile) }
        func point(_ p: Point2D,y: Double = 0) -> [String:Double] { ["x":p.x,"y":y,"z":-p.y] }
        func number(_ value: Double) -> String { String(format:"%.9f",locale:Locale(identifier:"en_US_POSIX"),value == 0 ? 0 : value) }
        let stories: [[String:Any]] = try house.stories.sorted { $0.index < $1.index }.map { original in
            var story = original
            story.rooms.sort { $0.id.uuidString < $1.id.uuidString }
            for i in story.rooms.indices { story.rooms[i].walls.sort { $0.id.uuidString < $1.id.uuidString } }
            let local = House(id:house.id,name:house.name,stories:[story]),graph = HouseWallGraph(house:local)
            var ids: [Int:String] = [:]
            for wall in graph.walls {
                let segment = [wall.segment.start,wall.segment.end].map { number($0.x)+","+number($0.y) }.joined(separator:";")
                guard ids[wall.id] == nil else { throw CocoaError(.fileReadCorruptFile) }
                ids[wall.id] = "wall:\(story.index):"+wall.sourceWallIds.map(\.uuidString).sorted().joined(separator:",")+":"+segment
            }
            let walls: [[String:Any]] = graph.walls.map { wall in
                ["id":ids[wall.id] ?? "", "sourceWallIDs":wall.sourceWallIds.map(\.uuidString).sorted(),
                 "centreline":[point(wall.segment.start),point(wall.segment.end)],"footprints":wall.footprints.map { $0.map { point($0) } },
                 "thicknessM":wall.thickness,"wallType":wall.wallType == .interior ? "interior" : "exterior",
                 "thicknessSource":wall.thicknessSource == .measured ? "measuredScanGap" : wall.thicknessSource == .entered ? "storedOverrideUnverified" : "default",
                 "sideARoomIDs":wall.roomIdsOnSideA.map(\.uuidString).sorted(),"sideBRoomIDs":wall.roomIdsOnSideB.map(\.uuidString).sorted(),
                 "accuracyMm":null,"deviceValidationPending":true]
            }
            let rooms: [[String:Any]] = story.rooms.map { room in
                let m = RoomMeasurements(plan:room)
                return ["id":room.id.uuidString,"name":room.name,"netAreaM2":m.floorArea,"netPerimeterM":m.perimeter,
                        "ceilingMinM":m.ceilingHeight.lowerBound,"ceilingMaxM":m.ceilingHeight.upperBound,
                        "estimatedVolumeMinM3":m.floorArea*m.ceilingHeight.lowerBound,"estimatedVolumeMaxM3":m.floorArea*m.ceilingHeight.upperBound,
                        "netPolygon":room.floorPolygon.map { point(room.transform.apply($0)) },"accuracyMm":null,"deviceValidationPending":true]
            }
            let openings: [[String:Any]] = story.rooms.flatMap { room in
                room.openings.sorted { $0.id.uuidString < $1.id.uuidString }.map { opening in
                    let host = graph.openingHosts.first { $0.roomID == room.id && $0.openingID == opening.id }
                    return ["id":opening.id.uuidString,"roomID":room.id.uuidString,"type":opening.kind.rawValue,
                            "position":point(room.transform.apply(opening.center),y:opening.sillHeight),
                            "widthM":opening.width,"heightM":opening.height,"sillHeightM":opening.sillHeight,
                            "hostWallIDs":(host?.wallIDs ?? []).compactMap { ids[$0] },"accuracyMm":null,"deviceValidationPending":true] as [String:Any]
                }
            }
            let floors = HouseFloorGeometry.pieces(house:local).map { piece -> [String:Any] in
                ["roomID":piece.roomID.uuidString,"polygon":piece.polygon.map { point($0) }]
            }
            let solids = ResolvedWallGeometry.solids(house:local,graph:graph).map { solid -> [String:Any] in
                ["wallID":ids[solid.wallID] ?? "","footprint":solid.footprint.map { point($0) },"bottomM":solid.bottom,"topM":solid.top]
            }
            return ["index":story.index,"elevationM":storeyElevations[story.index].map { $0 as Any } ?? null,
                    "elevationSource":storeyElevations[story.index] == nil ? "unavailable" : "suppliedScanEvidence",
                    "coordinateFrame":"storey-local Y-up metres","netUnionAreaM2":HouseMeasurements(house:local).floorArea,
                    "rooms":rooms,"walls":walls,"wallSolids":solids,"openings":openings,"floorPieces":floors]
        }
        return try JSONSerialization.data(withJSONObject:["schemaVersion":1,"houseID":house.id.uuidString,"sourceID":(sourceID ?? house.id).uuidString,
            "units":"m","coordinateSystem":"right-handed Y-up; plan (x,y) maps to (x,0,-y)","storeys":stories,
            "accuracyMm":null,"deviceValidationPending":true,
            "limitations":["Derived geometry; not a certified survey.","Unknown storey elevation is null, not zero.","Default thickness is not measured.","Stored thickness overrides have no verified acquisition provenance in the legacy model.","Raw RoomPlan assets and legacy JSON are preserved separately."]],options:[.sortedKeys,.prettyPrinted])
    }
}
