import Foundation

/// IFC Z-up architecture from the same per-storey graph as the cleaned plan/mesh.
enum RevitResolvedHouseMapper {
    static func map(_ house: House,model: IFCModel,options: RevitExportOptions) throws {
        guard Set(house.stories.map(\.index)).count == house.stories.count else { throw RevitIFCExporter.Failure.invalid("Duplicate storey index") }
        var nextElevation = 0.0
        for original in house.stories.sorted(by:{ $0.index < $1.index }) {
            var story = original; story.rooms.sort { $0.id.uuidString < $1.id.uuidString }
            for i in story.rooms.indices { story.rooms[i].walls.sort { $0.id.uuidString < $1.id.uuidString } }
            let elevation = options.storeyElevations[story.index] ?? nextElevation
            let method = options.storeyElevations[story.index] == nil ? "Estimated cumulative scanned room height; structural separation unknown" : "Supplied scan floor elevation"
            let storey = model.storey(story.index,elevation:elevation,method:method)
            let height = story.rooms.map { $0.ceilingHeight.upperBound }.max() ?? 0
            guard height > 0 else { throw RevitIFCExporter.Failure.invalid("Storey has no usable height") }
            nextElevation = elevation+height
            if options.storeyElevations[story.index] == nil { model.warnings.append("Storey \(story.index) elevation is estimated; device validation pending.") }
            guard options.includeArchitecture else { continue }
            let local = House(id:house.id,name:house.name,stories:[story]),graph = HouseWallGraph(house:local)
            let floors = HouseFloorGeometry.pieces(house:local)
            var entities: [Int:Int] = [:]
            for wall in graph.walls where !wall.footprints.isEmpty {
                let roomIDs = wall.roomIdsOnSideA.union(wall.roomIdsOnSideB)
                let wallHeight = story.rooms.filter { roomIDs.contains($0.id) }.flatMap { $0.walls.filter { wall.sourceWallIds.contains($0.id) }.map(\.height) }.max() ?? 0
                guard wallHeight > 0,wall.thickness > 0 else { throw RevitIFCExporter.Failure.invalid("Invalid resolved wall") }
                let key = house.id.uuidString+"/story/\(story.index)/resolved-wall/\(wall.id)/"+wall.sourceWallIds.map(\.uuidString).sorted().joined(separator:",")
                let shape = model.extrusions(wall.footprints.map(model.polygon),length:wallHeight)
                let entity = model.product("IFCWALL",key:key,name:wall.wallType == .interior ? "Interior wall" : "Exterior wall",
                    placement:model.placement(.init(x:0,y:0,z:elevation)),shape:shape,suffix:options.schema == .ifc4 ? ",.NOTDEFINED." : "")
                entities[wall.id] = entity; model.elements[story.index,default:[]].append(entity)
                let source = wall.thicknessSource == .measured ? "measured scan gap" : wall.thicknessSource == .entered ? "stored override; acquisition unverified" : "default assumption"
                model.properties(entity,key:key,name:"Bau_Geometry",values:[("ThicknessM","IFCLENGTHMEASURE(\(IFCWriter.number(wall.thickness)))"),("ThicknessSource","IFCLABEL(\(IFCWriter.text(source)))"),("AccuracyMm","$"),("DeviceValidationPending","IFCBOOLEAN(.T.)")])
            }
            for room in story.rooms {
                let roomKey = house.id.uuidString+"/"+room.id.uuidString
                for opening in room.openings.sorted(by:{ $0.id.uuidString < $1.id.uuidString }) {
                    guard graph.panelOwner(roomID:room.id,opening:opening,house:local) else { continue }
                    guard opening.width > 0,opening.height > 0,opening.sillHeight >= 0 else { throw RevitIFCExporter.Failure.invalid("Invalid opening dimensions") }
                    let hostIDs = graph.openingHosts.first { $0.roomID == room.id && $0.openingID == opening.id }?.wallIDs ?? []
                    guard !hostIDs.isEmpty else { throw RevitIFCExporter.Failure.invalid("Opening has no resolved host") }
                    var firstVoid: Int?,fillFrame: (Point2D,Point2D)?
                    for host in graph.walls where hostIDs.contains(host.id) {
                        guard let wallEntity = entities[host.id] else { throw RevitIFCExporter.Failure.invalid("Opening host has no solid footprint") }
                        let a = room.transform.apply(opening.segment.start),b = room.transform.apply(opening.segment.end),d = host.segment.direction
                        func along(_ p: Point2D) -> Double { let v = p-host.segment.start; return v.x*d.x+v.y*d.y }
                        let low = max(0,min(along(a),along(b))),high = min(host.segment.length,max(along(a),along(b)))
                        guard high-low > 0.000001 else { continue }
                        let c = host.segment.start+d*((low+high)/2),key = roomKey+"/opening/"+opening.id.uuidString+"/host/\(host.id)"
                        let placement = model.placement(.init(x:c.x,y:c.y,z:elevation+opening.sillHeight),x:.init(x:d.x,y:d.y,z:0))
                        let shape = model.extrusion(model.rectangle(high-low,host.thickness*1.02),length:opening.height)
                        let void = model.product("IFCOPENINGELEMENT",key:key,name:"Opening",placement:placement,shape:shape,suffix:options.schema == .ifc4 ? ",.OPENING." : "")
                        model.writer.add("IFCRELVOIDSELEMENT","\(IFCWriter.guid(key+"/void")),#\(model.owner),$,$,#\(wallEntity),#\(void)")
                        if firstVoid == nil {
                            firstVoid = void
                            let observed = room.transform.apply(opening.center)
                            fillFrame = (host.segment.start+d*along(observed),d)
                        }
                    }
                    guard let void = firstVoid else { throw RevitIFCExporter.Failure.invalid("Opening has no positive host overlap") }
                    if opening.kind != .opening {
                        guard let (c,d) = fillFrame else { throw RevitIFCExporter.Failure.invalid("Opening fill has no resolved coordinate frame") }
                        let key = roomKey+"/opening/"+opening.id.uuidString
                        let placement = model.placement(.init(x:c.x,y:c.y,z:elevation+opening.sillHeight),x:.init(x:d.x,y:d.y,z:0))
                        let thickness = graph.hostThickness(roomID:room.id,openingID:opening.id)
                        let shape = model.extrusion(model.rectangle(opening.width,thickness),length:opening.height)
                        let extra = options.schema == .ifc4 ? ",.NOTDEFINED.,.NOTDEFINED.,$" : ""
                        let fill = model.product(opening.kind == .door ? "IFCDOOR" : "IFCWINDOW",key:key+"/fill",name:opening.kind.rawValue,placement:placement,shape:shape,
                            suffix:",\(IFCWriter.number(opening.height)),\(IFCWriter.number(opening.width))"+extra)
                        model.writer.add("IFCRELFILLSELEMENT","\(IFCWriter.guid(key+"/fills")),#\(model.owner),$,$,#\(void),#\(fill)")
                        model.elements[story.index,default:[]].append(fill)
                    }
                }
                guard room.floorPolygon.count >= 3,Polygon2D.triangulation(room.floorPolygon).complete else { throw RevitIFCExporter.Failure.invalid("Room has no valid net floor polygon") }
                let pieces = floors.filter { $0.roomID == room.id }
                if !pieces.isEmpty {
                    let shape = model.extrusions(pieces.map { model.polygon($0.polygon) },length:room.displayFloorSlabThickness)
                    let slab = model.product("IFCSLAB",key:roomKey+"/slab",name:room.name+" floor",placement:model.placement(.init(x:0,y:0,z:elevation-room.displayFloorSlabThickness)),shape:shape,suffix:",.FLOOR.")
                    model.elements[story.index,default:[]].append(slab)
                }
                let profile = model.polygon(room.floorPolygon.map(room.transform.apply))
                let space = model.product("IFCSPACE",key:roomKey+"/space",name:room.name,placement:model.placement(.init(x:0,y:0,z:elevation)),shape:model.extrusion(profile,length:room.ceilingHeight.upperBound),suffix:",.ELEMENT.,.INTERNAL.,$")
                model.aggregate(parent:storey,children:[space],key:roomKey+"/space")
                let quantity = model.writer.add("IFCQUANTITYAREA","'NetFloorArea',$,$,\(IFCWriter.number(RoomMeasurements(plan:room).floorArea))"+(options.schema == .ifc4 ? ",$" : ""))
                let set = model.writer.add("IFCELEMENTQUANTITY","\(IFCWriter.guid(roomKey+"/area")),#\(model.owner),'BaseQuantities',$,$,(#\(quantity))")
                model.writer.add("IFCRELDEFINESBYPROPERTIES","\(IFCWriter.guid(roomKey+"/areaRelation")),#\(model.owner),$,$,(#\(space)),#\(set)")
            }
        }
    }
}
