import Foundation

/// Shared geometry and relationships for the two independent mappers.
final class IFCModel {
    typealias P = TechnicalPoint3
    let writer: IFCWriter
    let owner: Int
    let context: Int
    let world: Int
    let building: Int
    let project: Int
    let projectKey: String
    var warnings: [String] = []
    var storeys: [Int: Int] = [:]
    var elevations: [Int: Double] = [:]
    var elements: [Int: [Int]] = [:]
    init(options: RevitExportOptions, key: String, name: String) {
        writer = IFCWriter(schema: options.schema)
        projectKey = key
        let w = writer
        let person = w.add("IFCPERSON", "$,$,'Survey',$,$,$,$,$")
        let org = w.add("IFCORGANIZATION", "$,'dWalkScan',$,$,$")
        let actor = w.add("IFCPERSONANDORGANIZATION", "#\(person),#\(org),$")
        let app = w.add("IFCAPPLICATION", "#\(org),'1','dWalkScan','dWalkScan'")
        owner = w.add("IFCOWNERHISTORY", "#\(actor),#\(app),$,.ADDED.,$,$,$,0")
        let origin = w.add("IFCCARTESIANPOINT", "(0.,0.,0.)")
        world = w.add("IFCAXIS2PLACEMENT3D", "#\(origin),$,$")
        context = w.add("IFCGEOMETRICREPRESENTATIONCONTEXT", "$,'Model',3,0.000001,#\(world),$")
        let units = w.add("IFCSIUNIT", "*,.LENGTHUNIT.,$,.METRE.")
        let area = w.add("IFCSIUNIT", "*,.AREAUNIT.,$,.SQUARE_METRE.")
        let volume = w.add("IFCSIUNIT", "*,.VOLUMEUNIT.,$,.CUBIC_METRE.")
        let radians = w.add("IFCSIUNIT", "*,.PLANEANGLEUNIT.,$,.RADIAN.")
        let assignment = w.add("IFCUNITASSIGNMENT", "(#\(units),#\(area),#\(volume),#\(radians))")
        project = w.add("IFCPROJECT", "\(IFCWriter.guid(key)),#\(owner),\(IFCWriter.text(name)),$,$,$,$,(#\(context)),#\(assignment)")
        let site = w.add("IFCSITE", "\(IFCWriter.guid(key+"/site")),#\(owner),'Site',$,$,$,$,$,.ELEMENT.,$,$,$,$,$")
        building = w.add("IFCBUILDING", "\(IFCWriter.guid(key+"/building")),#\(owner),'Building',$,$,$,$,$,.ELEMENT.,$,$,$")
        aggregate(parent: project, children: [site], key: "site")
        aggregate(parent: site, children: [building], key: "building")
    }
    func aggregate(parent: Int, children: [Int], key: String) {
        guard !children.isEmpty else { return }
        writer.add("IFCRELAGGREGATES", "\(IFCWriter.guid(projectKey+"/aggregate/"+key)),#\(owner),$,$,#\(parent),\(IFCWriter.refs(children))")
    }
    func storey(_ index: Int, elevation: Double, method: String) -> Int {
        if let existing = storeys[index] { return existing }
        let location = placement(P(x:0,y:0,z:elevation))
        let id = writer.add("IFCBUILDINGSTOREY", "\(IFCWriter.guid(projectKey+"/storey/\(index)")),#\(owner),\(IFCWriter.text("Storey \(index)")),\(IFCWriter.text(method)),$,#\(location),$,$,.ELEMENT.,\(IFCWriter.number(elevation))")
        storeys[index] = id
        elevations[index] = elevation
        return id
    }
    func finish() {
        aggregate(parent: building, children: storeys.keys.sorted().compactMap { storeys[$0] }, key: "storeys")
        for index in elements.keys.sorted() {
            guard let storey = storeys[index], let ids = elements[index], !ids.isEmpty else { continue }
            writer.add("IFCRELCONTAINEDINSPATIALSTRUCTURE", "\(IFCWriter.guid(projectKey+"/contain/\(index)")),#\(owner),$,$,\(IFCWriter.refs(ids)),#\(storey)")
        }
        if !warnings.isEmpty {
            properties(project, key: projectKey+"/warnings", name: "Bau_ExportWarnings",
                       values: [("Notes","IFCTEXT(\(IFCWriter.text(warnings.joined(separator: "\n"))))")])
        }
    }
    static func ifc(_ p: P) -> P { P(x: p.x,y: -p.z,z: p.y) }
    func point(_ p: P) -> Int {
        writer.add("IFCCARTESIANPOINT", "(\(IFCWriter.number(p.x)),\(IFCWriter.number(p.y)),\(IFCWriter.number(p.z)))")
    }
    func direction(_ p: P) -> Int {
        writer.add("IFCDIRECTION", "(\(IFCWriter.number(p.x)),\(IFCWriter.number(p.y)),\(IFCWriter.number(p.z)))")
    }
    func placement(_ origin: P, axis: P = P(x:0,y:0,z:1), x: P = P(x:1,y:0,z:0)) -> Int {
        let a = writer.add("IFCAXIS2PLACEMENT3D", "#\(point(origin)),#\(direction(axis)),#\(direction(x))")
        return writer.add("IFCLOCALPLACEMENT", "$,#\(a)")
    }
    func rectangle(_ width: Double, _ depth: Double) -> Int {
        writer.add("IFCRECTANGLEPROFILEDEF", ".AREA.,$,#\(profilePlacement()),\(IFCWriter.number(width)),\(IFCWriter.number(depth))")
    }
    func circle(_ diameter: Double) -> Int {
        writer.add("IFCCIRCLEPROFILEDEF", ".AREA.,$,#\(profilePlacement()),\(IFCWriter.number(diameter/2))")
    }
    private func profilePlacement() -> Int {
        let p = writer.add("IFCCARTESIANPOINT","(0.,0.)")
        return writer.add("IFCAXIS2PLACEMENT2D","#\(p),$")
    }
    func polygon(_ points: [Point2D]) -> Int {
        let ids = (points + [points[0]]).map { p in writer.add("IFCCARTESIANPOINT", "(\(IFCWriter.number(p.x)),\(IFCWriter.number(p.y)))") }
        let curve = writer.add("IFCPOLYLINE", IFCWriter.refs(ids))
        return writer.add("IFCARBITRARYCLOSEDPROFILEDEF", ".AREA.,$,#\(curve)")
    }
    func extrusion(_ profile: Int, length: Double) -> Int {
        let solid = writer.add("IFCEXTRUDEDAREASOLID", "#\(profile),#\(world),#\(direction(P(x:0,y:0,z:1))),\(IFCWriter.number(length))")
        let shape = writer.add("IFCSHAPEREPRESENTATION", "#\(context),'Body','SweptSolid',(#\(solid))")
        return writer.add("IFCPRODUCTDEFINITIONSHAPE", "$,$,(#\(shape))")
    }
    func extrusions(_ profiles: [Int],length: Double) -> Int {
        let solids = profiles.map { profile in
            writer.add("IFCEXTRUDEDAREASOLID","#\(profile),#\(world),#\(direction(P(x:0,y:0,z:1))),\(IFCWriter.number(length))")
        }
        let shape = writer.add("IFCSHAPEREPRESENTATION","#\(context),'Body','SweptSolid',\(IFCWriter.refs(solids))")
        return writer.add("IFCPRODUCTDEFINITIONSHAPE","$,$,(#\(shape))")
    }
    func product(_ type: String, key: String, name: String, placement: Int, shape: Int?, suffix: String = "") -> Int {
        writer.add(type, "\(IFCWriter.guid(key)),#\(owner),\(IFCWriter.text(name)),'device validation pending',$,#\(placement),\(shape.map { "#\($0)" } ?? "$"),$" + suffix)
    }
    func properties(_ element: Int, key: String, name: String, values: [(String,String)]) {
        let ids = values.map { writer.add("IFCPROPERTYSINGLEVALUE", "\(IFCWriter.text($0.0)),$,\($0.1),$") }
        let set = writer.add("IFCPROPERTYSET", "\(IFCWriter.guid(key+"/pset/"+name)),#\(owner),\(IFCWriter.text(name)),$,\(IFCWriter.refs(ids))")
        writer.add("IFCRELDEFINESBYPROPERTIES", "\(IFCWriter.guid(key+"/defines/"+name)),#\(owner),$,$,(#\(element)),#\(set)")
    }
    func fieldProvenance<T: Encodable>(_ element: Int,key: String,value: T) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = String(decoding:try encoder.encode(value),as:UTF8.self)
        properties(element,key:key,name:"Bau_FieldProvenance",values:[("OriginalFieldValues","IFCTEXT(\(IFCWriter.text(json)))")])
    }
    func provenance<T>(_ element: Int, key: String, value: TechnicalValue<T>,
                        dn: String? = nil, insulation: Double? = nil, notes: String = "") where T: Codable & Equatable {
        properties(element, key:key, name:"Bau_Provenance", values:[
            ("source","IFCLABEL(\(IFCWriter.text(value.source.rawValue)))"),
            ("method","IFCTEXT(\(IFCWriter.text(value.method)))"),
            ("accuracyMm",value.accuracyMm.map { "IFCREAL(\(IFCWriter.number($0)))" } ?? "$"),
            ("deviceValidationPending","IFCBOOLEAN(.T.)"),
            ("validationStatus","IFCLABEL('device validation pending')"),
            ("DN",dn.map { "IFCLABEL(\(IFCWriter.text($0)))" } ?? "$"),
            ("insulationThicknessMm",insulation.map { "IFCREAL(\(IFCWriter.number($0)))" } ?? "$"),
            ("notes","IFCTEXT(\(IFCWriter.text(notes)))")
        ])
    }
}
