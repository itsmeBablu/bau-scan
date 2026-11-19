import SwiftUI

/// Interactive 2D plan: rendered by `PlanRenderer` in high-resolution bitmap,
/// pinch/scroll zoom, pan drag, double-tap to recenter.
struct Plan2DView: View {
    let house: House
    @AppStorage("measurementUnit") private var unit: MeasurementUnit = .both
    @State private var scale: CGFloat = 1
    @State private var lastScale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            ZStack {
                Color(white: 0.97)
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
    }

    private func render(size: CGSize) -> CGImage? {
        guard size.width > 10, size.height > 10 else { return nil }
        var r = PlanRenderer()
        r.options.unit = unit
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

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { v in scale = min(max(lastScale * v.magnification, 0.5), 8) }
            .onEnded { _ in lastScale = scale }
    }
}
