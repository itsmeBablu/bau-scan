import Foundation

/// 2D plan in DXF **R12 ASCII** (AC1009): standard common denominator read by AutoCAD,
/// LibreCAD, QCAD, SketchUp, Fusion, Illustrator... Units in meters (`$INSUNITS` = 6),
/// Y up coordinates, one layer per element category.
/// R12 does not support LWPOLYLINE or simple DIMENSION: walls and objects are
/// closed POLYLINEs, dimensions are LINE + TEXT.
struct DXFExporter {
    var locale: Locale = .current
    var textHeight = 0.12  // m
    var unit: MeasurementUnit = .both

    enum Layer: String, CaseIterable {
        case walls = "WALLS", doors = "DOORS", windows = "WINDOWS", openings = "OPENINGS"
        case floor = "FLOOR", objects = "OBJECTS", dimensions = "DIMENSIONS", text = "TEXT"
        /// ACI color index.
        var color: Int {
            switch self {
            case .walls: 7; case .doors: 3; case .windows: 5; case .openings: 8
            case .floor: 254; case .objects: 8; case .dimensions: 4; case .text: 2
            }
        }
    }

    func dxf(for house: House) -> String {
        var e = Entities(fmt: fmt)
        let renderer = PlanRenderer()
        for room in house.allRooms {
            let t = room.transform
            let side = PlanRenderer.InteriorSide(polygon: room.floorPolygon, fallback: room.bounds.center)
            if room.floorPolygon.count >= 3 { e.polyline(room.floorPolygon.map(t.apply), layer: .floor) }
            for wall in room.walls {
                let ops = room.openings.filter { $0.wallID == wall.id }
                for piece in renderer.wallPieces(wall, openings: ops) {
                    let n = piece.leftNormal * (wall.thickness / 2)
                    e.polyline([piece.start + n, piece.end + n, piece.end - n, piece.start - n].map(t.apply), layer: .walls)
                }
                let seg = wall.segment
                guard seg.length >= PlanRenderer.minimumDimensionedLength else { continue }
                let outward = side.inward(of: seg) * -1
                let off = outward * PlanRenderer.dimensionOffset
                let a = seg.start + off, b = seg.end + off
                e.line(t.apply(a), t.apply(b), layer: .dimensions)
                e.line(t.apply(seg.start + outward * 0.05), t.apply(a + outward * 0.06), layer: .dimensions)
                e.line(t.apply(seg.end + outward * 0.05), t.apply(b + outward * 0.06), layer: .dimensions)
                // Oblique tick marks (architectural convention) at endpoints.
                let d = seg.direction * 0.04, nn = outward * 0.04
                e.line(t.apply(a - d - nn), t.apply(a + d + nn), layer: .dimensions)
                e.line(t.apply(b - d - nn), t.apply(b + d + nn), layer: .dimensions)
                let pos = t.apply(seg.midpoint + outward * (PlanRenderer.dimensionOffset + 0.10))
                e.text(MeasurementFormat.length(wall.length, unit: unit, locale: locale), at: pos, angle: readable(seg.angle + t.rotation), height: textHeight, layer: .dimensions)
            }
            for o in room.openings {
                let seg = o.segment
                let inward = side.inward(of: seg)
                let outward = inward * -1
                let ang = readable(seg.angle + t.rotation)
                switch o.kind {
                case .door:
                    let hinge = seg.start, leafEnd = hinge + inward * o.width
                    e.line(t.apply(hinge), t.apply(leafEnd), layer: .doors)
                    let a1 = atan2(seg.end.y - hinge.y, seg.end.x - hinge.x) + t.rotation
                    let a2 = atan2(leafEnd.y - hinge.y, leafEnd.x - hinge.x) + t.rotation
                    e.arc(center: t.apply(hinge), radius: o.width, from: a1, to: a2, layer: .doors)
                case .window:
                    let n = seg.leftNormal * (FloorPlan.defaultWallThickness * 0.3)
                    e.line(t.apply(seg.start + n), t.apply(seg.end + n), layer: .windows)
                    e.line(t.apply(seg.start - n), t.apply(seg.end - n), layer: .windows)
                    e.line(t.apply(seg.start + n), t.apply(seg.start - n), layer: .windows)
                    e.line(t.apply(seg.end + n), t.apply(seg.end - n), layer: .windows)
                    let parText = MeasurementFormat.parapetHeight(o.sillHeight, unit: unit, locale: locale)
                    e.text(parText, at: t.apply(seg.midpoint + inward * 0.16), angle: ang, height: textHeight * 0.7, layer: .windows)
                case .opening:
                    e.line(t.apply(seg.start), t.apply(seg.end), layer: .openings)
                }

                // Dimension line across opening with tick marks (Image 1 reference):
                let dimOffset = outward * 0.18
                let dStart = seg.start + dimOffset, dEnd = seg.end + dimOffset
                e.line(t.apply(dStart), t.apply(dEnd), layer: .dimensions)
                let tick = (seg.direction + outward).normalized * 0.04
                e.line(t.apply(dStart - tick), t.apply(dStart + tick), layer: .dimensions)
                e.line(t.apply(dEnd - tick), t.apply(dEnd + tick), layer: .dimensions)

                // Top (width above line):
                let wText = MeasurementFormat.openingWidth(o.width, unit: unit, locale: locale)
                e.text(wText, at: t.apply(seg.midpoint + outward * 0.25), angle: ang, height: textHeight * 0.7, layer: .dimensions)

                // Bottom (height below line):
                let hText = MeasurementFormat.openingHeight(o.height, unit: unit, locale: locale)
                e.text(hText, at: t.apply(seg.midpoint + outward * 0.11), angle: ang, height: textHeight * 0.7, layer: .dimensions)
            }
            // Room name and m² area
            let center = Polygon2D.interiorPoint(room.floorPolygon, fallback: room.bounds.center)
            let name = room.name.isEmpty ? RoomNaming.defaultBaseName(room.label) : room.name
            let area = Polygon2D.area(room.floorPolygon)
            let areaStr = MeasurementFormat.squareMeters(area, locale: locale)
            e.text(name, at: t.apply(Point2D(x: center.x, y: center.y + 0.10)), angle: readable(t.rotation), height: textHeight, layer: .text)
            e.text(areaStr, at: t.apply(Point2D(x: center.x, y: center.y - 0.10)), angle: readable(t.rotation), height: textHeight * 0.8, layer: .text)
            for o in room.objects {
                let c = cos(o.angle), s = sin(o.angle), hw = o.size.width / 2, hd = o.size.depth / 2
                let corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, y) in Point2D(x: o.center.x + x * c - y * s, y: o.center.y + x * s + y * c) }
                e.polyline(corners.map(t.apply), layer: .objects)
                e.text(ObjectNaming.localizedName(o.category), at: t.apply(o.center), angle: readable(o.angle + t.rotation), height: textHeight * 0.8, layer: .text)
            }
        }
        let b = house.bounds.insetBy(PlanRenderer.dimensionMargin)
        var out = ""
        out += header(bounds: b.isEmpty ? Rect2D(minX: 0, minY: 0, maxX: 1, maxY: 1) : b)
        out += tables()
        out += "0\nSECTION\n2\nENTITIES\n" + e.body + "0\nENDSEC\n"
        out += "0\nEOF\n"
        return out
    }

    /// File bytes: R12 does not support Unicode; declared as `$DWGCODEPAGE` ANSI_1252 and
    /// encoded in CP1252.
    func data(for house: House) -> Data {
        let text = dxf(for: house)
        return text.data(using: .windowsCP1252, allowLossyConversion: true) ?? Data(text.utf8)
    }

    // MARK: sections

    private func header(bounds b: Rect2D) -> String {
        """
        0\nSECTION\n2\nHEADER
        9\n$ACADVER\n1\nAC1009
        9\n$INSUNITS\n70\n6
        9\n$DWGCODEPAGE\n3\nANSI_1252
        9\n$EXTMIN\n10\n\(fmt(b.minX))\n20\n\(fmt(b.minY))\n30\n0
        9\n$EXTMAX\n10\n\(fmt(b.maxX))\n20\n\(fmt(b.maxY))\n30\n0
        0\nENDSEC\n
        """
    }

    private func tables() -> String {
        var s = "0\nSECTION\n2\nTABLES\n"
        s += "0\nTABLE\n2\nLTYPE\n70\n1\n0\nLTYPE\n2\nCONTINUOUS\n70\n0\n3\nFloorid line\n72\n65\n73\n0\n40\n0\n0\nENDTAB\n"
        s += "0\nTABLE\n2\nLAYER\n70\n\(Layer.allCases.count)\n"
        for l in Layer.allCases { s += "0\nLAYER\n2\n\(l.rawValue)\n70\n0\n62\n\(l.color)\n6\nCONTINUOUS\n" }
        s += "0\nENDTAB\n"
        s += "0\nTABLE\n2\nSTYLE\n70\n1\n0\nSTYLE\n2\nSTANDARD\n70\n0\n40\n0\n41\n1\n50\n0\n71\n0\n42\n0.2\n3\ntxt\n4\n\n0\nENDTAB\n"
        s += "0\nENDSEC\n"
        return s
    }

    private struct Entities {
        var fmt: (Double) -> String
        var body = ""
        mutating func line(_ a: Point2D, _ b: Point2D, layer: Layer) {
            body += "0\nLINE\n8\n\(layer.rawValue)\n10\n\(fmt(a.x))\n20\n\(fmt(a.y))\n30\n0\n11\n\(fmt(b.x))\n21\n\(fmt(b.y))\n31\n0\n"
        }
        mutating func polyline(_ pts: [Point2D], layer: Layer) {
            guard pts.count >= 2 else { return }
            // R12 requires a dummy coordinate point (10/20/30 zero) on POLYLINE before VERTEX.
            body += "0\nPOLYLINE\n8\n\(layer.rawValue)\n10\n0.0\n20\n0.0\n30\n0.0\n66\n1\n70\n1\n"
            for p in pts { body += "0\nVERTEX\n8\n\(layer.rawValue)\n10\n\(fmt(p.x))\n20\n\(fmt(p.y))\n30\n0\n" }
            body += "0\nSEQEND\n8\n\(layer.rawValue)\n"
        }
        /// Counterclockwise arc from `from` to `to` (radians); DXF requires this orientation.
        mutating func arc(center c: Point2D, radius r: Double, from a1: Double, to a2: Double, layer: Layer) {
            var d = a2 - a1
            while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
            let (s, e) = d >= 0 ? (a1, a2) : (a2, a1)
            body += "0\nARC\n8\n\(layer.rawValue)\n10\n\(fmt(c.x))\n20\n\(fmt(c.y))\n30\n0\n40\n\(fmt(r))\n50\n\(fmt(deg(s)))\n51\n\(fmt(deg(e)))\n"
        }
        mutating func text(_ raw: String, at p: Point2D, angle: Double, height: Double, layer: Layer) {
            // Thin / non-breaking spaces converted to standard space for CP1252 compatibility.
            let str = raw.replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
            // 72=1: horizontally centered on second point (11/21); 73=2: vertically centered.
            body += "0\nTEXT\n8\n\(layer.rawValue)\n10\n\(fmt(p.x))\n20\n\(fmt(p.y))\n30\n0\n40\n\(fmt(height))\n1\n\(str)\n50\n\(fmt(deg(angle)))\n72\n1\n11\n\(fmt(p.x))\n21\n\(fmt(p.y))\n31\n0\n73\n2\n"
        }
        private func deg(_ r: Double) -> Double { var d = r * 180 / .pi; while d < 0 { d += 360 }; while d >= 360 { d -= 360 }; return d }
    }

    private func fmt(_ v: Double) -> String {
        let r = (v * 10000).rounded() / 10000
        return String(format: "%.4f", locale: Locale(identifier: "en_US_POSIX"), r == 0 ? 0 : r)
    }
    /// Angle normalized to ]-90°, 90°] for readable orientation.
    private func readable(_ a: Double) -> Double {
        var x = a; while x > .pi / 2 { x -= .pi }; while x <= -.pi / 2 { x += .pi }; return x
    }
}
