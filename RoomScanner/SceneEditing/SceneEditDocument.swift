import Foundation
import Observation
import simd

enum SceneFurniture: String,Codable,CaseIterable,Identifiable {
    case sofa, bed, chair, table, television, cabinet, refrigerator, stove, sink, toilet, bathtub, shower, washer
    case radiator, boiler, tank, pump, manifold, electricalPanel, pipe, roundDuct, rectangularDuct, box, cylinder
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sofa: "sofa.fill"; case .bed: "bed.double.fill"; case .chair: "chair.fill"; case .table: "table.furniture.fill"
        case .television: "tv"; case .cabinet: "cabinet.fill"; case .refrigerator: "refrigerator.fill"
        case .stove: "stove.fill"; case .sink: "sink.fill"; case .toilet: "toilet.fill"; case .bathtub: "bathtub.fill"
        case .shower: "shower.fill"; case .washer: "washer.fill"; case .radiator: "heater.vertical.fill"
        case .boiler,.tank: "waterbottle.fill"; case .pump,.manifold,.pipe: "pipe.and.drop"
        case .roundDuct,.rectangularDuct: "wind"; case .electricalPanel: "bolt.fill"
        case .box: "cube.fill"; case .cylinder: "cylinder.fill"
        }
    }
    var title: String {
        switch self {
        case .television: "TV"; case .electricalPanel: "Electrical panel"
        case .roundDuct: "Round duct"; case .rectangularDuct: "Rectangular duct"
        default: rawValue.prefix(1).uppercased()+rawValue.dropFirst()
        }
    }
    static func detected(_ category: String) -> Self {
        let c = category.lowercased()
        if c.contains("sofa") { return .sofa }; if c.contains("bed") { return .bed }
        if c.contains("chair") { return .chair }; if c.contains("table") || c.contains("desk") { return .table }
        if c.contains("television") || c == "tv" { return .television }
        if c.contains("refrigerator") { return .refrigerator }; if c.contains("stove") || c.contains("oven") { return .stove }
        if c.contains("sink") { return .sink }; if c.contains("toilet") { return .toilet }
        if c.contains("bathtub") { return .bathtub }; if c.contains("shower") { return .shower }
        if c.contains("washer") || c.contains("dryer") { return .washer }
        if c.contains("storage") || c.contains("cabinet") { return .cabinet }
        return .box
    }
    var defaultSize: TechnicalPoint3 {
        switch self {
        case .sofa: .init(x: 2,y: 0.85,z: 0.9); case .bed: .init(x: 1.6,y: 0.9,z: 2)
        case .chair: .init(x: 0.5,y: 0.85,z: 0.55); case .table: .init(x: 1.4,y: 0.75,z: 0.85)
        case .television: .init(x: 1.2,y: 0.7,z: 0.12); case .radiator: .init(x: 1,y: 0.6,z: 0.12)
        case .pipe,.roundDuct: .init(x: 0.1,y: 1,z: 0.1)
        case .rectangularDuct: .init(x: 0.4,y: 1,z: 0.25)
        case .boiler,.tank: .init(x: 0.7,y: 1.6,z: 0.7)
        default: .init(x: 0.7,y: 0.9,z: 0.6)
        }
    }
}

struct SceneEditObject: Codable,Equatable,Identifiable {
    struct ScanReference: Codable,Equatable {
        var position: TechnicalPoint3
        var size: TechnicalPoint3
        var yaw: Double
        var axis: TechnicalPoint3?
        var crossAxis: TechnicalPoint3? = nil
        var family: SceneFurniture? = nil
    }
    var id = UUID()
    var sourceID: UUID?
    var origin: String
    var name: String
    var family: SceneFurniture
    var position: TechnicalPoint3
    var size: TechnicalPoint3
    var yaw = 0.0
    var story = 0
    /// Straight MEP segment local height axis; nil for upright furniture.
    var axis: TechnicalPoint3? = nil
    var crossAxis: TechnicalPoint3? = nil
    var scanReference: ScanReference? = nil
    var technicalData: StudioEquipmentData? = nil
    var color = TechnicalPoint3(x: 0.68,y: 0.73,z: 0.69)
    var capturedColor: TechnicalPoint3? = nil
    var colorSource = ColorSource.preset
    enum ColorSource: String,Codable { case preset, cameraSample, user }
    var finish = Finish.matte
    enum Finish: String,Codable,CaseIterable { case matte, painted, metal, wood, fabric }
    mutating func replaceFamily(_ family: SceneFurniture,preserveMeasurements: Bool = false) {
        if name == self.family.title { name = family.title }
        if preserveMeasurements { self.family = family; return }
        let bottom = position.y-planObject.height/2
        self.family = family; size = family.defaultSize
        axis = nil; crossAxis = nil
        position.y = max(0,bottom)+size.y/2
    }
    var planObject: PlacedObject {
        guard let axis else {
            return .init(id: id,category: family.title,center: .init(x: position.x,y: -position.z),size: .init(width: size.x,depth: size.z),height: size.y,angle: yaw,confidence: .low)
        }
        let rotation = orientation
        let direction = rotation.act(SIMD3<Double>(0,1,0))
        let angle = hypot(direction.x,direction.z) > 0.001 ? atan2(-direction.z,direction.x) : yaw
        let right = Point2D(x: cos(angle),y: sin(angle)),up = Point2D(x: -sin(angle),y: cos(angle))
        var xs: [Double] = [],ys: [Double] = [],heights: [Double] = []
        for x in [-0.5,0.5] { for y in [-0.5,0.5] { for z in [-0.5,0.5] {
            let p = rotation.act(SIMD3(x*size.x,y*size.y,z*size.z)),point = Point2D(x: p.x,y: -p.z)
            xs.append(point.x*right.x+point.y*right.y); ys.append(point.x*up.x+point.y*up.y); heights.append(p.y)
        } } }
        return .init(id: id,category: family.title,center: .init(x: position.x,y: -position.z),size: .init(width: xs.max()!-xs.min()!,depth: ys.max()!-ys.min()!),height: heights.max()!-heights.min()!,angle: angle,confidence: .low)
    }
    var orientation: simd_quatd {
        let yawRotation = simd_quatd(angle: yaw,axis: SIMD3(0,1,0))
        guard let axis else { return yawRotation }
        let up = SIMD3(axis.x,axis.y,axis.z)
        if let crossAxis {
            let right = SIMD3(crossAxis.x,crossAxis.y,crossAxis.z)
            return yawRotation*simd_quatd(simd_double3x3(columns: (right,up,simd_cross(right,up))))
        }
        return yawRotation*simd_quatd(from: SIMD3(0,1,0),to: up)
    }
    func validate() throws {
        try technicalData?.validate()
        if let capturedColor { guard [capturedColor.x,capturedColor.y,capturedColor.z].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw SceneEditDocument.Failure.invalid } }
        let values = [position.x,position.y,position.z,size.x,size.y,size.z,yaw,color.x,color.y,color.z]
        guard values.allSatisfy(\.isFinite),[position.x,position.y,position.z].allSatisfy({ abs($0) <= 1000 }),
              [size.x,size.y,size.z].allSatisfy({ $0 >= 0.005 && $0 <= 100 }),
              [color.x,color.y,color.z].allSatisfy({ (0...1).contains($0) }),abs(yaw) <= 1000,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,name.count <= 120,origin.count <= 160 else { throw SceneEditDocument.Failure.invalid }
        if let axis { guard [axis.x,axis.y,axis.z].allSatisfy(\.isFinite),abs(MEPVector.dot(axis,axis)-1) < 0.001 else { throw SceneEditDocument.Failure.invalid } }
        if let crossAxis {
            guard let axis,[crossAxis.x,crossAxis.y,crossAxis.z].allSatisfy(\.isFinite),abs(MEPVector.dot(crossAxis,crossAxis)-1) < 0.001,abs(MEPVector.dot(axis,crossAxis)) < 0.001 else { throw SceneEditDocument.Failure.invalid }
        }
        if let scanReference {
            var check = self; check.scanReference = nil
            check.position = scanReference.position; check.size = scanReference.size; check.yaw = scanReference.yaw; check.axis = scanReference.axis
            check.crossAxis = scanReference.crossAxis
            try check.validate()
        }
    }
}

struct SceneEditDocument: Codable,Equatable,Identifiable {
    enum Source: String,Codable { case room, house, technical }
    enum Failure: LocalizedError {
        case invalid, wrongSource, oversized, exportFailed
        var errorDescription: String? {
            switch self {
            case .invalid: "The edited scene contains invalid values."
            case .wrongSource: "This edit belongs to a different scan."
            case .oversized: "This scene exceeds the supported editing limit."
            case .exportFailed: "The edited scene could not be exported."
            }
        }
    }
    var engineering: StudioEngineering? = nil
    var schemaVersion = 1
    var source: Source
    var sourceID: UUID
    var id: UUID { sourceID }
    var title: String
    /// Immutable shell snapshot: furniture edits never write to original scan packages.
    var shell: House
    var objects: [SceneEditObject]
    var wallColor = TechnicalPoint3(x: 0.88,y: 0.86,z: 0.80)
    var floorColor = TechnicalPoint3(x: 0.66,y: 0.49,z: 0.31)
    var interior = Interior.natural
    var lighting = Lighting.day
    var season = Season.summer
    enum Interior: String,Codable,CaseIterable { case natural, scandinavian, modern, industrial, pastel }
    enum Lighting: String,Codable,CaseIterable { case day, night }
    enum Season: String,Codable,CaseIterable { case summer, winter }
    mutating func apply(_ theme: Interior) {
        interior = theme
        switch theme {
        case .natural: wallColor = .init(x: 0.88,y: 0.86,z: 0.80); floorColor = .init(x: 0.66,y: 0.49,z: 0.31)
        case .scandinavian: wallColor = .init(x: 0.94,y: 0.93,z: 0.88); floorColor = .init(x: 0.79,y: 0.68,z: 0.51)
        case .modern: wallColor = .init(x: 0.81,y: 0.83,z: 0.82); floorColor = .init(x: 0.52,y: 0.48,z: 0.43)
        case .industrial: wallColor = .init(x: 0.57,y: 0.59,z: 0.58); floorColor = .init(x: 0.39,y: 0.32,z: 0.26)
        case .pastel: wallColor = .init(x: 0.87,y: 0.86,z: 0.75); floorColor = .init(x: 0.75,y: 0.59,z: 0.41)
        }
        for i in objects.indices {
            guard ![SceneFurniture.pipe,.roundDuct,.rectangularDuct,.boiler,.tank,.pump,.electricalPanel,.manifold].contains(objects[i].family) else { continue }
            objects[i].color = theme == .pastel ? .init(x: 0.52,y: 0.72,z: 0.62) : theme == .industrial ? .init(x: 0.35,y: 0.39,z: 0.40) : .init(x: 0.74,y: 0.73,z: 0.65)
            objects[i].colorSource = .preset
        }
    }
    func validate() throws {
        guard schemaVersion == 1,!title.isEmpty,title.count <= 240,objects.count <= 500,
              Set(objects.map(\.id)).count == objects.count,shell.allRooms.count <= 100,
              shell.allRooms.reduce(0,{ $0+$1.walls.count+$1.openings.count+$1.floorPolygon.count }) <= 20_000,
              [wallColor.x,wallColor.y,wallColor.z,floorColor.x,floorColor.y,floorColor.z].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw Failure.invalid }
        try engineering?.validate(ids: Set(engineeringElements.map(\.id)))
        for object in objects { try object.validate() }
        let stories = Set(shell.stories.map(\.index))
        guard Set(objects.map(\.story)).isSubset(of: stories) else { throw Failure.invalid }
        // Reject nonfinite shell geometry before passing it to native rendering/export.
        for room in shell.allRooms {
            guard room.floorPolygon.count <= 512,room.walls.count <= 1000,room.openings.count <= 1000,
                  room.walls.allSatisfy({ $0.height > 0 && $0.thickness > 0 }),
                  room.openings.allSatisfy({ $0.width > 0 && $0.height > 0 }) else { throw Failure.invalid }
            let values = room.walls.flatMap { [$0.start.x,$0.start.y,$0.end.x,$0.end.y,$0.height,$0.thickness] }
                + room.floorPolygon.flatMap { [$0.x,$0.y] }
                + room.openings.flatMap { [$0.center.x,$0.center.y,$0.width,$0.height,$0.sillHeight,$0.angle] }
                + [room.transform.translation.x,room.transform.translation.y,room.transform.rotation]
            guard values.allSatisfy({ $0.isFinite && abs($0) <= 1000 }) else { throw Failure.invalid }
        }
    }
    var plan: House {
        var house = shell
        for si in house.stories.indices {
            for ri in house.stories[si].rooms.indices {
                house.stories[si].rooms[ri].objects = []
                house.stories[si].rooms[ri].walls.removeAll { !includesElement($0.id) }
                let wallIDs = Set(house.stories[si].rooms[ri].walls.map(\.id))
                house.stories[si].rooms[ri].openings.removeAll { $0.wallID.map { !wallIDs.contains($0) } ?? false }
            }
        }
        // Edited positions are world coordinates. Add an identity overlay per storey.
        if house.stories.isEmpty { house.stories = [.init(index: 0,rooms: [])] }
        for si in house.stories.indices {
            let story = house.stories[si].index
            let overlay = FloorPlan(id: sourceID,name: "Edited objects",label: .unidentified,story: story,transform: .identity,walls: [],openings: [],
                objects: presentationObjects.filter { $0.story == story }.map(\.planObject),floorPolygon: [],ceilingHeight: 0...0)
            house.stories[si].rooms.append(overlay)
        }
        return house
    }
    static func seed(house: House,source: Source,id: UUID,scans: [ScanInput] = []) -> Self {
        var shell = house
        var objects: [SceneEditObject] = []
        for room in house.allRooms {
            for object in room.objects {
                let point = room.transform.apply(object.center)
                let family = SceneFurniture.detected(object.category)
                let size = TechnicalPoint3(x: max(0.005,object.size.width),y: max(0.005,object.height),z: max(0.005,object.size.depth))
                let scan = scans.first { $0.id == room.id }
                let raw = scan?.objects.first { $0.id == object.id }
                let elevation = raw.map { Double($0.transform.translation.y)-(scan.map { StoryDetector.floorHeight(of: $0) } ?? 0) } ?? size.y/2
                objects.append(.init(sourceID: object.id,origin: "RoomPlan category and bounding dimensions; modelled appearance",name: family.title,family: family,position: .init(x: point.x,y: elevation,z: -point.y),size: size,yaw: object.angle+room.transform.rotation,story: room.story))
            }
        }
        for si in shell.stories.indices { for ri in shell.stories[si].rooms.indices { shell.stories[si].rooms[ri].objects = [] } }
        for i in objects.indices { objects[i].scanReference = .init(position: objects[i].position,size: objects[i].size,yaw: objects[i].yaw,axis: objects[i].axis,family: objects[i].family) }
        return .init(source: source,sourceID: id,title: house.name+" · Edited",shell: shell,objects: objects)
    }
}

@MainActor @Observable final class SceneEditSession {
    private(set) var document: SceneEditDocument
    private(set) var undoStack: [SceneEditDocument] = []
    private(set) var redoStack: [SceneEditDocument] = []
    private(set) var saved: SceneEditDocument
    var selectedID: UUID?
    var selected: SceneEditObject? { document.objects.first { $0.id == selectedID } }
    var dirty: Bool { document != saved }
    init(_ document: SceneEditDocument) { self.document = document; saved = document }
    func change(_ body: (inout SceneEditDocument) -> Void) throws {
        var next = document; body(&next)
        let ids = Set(next.engineeringElements.map(\.id))
        next.engineering?.records.removeAll { !ids.contains($0.id) }
        try next.validate()
        guard next != document else { return }
        undoStack.append(document); if undoStack.count > 40 { undoStack.removeFirst() }
        redoStack = []; document = next
    }
    func update(_ item: SceneEditObject) throws {
        try change { doc in if let index = doc.objects.firstIndex(where: { $0.id == item.id }) { doc.objects[index] = item } }
    }
    func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(document); document = previous }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(document); document = next }
    func markSaved() { saved = document }
}

enum SceneEditStore {
    static func url(root: URL,source: SceneEditDocument.Source,id: UUID) -> URL {
        root.appendingPathComponent("SceneEdits",isDirectory: true).appendingPathComponent(source.rawValue+"-"+id.uuidString+".json")
    }
    static func read(_ url: URL,source: SceneEditDocument.Source,id: UUID) throws -> SceneEditDocument? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try RoomPackage.coordinatedRead(at: url) { file in
            let info = try file.resourceValues(forKeys: [.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey])
            guard info.isRegularFile == true,info.isSymbolicLink != true,(info.fileSize ?? Int.max) <= 12*1_048_576 else { throw SceneEditDocument.Failure.oversized }
            let document = try JSONDecoder().decode(SceneEditDocument.self,from: Data(contentsOf: file))
            guard document.source == source,document.sourceID == id else { throw SceneEditDocument.Failure.wrongSource }
            try document.validate(); return document
        }
    }
    static func write(_ document: SceneEditDocument,to url: URL) throws {
        try document.validate()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(document)
        guard data.count <= 12*1_048_576 else { throw SceneEditDocument.Failure.oversized }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
        try RoomPackage.coordinatedWrite(at: url,options: .forReplacing) { file in
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SceneEditDocument.Failure.invalid }
            try data.write(to: file,options: .atomic)
        }
    }
}
