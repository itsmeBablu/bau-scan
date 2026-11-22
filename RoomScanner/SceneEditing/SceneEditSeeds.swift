import Foundation

extension SceneEditDocument {
    static func technical(_ package: TechnicalRoomPackage) throws -> Self {
        let reference = package.alignment.referenceFrame
        let geometry = try TechnicalSavedMeshGeometry.latest(in: package.journal.meshes).map { try TechnicalSavedMeshGeometry(snapshot: $0,reference: reference) }
        let center = geometry?.center ?? .init(x: 0,y: 0,z: 0)
        let extent = geometry?.extent ?? .init(x: 4,y: 3,z: 4)
        let floor = center.y-extent.y/2
        let halfX = max(1,extent.x/2),halfZ = max(1,extent.z/2)
        let polygon = [Point2D(x: center.x-halfX,y: -center.z-halfZ),.init(x: center.x+halfX,y: -center.z-halfZ),.init(x: center.x+halfX,y: -center.z+halfZ),.init(x: center.x-halfX,y: -center.z+halfZ)]
        let room = FloorPlan(id: package.manifest.id,name: "Technik Room",label: .unidentified,story: 0,transform: .identity,walls: [],openings: [],objects: [],floorPolygon: polygon,ceilingHeight: 0...0)
        var result = Self(source: .technical,sourceID: package.manifest.id,title: package.manifest.name+" · Edited",shell: House(room: room),objects: [])
        result.floorColor = .init(x: 0.61,y: 0.63,z: 0.64)
        func point(_ p: TechnicalPoint3) -> TechnicalPoint3 {
            var value = reference.map { TechnicalReferenceFrame.apply($0,to: p) } ?? p
            value.y -= floor; return value
        }
        func segment(id: UUID,start: TechnicalPoint3,end: TechnicalPoint3,width: Double,depth: Double,family: SceneFurniture,origin: String,color: TechnicalPoint3? = nil,crossAxis: TechnicalPoint3? = nil) {
            let a = point(start),b = point(end),direction = MEPVector.sub(b,a),length = sqrt(MEPVector.dot(direction,direction))
            guard length >= 0.005,width >= 0.005,depth >= 0.005 else { return }
            let cross: TechnicalPoint3? = crossAxis.map { value in
                let origin = TechnicalPoint3(x: 0,y: 0,z: 0)
                let transformed = reference.map { MEPVector.sub(TechnicalReferenceFrame.apply($0,to: value),TechnicalReferenceFrame.apply($0,to: origin)) } ?? value
                return MEPVector.unit(transformed)
            }
            result.objects.append(.init(sourceID: id,origin: origin,name: family.title,family: family,position: MEPVector.mul(MEPVector.add(a,b),0.5),size: .init(x: width,y: length,z: depth),axis: MEPVector.unit(direction),crossAxis: cross,color: color ?? .init(x: 0.68,y: 0.70,z: 0.72),capturedColor: color,colorSource: color == nil ? .preset : .cameraSample,finish: .matte))
        }
        for suggestion in package.recognition.suggestions where suggestion.status == .accepted {
            segment(id: suggestion.id,start: suggestion.start,end: suggestion.end,width: suggestion.width,depth: suggestion.height,family: suggestion.kind == .rectangularDuct ? .rectangularDuct : suggestion.kind == .roundDuct ? .roundDuct : .pipe,origin: "Accepted MEP suggestion; editable reconstruction",color: suggestion.color,crossAxis: suggestion.crossAxis)
        }
        for pipe in package.document.effectiveRoom.pipeRuns {
            let points = pipe.centerline.value
            for pair in zip(points,points.dropFirst()) {
                segment(id: pipe.id,start: pair.0,end: pair.1,width: pipe.outerDiameterMm.value/1000,depth: pipe.outerDiameterMm.value/1000,family: .pipe,origin: "Survey pipe centreline; editable reconstruction")
            }
        }
        for duct in package.document.ducts {
            let points = package.document.points(for: .duct(duct.id))
            for pair in zip(points,points.dropFirst()) { segment(id: duct.id,start: pair.0,end: pair.1,width: duct.width.value,depth: duct.height.value,family: .rectangularDuct,origin: "Survey duct; editable reconstruction") }
        }
        for equipment in package.document.effectiveRoom.equipment {
            let family: SceneFurniture = switch equipment.type.value {
            case .boiler: .boiler; case .bufferTank,.dhwTank,.expansionVessel: .tank
            case .pump,.heatPump: .pump; case .manifold: .manifold; case .electricalPanel: .electricalPanel
            default: .box
            }
            result.objects.append(.init(sourceID: equipment.id,origin: "Survey equipment; generic model",name: equipment.name.value,family: family,position: point(equipment.center.value),size: equipment.size.value,yaw: equipment.rotation.value))
        }
        for i in result.objects.indices { result.objects[i].scanReference = .init(position: result.objects[i].position,size: result.objects[i].size,yaw: result.objects[i].yaw,axis: result.objects[i].axis,crossAxis: result.objects[i].crossAxis,family: result.objects[i].family) }
        try result.validate(); return result
    }

    mutating func includeRadiators(_ radiators: [HouseRadiator]) {
        for radiator in radiators where radiator.capturedInHouseCoordinates == true {
            guard let frame = try? RadiatorScanGeometry(frontCorners: radiator.frontCorners,wall: radiator.wallSample),let floor = radiator.houseFloorElevation else { continue }
            let depth = radiator.depth?.metres ?? 0.02
            let center = frame.origin+frame.right*(radiator.width.metres/2)+frame.up*(radiator.height.metres/2)-frame.frontNormal*(depth/2)
            objects.append(.init(sourceID: radiator.id,origin: radiator.depth == nil ? "Radiator scan; 0.02 m display thickness assumed" : "Radiator scan; editable model",name: radiator.name,family: .radiator,position: .init(x: center.x,y: center.y-floor,z: center.z),size: .init(x: radiator.width.metres,y: radiator.height.metres,z: depth),yaw: atan2(-frame.right.z,frame.right.x),story: shell.allRooms.first { $0.id == radiator.roomID }?.story ?? 0))
            let i = objects.count-1
            objects[i].scanReference = .init(position: objects[i].position,size: objects[i].size,yaw: objects[i].yaw,axis: nil,family: objects[i].family)
        }
    }
}
