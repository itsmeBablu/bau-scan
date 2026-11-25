import Foundation
import Observation
import simd

enum SceneFurniture: String,Codable,CaseIterable,Identifiable {
    case sofa, bed, chair, table, television, cabinet, refrigerator, stove, sink, toilet, bathtub, shower, washer
    case desk, officeChair, conferenceTable, computer, monitor, bookshelf, whiteboard
    case radiator, boiler, tank, pump, manifold, electricalPanel, pipe, roundDuct, rectangularDuct, box, cylinder
    var id: String { rawValue }
    var symbol: String {
        switch self {
        case .sofa: "sofa.fill"; case .bed: "bed.double.fill"; case .chair: "chair.fill"; case .table: "table.furniture.fill"
        case .desk: "table.furniture.fill"; case .officeChair: "chair.lounge.fill"; case .conferenceTable: "person.3.sequence.fill"
        case .computer: "desktopcomputer"; case .monitor: "display"; case .bookshelf: "books.vertical.fill"; case .whiteboard: "character.textbox"
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
        case .television: AppLanguage.text("TV"); case .electricalPanel: AppLanguage.text("Electrical panel")
        case .roundDuct: AppLanguage.text("Round duct"); case .rectangularDuct: AppLanguage.text("Rectangular duct")
        case .officeChair: AppLanguage.text("Office chair"); case .conferenceTable: AppLanguage.text("Conference table")
        default: AppLanguage.text(rawValue.prefix(1).uppercased()+rawValue.dropFirst())
        }
    }
    static func detected(_ category: String, size: TechnicalPoint3? = nil) -> Self {
        let c = category.lowercased()
        if c.contains("desk") { return .desk }
        if c.contains("office chair") || c.contains("swivel") { return .officeChair }
        if c.contains("conference") || c.contains("meeting") { return .conferenceTable }
        if c.contains("computer") || c.contains("desktop") || c.contains("pc") { return .computer }
        if c.contains("monitor") { return .monitor }
        if c.contains("bookshelf") || c.contains("bookcase") { return .bookshelf }
        if c.contains("whiteboard") { return .whiteboard }
        if c.contains("sofa") { return .sofa }; if c.contains("bed") { return .bed }
        if c.contains("chair") { return .chair }; if c.contains("table") { return .table }
        if c.contains("television") || c == "tv" || c.contains("screen") || c.contains("display") {
            if let size {
                let estimatedScreenHeight = min(size.y, size.x * 9.0 / 16.0)
                let diagonalInches = sqrt(size.x * size.x + estimatedScreenHeight * estimatedScreenHeight) / 0.0254
                if diagonalInches <= 32.5 || size.x <= 0.78 {
                    return .monitor
                }
            }
            return .television
        }
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
        case .desk: .init(x: 1.6,y: 0.75,z: 0.80); case .officeChair: .init(x: 0.65,y: 0.95,z: 0.65)
        case .conferenceTable: .init(x: 2.4,y: 0.75,z: 1.10); case .computer: .init(x: 0.22,y: 0.45,z: 0.45)
        case .monitor: .init(x: 0.72,y: 0.52,z: 0.20); case .bookshelf: .init(x: 1.0,y: 1.8,z: 0.35)
        case .whiteboard: .init(x: 1.5,y: 1.8,z: 0.45)
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
    struct FloorRegion: Codable,Equatable {
        let roomID: UUID
        let polygon: [Point2D]
    }
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
    var revision: Int? = nil
    var modifiedAt: Date? = nil
    /// Immutable shell snapshot: furniture edits never write to original scan packages.
    var shell: House
    var objects: [SceneEditObject]
    /// All captured floor regions, aligned to each saved room's local plan frame.
    var floorRegions: [FloorRegion]? = nil
    var wallColor = TechnicalPoint3(x: 0.88,y: 0.86,z: 0.80)
    enum FloorFinish: String,Codable,CaseIterable { case wood, tile, plain }
    var floorFinish: FloorFinish? = nil
    var floorPatternSize: Double? = nil
    var floorColor = TechnicalPoint3(x: 0.66,y: 0.49,z: 0.31)
    var interior = Interior.natural
    var lighting = Lighting.day
    var season = Season.summer
    enum TechnicalTemplate: String,Codable,CaseIterable {
        case captured, equipment, categories, monochrome
        var title: String {
            switch self {
            case .captured: AppLanguage.text("Captured colours · measured shapes")
            case .equipment: AppLanguage.text("Equipment shapes")
            case .categories: AppLanguage.text("Category colours")
            case .monochrome: AppLanguage.text("Monochrome engineering")
            }
        }
    }
    var technicalTemplate: TechnicalTemplate? = nil
    enum DoorTemplate: String,Codable,CaseIterable { case single, double, glazed, sliding }
    enum WindowTemplate: String,Codable,CaseIterable { case fixed, casement, sliding, doubleHung }
    var doorTemplate: DoorTemplate? = nil
    var windowTemplate: WindowTemplate? = nil
    var doorOpeningDegrees: Double? = nil
    var windowOpeningDegrees: Double? = nil
    mutating func applyTechnicalTemplate(_ template: TechnicalTemplate) {
        guard source == .technical else { return }
        technicalTemplate = template
        for i in objects.indices {
            if template == .captured || template == .equipment {
                objects[i].color = objects[i].capturedColor ?? .init(x: 0.68,y: 0.70,z: 0.72)
                objects[i].colorSource = objects[i].capturedColor == nil ? .preset : .cameraSample
            } else {
                objects[i].colorSource = .preset
                if template == .monochrome { objects[i].color = .init(x: 0.66,y: 0.68,z: 0.70) }
                else {
                    objects[i].color = switch objects[i].family {
                    case .pipe: .init(x: 0.22,y: 0.48,z: 0.78)
                    case .roundDuct,.rectangularDuct: .init(x: 0.60,y: 0.68,z: 0.73)
                    case .boiler,.tank: .init(x: 0.82,y: 0.55,z: 0.28)
                    case .pump,.manifold: .init(x: 0.32,y: 0.65,z: 0.48)
                    case .electricalPanel: .init(x: 0.74,y: 0.67,z: 0.32)
                    default: .init(x: 0.68,y: 0.70,z: 0.72)
                    }
                }
            }
        }
    }
    mutating func generateModularTechnikLayout() {
        guard source == .technical else { return }
        let roomBounds = shell.bounds
        let cx = roomBounds.isEmpty ? 0.0 : roomBounds.center.x
        let cz = roomBounds.isEmpty ? 0.0 : -roomBounds.center.y
        let halfX = roomBounds.isEmpty ? 1.8 : max(1.2, roomBounds.width / 2)
        let halfZ = roomBounds.isEmpty ? 1.8 : max(1.2, roomBounds.height / 2)
        let wallHeight = shell.allRooms.first?.ceilingHeight.upperBound ?? 2.50

        var newObjects: [SceneEditObject] = []

        // 1. Heat Generator / Boiler (Wärmeerzeuger)
        let boilerSize = TechnicalPoint3(x: 0.75, y: 1.65, z: 0.70)
        let boilerPos = TechnicalPoint3(x: cx - halfX * 0.45, y: boilerSize.y / 2, z: cz - halfZ * 0.65)
        newObjects.append(SceneEditObject(
            origin: "Modular Technik template; editable model",
            name: "Wärmeerzeuger · Boiler",
            family: .boiler,
            position: boilerPos,
            size: boilerSize
        ))

        // 2. Buffer Tank (Pufferspeicher)
        let tankSize = TechnicalPoint3(x: 0.75, y: 1.85, z: 0.75)
        let tankPos = TechnicalPoint3(x: cx + halfX * 0.20, y: tankSize.y / 2, z: cz - halfZ * 0.65)
        newObjects.append(SceneEditObject(
            origin: "Modular Technik template; editable model",
            name: "Pufferspeicher · Buffer Tank",
            family: .tank,
            position: tankPos,
            size: tankSize
        ))

        // 3. Expansion Vessel (Membran-Ausdehnungsgefäß / MAG)
        let magSize = TechnicalPoint3(x: 0.48, y: 0.85, z: 0.48)
        let magPos = TechnicalPoint3(x: cx + halfX * 0.65, y: magSize.y / 2, z: cz - halfZ * 0.65)
        newObjects.append(SceneEditObject(
            origin: "Modular Technik template; editable model",
            name: "Ausdehnungsgefäß · Expansion Vessel",
            family: .tank,
            position: magPos,
            size: magSize
        ))

        // 4. Circulation Pump (Heizkreispumpe)
        let pumpSize = TechnicalPoint3(x: 0.22, y: 0.32, z: 0.22)
        let pumpPos = TechnicalPoint3(x: cx - halfX * 0.05, y: 1.05, z: cz - halfZ * 0.65)
        newObjects.append(SceneEditObject(
            origin: "Modular Technik template; editable model",
            name: "Heizkreispumpe · Pump",
            family: .pump,
            position: pumpPos,
            size: pumpSize
        ))

        // 5. Heating Manifold (Heizkreisverteiler)
        let manifoldSize = TechnicalPoint3(x: 0.90, y: 0.48, z: 0.20)
        let manifoldPos = TechnicalPoint3(x: cx - halfX * 0.05, y: 0.65, z: cz - halfZ * 0.82)
        newObjects.append(SceneEditObject(
            origin: "Modular Technik template; editable model",
            name: "Heizkreisverteiler · Manifold",
            family: .manifold,
            position: manifoldPos,
            size: manifoldSize
        ))

        // 6. Main Electrical / Control Panel (Schaltschrank)
        let panelSize = TechnicalPoint3(x: 0.60, y: 0.90, z: 0.22)
        let panelPos = TechnicalPoint3(x: cx - halfX * 0.85, y: 1.25, z: cz)
        newObjects.append(SceneEditObject(
            origin: "Modular Technik template; editable model",
            name: "Schaltschrank · Electrical Panel",
            family: .electricalPanel,
            position: panelPos,
            size: panelSize,
            yaw: .pi / 2
        ))

        // 7. Heating Supply Pipe (Vorlauf)
        let supplyStart = TechnicalPoint3(x: cx - halfX * 0.45, y: 1.35, z: cz - halfZ * 0.65)
        let supplyEnd = TechnicalPoint3(x: cx - halfX * 0.05, y: 1.35, z: cz - halfZ * 0.65)
        let supplyDir = MEPVector.sub(supplyEnd, supplyStart)
        let supplyLen = sqrt(MEPVector.dot(supplyDir, supplyDir))
        if supplyLen >= 0.01 {
            newObjects.append(SceneEditObject(
                origin: "Modular Technik template; editable model",
                name: "Vorlauf · Supply Pipe",
                family: .pipe,
                position: MEPVector.mul(MEPVector.add(supplyStart, supplyEnd), 0.5),
                size: .init(x: 0.042, y: supplyLen, z: 0.042),
                axis: MEPVector.unit(supplyDir),
                color: .init(x: 0.85, y: 0.25, z: 0.20)
            ))
        }

        // 8. Heating Return Pipe (Rücklauf)
        let returnStart = TechnicalPoint3(x: cx - halfX * 0.05, y: 0.40, z: cz - halfZ * 0.65)
        let returnEnd = TechnicalPoint3(x: cx + halfX * 0.20, y: 0.40, z: cz - halfZ * 0.65)
        let returnDir = MEPVector.sub(returnEnd, returnStart)
        let returnLen = sqrt(MEPVector.dot(returnDir, returnDir))
        if returnLen >= 0.01 {
            newObjects.append(SceneEditObject(
                origin: "Modular Technik template; editable model",
                name: "Rücklauf · Return Pipe",
                family: .pipe,
                position: MEPVector.mul(MEPVector.add(returnStart, returnEnd), 0.5),
                size: .init(x: 0.042, y: returnLen, z: 0.042),
                axis: MEPVector.unit(returnDir),
                color: .init(x: 0.22, y: 0.48, z: 0.78)
            ))
        }

        // 9. Ventilation / Exhaust Duct (Lüftungsrohr)
        let ductY = min(wallHeight - 0.25, 2.30)
        let ductStart = TechnicalPoint3(x: cx - halfX * 0.45, y: ductY, z: cz - halfZ * 0.65)
        let ductEnd = TechnicalPoint3(x: cx - halfX * 0.45, y: ductY, z: cz + halfZ * 0.65)
        let ductDir = MEPVector.sub(ductEnd, ductStart)
        let ductLen = sqrt(MEPVector.dot(ductDir, ductDir))
        if ductLen >= 0.01 {
            newObjects.append(SceneEditObject(
                origin: "Modular Technik template; editable model",
                name: "Lüftung · Duct",
                family: .roundDuct,
                position: MEPVector.mul(MEPVector.add(ductStart, ductEnd), 0.5),
                size: .init(x: 0.16, y: ductLen, z: 0.16),
                axis: MEPVector.unit(ductDir),
                color: .init(x: 0.65, y: 0.72, z: 0.76)
            ))
        }

        for i in newObjects.indices {
            newObjects[i].scanReference = .init(
                position: newObjects[i].position,
                size: newObjects[i].size,
                yaw: newObjects[i].yaw,
                axis: newObjects[i].axis,
                crossAxis: newObjects[i].crossAxis,
                family: newObjects[i].family
            )
        }

        objects.append(contentsOf: newObjects)
        applyTechnicalTemplate(technicalTemplate ?? .equipment)
    }

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
        guard (revision ?? 0) >= 0,modifiedAt?.timeIntervalSince1970.isFinite ?? true,
              schemaVersion == 1,!title.isEmpty,title.count <= 240,objects.count <= 500,
              Set(objects.map(\.id)).count == objects.count,shell.allRooms.count <= 100,
              shell.allRooms.reduce(0,{ $0+$1.walls.count+$1.openings.count+$1.floorPolygon.count }) <= 20_000,
              [wallColor.x,wallColor.y,wallColor.z,floorColor.x,floorColor.y,floorColor.z].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else { throw Failure.invalid }
        if let size = floorPatternSize { guard size.isFinite,(0.1...2).contains(size) else { throw Failure.invalid } }
        if let angle = doorOpeningDegrees { guard angle.isFinite,(0...120).contains(angle) else { throw Failure.invalid } }
        if let angle = windowOpeningDegrees { guard angle.isFinite,(0...90).contains(angle) else { throw Failure.invalid } }
        if let floorRegions {
            let ids = Set(shell.allRooms.map(\.id))
            guard floorRegions.count <= 2000,floorRegions.reduce(0,{ $0+$1.polygon.count }) <= 50_000,
                  floorRegions.allSatisfy({ ids.contains($0.roomID) && (3...512).contains($0.polygon.count) && $0.polygon.allSatisfy { $0.x.isFinite && $0.y.isFinite && abs($0.x) <= 1000 && abs($0.y) <= 1000 } }) else { throw Failure.invalid }
        }
        let elements = engineeringElements
        try engineering?.validate(ids: Set(elements.map(\.id)),thicknessIDs: Set(elements.filter { $0.kind == "Wall" || $0.kind == "Floor" }.map(\.id)),floorIDs: Set(elements.filter { $0.kind == "Floor" }.map(\.id)))
        for object in objects { try object.validate() }
        let stories = Set(shell.stories.map(\.index))
        guard Set(objects.map(\.story)).isSubset(of: stories) else { throw Failure.invalid }
        // Reject nonfinite shell geometry before passing it to native rendering/export.
        for room in shell.allRooms {
            if let thickness = room.floorSlabThickness { guard thickness.isFinite,(0.005...2).contains(thickness) else { throw Failure.invalid } }
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
    var renderingSnapshot: SceneEditDocument {
        var copy = self
        copy.title = ""
        for i in copy.objects.indices { copy.objects[i].technicalData = nil; copy.objects[i].origin = ""; copy.objects[i].name = "" }
        if var data = copy.engineering {
            data.records = data.records.filter { $0.phase != .existing || $0.thicknessOverride != nil }.map { record in
                var clean = StudioEngineering.Record(id: record.id)
                clean.phase = record.phase; clean.thicknessOverride = record.thicknessOverride
                return clean
            }.sorted { $0.id.uuidString < $1.id.uuidString }
            copy.engineering = data.view == .all && data.records.isEmpty ? nil : data
        }
        return copy
    }
    var plan: House {
        var house = architecturalShell
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
            let overlay = FloorPlan(id: overlayID(story:story),name: "Edited objects",label: .unidentified,story: story,transform: .identity,walls: [],openings: [],
                objects: presentationObjects.filter { $0.story == story }.map(\.planObject),floorPolygon: [],ceilingHeight: 0...0)
            house.stories[si].rooms.append(overlay)
        }
        return house
    }
    func overlayID(story: Int) -> UUID {
        var uuid = sourceID.uuid
        var bytes = withUnsafeBytes(of:&uuid) { Array($0) }
        // Namespace the overlay and inject all 64 story bits in a fixed byte order.
        bytes[0] ^= 0xA5
        let level = UInt64(bitPattern:Int64(story))
        for i in 0..<8 { bytes[8+i] ^= UInt8(truncatingIfNeeded:level >> (i*8)) }
        return UUID(uuid:(bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15]))
    }
    static func seed(house: House,source: Source,id: UUID,scans: [ScanInput] = []) -> Self {
        var shell = house
        var objects: [SceneEditObject] = []
        for room in house.allRooms {
            for object in room.objects {
                let point = room.transform.apply(object.center)
                let size = TechnicalPoint3(x: max(0.005,object.size.width),y: max(0.005,object.height),z: max(0.005,object.size.depth))
                let family = SceneFurniture.detected(object.category, size: size)
                let scan = scans.first { $0.id == room.id }
                let raw = scan?.objects.first { $0.id == object.id }
                let elevation = raw.map { Double($0.transform.translation.y)-(scan.map { StoryDetector.floorHeight(of: $0) } ?? 0) } ?? size.y/2
                objects.append(.init(sourceID: object.id,origin: "RoomPlan category and bounding dimensions; modelled appearance",name: family.title,family: family,position: .init(x: point.x,y: elevation,z: -point.y),size: size,yaw: object.angle+room.transform.rotation,story: room.story))
            }
        }
        for si in shell.stories.indices { for ri in shell.stories[si].rooms.indices { shell.stories[si].rooms[ri].objects = [] } }
        for i in objects.indices { objects[i].scanReference = .init(position: objects[i].position,size: objects[i].size,yaw: objects[i].yaw,axis: objects[i].axis,family: objects[i].family) }
        var result = Self(source: source,sourceID: id,title: house.name+" · Edited",shell: shell,objects: objects)
        result.recoverFloorRegions(scans: scans)
        return result
    }
    mutating func recoverFloorRegions(scans: [ScanInput]) {
        guard floorRegions == nil else { return }
        var regions: [FloorRegion] = []
        for room in shell.allRooms {
            guard let scan = scans.first(where: { $0.id == room.id }) else { continue }
            var placement = Transform2D.identity
            if let raw = scan.walls.first(where: { raw in room.walls.contains { $0.id == raw.id } }),
               let wall = room.walls.first(where: { $0.id == raw.id }) {
                let direction = Point2D(x: Double(raw.transform.xAxis.x),y: -Double(raw.transform.xAxis.z))
                placement.rotation = wall.segment.angle-atan2(direction.y,direction.x)
                let rawCenter = Point2D(projecting: raw.transform.translation)
                placement.translation = wall.segment.midpoint-placement.apply(rawCenter)
            }
            if scan.floors.contains(where: { $0.polygonCorners.count < 3 }),room.floorPolygon.count >= 3 {
                regions.append(.init(roomID: room.id,polygon: room.floorPolygon))
            }
            let floorHeight = StoryDetector.floorHeight(of: scan)
            for floor in scan.floors where abs(Double(floor.transform.translation.y)-floorHeight) < 0.25 {
                let points = floor.polygonCorners.map { corner -> Point2D in
                    let p = floor.transform*SIMD4<Float>(corner.x,corner.y,corner.z,1)
                    return placement.apply(Point2D(projecting: SIMD3(p.x,p.y,p.z)))
                }
                let polygon = Polygon2D.simplified(points,tolerance: 0.01)
                guard polygon.count >= 3,polygon.count <= 512,Polygon2D.area(polygon) > 0.01,Polygon2D.triangulation(polygon).1 else { continue }
                regions.append(.init(roomID: room.id,polygon: polygon))
            }
        }
        if !regions.isEmpty { floorRegions = regions }
    }
}

@MainActor @Observable final class SceneEditSession {
    private(set) var document: SceneEditDocument
    private(set) var undoStack: [SceneEditDocument] = []
    private(set) var redoStack: [SceneEditDocument] = []
    private(set) var saved: SceneEditDocument
    var selectedID: UUID?
    var selectedIDs: Set<UUID> = []
    var onSave: (() -> Void)?
    var selectAllOnFloor: (() -> Void)?
    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    func select(_ id: UUID?, multiple: Bool) {
        if multiple {
            guard let id else { return }
            if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
            selectedID = selectedIDs.count == 1 ? selectedIDs.first : nil
        } else {
            selectedID = id
            selectedIDs = Set(id.map { [$0] } ?? [])
        }
    }
    func deleteSelection() throws {
        let ids = selectedIDs.union(selectedID.map { [$0] } ?? [])
        try change { $0.objects.removeAll { ids.contains($0.id) } }
        selectedIDs = []; selectedID = nil
    }
    var selected: SceneEditObject? { document.objects.first { $0.id == selectedID } }
    func nudgeSelection(dx: Double,dz: Double,allowOverlap: Bool) throws {
        let ids = selectedIDs.union(selectedID.map { [$0] } ?? [])
        guard !ids.isEmpty else { return }
        var next = document
        for i in next.objects.indices where ids.contains(next.objects[i].id) {
            next.objects[i].position.x += dx; next.objects[i].position.z += dz
        }
        if !allowOverlap {
            for item in next.objects where ids.contains(item.id) { try StudioPlacement.check(item,in:next) }
        }
        try change { $0 = next }
    }
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
    func addDesignObject(_ item: SceneEditObject,allowOverlap: Bool) throws {
        var target = document,data = document.engineering ?? .init()
        if data.view == .existing || data.view == .demolition { data.view = .proposed }
        target.engineering = data
        let placed = try StudioPlacement.available(item,in: target,allowOverlap: allowOverlap)
        target.objects.append(placed)
        var record = data.record(placed.id); record.phase = .new; data.set(record); target.engineering = data
        try change { $0 = target }; selectedID = placed.id
    }
    func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(document); document = previous }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(document); document = next }
    func markSaved(_ committed: SceneEditDocument? = nil) { if let committed { document = committed }; saved = document }
}

enum SceneEditStore {
    struct Conflict: LocalizedError {
        let copy: URL
        var errorDescription: String? { AppLanguage.text("studio.conflict.saved")+"\n"+copy.path }
    }
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
    @discardableResult static func write(_ document: SceneEditDocument,to url: URL) throws -> SceneEditDocument {
        try document.validate()
        var committed = document
        guard (document.revision ?? 0) >= 0,(document.revision ?? 0) < Int.max else { throw SceneEditDocument.Failure.invalid }
        committed.revision = (document.revision ?? 0)+1; committed.modifiedAt = Date()
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        let data = try encoder.encode(committed)
        guard data.count <= 12*1_048_576 else { throw SceneEditDocument.Failure.oversized }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),withIntermediateDirectories: true)
        try RoomPackage.coordinatedWrite(at: url,options: .forReplacing) { file in
            guard (try? file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { throw SceneEditDocument.Failure.invalid }
            var latest: SceneEditDocument?
            if FileManager.default.fileExists(atPath:file.path) {
                let info = try file.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey])
                guard info.isRegularFile == true,(info.fileSize ?? Int.max) <= 12*1_048_576 else { throw SceneEditDocument.Failure.oversized }
                latest = try JSONDecoder().decode(SceneEditDocument.self,from:Data(contentsOf:file))
                try latest?.validate()
            }
            if (latest?.revision ?? 0) != (document.revision ?? 0) || latest?.modifiedAt != document.modifiedAt {
                var copy = document; copy.sourceID = UUID(); copy.revision = nil; copy.modifiedAt = nil
                copy.title = String(document.title.prefix(200))+" "+AppLanguage.text("cloud.conflictSuffix")
                let destination = Self.url(root:file.deletingLastPathComponent().deletingLastPathComponent(),source:copy.source,id:copy.sourceID)
                try encoder.encode(copy).write(to:destination,options:.atomic)
                throw Conflict(copy:destination)
            }
            try data.write(to: file,options: .atomic)
        }
        return committed
    }
}
