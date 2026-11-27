import SwiftUI

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
    var body: some View {
        HStack {
            Text(title).font(DS.Typography.headline)
            Spacer()
            if let action { Button("See All",action:action).font(DS.Typography.subheadline) }
        }.accessibilityElement(children:.contain)
    }
}
struct DSStatCell: View {
    var title: LocalizedStringKey
    var value: String
    var body: some View {
        VStack(alignment:.leading,spacing:DS.Spacing.xs) {
            Text(value).font(DS.Typography.headline).monospacedDigit()
            Text(title).font(DS.Typography.caption).foregroundStyle(DS.ColorToken.textSecondary.color)
        }.frame(maxWidth:.infinity,alignment:.leading).accessibilityElement(children:.combine)
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
