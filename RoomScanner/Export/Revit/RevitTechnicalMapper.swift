import Foundation

enum RevitTechnicalMapper {
    typealias P = TechnicalPoint3
    static func validate(_ t: TechnicalTransform) throws {
        let axes = [t.xAxis,t.yAxis,t.zAxis]
        guard TechnicalPointEditing.valid(t.translation),
              axes.allSatisfy({ TechnicalPointEditing.valid($0) && abs(MEPVector.dot($0,$0)-1) < 1e-6 }),
              abs(MEPVector.dot(axes[0],axes[1])) < 1e-6,
              abs(MEPVector.dot(axes[1],axes[2])) < 1e-6,
              MEPVector.dot(MEPVector.cross(axes[0],axes[1]),axes[2]) > 0.999999 else {
            throw RevitIFCExporter.Failure.invalid("Invalid right-handed rigid shell transform")
        }
    }
    static func map(_ input: RevitTechnicalRoomInput, house: House?, model: IFCModel,
                    options: RevitExportOptions) throws {
        let doc = input.document, room = doc.effectiveRoom, key = room.id.uuidString
        try validate(room.shellToRoom.value)
        let matched = house?.allRooms.first { $0.id == room.shellID }
        var shellPlacement: TechnicalTransform?
        let story: Int
        if house != nil {
            guard let matched, let placement = options.shellPlacements[room.shellID] else {
                throw RevitIFCExporter.Failure.invalid("Technical room \(input.name) requires a matching shellID and explicit shell-to-house placement. Export it alone if registration is unavailable.")
            }
            try validate(placement)
            shellPlacement = placement
            story = matched.story
        } else {
            story = 0
            model.warnings.append("Technical room \(input.name) exported alone in its room coordinate frame. House registration is unavailable.")
            _ = model.storey(0,elevation:0,method:"Standalone technical room origin")
        }
        func point(_ p: P) -> P {
            let world: P
            if let shellPlacement {
                world = TechnicalReferenceFrame.apply(shellPlacement,to:TechnicalReferenceFrame.inverseApply(room.shellToRoom.value,to:p))
            } else { world = p }
            return IFCModel.ifc(world)
        }
        func vector(_ v: P) -> P { MEPVector.sub(point(v),point(.init(x:0,y:0,z:0))) }
        var equipmentPorts: [UUID:Int] = [:]
        let note = room.notes.map { $0.value }.joined(separator:"\n")
        func addPort(_ position: P, direction: P, host: Int, portKey: String, evidence: TechnicalValue<P>? = nil) -> Int {
            let axis = MEPVector.unit(direction)
            let x = perpendicular(axis)
            let placement = model.placement(position,axis:axis,x:x)
            let extra = options.schema == .ifc4 ? ",.NOTDEFINED.,.NOTDEFINED." : ""
            let port = model.writer.add("IFCDISTRIBUTIONPORT","\(IFCWriter.guid(portKey)),#\(model.owner),'Port','device validation pending',$,#\(placement),$,.NOTDEFINED."+extra)
            model.writer.add("IFCRELCONNECTSPORTTOELEMENT","\(IFCWriter.guid(portKey+"/host")),#\(model.owner),$,$,#\(port),#\(host)")
            let value = evidence ?? TechnicalValue(value:position,unit:"m",source:.estimated,method:"derivedHostEndpointInIFCCoordinates",accuracyMm:nil)
            model.provenance(port,key:portKey,value:value,notes:note)
            return port
        }
        func connect(_ a: Int,_ b: Int,_ connectionKey: String) {
            model.writer.add("IFCRELCONNECTSPORTS","\(IFCWriter.guid(connectionKey)),#\(model.owner),$,$,#\(a),#\(b),$")
        }
        for equipment in room.equipment.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let itemKey = key+"/equipment/"+equipment.id.uuidString
            let center = equipment.center.value, size = equipment.size.value, yaw = equipment.rotation.value
            let bottom = P(x:center.x,y:center.y-size.y/2,z:center.z)
            let axis = vector(.init(x:0,y:1,z:0)), x = vector(.init(x:cos(yaw),y:0,z:-sin(yaw)))
            let placement = model.placement(point(bottom),axis:axis,x:x)
            let shape = model.extrusion(model.rectangle(size.x,size.z),length:size.y)
            let type = equipmentClass(equipment.type.value,schema:options.schema)
            let suffix = options.schema == .ifc4 ? ",.NOTDEFINED." : type == "IFCBUILDINGELEMENTPROXY" ? ",.ELEMENT." : ""
            let entity = model.product(type,key:itemKey,name:equipment.name.value,placement:placement,shape:shape,suffix:suffix)
            model.elements[story,default:[]].append(entity)
            model.provenance(entity,key:itemKey,value:equipment.center,notes:note)
            try model.fieldProvenance(entity,key:itemKey,value:equipment)
            let common: String
            switch equipment.type.value {
            case .boiler: common = "Pset_BoilerTypeCommon"
            case .pump: common = "Pset_PumpTypeCommon"
            case .bufferTank,.dhwTank,.expansionVessel: common = "Pset_TankTypeCommon"
            default: common = "Bau_EquipmentReference"
            }
            model.properties(entity,key:itemKey,name:common,values:[("Reference","IFCIDENTIFIER(\(IFCWriter.text(equipment.name.value)))")])
            var fields: [(String,String)] = []
            for (name,value) in [("Type",equipment.type.value.rawValue),("Manufacturer",equipment.manufacturer?.value ?? ""),("Model",equipment.model?.value ?? "")] {
                fields.append((name,"IFCLABEL(\(IFCWriter.text(value)))"))
            }
            model.properties(entity,key:itemKey,name:"Bau_Equipment",values:fields)
            for port in equipment.ports.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
                let portKey = itemKey+"/port/"+port.id.uuidString
                let id = addPort(point(port.position.value),direction:vector(port.direction.value),host:entity,portKey:portKey,evidence:port.position)
                equipmentPorts[port.id] = id
                try model.fieldProvenance(id,key:portKey,value:port)
            }
        }
        var endpoints: [UUID:(Int,Int)] = [:]
        for pipe in room.pipeRuns.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let points = pipe.centerline.value
            var first: Int?, last: Int?
            for index in 1..<points.count {
                let itemKey = key+"/pipe/"+pipe.id.uuidString+"/\(index)"
                let a = point(points[index-1]),b = point(points[index])
                let delta = MEPVector.sub(b,a), length = sqrt(MEPVector.dot(delta,delta))
                guard length > 1e-6 else { throw RevitIFCExporter.Failure.invalid("Zero-length pipe segment") }
                let axis = MEPVector.unit(delta)
                let placement = model.placement(a,axis:axis,x:perpendicular(axis))
                let shape = model.extrusion(model.circle(pipe.outerDiameterMm.value/1000),length:length)
                let entity = model.product(options.schema == .ifc4 ? "IFCPIPESEGMENT" : "IFCFLOWSEGMENT",
                    key:itemKey,name:pipe.systemLabel.value,placement:placement,shape:shape,suffix:options.schema == .ifc4 ? ",.RIGIDSEGMENT." : "")
                model.elements[story,default:[]].append(entity)
                model.provenance(entity,key:itemKey,value:pipe.centerline,dn:pipe.nominalDN?.value,insulation:pipe.insulationThicknessMm?.value,notes:note)
                try model.fieldProvenance(entity,key:itemKey,value:pipe)
                model.properties(entity,key:itemKey,name:"Pset_PipeSegmentTypeCommon",values:[
                    ("Reference","IFCIDENTIFIER(\(IFCWriter.text(pipe.nominalDN?.value ?? "")))")])
                model.properties(entity,key:itemKey,name:"Bau_Measurements",values:[
                    ("GeometricLength","IFCLENGTHMEASURE(\(IFCWriter.number(length)))"),
                    ("LengthCorrectionFactor","IFCREAL(\(IFCWriter.number(doc.calibration?.factor ?? 1)))"),
                    ("OutsideDiameterMm","IFCREAL(\(IFCWriter.number(pipe.outerDiameterMm.value)))"),
                    ("Material","IFCLABEL(\(IFCWriter.text(pipe.material.value)))"),
                    ("Medium","IFCLABEL(\(IFCWriter.text(pipe.medium.value.rawValue)))")])
                let start = addPort(a,direction:MEPVector.mul(axis,-1),host:entity,portKey:itemKey+"/start")
                let end = addPort(b,direction:axis,host:entity,portKey:itemKey+"/end")
                if let last { connect(last,start,itemKey+"/previous") }
                if first == nil { first = start }
                last = end
            }
            if let first,let last { endpoints[pipe.id] = (first,last) }
        }
        for duct in doc.ducts.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let points = doc.points(for:.duct(duct.id))
            var previous: Int?
            for index in 1..<points.count {
                let itemKey = key+"/duct/"+duct.id.uuidString+"/\(index)"
                let a = point(points[index-1]),b = point(points[index])
                let delta = MEPVector.sub(b,a),length = sqrt(MEPVector.dot(delta,delta))
                guard length > 1e-6 else { throw RevitIFCExporter.Failure.invalid("Zero-length duct segment") }
                let axis = MEPVector.unit(delta)
                let placement = model.placement(a,axis:axis,x:perpendicular(axis))
                let shape = model.extrusion(model.rectangle(duct.width.value,duct.height.value),length:length)
                let entity = model.product(options.schema == .ifc4 ? "IFCDUCTSEGMENT" : "IFCFLOWSEGMENT",
                    key:itemKey,name:"Duct",placement:placement,shape:shape,suffix:options.schema == .ifc4 ? ",.RIGIDSEGMENT." : "")
                model.elements[story,default:[]].append(entity)
                model.provenance(entity,key:itemKey,value:duct.points[index],notes:note)
                try model.fieldProvenance(entity,key:itemKey,value:duct)
                model.properties(entity,key:itemKey,name:"Pset_DuctSegmentTypeCommon",values:[
                    ("Reference","IFCIDENTIFIER(\(IFCWriter.text(duct.id.uuidString)))")])
                let start = addPort(a,direction:MEPVector.mul(axis,-1),host:entity,portKey:itemKey+"/start")
                let end = addPort(b,direction:axis,host:entity,portKey:itemKey+"/end")
                if let previous { connect(previous,start,itemKey+"/previous") }
                previous = end
            }
        }
        for fitting in room.fittings.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let itemKey = key+"/fitting/"+fitting.id.uuidString
            let type = options.schema == .ifc4 ? (fitting.type.value == .valve ? "IFCVALVE" : "IFCPIPEFITTING") : "IFCFLOWFITTING"
            let entity = model.product(type,key:itemKey,name:fitting.type.value.rawValue,
                placement:model.placement(point(fitting.position.value)),shape:nil,
                suffix:options.schema == .ifc4 ? ",.NOTDEFINED." : "")
            model.elements[story,default:[]].append(entity)
            model.provenance(entity,key:itemKey,value:fitting.position,dn:fitting.nominalDN?.value,
                notes:note+"\nHost pipe "+fitting.hostPipeRunId.uuidString+"; dimensions unavailable; position-only fitting.")
            try model.fieldProvenance(entity,key:itemKey,value:fitting)
        }
        for connection in doc.connections.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            guard let pipe = endpoints[connection.pipeID],let equipmentPort = equipmentPorts[connection.portID] else {
                throw RevitIFCExporter.Failure.invalid("Unresolved equipment port connection")
            }
            connect(connection.endpoint == .start ? pipe.0 : pipe.1,equipmentPort,key+"/connection/"+connection.id.uuidString)
        }
        if !doc.connections.isEmpty {
            model.warnings.append(contentsOf:doc.connectionWarnings)
        }
    }
    static func perpendicular(_ axis: P) -> P {
        let reference = abs(axis.z) < 0.9 ? P(x:0,y:0,z:1) : P(x:0,y:1,z:0)
        return MEPVector.unit(MEPVector.cross(reference,axis))
    }
    static func equipmentClass(_ type: TechnicalEquipmentType, schema: RevitExportOptions.Schema) -> String {
        if schema == .ifc2x3 {
            switch type {
            case .boiler,.heatPump: return "IFCENERGYCONVERSIONDEVICE"
            case .pump: return "IFCFLOWMOVINGDEVICE"
            case .bufferTank,.dhwTank,.expansionVessel: return "IFCFLOWSTORAGEDEVICE"
            default: return "IFCBUILDINGELEMENTPROXY"
            }
        }
        switch type {
        case .boiler: return "IFCBOILER"
        case .pump: return "IFCPUMP"
        case .bufferTank,.dhwTank,.expansionVessel: return "IFCTANK"
        case .electricalPanel: return "IFCELECTRICDISTRIBUTIONBOARD"
        case .meter: return "IFCFLOWMETER"
        default: return "IFCBUILDINGELEMENTPROXY"
        }
    }
}
