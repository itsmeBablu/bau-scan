import XCTest
@testable import RoomScanner

final class GeometryTests: XCTestCase {
    func testUnionMatchesIndependentIntegerCellOracle() {
        var seed: UInt64 = 7
        for _ in 0..<40 {
            var polygons: [[Point2D]] = [],occupied = Set<String>()
            for _ in 0..<10 {
                seed = seed &* 6364136223846793005 &+ 1
                let x = Int(seed%8),y = Int((seed>>8)%8),w = Int((seed>>16)%4)+1,h = Int((seed>>24)%4)+1
                polygons.append([.init(x:Double(x),y:Double(y)),.init(x:Double(x+w),y:Double(y)),.init(x:Double(x+w),y:Double(y+h)),.init(x:Double(x),y:Double(y+h))])
                for a in x..<(x+w) { for b in y..<(y+h) { occupied.insert("\(a),\(b)") } }
            }
            XCTAssertEqual(Polygon2D.unionArea(polygons),Double(occupied.count),accuracy:0.000001)
        }
    }
    let square = [Point2D(x: 0, y: 0), Point2D(x: 4, y: 0), Point2D(x: 4, y: 3), Point2D(x: 0, y: 3)]

    func testShoelaceArea() {
        XCTAssertEqual(Polygon2D.area(square), 12, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.signedArea(square), 12, accuracy: 1e-9, "sens trigonométrique ⇒ positif")
        XCTAssertEqual(Polygon2D.signedArea(square.reversed()), -12, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.area([Point2D(x: 0, y: 0), Point2D(x: 1, y: 1)]), 0)
    }

    func testPerimeter() {
        XCTAssertEqual(Polygon2D.perimeter(square), 14, accuracy: 1e-9)
    }

    func testCentroidAndInteriorPoint() {
        let c = Polygon2D.centroid(square)
        XCTAssertEqual(c.x, 2.0, accuracy: 1e-9)
        XCTAssertEqual(c.y, 1.5, accuracy: 1e-9)
        let inside = Polygon2D.interiorPoint(square)
        XCTAssertTrue(Polygon2D.contains(square, inside))

        let lShape = SyntheticRooms.lShapeCorners
        let lInside = Polygon2D.interiorPoint(lShape)
        XCTAssertTrue(Polygon2D.contains(lShape, lInside), "interiorPoint garantit d'être dans la pièce en L")
    }

    func testChainReordersAndReversesSegments() {
        let segs = [Segment2D(start: square[2], end: square[3]),   // désordonné
                    Segment2D(start: square[1], end: square[0]),   // inversé
                    Segment2D(start: square[3], end: square[0]),
                    Segment2D(start: square[1], end: square[2])]
        let contour = Polygon2D.chain(segs, tolerance: 0.01)
        XCTAssertEqual(contour?.count, 4)
        XCTAssertEqual(Polygon2D.area(contour ?? []), 12, accuracy: 1e-9)
    }

    func testChainFailsOnGap() {
        var segs = square.indices.map { Segment2D(start: square[$0], end: square[($0 + 1) % 4]) }
        segs[2].end = Point2D(x: 0.5, y: 3)   // le contour ne se referme plus
        XCTAssertNil(Polygon2D.chain(segs, tolerance: 0.1))
    }

    func testChainToleratesSmallGaps() {
        var segs = square.indices.map { Segment2D(start: square[$0], end: square[($0 + 1) % 4]) }
        segs[0].end = Point2D(x: 3.9, y: 0.05)   // 11 cm d'écart, typique d'un scan
        XCTAssertNotNil(Polygon2D.chain(segs, tolerance: 0.25))
    }

    func testSegmentDistance() {
        let s = Segment2D(start: Point2D(x: 0, y: 0), end: Point2D(x: 4, y: 0))
        XCTAssertEqual(s.distance(to: Point2D(x: 2, y: 1)), 1, accuracy: 1e-9)
        XCTAssertEqual(s.distance(to: Point2D(x: 6, y: 0)), 2, accuracy: 1e-9, "au-delà de l'extrémité")
    }

    func testTriangulationCoversArea() {
        for poly in [square, SyntheticRooms.lShapeCorners, SyntheticRooms.lShapeCorners.reversed()] {
            let tris = Polygon2D.triangulate(poly)
            XCTAssertEqual(tris.count, poly.count - 2)
            let area = tris.reduce(0.0) { $0 + Polygon2D.area([poly[$1.0], poly[$1.1], poly[$1.2]]) }
            XCTAssertEqual(area, Polygon2D.area(poly), accuracy: 1e-9, "les triangles recouvrent exactement le polygone")
        }
        XCTAssertTrue(Polygon2D.triangulate([Point2D(x: 0, y: 0), Point2D(x: 1, y: 0)]).isEmpty)
    }

    func testProjectionFlipsZ() {
        let p = Point2D(projecting: SIMD3<Float>(1, 5, 2))
        XCTAssertEqual(p, Point2D(x: 1, y: -2))
    }

    func testTriangulationSkipsFlatLastTripletAndReportsDegenerateContours() {
        // Rectangle with a vertex aligned on one side: last triplet can be flat.
        let pts = [Point2D(x: 0, y: 0), Point2D(x: 2, y: 0), Point2D(x: 4, y: 0), Point2D(x: 4, y: 3), Point2D(x: 0, y: 3)]
        let (tris, complete) = Polygon2D.triangulation(pts)
        XCTAssertTrue(complete)
        for t in tris {
            let a = pts[t.0], b = pts[t.1], c = pts[t.2]
            XCTAssertGreaterThan(abs(Polygon2D.signedArea([a, b, c])), 1e-9, "aucun triangle plat")
        }
        XCTAssertEqual(tris.reduce(0.0) { $0 + abs(Polygon2D.signedArea([pts[$1.0], pts[$1.1], pts[$1.2]])) }, 12, accuracy: 1e-9)
        // Degenerate contour (all collinear): incomplete, no triangle.
        let flat = [Point2D(x: 0, y: 0), Point2D(x: 1, y: 0), Point2D(x: 2, y: 0), Point2D(x: 3, y: 0)]
        let r = Polygon2D.triangulation(flat)
        XCTAssertFalse(r.complete); XCTAssertTrue(r.triangles.isEmpty)
    }

    // MARK: - Polygon union and intersection (house floor area)

    private func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double) -> [Point2D] {
        [Point2D(x: x0, y: y0), Point2D(x: x1, y: y0), Point2D(x: x1, y: y1), Point2D(x: x0, y: y1)]
    }

    func testUnionOfDisjointPolygonsIsTheSum() {
        let a = rect(0, 0, 1, 1), b = rect(2, 0, 3, 1)
        XCTAssertEqual(Polygon2D.unionArea([a, b]), 2, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.intersectionArea([a, b]), 0, accuracy: 1e-9)
    }

    func testUnionOfIdenticalPolygonsIsOneOfThem() {
        let a = rect(0, 0, 2, 3)
        XCTAssertEqual(Polygon2D.unionArea([a, a, a]), 6, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.intersectionArea([a, a]), 6, accuracy: 1e-9)
    }

    func testUnionSubtractsThePairwiseOverlap() {
        // [0,1]² et [0.5,1.5]×[0,1] : recouvrement de 0,5.
        let a = rect(0, 0, 1, 1), b = rect(0.5, 0, 1.5, 1)
        XCTAssertEqual(Polygon2D.intersectionArea([a, b]), 0.5, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([a, b]), 1.5, accuracy: 1e-9)
    }

    /// Case distinguishing full inclusion-exclusion from simple pairwise subtraction
    /// of overlaps: three squares sharing the same area. Sum 3,
    /// recouvrements deux à deux 0,5 + 0,5 + 0,25, zone triple 0,25 ⇒ union = 2.
    /// An implementation stopping at pairs would return 1.75.
    func testUnionHandlesARegionSharedByThreePolygons() {
        let a = rect(0, 0, 1, 1), b = rect(0.5, 0, 1.5, 1), c = rect(0, 0.5, 1, 1.5)
        XCTAssertEqual(Polygon2D.intersectionArea([a, b, c]), 0.25, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([a, b, c]), 2, accuracy: 1e-9)
    }

    func testUnionOfConcavePolygons() {
        // L renversé : [0,2]×[0,1] ∪ [0,1]×[0,2] décrit d'un seul tenant (aire 3),
        // union with missing square [1,2]x[1,2] => solid square 2x2.
        let l = [Point2D(x: 0, y: 0), Point2D(x: 2, y: 0), Point2D(x: 2, y: 1),
                 Point2D(x: 1, y: 1), Point2D(x: 1, y: 2), Point2D(x: 0, y: 2)]
        XCTAssertEqual(Polygon2D.area(l), 3, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([l, rect(1, 1, 2, 2)]), 4, accuracy: 1e-9)
    }

    func testUnionIgnoresDegeneratePolygons() {
        let a = rect(0, 0, 1, 1)
        XCTAssertEqual(Polygon2D.unionArea([a, [], [Point2D(x: 5, y: 5), Point2D(x: 6, y: 6)]]), 1, accuracy: 1e-9)
        XCTAssertEqual(Polygon2D.unionArea([]), 0)
    }

    func testUnionOfTenOverlappingRooms() {
        let rooms = (0..<10).map { rect(Double($0), 0, Double($0) + 2, 3) }
        XCTAssertEqual(Polygon2D.unionArea(rooms), 33, accuracy: 0.01)
        XCTAssertEqual(Polygon2D.unionArea(Array(repeating: rect(0, 0, 4, 3), count: 10)), 12, accuracy: 0.01)
        XCTAssertEqual(Polygon2D.unionArea(Array(rooms.reversed())), 33, accuracy: 0.01)
    }

    func testClipByConvexKeepsTheCommonPart() {
        let clipped = Polygon2D.clip(rect(0, 0, 2, 2), byConvex: rect(1, 1, 3, 3))
        XCTAssertEqual(Polygon2D.area(clipped), 1, accuracy: 1e-9)
    }
}
