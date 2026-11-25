import Foundation

/// 2D plan in SVG: units in **millimeters** (1 unit = 1 mm), layers in `<g id>`.
/// SVG coordinate system Y down: y_svg = (maxY - y_plan). Readable in Illustrator,
/// Figma, Inkscape, and web browsers.
struct SVGExporter {
    var locale: Locale = AppLanguage.locale
    var margin = 0.6  // margin around plan in meters (for dimension lines)
    var unit: MeasurementUnit = .both

    func svg(for house: House) -> String {
        let rooms = house.allRooms
        let b = house.bounds.insetBy(margin)
        guard !b.isEmpty else { return emptyDocument() }
        let W = mm(b.width), H = mm(b.height)
        let graph = HouseWallGraph(house: house)
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(W)mm" height="\(H)mm" viewBox="0 0 \(W) \(H)" font-family="sans-serif">
        <title>\(esc(house.name))</title>
        <desc>dWalkScan — millimetres</desc>

        """
        func X(_ p: Point2D, _ t: Transform2D) -> String { let q = t.apply(p); return mm(q.x - b.minX) }
        func Y(_ p: Point2D, _ t: Transform2D) -> String { let q = t.apply(p); return mm(b.maxY - q.y) }
        func line(_ s: Segment2D, _ t: Transform2D, _ attrs: String) -> String {
            "  <line x1=\"\(X(s.start, t))\" y1=\"\(Y(s.start, t))\" x2=\"\(X(s.end, t))\" y2=\"\(Y(s.end, t))\" \(attrs)/>\n"
        }
        func poly(_ pts: [Point2D], _ t: Transform2D, _ attrs: String) -> String {
            "  <polygon points=\"" + pts.map { "\(X($0, t)),\(Y($0, t))" }.joined(separator: " ") + "\" \(attrs)/>\n"
        }

        var floors = "", walls = "", doors = "", windows = "", openings = "", objects = "", dims = "", texts = ""
        let hiddenDoors = PlanRenderer.duplicateDoorIndices(in: rooms)
        for solid in ResolvedWallGeometry.solids(house: house, graph: graph) where solid.bottom == 0 {
            walls += poly(solid.footprint, .identity, "fill=\"#111110\" stroke=\"none\"")
        }
        for room in rooms {
            let t = room.transform
            let side = PlanRenderer.InteriorSide(polygon: room.floorPolygon, fallback: room.bounds.center)
            if room.floorPolygon.count >= 3 { floors += poly(room.floorPolygon, t, "data-role=\"room-floor\" fill=\"#fef3c7\" stroke=\"none\"") }
            for wall in room.walls {
                // Cote
                let seg = wall.segment
                guard seg.length >= PlanRenderer.minimumDimensionedLength else { continue }
                let outward = side.inward(of: seg) * -1
                let a = seg.start + outward * PlanRenderer.dimensionOffset, c = seg.end + outward * PlanRenderer.dimensionOffset
                dims += line(Segment2D(start: a, end: c), t, "stroke=\"#facc15\" stroke-width=\"12\" marker-start=\"url(#arrow)\" marker-end=\"url(#arrow)\"")
                dims += line(Segment2D(start: seg.start + outward * 0.05, end: a + outward * 0.06), t, "stroke=\"#facc15\" stroke-width=\"8\"")
                dims += line(Segment2D(start: seg.end + outward * 0.05, end: c + outward * 0.06), t, "stroke=\"#facc15\" stroke-width=\"8\"")
                let label = MeasurementFormat.length(wall.length, unit: unit, locale: locale)
                let pos = seg.midpoint + outward * (PlanRenderer.dimensionOffset + 0.16)
                let q = t.apply(pos)
                var angle = -(seg.angle + t.rotation) * 180 / .pi
                while angle > 90 { angle -= 180 }; while angle <= -90 { angle += 180 }
                texts += "  <text x=\"\(mm(q.x - b.minX))\" y=\"\(mm(b.maxY - q.y))\" font-size=\"120\" fill=\"#272000\" text-anchor=\"middle\" dominant-baseline=\"middle\" transform=\"rotate(\(fmt(angle)) \(mm(q.x - b.minX)) \(mm(b.maxY - q.y)))\">\(esc(label))</text>\n"
            }
            for (index, o) in room.openings.enumerated() where !(hiddenDoors[room.id]?.contains(index) ?? false) {
                let seg = o.segment
                let inward = side.inward(of: seg)
                let outward = inward * -1
                var angle = -(seg.angle + t.rotation) * 180 / .pi
                while angle > 90 { angle -= 180 }; while angle <= -90 { angle += 180 }
                switch o.kind {
                case .door:
                    let leaf = Segment2D(start: seg.start, end: seg.start + inward * o.width)
                    doors += line(leaf, t, "stroke=\"#1a1a1a\" stroke-width=\"15\"")
                    // Door swing arc around the hinge
                    let r = mm(o.width)
                    let sweep = arcSweep(hinge: seg.start, from: seg.end, to: leaf.end, flipY: true)
                    doors += "  <path d=\"M \(X(seg.end, t)) \(Y(seg.end, t)) A \(r) \(r) 0 0 \(sweep) \(X(leaf.end, t)) \(Y(leaf.end, t))\" fill=\"none\" stroke=\"#1a1a1a\" stroke-width=\"10\" stroke-dasharray=\"50 40\"/>\n"
                case .window:
                    let n = seg.leftNormal * (graph.hostThickness(roomID: room.id, openingID: o.id) * 0.3)
                    windows += line(Segment2D(start: seg.start + n, end: seg.end + n), t, "stroke=\"#facc15\" stroke-width=\"15\"")
                    windows += line(Segment2D(start: seg.start - n, end: seg.end - n), t, "stroke=\"#facc15\" stroke-width=\"15\"")
                    let parText = MeasurementFormat.parapetHeight(o.sillHeight, unit: unit, locale: locale)
                    let pBRH = t.apply(seg.midpoint + inward * 0.16)
                    windows += "  <text x=\"\(mm(pBRH.x - b.minX))\" y=\"\(mm(b.maxY - pBRH.y))\" font-size=\"80\" fill=\"#272000\" text-anchor=\"middle\" dominant-baseline=\"middle\" transform=\"rotate(\(fmt(angle)) \(mm(pBRH.x - b.minX)) \(mm(b.maxY - pBRH.y)))\">\(esc(parText))</text>\n"
                case .opening:
                    openings += line(seg, t, "stroke=\"#1a1a1a\" stroke-width=\"12\" stroke-dasharray=\"80 60\"")
                }

                // Dimension line across opening with tick marks (Image 1 reference):
                let dimOffset = outward * 0.18
                let dStart = seg.start + dimOffset, dEnd = seg.end + dimOffset
                dims += line(Segment2D(start: dStart, end: dEnd), t, "stroke=\"#272000\" stroke-width=\"8\"")
                let tick = (seg.direction + outward).normalized * 0.04
                dims += line(Segment2D(start: dStart - tick, end: dStart + tick), t, "stroke=\"#272000\" stroke-width=\"8\"")
                dims += line(Segment2D(start: dEnd - tick, end: dEnd + tick), t, "stroke=\"#272000\" stroke-width=\"8\"")

                // Top (width above line):
                let wText = MeasurementFormat.openingWidth(o.width, unit: unit, locale: locale)
                let pW = t.apply(seg.midpoint + outward * 0.25)
                texts += "  <text x=\"\(mm(pW.x - b.minX))\" y=\"\(mm(b.maxY - pW.y))\" font-size=\"85\" fill=\"#272000\" text-anchor=\"middle\" dominant-baseline=\"middle\" transform=\"rotate(\(fmt(angle)) \(mm(pW.x - b.minX)) \(mm(b.maxY - pW.y)))\">\(esc(wText))</text>\n"

                // Bottom (height below line):
                let hText = MeasurementFormat.openingHeight(o.height, unit: unit, locale: locale)
                let pH = t.apply(seg.midpoint + outward * 0.11)
                texts += "  <text x=\"\(mm(pH.x - b.minX))\" y=\"\(mm(b.maxY - pH.y))\" font-size=\"85\" fill=\"#272000\" text-anchor=\"middle\" dominant-baseline=\"middle\" transform=\"rotate(\(fmt(angle)) \(mm(pH.x - b.minX)) \(mm(b.maxY - pH.y)))\">\(esc(hText))</text>\n"
            }
            // Room label (name + m² area)
            let center = Polygon2D.interiorPoint(room.floorPolygon, fallback: room.bounds.center)
            let q = t.apply(center)
            let name = room.name.isEmpty ? RoomNaming.defaultBaseName(room.label) : room.name
            let area = Polygon2D.area(room.floorPolygon)
            let areaStr = MeasurementFormat.squareMeters(area, locale: locale)
            texts += "  <text x=\"\(mm(q.x - b.minX))\" y=\"\(mm(b.maxY - q.y - 0.10))\" font-size=\"140\" font-weight=\"bold\" fill=\"#111110\" text-anchor=\"middle\" dominant-baseline=\"middle\">\(esc(name))</text>\n"
            texts += "  <text x=\"\(mm(q.x - b.minX))\" y=\"\(mm(b.maxY - q.y + 0.12))\" font-size=\"110\" fill=\"#272000\" text-anchor=\"middle\" dominant-baseline=\"middle\">\(esc(areaStr))</text>\n"
            for o in room.objects {
                let c = cos(o.angle), s = sin(o.angle), hw = o.size.width / 2, hd = o.size.depth / 2
                let corners = [(-hw, -hd), (hw, -hd), (hw, hd), (-hw, hd)].map { (x, y) in Point2D(x: o.center.x + x * c - y * s, y: o.center.y + x * s + y * c) }
                objects += poly(corners, t, "fill=\"#cccccc\" fill-opacity=\"0.5\" stroke=\"#737373\" stroke-width=\"12\"")
                let q = t.apply(o.center)
                objects += "  <text x=\"\(mm(q.x - b.minX))\" y=\"\(mm(b.maxY - q.y))\" font-size=\"110\" fill=\"#737373\" text-anchor=\"middle\" dominant-baseline=\"middle\">\(esc(ObjectNaming.localizedName(o.category)))</text>\n"
            }
        }
        out += """
        <defs>
          <marker id="arrow" viewBox="0 0 10 10" refX="1" refY="5" markerWidth="8" markerHeight="8" orient="auto-start-reverse">
            <path d="M 0 0 L 10 5 L 0 10 z" fill="#facc15"/>
          </marker>
        </defs>
        <g id="floors">\n\(floors)</g>
        <g id="objects">\n\(objects)</g>
        <g id="walls">\n\(walls)</g>
        <g id="doors">\n\(doors)</g>
        <g id="windows">\n\(windows)</g>
        <g id="openings">\n\(openings)</g>
        <g id="dimensions">\n\(dims)</g>
        <g id="text">\n\(texts)</g>
        </svg>

        """
        return out
    }

    func data(for house: House) -> Data { Data(svg(for: house).utf8) }

    // MARK: helpers

    private func emptyDocument() -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100mm\" height=\"100mm\" viewBox=\"0 0 100 100\"/>\n"
    }
    private func mm(_ m: Double) -> String { fmt(m * 1000) }
    private func fmt(_ v: Double) -> String {
        let r = (v * 10).rounded() / 10
        return r == r.rounded() ? String(Int(r)) : String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), r)
    }
    private func esc(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
    /// SVG sweep direction (0/1) for arc from `from` to `to` around `hinge`.
    private func arcSweep(hinge: Point2D, from: Point2D, to: Point2D, flipY: Bool) -> Int {
        let a1 = atan2(from.y - hinge.y, from.x - hinge.x), a2 = atan2(to.y - hinge.y, to.x - hinge.x)
        var d = a2 - a1
        while d > .pi { d -= 2 * .pi }; while d < -.pi { d += 2 * .pi }
        // In SVG (Y down), increasing plan angle becomes clockwise sweep (flag 0 = counterclockwise).
        let ccwInPlan = d > 0
        return (ccwInPlan != flipY) ? 1 : 0
    }
}
