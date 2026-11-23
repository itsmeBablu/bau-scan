import Foundation

enum RevitHouseMapper {
    static func map(_ house: House, model: IFCModel, options: RevitExportOptions) throws {
        let stories = house.stories.sorted { $0.index < $1.index }
        guard Set(stories.map(\.index)).count == stories.count else { throw RevitIFCExporter.Failure.invalid("Duplicate storey index") }
        var derivedElevation = 0.0
        for story in stories {
            let measured = options.storeyElevations[story.index]
            let elevation = measured ?? derivedElevation
            let method = measured == nil ? "Estimated cumulative scanned room height; missing structural floor separation" : "Supplied scan floor elevation"
            let storey = model.storey(story.index,elevation:elevation,method:method)
            if measured == nil { model.warnings.append("Storey \(story.index) elevation \(elevation) m is estimated from scanned room heights.") }
            let height = story.rooms.map { $0.ceilingHeight.upperBound }.max() ?? 0
            guard height > 0 else { throw RevitIFCExporter.Failure.invalid("Storey has no usable scanned height") }
            derivedElevation = elevation + height
            if !options.includeArchitecture { continue }
            for room in story.rooms.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                guard room.ceilingHeight.upperBound > 0 else { throw RevitIFCExporter.Failure.invalid("Room has no usable height") }
                let roomKey = house.id.uuidString+"/"+room.id.uuidString
                func point(_ p: Point2D, _ z: Double = 0) -> TechnicalPoint3 {
                    let q = room.transform.apply(p)
                    return .init(x:q.x,y:q.y,z:elevation+z)
                }
                var wallIDs: [UUID:Int] = [:]
                for wall in room.walls.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    guard wall.length > 1e-6, wall.height > 0,wall.thickness > 0 else { throw RevitIFCExporter.Failure.invalid("Invalid wall dimensions") }
                    let a = point(wall.start),b = point(wall.end)
                    let direction = MEPVector.unit(MEPVector.sub(b,a))
                    let mid = MEPVector.mul(MEPVector.add(a,b),0.5)
                    let placement = model.placement(mid,x:direction)
                    let shape = model.extrusion(model.rectangle(wall.length,wall.thickness),length:wall.height)
                    let key = roomKey+"/wall/"+wall.id.uuidString
                    let wallID = model.product("IFCWALL",key:key,name:room.name+" wall",placement:placement,shape:shape,suffix: options.schema == .ifc4 ? ",.NOTDEFINED." : "")
                    wallIDs[wall.id] = wallID
                    model.elements[story.index,default:[]].append(wallID)
                }
                for opening in room.openings.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                    guard let host = room.wall(withID:opening.wallID),let hostID = wallIDs[host.id] else {
                        throw RevitIFCExporter.Failure.invalid("Opening \(opening.id) has no valid host wall")
                    }
                    guard opening.width > 0,opening.height > 0,opening.sillHeight >= 0 else { throw RevitIFCExporter.Failure.invalid("Invalid opening dimensions") }
                    let key = roomKey+"/opening/"+opening.id.uuidString
                    let center = point(opening.center,opening.sillHeight)
                    let angle = opening.angle + room.transform.rotation
                    let placement = model.placement(center,x:.init(x:cos(angle),y:sin(angle),z:0))
                    let voidShape = model.extrusion(model.rectangle(opening.width,host.thickness*1.02),length:opening.height)
                    let void = model.product("IFCOPENINGELEMENT",key:key,name:"Opening",placement:placement,shape:voidShape,suffix:options.schema == .ifc4 ? ",.OPENING." : "")
                    model.writer.add("IFCRELVOIDSELEMENT","\(IFCWriter.guid(key+"/void")),#\(model.owner),$,$,#\(hostID),#\(void)")
                    if opening.kind != .opening {
                        let type = opening.kind == .door ? "IFCDOOR" : "IFCWINDOW"
                        let dims = ",\(IFCWriter.number(opening.height)),\(IFCWriter.number(opening.width))"
                        let shape = model.extrusion(model.rectangle(opening.width,host.thickness),length:opening.height)
                        let extra = options.schema == .ifc4 ? ",.NOTDEFINED.,.NOTDEFINED.,$" : ""
                        let fill = model.product(type,key:key+"/fill",name:opening.kind.rawValue,placement:placement,shape:shape,suffix:dims+extra)
                        model.writer.add("IFCRELFILLSELEMENT","\(IFCWriter.guid(key+"/fills")),#\(model.owner),$,$,#\(void),#\(fill)")
                        model.elements[story.index,default:[]].append(fill)
                    }
                }
                if room.floorPolygon.count >= 3 {
                    guard Polygon2D.triangulation(room.floorPolygon).1 else { throw RevitIFCExporter.Failure.invalid("Invalid floor polygon") }
                    let polygon = room.floorPolygon.map(room.transform.apply)
                    let profile = model.polygon(polygon)
                    let floorShape = model.extrusion(profile,length:room.displayFloorSlabThickness)
                    let slab = model.product("IFCSLAB",key:roomKey+"/slab",name:room.name+" floor",
                        placement:model.placement(.init(x:0,y:0,z:elevation-room.displayFloorSlabThickness)),shape:floorShape,suffix:",.FLOOR.")
                    model.elements[story.index,default:[]].append(slab)
                    model.properties(slab,key:roomKey+"/slab",name:"Bau_Geometry",values:[
                        ("ThicknessMethod","IFCLABEL('Presentation thickness; not a measured structural assembly')")])
                    let space = model.product("IFCSPACE",key:roomKey+"/space",name:room.name,
                        placement:model.placement(.init(x:0,y:0,z:elevation)),
                        shape:model.extrusion(profile,length:room.ceilingHeight.upperBound),suffix:",.ELEMENT.,.INTERNAL.,$")
                    model.aggregate(parent:storey,children:[space],key:roomKey+"/space")
                    let quantity = model.writer.add("IFCQUANTITYAREA","'NetFloorArea',$,$,\(IFCWriter.number(Polygon2D.area(room.floorPolygon)))" + (options.schema == .ifc4 ? ",$" : ""))
                    let quantities = model.writer.add("IFCELEMENTQUANTITY","\(IFCWriter.guid(roomKey+"/area")),#\(model.owner),'BaseQuantities',$,$,(#\(quantity))")
                    model.writer.add("IFCRELDEFINESBYPROPERTIES","\(IFCWriter.guid(roomKey+"/areaRelation")),#\(model.owner),$,$,(#\(space)),#\(quantities)")
                } else { model.warnings.append("Room \(room.name) has no usable floor polygon. Slab and space geometry omitted.") }
            }
        }
    }
}
