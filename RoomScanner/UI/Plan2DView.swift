import SwiftUI

/// Interactive 2D plan: rendered by `PlanRenderer` in high-resolution bitmap,
/// pinch/scroll zoom, pan drag, double-tap to recenter, 2-point measurement, and photo markers.
struct Plan2DView: View {
    let house: House
    var packageURL: URL? = nil
    @AppStorage("planTextScale") private var textScale = 1.0
    @AppStorage("planShowDimensions") private var showDimensions = true
    @AppStorage("planShowLabels") private var showLabels = true
    @AppStorage("planShowObjects") private var showObjects = true
    @AppStorage("planShowGrid") private var showGrid = true
    @AppStorage("measurementUnit") private var unit: MeasurementUnit = .both

    @State private var showingOptions = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isMeasuring = false
    @State private var measureStart: CGPoint?
    @State private var measureEnd: CGPoint?
    @State private var lastMeasurementText: String?
    @State private var photos: [SurveyPhotoImage] = []
    @State private var showPhotos = true
    @State private var selectedPhoto: SurveyPhotoImage?

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(white: 0.16)
                if showGrid { CADGridBackground() }
                if let image = render(size: size) {
                    Image(decorative: image, scale: displayScale * 2)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: size.width, height: size.height)
                        .scaleEffect(scale)
                        .offset(offset)
                }

                // Photo markers on 2D plan
                if showPhotos && !photos.isEmpty {
                    ForEach(photos) { photo in
                        let pos = viewPoint(from: Point2D(x: photo.photo.viewingPose[12], y: -photo.photo.viewingPose[14]), size: size)
                        Button { selectedPhoto = photo } label: {
                            ZStack {
                                Circle().fill(.yellow).frame(width: 22, height: 22)
                                Circle().stroke(.black.opacity(0.4), lineWidth: 1).frame(width: 22, height: 22)
                                Text("\(photo.photo.number)")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.black)
                            }
                        }
                        .buttonStyle(.plain)
                        .position(pos)
                    }
                }

                // Measurement line overlay
                if isMeasuring {
                    Canvas { ctx, _ in
                        if let start = measureStart, let end = measureEnd {
                            var path = Path()
                            path.move(to: start)
                            path.addLine(to: end)
                            ctx.stroke(path, with: .color(.yellow), lineWidth: 2)
                            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(.yellow))
                            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(.yellow))
                        } else if let start = measureStart {
                            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(.yellow))
                        }
                    }
                }
            }
            .contentShape(Rectangle())
            .gesture(drag.simultaneously(with: magnify))
            .onTapGesture(count: 2) { withAnimation(.snappy) { resetView() } }
            .simultaneousGesture(
                SpatialTapGesture().onEnded { val in
                    if isMeasuring {
                        let pt = val.location
                        if let start = measureStart {
                            measureEnd = pt
                            let p1 = housePoint(from: start, size: size)
                            let p2 = housePoint(from: pt, size: size)
                            let dist = hypot(p2.x - p1.x, p2.y - p1.y)
                            let text = MeasurementFormat.length(dist, unit: unit, locale: AppLanguage.locale)
                            lastMeasurementText = text
                            #if os(macOS)
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                            #endif
                        } else {
                            measureStart = pt
                            measureEnd = nil
                            lastMeasurementText = nil
                        }
                    }
                }
            )
            .clipped()
        }
        .accessibilityLabel(Text("plan.accessibility"))
        .task(id: packageURL) {
            guard let url = packageURL else { return }
            photos = (try? await Task.detached { try SurveyPhotoStore.images(from: url, house: house) }.value) ?? []
        }
        .sheet(item: $selectedPhoto) { photo in
            SurveyPhotoGallery(photos: photos, initial: photo.id)
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button { textScale = max(0.7, ((textScale - 0.1) * 10).rounded() / 10) } label: {
                    Label("Smaller text", systemImage: "textformat.size.smaller")
                }
                .disabled(textScale <= 0.7)
                Text("\(Int((textScale * 100).rounded()))%")
                    .monospacedDigit().frame(minWidth: 48)
                Button { textScale = min(1.8, ((textScale + 0.1) * 10).rounded() / 10) } label: {
                    Label("Larger text", systemImage: "textformat.size.larger")
                }
                .disabled(textScale >= 1.8)

                Divider().frame(height: 18)

                Toggle(isOn: $isMeasuring) {
                    Label("plan.measure", systemImage: "ruler.fill")
                }
                .toggleStyle(.button)

                if let last = lastMeasurementText {
                    Text("Measured: \(last)").bold()
                    Text("measure.copied").font(.caption).foregroundStyle(.secondary)
                    Button("Clear") {
                        lastMeasurementText = nil
                        measureStart = nil
                        measureEnd = nil
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Spacer(minLength: 0)
                Button { showingOptions = true } label: { Label("Plan options", systemImage: "slider.horizontal.3") }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .padding(12)
            .background(.regularMaterial)
        }
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { showingOptions = true } label: { Label("Plan options", systemImage: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $showingOptions) {
            NavigationStack {
                Form {
                    Section("Text size") {
                        LabeledContent("Size", value: "\(Int(textScale * 100))%")
                        Slider(value: $textScale, in: 0.7...1.8, step: 0.1) { Text("Text size") }
                    }
                    Section("Visibility") {
                        Toggle("Dimensions", isOn: $showDimensions)
                        Toggle("Room labels", isOn: $showLabels)
                        Toggle("Furniture and objects", isOn: $showObjects)
                        Toggle("Photos", isOn: $showPhotos)
                        Toggle("Drafting grid", isOn: $showGrid)
                    }
                    Section {
                        Button("Reset view") { resetView(); showingOptions = false }
                        Button("Restore defaults") {
                            textScale = 1; showDimensions = true; showLabels = true
                            showObjects = true; showPhotos = true; showGrid = true
                        }
                    }
                }
                .navigationTitle("Plan options")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingOptions = false } } }
            }
            .presentationDetents([.medium, .large])
            .frame(minWidth: 320, minHeight: 420)
        }
    }

    private func render(size: CGSize) -> CGImage? {
        guard size.width > 10, size.height > 10 else { return nil }
        var r = PlanRenderer()
        r.options.unit = .meters
        r.options.textScale = CGFloat(textScale)
        r.options.transparentBackground = true
        r.options.showFloor = false
        r.options.tintRooms = false
        r.options.showLabelBackground = false
        r.options.showDimensions = showDimensions
        r.options.showOpeningDimensions = showDimensions
        r.options.showRoomLabels = showLabels
        r.options.showObjects = showObjects
        r.options.objectFill = CGColor(gray: 0.6, alpha: 0.12)
        r.options.objectStroke = CGColor(gray: 0.65, alpha: 1)
        r.options.wallColor = CGColor(gray: 0.88, alpha: 1)
        r.options.dimensionColor = CGColor(gray: 0.72, alpha: 1)
        r.options.dimensionLineColor = CGColor(gray: 0.62, alpha: 1)
        r.options.textColor = CGColor(gray: 0.94, alpha: 1)
        r.options.windowColor = CGColor(red: 0.35, green: 0.78, blue: 0.90, alpha: 1)
        r.options.mode = .fill
        return r.image(house, pageSize: size, pixelScale: displayScale * 2)
    }

    private func housePoint(from viewPt: CGPoint, size: CGSize) -> Point2D {
        let b = house.bounds
        guard !b.isEmpty else { return .zero }
        let inset = size.width * 0.02
        let area = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let margin = showDimensions ? PlanRenderer.dimensionMargin : 0.15
        let ppm = min(Double(area.width) / (b.width + 2 * margin), Double(area.height) / (b.height + 2 * margin))
        let planW = (b.width + 2 * margin) * ppm, planH = (b.height + 2 * margin) * ppm
        let origin = CGPoint(x: area.midX - planW / 2 + margin * ppm - b.minX * ppm,
                             y: area.midY - planH / 2 + margin * ppm - b.minY * ppm)
        let unscaledX = (viewPt.x - size.width / 2 - offset.width) / scale + size.width / 2
        let unscaledY = (viewPt.y - size.height / 2 - offset.height) / scale + size.height / 2
        let cgY = size.height - unscaledY
        let meterX = Double(unscaledX - origin.x) / ppm
        let meterY = Double(cgY - origin.y) / ppm
        return Point2D(x: meterX, y: meterY)
    }

    private func viewPoint(from housePt: Point2D, size: CGSize) -> CGPoint {
        let b = house.bounds
        guard !b.isEmpty else { return .zero }
        let inset = size.width * 0.02
        let area = CGRect(x: inset, y: inset, width: size.width - 2 * inset, height: size.height - 2 * inset)
        let margin = showDimensions ? PlanRenderer.dimensionMargin : 0.15
        let ppm = min(Double(area.width) / (b.width + 2 * margin), Double(area.height) / (b.height + 2 * margin))
        let planW = (b.width + 2 * margin) * ppm, planH = (b.height + 2 * margin) * ppm
        let origin = CGPoint(x: area.midX - planW / 2 + margin * ppm - b.minX * ppm,
                             y: area.midY - planH / 2 + margin * ppm - b.minY * ppm)
        let unscaledX = origin.x + CGFloat(housePt.x * ppm)
        let cgY = origin.y + CGFloat(housePt.y * ppm)
        let unscaledY = size.height - cgY
        let viewX = (unscaledX - size.width / 2) * scale + size.width / 2 + offset.width
        let viewY = (unscaledY - size.height / 2) * scale + size.height / 2 + offset.height
        return CGPoint(x: viewX, y: viewY)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetView() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
        measureStart = nil; measureEnd = nil; lastMeasurementText = nil
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = min(max(lastScale * v.magnification, 0.5), 8) }
            .onEnded { _ in lastScale = scale }
    }
}

/// Subtle drafting grid, like an AutoCAD model space; the plan stays crisp above it.
private struct CADGridBackground: View {
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(white: 0.16)))
            let minor: CGFloat = 16
            let major: CGFloat = minor * 5
            for x in stride(from: 0, through: size.width, by: minor) {
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.white.opacity(x.truncatingRemainder(dividingBy: major) == 0 ? 0.11 : 0.045)), lineWidth: 1)
            }
            for y in stride(from: 0, through: size.height, by: minor) {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color(.white.opacity(y.truncatingRemainder(dividingBy: major) == 0 ? 0.11 : 0.045)), lineWidth: 1)
            }
        }
        .ignoresSafeArea()
    }
}
