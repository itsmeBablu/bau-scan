import XCTest
@testable import RoomScanner

final class RevitIFCExportTests: XCTestCase {
    private func resource(_ name: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for:Self.self).url(forResource:name,withExtension:"json"))
        return try Data(contentsOf:url)
    }
    private func room(_ name: String) throws -> TechnicalRoom {
        try JSONDecoder().decode(TechnicalRoom.self,from:resource(name))
    }
    private func text(_ data: Data) -> String { String(decoding:data,as:UTF8.self) }
    private func count(_ entity: String, in value: String) -> Int {
        value.components(separatedBy:"="+entity+"(").count-1
    }
    func testFixtureGoldenSemanticSnapshotsAndDeterminism() throws {
        let snapshots = try JSONDecoder().decode([String:[String:Int]].self,from:resource("revit-ifc-counts"))
        for name in ["small-boiler-room","vertical-riser","estimated-diameter"] {
            let input = RevitTechnicalRoomInput(name:name,document:.init(room:try room(name)))
            let data = try RevitIFCExporter.export(house:nil,technicalRooms:[input])
            XCTAssertEqual(data,try RevitIFCExporter.export(house:nil,technicalRooms:[input]))
            let step = text(data)
            for (entity,expected) in try XCTUnwrap(snapshots[name]) { XCTAssertEqual(count(entity,in:step),expected,"\(name): \(entity)") }
            XCTAssertTrue(step.contains("device validation pending"))
            XCTAssertTrue(step.contains("'GeometricLength',$,IFCLENGTHMEASURE(2.),$"))
            XCTAssertTrue(step.contains("'accuracyMm',$,$,$"),"Unknown accuracy must remain unset")
        }
    }
    func testRiserEndpointsAndRightHandedAsymmetricMapping() throws {
        let room = try room("vertical-riser")
        let points = room.pipeRuns[0].centerline.value.map(IFCModel.ifc)
        XCTAssertEqual(points[0].x,1,accuracy:1e-9)
        XCTAssertEqual(points[0].y,-0.989,accuracy:1e-9)
        XCTAssertEqual(points[0].z,0.5,accuracy:1e-9)
        XCTAssertEqual(points[1].z,2.5,accuracy:1e-9)
        let p = IFCModel.ifc(.init(x:2,y:3,z:5))
        XCTAssertEqual(p,.init(x:2,y:-5,z:3))
        let x = IFCModel.ifc(.init(x:1,y:0,z:0))
        let y = IFCModel.ifc(.init(x:0,y:1,z:0))
        let z = IFCModel.ifc(.init(x:0,y:0,z:1))
        XCTAssertEqual(MEPVector.dot(MEPVector.cross(x,y),z),1)
        let step = text(try RevitIFCExporter.export(house:nil,technicalRooms:[.init(name:"Riser",document:.init(room:room))]))
        XCTAssertTrue(step.contains("IFCCARTESIANPOINT((1.,-0.989,0.5))"))
        XCTAssertTrue(step.contains("IFCCARTESIANPOINT((1.,-0.989,2.5))"))
    }
    func testGUIDCompressionAndEscaping() {
        XCTAssertEqual(IFCWriter.compressedGUID(UUID(uuidString:"00000000-0000-0000-0000-000000000000")!),"0000000000000000000000")
        XCTAssertEqual(IFCWriter.compressedGUID(UUID(uuidString:"FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF")!),"3$$$$$$$$$$$$$$$$$$$$$")
        XCTAssertEqual(IFCWriter.text("O'Brien"),"'O''Brien'")
        XCTAssertEqual(IFCWriter.text("ü"),"'\\X2\\00FC\\X0\\'")
        XCTAssertEqual(IFCWriter.guid("fixed"),IFCWriter.guid("fixed"))
    }
    func testRealHouseSemanticGoldenAndMeasuredElevation() throws {
        let data = try resource("house.structure")
        let source = try RoomPackage.decoder.decode(StructureInput.self,from:data)
        let house = try HouseBuilder().build(from:source,name:"House")
        let options = try RevitScanEvidence.options(house:house,structureData:data)
        XCTAssertEqual(options.storeyElevations.count,1)
        XCTAssertEqual(options.shellPlacements.count,3)
        let output = try RevitIFCExporter.export(house:house,options:options)
        XCTAssertEqual(output,try RevitIFCExporter.export(house:house,options:options))
        let snapshots = try JSONDecoder().decode([String:[String:Int]].self,from:resource("revit-ifc-counts"))
        for (entity,expected) in try XCTUnwrap(snapshots["house.structure"]) {
            XCTAssertEqual(count(entity,in:text(output)),expected)
        }
        XCTAssertTrue(text(output).contains(IFCWriter.number(try XCTUnwrap(options.storeyElevations[0]))))
    }
    func testSeparateStoreysAndCombinedRegistration() throws {
        let technical = try room("small-boiler-room")
        func plan(_ index: Int, id: UUID) -> FloorPlan {
            let wall = Wall(id:UUID(),segment:.init(start:.init(x:0,y:0),end:.init(x:4,y:0)),height:3,thickness:0.1,confidence:.high)
            return .init(id:id,name:"Room",label:.unidentified,story:index,transform:.identity,walls:[wall],openings:[],objects:[],
                         floorPolygon:[.init(x:0,y:0),.init(x:4,y:0),.init(x:4,y:2),.init(x:0,y:2)],ceilingHeight:3...3)
        }
        let a = plan(0,id:technical.shellID),b = plan(1,id:UUID())
        let house = House(name:"House",stories:[.init(index:0,rooms:[a]),.init(index:1,rooms:[b])])
        let input = RevitTechnicalRoomInput(name:"Boiler",document:.init(room:technical))
        XCTAssertThrowsError(try RevitIFCExporter.export(house:house,technicalRooms:[input]))
        var options = RevitExportOptions()
        options.storeyElevations = [0:0,1:3.4]
        options.shellPlacements[technical.shellID] = .init(translation:.init(x:10,y:0,z:0),xAxis:.init(x:1,y:0,z:0),yAxis:.init(x:0,y:1,z:0),zAxis:.init(x:0,y:0,z:1))
        let step = text(try RevitIFCExporter.export(house:house,technicalRooms:[input],options:options))
        XCTAssertEqual(count("IFCBUILDINGSTOREY",in:step),2)
        XCTAssertTrue(step.contains(".ELEMENT.,3.4)"))
        XCTAssertEqual(count("IFCBOILER",in:step),1)
        options.schema = .ifc2x3
        let legacy = text(try RevitIFCExporter.export(house:house,technicalRooms:[input],options:options))
        XCTAssertTrue(legacy.contains("FILE_SCHEMA(('IFC2X3'))"))
        XCTAssertEqual(count("IFCFLOWSEGMENT",in:legacy),1)
        XCTAssertEqual(count("IFCPIPESEGMENT",in:legacy),0)
    }
    func testEffectivePointsAndConnectionsAreExported() throws {
        var doc = TechnicalAnnotationDocument(room:try room("small-boiler-room"))
        let pipeID = doc.room.pipeRuns[0].id
        var changed = doc.room.pipeRuns[0].surfaceHits[0].position
        changed.value.x += 0.3
        doc.pointOverrides = [.init(objectID:pipeID,pointIndex:0,position:changed)]
        let portID = doc.room.equipment[0].ports[0].id
        doc.connections = [.init(id:UUID(),pipeID:pipeID,endpoint:.start,portID:portID)]
        doc.room.pipeRuns[0].connectedPorts = [portID]
        let step = text(try RevitIFCExporter.export(house:nil,technicalRooms:[.init(name:"Edited",document:doc)]))
        XCTAssertTrue(step.contains("IFCCARTESIANPOINT((0.3,-0.989,1.))"))
        XCTAssertEqual(count("IFCRELCONNECTSPORTS",in:step),1)
    }
}
