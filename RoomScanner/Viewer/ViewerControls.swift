import SwiftUI

/// Viewer control bar: mode, dimensions, objects, AR scale, recenter, Quick Look.
struct ViewerControls: View {
    @Bindable var state: ViewerState
    var usdzURL: URL?
    var onVoiceNote: (() -> Void)? = nil
    @State private var showQuickLook = false

    var body: some View {
        ViewThatFits(in:.horizontal) {
            toolRow.fixedSize()
            ScrollView(.horizontal) { toolRow }.scrollIndicators(.hidden)
        }
        .frame(maxWidth:.infinity)
        .padding(.horizontal,12).padding(.vertical,8)
        .fixedSize(horizontal:false,vertical:true)
        .onChange(of:state.mode) { _,mode in if mode == .ar { state.isMeasuring = false } }
    }
    private var toolRow:some View {
        HStack(spacing:6) {
            ForEach(ViewerMode.available) { mode in
                Button { state.mode = mode } label: {
                    Label(LocalizedStringKey(mode.titleKey),systemImage:mode == .threeD ? DS.Symbol.studio : mode == .twoD ? DS.Symbol.floorPlan : DS.Symbol.ar).labelStyle(.iconOnly)
                }
                    .buttonStyle(DSCanvasToolStyle(selected:state.mode == mode))
            }
            tools
        }
    }
    @ViewBuilder private var tools: some View {
        if let onVoiceNote {
            Button(action:onVoiceNote) { controlLabel("Voice note",icon:DS.Symbol.voiceNote) }
                .buttonStyle(DSCanvasToolStyle())
                .accessibilityIdentifier("viewer.addVoiceNote")
        }
        Button { state.resetToken += 1 } label: { controlLabel("viewer.recenter",icon:DS.Symbol.recenter) }
            .buttonStyle(DSCanvasToolStyle()).help(Text("viewer.recenter"))
        Button { state.isMeasuring.toggle() } label: { controlLabel("viewer.measure",icon:DS.Symbol.measure) }
            .buttonStyle(DSCanvasToolStyle(selected:state.isMeasuring)).disabled(state.mode == .ar)
        Menu {
            if state.mode == .ar {
                Picker("viewer.arScale",selection: $state.arScale) { ForEach(ARScale.allCases) { Text($0.label).tag($0) } }
            }
            Toggle("viewer.dimensions",isOn: $state.showDimensions)
            Toggle("viewer.objects",isOn: $state.showObjects)
            Toggle("Photos",isOn:$state.showPhotos)
            Toggle("Voice notes",isOn:$state.showNotes)
            Toggle("Pins",isOn:$state.showPins)
            if state.mode != .ar { Toggle("viewer.measure",isOn: $state.isMeasuring) }
            if usdzURL != nil { Button("viewer.quicklook") { showQuickLook = true } }
        } label: { controlLabel("Options",icon:DS.Symbol.options).frame(minWidth:DS.Size.libraryAction,minHeight:DS.Size.libraryAction).dsMaterial(in:Circle()) }
            .buttonStyle(.plain)
            .accessibilityLabel("Viewer options")
            .background { if let usdzURL { Color.clear.quickLookPreview(usdzURL,isPresented: $showQuickLook) } }
    }
    private func controlLabel(_ title: LocalizedStringKey,icon: String) -> some View {
        Label(title,systemImage: icon).labelStyle(.iconOnly).frame(minWidth: 32,minHeight: 32)
    }
}

private extension View {
    /// Quick Look file preview — iOS: native `quickLookPreview`; macOS: QLPreviewPanel via `NSWorkspace`.
    @ViewBuilder
    func quickLookPreview(_ url: URL, isPresented: Binding<Bool>) -> some View {
        #if os(iOS)
        self.quickLookPreview(isPresented.wrappedValue ? url : nil, onDismiss: { isPresented.wrappedValue = false })
        #else
        self.onChange(of: isPresented.wrappedValue) { _, shown in
            if shown { NSWorkspace.shared.open(url); isPresented.wrappedValue = false }
        }
        #endif
    }

    #if os(iOS)
    func quickLookPreview(_ url: URL?, onDismiss: @escaping () -> Void) -> some View {
        modifier(QuickLookModifier(url: url, onDismiss: onDismiss))
    }
    #endif
}

#if os(iOS)
import QuickLook

private struct QuickLookModifier: ViewModifier {
    let url: URL?
    let onDismiss: () -> Void
    @State private var item: URL?
    func body(content: Content) -> some View {
        content
            .onChange(of: url) { _, new in item = new }
            .quickLookPreview($item)
            .onChange(of: item) { _, new in if new == nil { onDismiss() } }
    }
}
#endif
