import SwiftUI

#if os(iOS)
private struct DSLibraryPressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: DS.Motion.feedback), value: configuration.isPressed)
    }
}
#endif

/// Simple building window with four panes and a sill; original vector drawing.
/// Decorative inside a Label so its text remains the accessibility description.
struct DSWindowFrameIcon:View {
    @ScaledMetric(relativeTo:.body) private var size:CGFloat = 18
    var body:some View {
        GeometryReader { geometry in
            Path { path in
                let width = geometry.size.width,height = geometry.size.height
                path.addRoundedRect(in:CGRect(x:width*0.15,y:height*0.08,width:width*0.7,height:height*0.76),cornerSize:CGSize(width:width*0.04,height:height*0.04))
                path.move(to:CGPoint(x:width*0.5,y:height*0.08)); path.addLine(to:CGPoint(x:width*0.5,y:height*0.84))
                path.move(to:CGPoint(x:width*0.15,y:height*0.46)); path.addLine(to:CGPoint(x:width*0.85,y:height*0.46))
                path.move(to:CGPoint(x:width*0.06,y:height*0.94)); path.addLine(to:CGPoint(x:width*0.94,y:height*0.94))
            }.stroke(style:StrokeStyle(lineWidth:max(1,size/12),lineCap:.round,lineJoin:.round))
        }.frame(width:size,height:size).accessibilityHidden(true)
    }
}

/// Independent canvas tools: no enclosing panel, and full-size hit targets.
struct DSCanvasToolStyle:ButtonStyle {
    var selected = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration:Configuration) -> some View {
        configuration.label.font(DS.Typography.subheadline.weight(.semibold))
            .frame(minWidth:DS.Size.libraryAction,minHeight:DS.Size.libraryAction)
            .foregroundStyle(selected ? DS.ColorToken.onAccent.color : DS.ColorToken.textPrimary.color)
            .background(selected ? DS.ColorToken.accent.color : .clear,in:Circle())
            .dsMaterial(in:Circle()).contentShape(Circle())
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.4)
    }
}

struct DSButtonStyle: ButtonStyle {
    enum Kind: String,CaseIterable { case primary,secondary,plainRow,destructive,pill,floating,recording }
    var kind: Kind = .primary
    @Environment(\.isEnabled) private var enabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var filled: Bool { [.primary,.pill,.floating,.recording].contains(kind) }
    func makeBody(configuration:Configuration) -> some View {
        configuration.label
            .font(DS.Typography.body.weight(.semibold))
            .padding(.horizontal,kind == .floating ? DS.Spacing.s : DS.Spacing.l)
            .frame(minWidth:DS.Size.minimumTouchTarget,minHeight:DS.Size.minimumTouchTarget)
            .foregroundStyle(kind == .recording ? DS.ColorToken.onRecording.color : filled ? DS.ColorToken.onBrand.color : kind == .destructive ? DS.ColorToken.error.color : DS.ColorToken.accent.color)
            .background(kind == .recording ? DS.ColorToken.recording.color : filled ? DS.ColorToken.brand.color : Color.clear,
                in:RoundedRectangle(cornerRadius:[.pill,.floating].contains(kind) ? DS.Size.minimumTouchTarget/2 : DS.Radius.small))
            .overlay { if kind == .secondary {
                RoundedRectangle(cornerRadius:DS.Radius.small).stroke(DS.ColorToken.separator.color,lineWidth:DS.Stroke.emphasis)
            } }
            .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.45)
            .animation(DS.Motion.animation(reduceMotion:reduceMotion),value:configuration.isPressed)
    }
}

/// The sole material decision, also used by the legacy liquidGlass API.
struct DSFloatingSurface: ViewModifier {
    var radius: CGFloat = DS.Radius.floating
    func body(content:Content) -> some View { content.modifier(DSMaterialSurface(shape:RoundedRectangle(cornerRadius:radius))) }
}
private struct DSMaterialSurface<S:Shape>: ViewModifier {
    var shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @ViewBuilder func body(content:Content) -> some View {
        if reduceTransparency { content.background(DS.ColorToken.card.color,in:shape) }
        else {
            #if compiler(>=6.2)
            if #available(iOS 26,macOS 26,*) { content.glassEffect(.regular,in:shape) }
            else { legacy(content) }
            #else
            legacy(content)
            #endif
        }
    }
    private func legacy(_ content:Content) -> some View {
        content.background(.regularMaterial,in:shape)
    }
}

extension View {
    func dsLibraryButton() -> some View {
        #if os(iOS)
        buttonStyle(DSLibraryPressStyle())
        #else
        buttonStyle(.plain)
        #endif
    }

    func dsLibraryCard() -> some View {
        #if os(iOS)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return padding(DS.Spacing.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.ColorToken.surfaceGrouped.color, in: shape)
        #else
        padding(DS.Spacing.m).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: DS.Radius.project))
        #endif
    }
    func dsMaterial<S:Shape>(in shape:S) -> some View { modifier(DSMaterialSurface(shape:shape)) }
    func dsMaterial() -> some View { dsMaterial(in:Rectangle()) }
    func dsCard() -> some View {
        padding(DS.Spacing.l).background(DS.ColorToken.card.color,in:RoundedRectangle(cornerRadius:DS.Radius.card))
    }
    func dsSection() -> some View { padding(.vertical,DS.Spacing.s) }
    func dsFloatingBar() -> some View { padding(DS.Spacing.s).modifier(DSFloatingSurface()) }
    func dsBadge() -> some View {
        font(DS.Typography.caption).padding(.horizontal,DS.Spacing.s).padding(.vertical,DS.Spacing.xs)
            .background(DS.ColorToken.selection.color,in:Capsule()).foregroundStyle(DS.ColorToken.textPrimary.color)
    }
    var dsRowInset: some View { padding(.vertical,DS.Spacing.xs) }
    func dsFeedback<T:Equatable>(trigger:T) -> some View { sensoryFeedback(.selection,trigger:trigger) }
}

struct DSStatusBadge: View {
    var title: LocalizedStringKey
    var symbol: String
    var role: DS.ColorToken = .info
    var body: some View { Label(title,systemImage:symbol).foregroundStyle(role.color).font(DS.Typography.caption).dsRowInset }
}
struct DSSectionHeader: View {
    var title: LocalizedStringKey
    var action:(()->Void)? = nil
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var textSize
    #endif
    var body: some View {
        #if os(iOS)
        let layout = textSize >= .xxLarge
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: DS.Spacing.xs))
            : AnyLayout(HStackLayout(spacing: DS.Spacing.s))
        layout {
            Text(title).font(DS.Typography.headline).accessibilityAddTraits(.isHeader)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action {
                Button(action: action) {
                    Text("See All").font(DS.Typography.subheadline)
                        .frame(minWidth: DS.Size.minimumTouchTarget, minHeight: DS.Size.minimumTouchTarget)
                        .contentShape(Rectangle())
                }
            }
        }.accessibilityElement(children: .contain)
        #else
        HStack {
            Text(title).font(DS.Typography.headline)
            Spacer()
            if let action { Button("See All",action:action).font(DS.Typography.subheadline) }
        }.accessibilityElement(children:.contain)
        #endif
    }
}
struct DSStatGrid<Content: View>: View {
    let content: () -> Content
    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var textSize
    @ScaledMetric(relativeTo: .headline) private var minimumWidth = DS.Size.statMinimumWidth
    private var column: GridItem {
        textSize.isAccessibilitySize ? GridItem(.flexible()) : GridItem(.adaptive(minimum: minimumWidth), alignment: .leading)
    }
    #else
    private var column: GridItem { GridItem(.adaptive(minimum: DS.Size.statMinimumWidth), alignment: .leading) }
    #endif

    var body: some View { LazyVGrid(columns: [column], spacing: DS.Spacing.l, content: content) }
}

struct DSStatCell: View {
    var title: LocalizedStringKey
    var value: String
    var body: some View {
        VStack(alignment:.leading,spacing:DS.Spacing.xs) {
            Text(value).font(DS.Typography.measurement)
            Text(title).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.textSecondary.color)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
            #if os(iOS)
            .accessibilityLabel(Text(title)).accessibilityValue(Text(verbatim: value))
            #endif
    }
}
struct DSThumbnailCard<Content:View>: View {
    var title: String
    @ViewBuilder var content:()->Content
    var body: some View {
        VStack(alignment:.leading,spacing:DS.Spacing.s) { content(); Text(title).font(DS.Typography.subheadline).lineLimit(2) }
    }
}
struct DSEmptyState: View {
    var title: LocalizedStringKey
    var symbol: String
    var detail: LocalizedStringKey
    var body: some View { ContentUnavailableView { Label(title,systemImage:symbol) } description: { Text(detail) } }
}
struct DSInlineAudioRow: View {
    var title: String
    var subtitle: String
    var time: String
    var playing: Bool
    var waveform: [Double] = []
    @Binding var progress: Double
    var toggle:()->Void
    var body: some View {
        VStack(alignment:.leading,spacing:2) {
            Text(title).font(DS.Typography.subheadline.weight(.semibold)).lineLimit(1)
            HStack(spacing:DS.Spacing.xs) {
                Button(action:toggle) { Image(systemName:playing ? "pause.fill" : "play.fill") }
                    .font(.system(size:16,weight:.semibold)).frame(width:44,height:44).contentShape(Rectangle())
                    .buttonStyle(.plain).accessibilityLabel(playing ? "Pause playback" : "Play recording")
                DSAudioScrubber(waveform:waveform,progress:$progress)
                Text(time).font(.caption2).monospacedDigit().lineLimit(1).minimumScaleFactor(0.75)
            }
            Text(subtitle).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.textSecondary.color).lineLimit(1)
        }.padding(.horizontal,8).padding(.vertical,3).background(DS.ColorToken.surface.color,in:RoundedRectangle(cornerRadius:12))
    }
}

private struct DSAudioScrubber:View {
    let waveform:[Double]
    @Binding var progress:Double
    var body:some View {
        GeometryReader { geometry in
            Canvas { context,size in
                let count = 48,step = size.width/Double(count)
                for index in 0..<count {
                    let peak = waveform.isEmpty ? 0.18 : waveform[min(waveform.count-1,index*waveform.count/count)]
                    let height = max(3,28*min(1,max(0,peak)))
                    let rect = CGRect(x:Double(index)*step,y:(size.height-height)/2,width:max(1,step-2),height:height)
                    let color = Double(index)/Double(count) <= progress ? DS.ColorToken.accent.color : DS.ColorToken.textSecondary.color.opacity(0.35)
                    context.fill(Path(roundedRect:rect,cornerRadius:1.5),with:.color(color))
                }
            }.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged { value in progress = min(1,max(0,value.location.x/max(1,geometry.size.width))) })
        }.frame(minWidth:60,maxWidth:.infinity).frame(height:44)
            .accessibilityElement().accessibilityLabel("Playback position")
            .accessibilityValue(Text(progress,format:.percent.precision(.fractionLength(0))))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: progress = min(1,progress+0.05)
                case .decrement: progress = max(0,progress-0.05)
                @unknown default: break
                }
            }
    }
}

/// Horizontal wrapping flow layout that advances subviews onto the next line when needed.
struct DSFlowLayout: Layout {
    var spacing: CGFloat = DS.Spacing.s
    var lineSpacing: CGFloat = DS.Spacing.s

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
        var sizes: [CGSize] = []
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = computeRows(proposalWidth: proposal.width, subviews: subviews)
        let totalHeight = rows.reduce(CGFloat(0)) { $0 + $1.height }
            + CGFloat(max(0, rows.count - 1)) * lineSpacing
        let maxRowWidth = rows.map(\.width).max() ?? 0
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? maxRowWidth
        return CGSize(width: max(width, maxRowWidth), height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = computeRows(proposalWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in rows {
            var x = bounds.minX
            for (offset, index) in row.indices.enumerated() {
                let size = row.sizes[offset]
                let itemY = y + (row.height - size.height) / 2
                subviews[index].place(
                    at: CGPoint(x: x, y: itemY),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: size.width, height: size.height)
                )
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private func computeRows(proposalWidth: CGFloat?, subviews: Subviews) -> [Row] {
        guard !subviews.isEmpty else { return [] }
        let limit = proposalWidth.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        var rows = [Row()]
        for index in subviews.indices {
            var measured = subviews[index].sizeThatFits(.unspecified)
            if let limit, measured.width > limit {
                measured = subviews[index].sizeThatFits(ProposedViewSize(width: limit, height: nil))
            }
            let current = rows[rows.count - 1]
            let candidateWidth = current.indices.isEmpty ? measured.width : current.width + spacing + measured.width
            if let limit, !current.indices.isEmpty, candidateWidth > limit {
                rows.append(Row(indices: [index], width: measured.width, height: measured.height, sizes: [measured]))
            } else {
                rows[rows.count - 1].indices.append(index)
                rows[rows.count - 1].sizes.append(measured)
                rows[rows.count - 1].width = candidateWidth
                rows[rows.count - 1].height = max(current.height, measured.height)
            }
        }
        return rows
    }
}

/// Appearance-adaptive soft pastel fill and border tones for metric badges.
enum DSPastelTone: CaseIterable {
    case sky, lavender, butter, mint, peach

    func colors(scheme: ColorScheme, highContrast: Bool) -> (background: Color, border: Color) {
        switch (self, scheme == .dark, highContrast) {
        case (.sky, false, false):      return (Color(red: 0.894, green: 0.945, blue: 0.996), Color(red: 0.725, green: 0.851, blue: 0.980).opacity(0.75))
        case (.sky, false, true):       return (Color(red: 0.835, green: 0.914, blue: 0.996), Color(red: 0.486, green: 0.690, blue: 0.922))
        case (.sky, true, false):       return (Color(red: 0.102, green: 0.196, blue: 0.294), Color(red: 0.231, green: 0.404, blue: 0.588).opacity(0.75))
        case (.sky, true, true):        return (Color(red: 0.075, green: 0.161, blue: 0.255), Color(red: 0.451, green: 0.682, blue: 0.918))
        case (.lavender, false, false): return (Color(red: 0.937, green: 0.918, blue: 0.996), Color(red: 0.824, green: 0.776, blue: 0.980).opacity(0.75))
        case (.lavender, false, true):  return (Color(red: 0.898, green: 0.867, blue: 0.996), Color(red: 0.616, green: 0.533, blue: 0.910))
        case (.lavender, true, false):  return (Color(red: 0.176, green: 0.141, blue: 0.282), Color(red: 0.369, green: 0.302, blue: 0.569).opacity(0.75))
        case (.lavender, true, true):   return (Color(red: 0.141, green: 0.110, blue: 0.239), Color(red: 0.643, green: 0.569, blue: 0.910))
        case (.butter, false, false):   return (Color(red: 0.996, green: 0.961, blue: 0.800), Color(red: 0.949, green: 0.871, blue: 0.533).opacity(0.80))
        case (.butter, false, true):    return (Color(red: 0.996, green: 0.941, blue: 0.690), Color(red: 0.761, green: 0.620, blue: 0.141))
        case (.butter, true, false):    return (Color(red: 0.220, green: 0.180, blue: 0.039), Color(red: 0.490, green: 0.404, blue: 0.118).opacity(0.75))
        case (.butter, true, true):     return (Color(red: 0.184, green: 0.149, blue: 0.024), Color(red: 0.820, green: 0.686, blue: 0.239))
        case (.mint, false, false):     return (Color(red: 0.886, green: 0.965, blue: 0.925), Color(red: 0.698, green: 0.898, blue: 0.796).opacity(0.75))
        case (.mint, false, true):      return (Color(red: 0.824, green: 0.945, blue: 0.882), Color(red: 0.322, green: 0.698, blue: 0.510))
        case (.mint, true, false):      return (Color(red: 0.082, green: 0.216, blue: 0.165), Color(red: 0.180, green: 0.435, blue: 0.337).opacity(0.75))
        case (.mint, true, true):       return (Color(red: 0.063, green: 0.180, blue: 0.137), Color(red: 0.431, green: 0.792, blue: 0.620))
        case (.peach, false, false):    return (Color(red: 1.000, green: 0.925, blue: 0.851), Color(red: 0.980, green: 0.816, blue: 0.663).opacity(0.75))
        case (.peach, false, true):     return (Color(red: 1.000, green: 0.890, blue: 0.784), Color(red: 0.820, green: 0.518, blue: 0.263))
        case (.peach, true, false):     return (Color(red: 0.239, green: 0.153, blue: 0.078), Color(red: 0.478, green: 0.314, blue: 0.173).opacity(0.75))
        case (.peach, true, true):      return (Color(red: 0.200, green: 0.125, blue: 0.059), Color(red: 0.886, green: 0.624, blue: 0.400))
        }
    }
}

/// Rounded pastel pill displaying a compact metric label and value.
struct DSMetricBadge: View {
    var title: LocalizedStringKey
    var value: String
    var tone: DSPastelTone
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var colorContrast

    var body: some View {
        let highContrast = colorContrast == .increased
        let palette = tone.colors(scheme: colorScheme, highContrast: highContrast)
        let shape = RoundedRectangle(cornerRadius: DS.Radius.small, style: .continuous)
        HStack(spacing: DS.Spacing.xs) {
            Text(title)
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary.color)
            Text(verbatim: value)
                .font(DS.Typography.caption.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(DS.ColorToken.textPrimary.color)
        }
        .padding(.horizontal, DS.Spacing.s)
        .padding(.vertical, DS.Spacing.xs)
        .background(palette.background, in: shape)
        .overlay {
            shape.strokeBorder(palette.border, lineWidth: highContrast ? DS.Stroke.emphasis : DS.Stroke.separator)
        }
        .accessibilityElement(children: .combine)
        #if os(iOS)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(verbatim: value))
        #endif
    }
}
