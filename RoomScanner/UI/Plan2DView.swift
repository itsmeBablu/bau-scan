import SwiftUI

/// Interactive 2D plan: rendered by `PlanRenderer` in high-resolution bitmap,
/// pinch/scroll zoom, pan drag, double-tap to recenter.
struct Plan2DView: View {
    let house: House
    @AppStorage("planTextScale") private var textScale = 1.0
    @AppStorage("planShowDimensions") private var showDimensions = true
    @AppStorage("planShowLabels") private var showLabels = true
    @AppStorage("planShowObjects") private var showObjects = true
    @AppStorage("planShowGrid") private var showGrid = true
    @State private var showingOptions = false
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
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
            }
            .contentShape(Rectangle())
            .gesture(drag.simultaneously(with: magnify))
            .onTapGesture(count: 2) { withAnimation(.snappy) { scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero } }
            .clipped()
        }
        .accessibilityLabel(Text("plan.accessibility"))
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
                        Toggle("Drafting grid", isOn: $showGrid)
                    }
                    Section {
                        Button("Reset view") { resetView(); showingOptions = false }
                        Button("Restore defaults") {
                            textScale = 1; showDimensions = true; showLabels = true
                            showObjects = true; showGrid = true
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
        // On screen: plan fills area (no paper scale) and text is in points,
        // rendered at 2× screen density to stay crisp when zoomed.
        r.options.mode = .fill
        return r.image(house, pageSize: size, pixelScale: displayScale * 2)
    }

    private var drag: some Gesture {
        DragGesture()
            .onChanged { v in offset = CGSize(width: lastOffset.width + v.translation.width, height: lastOffset.height + v.translation.height) }
            .onEnded { _ in lastOffset = offset }
    }

    private func resetView() {
        scale = 1; lastScale = 1; offset = .zero; lastOffset = .zero
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
