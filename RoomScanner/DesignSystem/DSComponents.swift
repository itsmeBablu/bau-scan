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
