import SwiftUI

extension View {
    @ViewBuilder func studioPresentation<Content: View>(isPresented: Binding<Bool>,@ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(isPresented: isPresented,content: content)
        #else
        sheet(isPresented: isPresented,content: content)
        #endif
    }
    @ViewBuilder func studioPresentation<Item: Identifiable,Content: View>(item: Binding<Item?>,onDismiss: (() -> Void)? = nil,@ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(iOS)
        fullScreenCover(item: item,onDismiss: onDismiss,content: content)
        #else
        sheet(item: item,onDismiss: onDismiss,content: content)
        #endif
    }
}
