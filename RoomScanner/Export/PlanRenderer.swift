import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Renders a dimensioned 2D plan in **pure Core Graphics** — identical on iOS and macOS.
/// Used for PDF, PNG, thumbnail, viewer floor texture, and
/// printing. Input units: meters (plan coordinate system, Y up);
/// the CG context also has its origin at bottom-left, requiring no flipping.
struct PlanRenderer {
    enum Mode: Equatable {
        /// Sheet at standard scale (1:n), with or without title block.
        case page(titleBlock: Bool)
        /// Fills viewport (floor texture, thumbnail): unscaled, no title block.
        case fill
    }

    struct Options {
        var mode: Mode = .page(titleBlock: true)
        var locale: Locale = AppLanguage.locale
        var unit: MeasurementUnit = .meters
        var showDimensions = true
        var showOpeningDimensions = true
        var showRoomLabels = true
        var showObjects = true
        var showFloor = true
        /// Transparent background (texture) or white (sheet).
        var transparentBackground = false
        /// Neutral CAD palette; optional room tints remain an explicit presentation choice.
        var wallColor = CGColor(red: 17/255, green: 17/255, blue: 16/255, alpha: 1) // #111110
        var floorColor = CGColor(gray: 0.97, alpha: 1)
        var dimensionColor = CGColor(gray:0.18,alpha:1)
        var dimensionLineColor = CGColor(gray: 0.45, alpha: 1)
        var objectFill = CGColor(gray: 0.90, alpha: 0.5)
        var objectStroke = CGColor(gray:0.30,alpha:1)
        var textColor = CGColor(red: 17/255, green: 17/255, blue: 16/255, alpha: 1) // #111110
        /// Multiplier for in-plan labels and dimensions. The interactive 2D viewer exposes this to users.
        var textScale: CGFloat = 1
        var showLabelBackground = false
        var windowColor = CGColor(gray: 0.28, alpha: 1)
        /// House: each room receives a distinct floor tint (`PlanRenderer.roomTint`).
        var tintRooms = false
    }

    /// Pastel floor tints to distinguish rooms of a house (cycle of 6 in warm yellow/cream tones).
    static let roomPalette: [CGColor] = [
        CGColor(red: 254/255, green: 243/255, blue: 199/255, alpha: 1),
        CGColor(red: 254/255, green: 240/255, blue: 138/255, alpha: 1),
        CGColor(red: 253/255, green: 230/255, blue: 138/255, alpha: 1),
        CGColor(red: 254/255, green: 249/255, blue: 195/255, alpha: 1),
        CGColor(red: 250/255, green: 204/255, blue: 21/255, alpha: 0.35),
        CGColor(red: 255/255, green: 251/255, blue: 235/255, alpha: 1),
    ]
    static func roomTint(_ index: Int) -> CGColor { roomPalette[((index % roomPalette.count) + roomPalette.count) % roomPalette.count] }

    /// Room floor color: palette tint in multi-room houses, otherwise `floorColor`.
    func floorColor(forRoomAt index: Int, of count: Int) -> CGColor {
        options.tintRooms && count > 1 ? Self.roomTint(index) : options.floorColor
    }

    /// Standard architectural scale denominators.
    static let standardScales: [Double] = [10, 20, 25, 50, 75, 100, 200, 500]
    /// PostScript points per meter at 1:1 scale.
    static let pointsPerMeter = 72.0 / 0.0254

    /// Margin around plan (m) reserved for dimensions.
    static let dimensionMargin = 0.55
    static let dimensionOffset = 0.45
    /// Shorter walls (pillars, returns) are not dimensioned to avoid overlapping labels on real scans.
    static let minimumDimensionedLength = 0.5

    var options = Options()

    // MARK: - Outputs

    /// Vector PDF A4 landscape by default: one page per story (multi-level houses
    /// stacked on one sheet would be unreadable), single page for single rooms or stories.
    func pdfData(_ house: House, size: CGSize = CGSize(width: 842, height: 595), title: String? = nil) -> Data {
        let interval = PerformanceTrace.begin("PlanPDFRender")
        defer { interval.end() }
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var info: [CFString: Any] = [kCGPDFContextCreator: "dWalkScan"]
        if let title { info[kCGPDFContextTitle] = title }
        let ctx = CGContext(consumer: consumer, mediaBox: &box, info as CFDictionary)!
        for page in Self.pages(of: house) {
            ctx.beginPDFPage(nil)
            draw(page, in: ctx, size: size)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    /// Plan pages: entire house if single story, otherwise one 'house' per level,
    /// named 'House — Level' for the title block.
    static func pages(of house: House) -> [House] {
        guard house.stories.count > 1 else { return [house] }
        return house.stories.map { story in
            House(id: house.id, name: "\(house.name) — \(StoryNaming.localizedName(for: story.index))", stories: [story])
        }
    }

    /// RGBA bitmap image (`makeImage`) of `pixels` pixels.
    func image(_ house: House, pixels: CGSize) -> CGImage? {
        let w = Int(pixels.width.rounded()), h = Int(pixels.height.rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        draw(house, in: ctx, size: pixels)
        return ctx.makeImage()
    }

    /// Image of a *page* (points) rendered at `pixelScale` × : scale calculation
    /// is done in points, keeping 'Scale 1:n' exact regardless of pixel density.
    /// Bitmap of a page; for multi-story houses, pages are stacked vertically.
    func image(_ house: House, pageSize: CGSize, pixelScale: CGFloat) -> CGImage? {
        let pages = Self.pages(of: house)
        let w = Int((pageSize.width * pixelScale).rounded()), h = Int((pageSize.height * pixelScale).rounded()) * pages.count
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: pixelScale, y: pixelScale)
        for (i, page) in pages.enumerated() {
            ctx.saveGState()
            // Core Graphics bottom-left origin: first page is at top of image.
            ctx.translateBy(x: 0, y: CGFloat(pages.count - 1 - i) * pageSize.height)
            draw(page, in: ctx, size: pageSize)
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    func pngData(_ house: House, pageSize: CGSize, pixelScale: CGFloat) -> Data? {
        image(house, pageSize: pageSize, pixelScale: pixelScale).flatMap(Self.encodePNG)
    }

    /// PNG of `pixels` pixels.
    func pngData(_ house: House, pixels: CGSize) -> Data? {
        image(house, pixels: pixels).flatMap(Self.encodePNG)
    }

    static func encodePNG(_ img: CGImage) -> Data? {
        let data = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(data as CFMutableData, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, img, nil)
        return CGImageDestinationFinalize(dest) ? data as Data : nil
    }

    // MARK: - Scale

    /// Largest standard scale (smallest `n`) such that the plan and its
    /// dimensions fit within `area` (points).
    static func standardScale(fitting bounds: Rect2D, into area: CGSize) -> Double {
        let w = bounds.width + 2 * dimensionMargin, h = bounds.height + 2 * dimensionMargin
        for n in standardScales {
            let ppm = pointsPerMeter / n
            if w * ppm <= Double(area.width), h * ppm <= Double(area.height) { return n }
        }
        return standardScales.last!
    }

    // MARK: - Drawing

    /// Draws the house into `ctx`, sized `size` (points or pixels).
    func draw(_ house: House, in ctx: CGContext, size: CGSize) {
        let interval = PerformanceTrace.begin("PlanDraw")
        defer { interval.end() }
        let rooms = house.allRooms
        if !options.transparentBackground {
            ctx.setFillColor(CGColor(gray: 1, alpha: 1))
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        // Drawing area: reserves title block at bottom if requested.
        let titleHeight: CGFloat = options.mode == .page(titleBlock: true) ? min(size.height * 0.16, 96) : 0
        let inset: CGFloat = options.mode == .fill ? size.width * 0.02 : min(size.width, size.height) * 0.05
        let area = CGRect(x: inset, y: titleHeight + inset, width: size.width - 2 * inset, height: size.height - titleHeight - 2 * inset)

        var bounds = Rect2D.empty
        for r in rooms { bounds = r.bounds.isEmpty ? bounds : merge(bounds, transformed(r.bounds, r.transform)) }
        guard !bounds.isEmpty else {
            if titleHeight > 0 { drawTitleBlock(house, rooms: rooms, scaleDenominator: nil, in: ctx, size: size, height: titleHeight) }
            return
        }

        let margin = options.showDimensions ? Self.dimensionMargin : 0.15
        let ppm: Double
        var scaleDenominator: Double? = nil
        switch options.mode {
        case .page:
            let n = Self.standardScale(fitting: bounds.insetBy(margin - Self.dimensionMargin), into: area.size)
            ppm = Self.pointsPerMeter / n; scaleDenominator = n
        case .fill:
            ppm = min(Double(area.width) / (bounds.width + 2 * margin), Double(area.height) / (bounds.height + 2 * margin))
        }
        // Centers the plan within the drawing area.
        let planW = (bounds.width + 2 * margin) * ppm, planH = (bounds.height + 2 * margin) * ppm
        let origin = CGPoint(x: area.midX - planW / 2 + margin * ppm - bounds.minX * ppm,
                             y: area.midY - planH / 2 + margin * ppm - bounds.minY * ppm)
        let mapper = Mapper(origin: origin, ppm: ppm)

        let hiddenDoors = Self.duplicateDoorIndices(in:rooms)
        for (i, room) in rooms.enumerated() { drawFloor(room, mapper: mapper, color: floorColor(forRoomAt: i, of: rooms.count), in: ctx) }
        let graph = HouseWallGraph(house: house)
        drawResolvedWalls(house, graph: graph, mapper: mapper, in: ctx)
        for (i, room) in rooms.enumerated() { drawRoom(room, mapper: mapper, floor: floorColor(forRoomAt: i, of: rooms.count), graph:graph,hiddenDoors:hiddenDoors[room.id] ?? [],in:ctx) }
        if titleHeight > 0 { drawTitleBlock(house, rooms: rooms, scaleDenominator: scaleDenominator, in: ctx, size: size, height: titleHeight) }
    }

    /// Floor texture for the viewer: rooms are drawn such that
    /// `bounds` (m, house coordinates) exactly covers the image — no margin, no
    /// title block. `pixelsPerMeter` sets resolution.
    func floorTextureImage(_ house: House, bounds: Rect2D, pixelsPerMeter: Double) -> CGImage? {
        let w = Int((bounds.width * pixelsPerMeter).rounded()), h = Int((bounds.height * pixelsPerMeter).rounded())
        guard w > 0, h > 0,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let mapper = Mapper(origin: CGPoint(x: -bounds.minX * pixelsPerMeter, y: -bounds.minY * pixelsPerMeter), ppm: pixelsPerMeter)
        let rooms = house.allRooms
        var r = self
        r.options.showDimensions = false
        r.options.showOpeningDimensions = false
        r.options.showRoomLabels = true
        let hiddenDoors = Self.duplicateDoorIndices(in:rooms)
        for (i, room) in rooms.enumerated() { r.drawFloor(room, mapper: mapper, color: floorColor(forRoomAt: i, of: rooms.count), in: ctx) }
        let graph = HouseWallGraph(house: house)
        r.drawResolvedWalls(house, graph: graph, mapper: mapper, in: ctx)
        for (i, room) in rooms.enumerated() { r.drawRoom(room, mapper: mapper, floor: floorColor(forRoomAt: i, of: rooms.count), graph:graph,hiddenDoors:hiddenDoors[room.id] ?? [],in:ctx) }
        return ctx.makeImage()
    }

    /// Plan (m) → context (pt/px) mapping, applying room transform within the house.
    struct Mapper {
        var origin: CGPoint
        var ppm: Double
        var transform: Transform2D = .identity
        func point(_ p: Point2D) -> CGPoint {
            let q = transform.apply(p)
            return CGPoint(x: origin.x + q.x * ppm, y: origin.y + q.y * ppm)
        }
        func length(_ m: Double) -> CGFloat { CGFloat(m * ppm) }
    }

    private func drawResolvedWalls(_ house: House, graph: HouseWallGraph, mapper: Mapper, in ctx: CGContext) {
        ctx.setFillColor(options.wallColor)
        for solid in ResolvedWallGeometry.solids(house: house, graph: graph) where solid.bottom == 0 {
            path(solid.footprint, mapper: mapper, in: ctx)
            ctx.fillPath()
        }
    }

    private func drawFloor(_ room: FloorPlan, mapper base: Mapper, color: CGColor, in ctx: CGContext) {
        guard options.showFloor, room.floorPolygon.count >= 3 else { return }
        var mapper = base
        mapper.transform = room.transform
        ctx.setFillColor(color)
        path(room.floorPolygon, mapper: mapper, in: ctx)
        ctx.fillPath()
    }
    private func drawRoom(_ room: FloorPlan, mapper base: Mapper, floor floorColor: CGColor, graph:HouseWallGraph,hiddenDoors:Set<Int> = [],in ctx: CGContext) {
        var mapper = base; mapper.transform = room.transform
        let side = InteriorSide(polygon: room.floorPolygon, fallback: room.bounds.center)

        // Floor
        if options.showFloor, room.floorPolygon.count >= 3 {
            ctx.setFillColor(floorColor)
            path(room.floorPolygon, mapper: mapper, in: ctx); ctx.fillPath()
        }
        // Objects
        if options.showObjects {
            for o in room.objects { drawObject(o, mapper: mapper, in: ctx) }
        }
        // Doors / windows / openings
        for (index,o) in room.openings.enumerated() where !hiddenDoors.contains(index) {
            drawOpening(PlanOpeningPlacement.window(o,in:room,graph:graph),side:side,mapper:mapper,
                        thickness:graph.hostThickness(roomID:room.id,openingID:o.id),in:ctx)
        }
        // Dimensions
        if options.showDimensions {
            for wall in room.walls { drawDimension(wall, side: side, mapper: mapper, in: ctx) }
        }
        // Room label (name + m² area)
        if options.showRoomLabels {
            drawRoomLabel(room, mapper: mapper, in: ctx)
        }
    }

    /// A shared doorway may be captured from each adjoining room. Keep one swing
    /// symbol without altering either room's wall cutout or measured opening.
    static func duplicateDoorIndices(in rooms: [FloorPlan]) -> [UUID: Set<Int>] {
        var shown: [(segment: Segment2D, story: Int)] = []
        var hidden: [UUID: Set<Int>] = [:]
        for room in rooms {
            for (index, opening) in room.openings.enumerated() where opening.kind == .door {
                let segment = Segment2D(start: room.transform.apply(opening.segment.start), end: room.transform.apply(opening.segment.end))
                let duplicate = shown.contains { previous in
                    guard previous.story == room.story,
                          abs(previous.segment.length - segment.length) < 0.10,
                          previous.segment.midpoint.distance(to: segment.midpoint) < 0.15 else { return false }
                    let a = previous.segment.direction, b = segment.direction
                    return abs(a.x * b.x + a.y * b.y) > 0.98
                }
                if duplicate { hidden[room.id, default: []].insert(index) }
                else { shown.append((segment, room.story)) }
            }
        }
        return hidden
    }

    /// Splits wall path around attached openings.
    func wallPieces(_ wall: Wall, openings: [Opening]) -> [Segment2D] {
        let len = wall.length
        guard len > 0 else { return [] }
        let dir = wall.segment.direction
        // Intervals [t0, t1] (m along wall) occupied by openings.
        var gaps: [(Double, Double)] = openings.map { o in
            let t = ((o.center.x - wall.start.x) * dir.x + (o.center.y - wall.start.y) * dir.y)
            return (max(0, t - o.width / 2), min(len, t + o.width / 2))
        }.filter { $0.1 > $0.0 }.sorted { $0.0 < $1.0 }
        var pieces: [Segment2D] = []
        var cursor = 0.0
        while !gaps.isEmpty {
            let g = gaps.removeFirst()
            if g.0 > cursor + 0.005 { pieces.append(Segment2D(start: wall.start + dir * cursor, end: wall.start + dir * g.0)) }
            cursor = max(cursor, g.1)
        }
        if cursor < len - 0.005 { pieces.append(Segment2D(start: wall.start + dir * cursor, end: wall.end)) }
        return pieces
    }

    private func drawOpening(_ o: Opening, side: InteriorSide, mapper: Mapper, thickness: Double, in ctx: CGContext) {
        let seg = o.segment
        let a = mapper.point(seg.start), b = mapper.point(seg.end)
        let n = seg.leftNormal
        let inward = side.inward(of: seg)
        let outward = inward * -1
        let thin = max(mapper.length(0.02), 0.8)
        let angle = readable(seg.angle)

        switch o.kind {
        case .door:
            // Door leaf open at 90° inward + swing arc from hinge (start).
            ctx.setStrokeColor(options.wallColor); ctx.setLineWidth(thin); ctx.setLineDash(phase: 0, lengths: [])
            let hinge = seg.start
            let leafEnd = hinge + inward * o.width
            ctx.move(to: mapper.point(hinge)); ctx.addLine(to: mapper.point(leafEnd)); ctx.strokePath()
            ctx.setLineWidth(thin * 0.8)
            ctx.setLineDash(phase: 0, lengths: [mapper.length(0.05), mapper.length(0.04)])
            let startAngle = atan2(seg.end.y - hinge.y, seg.end.x - hinge.x)
            let endAngle = atan2(leafEnd.y - hinge.y, leafEnd.x - hinge.x)
            let clockwise = normalizedDelta(from: startAngle, to: endAngle) < 0
            ctx.addArc(center: mapper.point(hinge), radius: mapper.length(o.width), startAngle: startAngle, endAngle: endAngle, clockwise: clockwise)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        case .window:
            // Plan cut: clear the solid wall band, then draw frame and glazing.
            // The sill remains in 3D; a floor-level wall fill must not hide glass.
            let half = n * (thickness / 2)
            let corners = [seg.start+half,seg.end+half,seg.end-half,seg.start-half]
            path(corners,mapper:mapper,in:ctx)
            ctx.setFillColor(CGColor(gray:1,alpha:1)); ctx.fillPath()
            ctx.setStrokeColor(options.windowColor); ctx.setLineWidth(thin); ctx.setLineDash(phase: 0, lengths: [])
            let off = n * (thickness * 0.15)
            for d in [half,half * -1,off,off * -1] {
                ctx.move(to: mapper.point(seg.start + d)); ctx.addLine(to: mapper.point(seg.end + d))
            }
            // End jambs tie the glazing symbol to the resolved wall band.
            for end in [seg.start, seg.end] {
                ctx.move(to: mapper.point(end + n * (thickness / 2)))
                ctx.addLine(to: mapper.point(end - n * (thickness / 2)))
            }
            ctx.strokePath()
        case .opening:
            // Cased opening (dashed line across opening).
            ctx.setStrokeColor(options.wallColor); ctx.setLineWidth(thin)
            ctx.setLineDash(phase: 0, lengths: [mapper.length(0.08), mapper.length(0.06)])
            ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        if options.showOpeningDimensions {
            let widthStr = MeasurementFormat.openingWidth(o.width, unit: options.unit, locale: options.locale)
            let heightStr = MeasurementFormat.openingHeight(o.height, unit: options.unit, locale: options.locale)
            let fontSize = max(min(mapper.length(0.16), 8.5), 3.2) * options.textScale
            let textSpacing = Double(fontSize) / mapper.ppm * 0.70 + 0.04

            // Opening dimension line (Image 1 reference):
            // Parallel to opening on outward side with oblique ticks at both ends
            let dimOffset = outward * 0.18
            let lineStart = seg.start + dimOffset
            let lineEnd = seg.end + dimOffset

            ctx.saveGState()
            ctx.setStrokeColor(options.dimensionColor)
            ctx.setLineWidth(max(mapper.length(0.008), 0.5))
            ctx.setLineDash(phase: 0, lengths: [])
            ctx.move(to: mapper.point(lineStart)); ctx.addLine(to: mapper.point(lineEnd))

            // Diagonal architectural tick marks at ends:
            let tick = (seg.direction + outward).normalized * 0.04
            ctx.move(to: mapper.point(lineStart - tick)); ctx.addLine(to: mapper.point(lineStart + tick))
            ctx.move(to: mapper.point(lineEnd - tick)); ctx.addLine(to: mapper.point(lineEnd + tick))
            ctx.strokePath()
            ctx.restoreGState()

            // A single opening-size label stays clear of both glazing and the
            // separate overall-wall dimension line.
            let posSize = seg.midpoint + outward * (0.18 + textSpacing)
            drawText(widthStr+" × "+heightStr, at: mapper.point(posSize), angle: angle, fontSize: fontSize, color: options.dimensionColor, in: ctx)

            // Window parapet height (Image 2 reference):
            // Centered on inward side (inside the room along the sill) with NO overlap
            if o.kind == .window {
                let parapetStr = MeasurementFormat.parapetHeight(o.sillHeight, unit: options.unit, locale: options.locale)
                let posBRH = seg.midpoint + inward * 0.23
                drawText(parapetStr, at: mapper.point(posBRH), angle: angle, fontSize: fontSize * 0.95, weight: .regular, color: options.dimensionColor, in: ctx)
            }
        }
    }

    private func drawRoomLabel(_ room: FloorPlan, mapper: Mapper, in ctx: CGContext) {
        guard options.showRoomLabels else { return }
        let center = Polygon2D.interiorPoint(room.floorPolygon, fallback: room.bounds.center)
        let pt = mapper.point(center)

        let name = room.name.isEmpty ? RoomNaming.defaultBaseName(room.label) : room.name
        let area = Polygon2D.area(room.floorPolygon)
        let areaStr = MeasurementFormat.squareMeters(area, locale: options.locale)

        let fontSize = max(min(mapper.length(0.30), 14), 8.5) * options.textScale
        let subFontSize = fontSize * 0.82

        // Optional quiet backing improves contrast over furniture; room tags
        // never have a border in the drawing or its exported versions.
        let textWidth = CGFloat(max(name.count, areaStr.count)) * fontSize * 0.65
        let pillW = max(mapper.length(1.3), textWidth + 20)
        let pillH = fontSize * 2.7 + 6
        let pillRect = CGRect(x: pt.x - pillW / 2, y: pt.y - pillH / 2, width: pillW, height: pillH)

        ctx.saveGState()
        let pillPath = CGPath(roundedRect: pillRect, cornerWidth: 8, cornerHeight: 8, transform: nil)
        ctx.addPath(pillPath)
        ctx.setFillColor(CGColor(red: 255/255, green: 255/255, blue: 255/255, alpha: 0.88))
        if options.showLabelBackground { ctx.fillPath() } else { ctx.beginPath() }
        ctx.restoreGState()

        drawText(name, at: CGPoint(x: pt.x, y: pt.y + fontSize * 0.45), angle: 0, fontSize: fontSize, weight: .bold, color: options.textColor, align: .center, in: ctx)
        drawText(areaStr, at: CGPoint(x: pt.x, y: pt.y - fontSize * 0.55), angle: 0, fontSize: subFontSize, weight: .regular, color: options.dimensionColor, align: .center, in: ctx)
    }

    private func drawObject(_ o: PlacedObject, mapper: Mapper, in ctx: CGContext) {
        let symbol = PlanFurnitureSymbol(o)
        ctx.setFillColor(options.objectFill); ctx.setStrokeColor(options.objectStroke)
        ctx.setLineWidth(max(mapper.length(0.015), 0.6)); ctx.setLineDash(phase: 0, lengths: [])
        path(symbol.footprint, mapper: mapper, in: ctx); ctx.drawPath(using: .fillStroke)
        if !symbol.detail.isEmpty {
            for segment in symbol.detail {
                ctx.move(to: mapper.point(segment.start))
                ctx.addLine(to: mapper.point(segment.end))
            }
            ctx.strokePath()
            return
        }
        let fontSize = max(min(mapper.length(0.22), 11), 4) * options.textScale
        if mapper.length(o.size.width) > fontSize * 2 {
            drawText(ObjectNaming.localizedName(o.category), at: mapper.point(o.center), angle: readable(o.angle),
                     fontSize: fontSize, color: options.objectStroke, in: ctx)
        }
    }

    private func drawDimension(_ wall: Wall, side: InteriorSide, mapper: Mapper, in ctx: CGContext) {
        let seg = wall.segment
        guard seg.length >= PlanRenderer.minimumDimensionedLength else { return }
        // Dimension line on exterior of wall.
        let n = seg.leftNormal
        let outward = side.inward(of: seg) * -1
        let off = outward * Self.dimensionOffset
        let a = seg.start + off, b = seg.end + off
        ctx.setStrokeColor(options.dimensionColor); ctx.setLineWidth(max(mapper.length(0.012), 0.6)); ctx.setLineDash(phase: 0, lengths: [])
        ctx.move(to: mapper.point(a)); ctx.addLine(to: mapper.point(b))
        // Witness lines and ends
        let tick = outward * 0.06
        for (p, q) in [(seg.start + outward * 0.05, a + tick), (seg.end + outward * 0.05, b + tick)] {
            ctx.move(to: mapper.point(p)); ctx.addLine(to: mapper.point(q))
        }
        ctx.strokePath()
        // Arrows (small filled triangles)
        let d = seg.direction
        let arrowLen = 0.09, arrowHalf = 0.03
        for (tip, back) in [(a, a + d * arrowLen), (b, b - d * arrowLen)] {
            let left = back + n * arrowHalf, right = back - n * arrowHalf
            ctx.setFillColor(options.dimensionColor)
            path([tip, left, right], mapper: mapper, in: ctx); ctx.fillPath()
        }
        let label = MeasurementFormat.length(wall.length, unit: options.unit, locale: options.locale)
        let fontSize = max(min(mapper.length(0.24), 12), 4) * options.textScale
        let textPos = seg.midpoint + off + outward * (0.12 + Double(fontSize) / mapper.ppm * 0.4)
        drawText(label, at: mapper.point(textPos), angle: readable(seg.angle), fontSize: fontSize, color: options.dimensionColor, in: ctx)
    }

    private func drawTitleBlock(_ house: House, rooms: [FloorPlan], scaleDenominator: Double?, in ctx: CGContext, size: CGSize, height: CGFloat) {
        let inset = min(size.width, size.height) * 0.05
        let rect = CGRect(x: inset, y: inset * 0.6, width: size.width - 2 * inset, height: height - inset * 0.2)
        ctx.setStrokeColor(CGColor(gray: 0.6, alpha: 1)); ctx.setLineWidth(0.8); ctx.setLineDash(phase: 0, lengths: [])
        ctx.stroke(rect)
        let loc = options.locale
        let area = HouseMeasurements(house:house).floorArea
        let perimeter = rooms.reduce(0) { $0 + $1.walls.reduce(0) { $0 + $1.length } }
        let ceil = (rooms.map { $0.ceilingHeight.lowerBound }.min() ?? 0)...(rooms.map { $0.ceilingHeight.upperBound }.max() ?? 0)
        let ceilText = abs(ceil.upperBound - ceil.lowerBound) < 0.02 ? MeasurementFormat.meters(ceil.lowerBound, locale: loc)
            : "\(MeasurementFormat.meters(ceil.lowerBound, locale: loc)) – \(MeasurementFormat.meters(ceil.upperBound, locale: loc))"
        let date = house.allRooms.isEmpty ? Date() : Date()
        let df = DateFormatter(); df.locale = loc; df.dateStyle = .medium; df.timeStyle = .none
        let big = min(rect.height * 0.30, 16), small = min(rect.height * 0.18, 9.5)
        let x = rect.minX + 10
        drawText(house.name, at: CGPoint(x: x, y: rect.maxY - big * 1.1), angle: 0, fontSize: big, weight: .bold, color: options.textColor, align: .left, in: ctx)
        let line1 = [String(localized: "plan.area", locale: loc) + " " + MeasurementFormat.squareMeters(area, locale: loc),
                     String(localized: "plan.perimeter", locale: loc) + " " + MeasurementFormat.meters(perimeter, locale: loc),
                     String(localized: "plan.ceiling", locale: loc) + " " + ceilText].joined(separator: "   ·   ")
        drawText(line1, at: CGPoint(x: x, y: rect.maxY - big * 1.1 - small * 1.6), angle: 0, fontSize: small, color: options.textColor, align: .left, in: ctx)
        var line2 = [df.string(from: date), "dWalkScan", String(localized: "plan.disclaimer", locale: loc)]
        if let n = scaleDenominator { line2.insert(String(localized: "plan.scale", locale: loc) + " 1:\(Int(n))", at: 0) }
        drawText(line2.joined(separator: "   ·   "), at: CGPoint(x: x, y: rect.minY + small * 0.8), angle: 0, fontSize: small, color: CGColor(gray: 0.4, alpha: 1), align: .left, in: ctx)
    }

    // MARK: - Text (Core Text)

    enum Align { case left, center }
    enum Weight { case regular, bold }

    func drawText(_ text: String, at p: CGPoint, angle: CGFloat, fontSize: CGFloat, weight: Weight = .regular,
                  color: CGColor, align: Align = .center, in ctx: CGContext) {
        let font = CTFontCreateUIFontForLanguage(weight == .bold ? .emphasizedSystem : .system, fontSize, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attrs))
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y)
        ctx.rotate(by: angle)
        ctx.textMatrix = .identity
        ctx.textPosition = CGPoint(x: align == .center ? -width / 2 : 0, y: -fontSize * 0.35)
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    /// Determines which side of a segment faces the room interior:
    /// point-in-polygon test 5 cm from midpoint (robust on L-shaped rooms),
    /// fallback to bounding box center.
    struct InteriorSide {
        let polygon: [Point2D]
        let fallback: Point2D
        func inward(of seg: Segment2D) -> Point2D {
            let n = seg.leftNormal
            if polygon.count >= 3 {
                let probe = seg.midpoint + n * 0.05
                if Polygon2D.contains(polygon, probe) { return n }
                if Polygon2D.contains(polygon, seg.midpoint - n * 0.05) { return n * -1 }
            }
            let toInterior = fallback - seg.midpoint
            return (n.x * toInterior.x + n.y * toInterior.y) >= 0 ? n : n * -1
        }
    }

    // MARK: - Helpers

    private func path(_ pts: [Point2D], mapper: Mapper, in ctx: CGContext) {
        guard let first = pts.first else { return }
        ctx.move(to: mapper.point(first))
        for p in pts.dropFirst() { ctx.addLine(to: mapper.point(p)) }
        ctx.closePath()
    }

    /// Angle normalized to ]−π/2, π/2] so text is never upside down.
    private func readable(_ angle: Double) -> CGFloat {
        var a = angle
        while a > .pi / 2 { a -= .pi }
        while a <= -.pi / 2 { a += .pi }
        return CGFloat(a)
    }

    private func normalizedDelta(from a: Double, to b: Double) -> Double {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return d
    }

    private func transformed(_ r: Rect2D, _ t: Transform2D) -> Rect2D {
        Rect2D.bounding([Point2D(x: r.minX, y: r.minY), Point2D(x: r.maxX, y: r.minY),
                         Point2D(x: r.maxX, y: r.maxY), Point2D(x: r.minX, y: r.maxY)].map(t.apply))
    }

    private func merge(_ a: Rect2D, _ b: Rect2D) -> Rect2D {
        if a.isEmpty { return b }
        if b.isEmpty { return a }
        return Rect2D(minX: min(a.minX, b.minX), minY: min(a.minY, b.minY), maxX: max(a.maxX, b.maxX), maxY: max(a.maxY, b.maxY))
    }
}

extension PlanRenderer {
    /// Library thumbnail (600 × 400 px, without title block).
    static func thumbnailPNG(for plan: FloorPlan) -> Data? { thumbnailPNG(for: House(room: plan)) }

    /// House thumbnail: first story only (overlapping multi-story plan would be unreadable).
    static func thumbnailPNG(for house: House) -> Data? {
        var r = PlanRenderer(); r.options.mode = .fill; r.options.showObjects = true
        r.options.showOpeningDimensions = false
        r.options.showRoomLabels = true
        let shown = house.stories.count > 1 ? House(id: house.id, name: house.name, stories: [house.stories[0]]) : house
        return r.pngData(shown, pixels: CGSize(width: 600, height: 400))
    }
}
