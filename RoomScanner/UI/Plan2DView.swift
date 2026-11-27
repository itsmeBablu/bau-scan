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
    @AppStorage("measurementUnit") private var appUnit: MeasurementUnit = .both
    @Environment(\.projectPreferences) private var projectPreferences
    @Environment(\.locale) private var locale
    private var unit:MeasurementUnit { ProjectPreferenceResolution.unit(projectPreferences,appDefault:appUnit) }

    @State private var showingOptions = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var isMeasuring = false
    @State private var measureStart: CGPoint?
    @State private var measureEnd: CGPoint?
    @State private var lastMeasurementText: String?
    @State private var notes:[ARNote] = []
    @State private var selectedNote:ARNote?
    @AppStorage("evidence.2d.audio") private var showNotes = false
    @AppStorage("evidence.2d.pins") private var showPins = false
    @State private var noteError:String?
    @State private var photos: [ProjectPhotoAsset] = []
    @AppStorage("evidence.2d.photos") private var showPhotos = false
    @State private var selectedPhoto: ProjectPhotoAsset?

    @Environment(\.colorScheme) private var colorScheme
    private var drawingInk:CGColor { CGColor(gray:colorScheme == .dark ? 0.94 : 0.08,alpha:1) }
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                (colorScheme == .dark ? Color(white:0.07) : .white)
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
                        if let angle = AnnotationPresentation.planDirection(photo.photo.viewingPose) {
                            photoDirection(at:pos,angle:angle).stroke(DS.ColorToken.onBrand.color.opacity(0.45),lineWidth:DS.Stroke.separator)
                                .allowsHitTesting(false)
                        }
                        Button { selectedPhoto = photo } label: {
                            EvidenceMarkerGlyph(symbol:AnnotationPresentation.cameraSymbol,number:photo.photo.number,selected:selectedPhoto?.id == photo.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(photo.title)
                        .position(pos)
                    }
                }

                if showNotes || showPins {
                    ForEach(notes.suffix(256).filter { $0.audioFileName == nil ? showPins : showNotes }) { note in
                        if let point = note.viewingPosition {
                            let anchor = viewPoint(from:.init(x:point.x,y:-point.z),size:size)
                            let label = CGPoint(x:anchor.x,y:anchor.y-(note.anchorPinID == nil ? 0 : 34))
                            if note.anchorPinID != nil { Path { path in path.move(to:anchor); path.addLine(to:label) }.stroke(DS.ColorToken.info.color,lineWidth:DS.Stroke.emphasis).allowsHitTesting(false) }
                            Button { selectedNote = note } label: {
                                EvidenceMarkerGlyph(symbol:note.audioFileName == nil ? "mappin" : AnnotationPresentation.audioSymbol)
                            }.buttonStyle(.plain).accessibilityLabel(note.title ?? AppLanguage.text("Voice note"))
                                .position(label)
                        }
                    }
                }

                // Measurement line overlay
                if isMeasuring {
                    Canvas { ctx, _ in
                        if let start = measureStart, let end = measureEnd {
                            var path = Path()
                            path.move(to: start)
                            path.addLine(to: end)
                            ctx.stroke(path, with: .color(DS.ColorToken.onBrand.color), lineWidth: 2)
                            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 4, y: start.y - 4, width: 8, height: 8)), with: .color(DS.ColorToken.onBrand.color))
                            ctx.fill(Path(ellipseIn: CGRect(x: end.x - 4, y: end.y - 4, width: 8, height: 8)), with: .color(DS.ColorToken.onBrand.color))
                        } else if let start = measureStart {
                            ctx.fill(Path(ellipseIn: CGRect(x: start.x - 5, y: start.y - 5, width: 10, height: 10)), with: .color(DS.ColorToken.onBrand.color))
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
                            let text = MeasurementFormat.length(dist, unit: unit, locale: locale)
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
            notes = []; photos = []; selectedNote = nil; selectedPhoto = nil; noteError = nil
            guard let url = packageURL else { return }
            let house = house, root = ScanVoiceNoteLibrary.root
            do {
                let loaded = try await BackgroundWork.run { try SavedScanEvidence.load(packageURL:url,house:house,notesRoot:root) }
                guard !Task.isCancelled else { return }
                notes = loaded.notes; photos = loaded.photos
                noteError = [loaded.noteFailure,loaded.photoFailure].compactMap { $0 }.joined(separator:"\n")
                if noteError?.isEmpty == true { noteError = nil }
            } catch { if !Task.isCancelled { noteError = error.localizedDescription } }
        }
        .overlay(alignment:.topLeading) { if let noteError { Text(noteError).font(.caption).padding().dsMaterial(in:Capsule()) } }
        .sheet(item:$selectedNote) { note in VoiceNotePlayerSheet(note:note) { saved in
            if let i = notes.firstIndex(where:{ $0.id == saved.id }) { var value = saved; value.displayPosition = notes[i].displayPosition; notes[i] = value }
        } }
        .sheet(item: $selectedPhoto) { photo in
            ProjectPhotoGallery(assets: photos, initial: photo.id,compactPresentation:true)
        }
        .safeAreaInset(edge: .bottom) {
            ScrollView(.horizontal) {
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
            }
            .scrollIndicators(.hidden).fixedSize(horizontal:false,vertical:true)
            .dsMaterial()
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
                        Toggle("Voice notes",isOn:$showNotes)
                        Toggle("Pins",isOn:$showPins)
                        Toggle("Drafting grid", isOn: $showGrid)
                    }
                    Section {
                        Button("Reset view") { resetView(); showingOptions = false }
                        Button("Restore defaults") {
                            textScale = 1; showDimensions = true; showLabels = true
                            showObjects = true; showPhotos = false; showNotes = false; showPins = false; showGrid = true
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
        r.options.unit = projectPreferences?.units.flatMap(MeasurementUnit.init(rawValue:)) ?? .meters
        r.options.locale = locale
        r.options.textScale = CGFloat(textScale)
        r.options.transparentBackground = true
        r.options.showFloor = false
        r.options.tintRooms = false
        r.options.showLabelBackground = false
        r.options.showDimensions = showDimensions
        r.options.showOpeningDimensions = showDimensions
        r.options.showRoomLabels = showLabels
        r.options.showObjects = showObjects
        r.options.objectFill = drawingInk.copy(alpha:0.04) ?? drawingInk
        r.options.objectStroke = drawingInk.copy(alpha:0.45) ?? drawingInk
        r.options.wallColor = drawingInk
        r.options.dimensionColor = drawingInk
        r.options.dimensionLineColor = drawingInk.copy(alpha:0.55) ?? drawingInk
        r.options.textColor = drawingInk
        r.options.windowColor = drawingInk
        r.options.mode = .fill
        return r.image(house, pageSize: size, pixelScale: displayScale * 2)
    }

    private func photoDirection(at origin:CGPoint,angle:Double) -> Path {
        let length = Double(AnnotationPresentation.planDirectionLength),half = AnnotationPresentation.planDirectionHalfAngle
        let first = CGPoint(x:origin.x+CGFloat(cos(angle-half)*length),y:origin.y+CGFloat(sin(angle-half)*length))
        let second = CGPoint(x:origin.x+CGFloat(cos(angle+half)*length),y:origin.y+CGFloat(sin(angle+half)*length))
        return Path { path in path.move(to:origin); path.addLine(to:first); path.addLine(to:second); path.closeSubpath() }
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

/// Quiet paper drafting grid; optional, independent of actual measurement geometry.
private struct CADGridBackground: View {
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(colorScheme == .dark ? Color(white:0.07) : .white))
            let minor: CGFloat = 16
            let major: CGFloat = minor * 5
            for x in stride(from: 0, through: size.width, by: minor) {
                var line = Path(); line.move(to: CGPoint(x: x, y: 0)); line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color((colorScheme == .dark ? Color.white : .black).opacity(x.truncatingRemainder(dividingBy: major) == 0 ? 0.08 : 0.025)), lineWidth: DS.Stroke.separator)
            }
            for y in stride(from: 0, through: size.height, by: minor) {
                var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(line, with: .color((colorScheme == .dark ? Color.white : .black).opacity(y.truncatingRemainder(dividingBy: major) == 0 ? 0.08 : 0.025)), lineWidth: DS.Stroke.separator)
            }
        }
        .ignoresSafeArea()
    }
}
