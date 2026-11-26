import SwiftUI

/// Viewer control bar: mode, dimensions, objects, AR scale, recenter, Quick Look.
struct ViewerControls: View {
    @Bindable var state: ViewerState
    var usdzURL: URL?
    var onVoiceNote: (() -> Void)? = nil
    @State private var showQuickLook = false
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(spacing: 8) {
            if textSize.isAccessibilitySize {
                modePicker.pickerStyle(.menu)
            } else {
                modePicker.pickerStyle(.segmented)
            }
            Group {
                if textSize.isAccessibilitySize {
                    VStack(spacing: 8) { tools }
                } else {
                    HStack(spacing: 8) { tools }
                }
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .dsMaterial(in:RoundedRectangle(cornerRadius: DS.Radius.floating, style: .continuous))
        .padding(.horizontal)
        .padding(.vertical, 6)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: state.mode) { _,mode in if mode == .ar { state.isMeasuring = false } }
    }
    @ViewBuilder private var tools: some View {
        if let onVoiceNote {
            Button(action: onVoiceNote) { Label("Voice note",systemImage: "mic.fill").font(.subheadline.weight(.semibold)).frame(minHeight: 32) }
                .accessibilityIdentifier("viewer.addVoiceNote")
        }
        Button { state.resetToken += 1 } label: { controlLabel("viewer.recenter",icon: "scope") }
            .help(Text("viewer.recenter"))
        Menu {
            if state.mode == .ar {
                Picker("viewer.arScale",selection: $state.arScale) { ForEach(ARScale.allCases) { Text($0.label).tag($0) } }
            }
            Toggle("viewer.dimensions",isOn: $state.showDimensions)
            Toggle("viewer.objects",isOn: $state.showObjects)
            if state.mode != .ar { Toggle("viewer.measure",isOn: $state.isMeasuring) }
            if usdzURL != nil { Button("viewer.quicklook") { showQuickLook = true } }
        } label: { controlLabel("Options",icon: "ellipsis.circle") }
            .accessibilityLabel("Viewer options")
            .background { if let usdzURL { Color.clear.quickLookPreview(usdzURL,isPresented: $showQuickLook) } }
    }
    private var modePicker: some View {
        Picker("viewer.mode",selection: $state.mode) {
            ForEach(ViewerMode.available) { mode in Text(LocalizedStringKey(mode.titleKey)).tag(mode) }
        }.frame(maxWidth: .infinity)
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
