#if os(iOS)
import SwiftUI
import UIKit

@MainActor enum CaptureAwake {
    private static var leases:Set<UUID> = []
    private static var original = false
    static func acquire(_ id:UUID) {
        if leases.isEmpty { original = UIApplication.shared.isIdleTimerDisabled }
        leases.insert(id); UIApplication.shared.isIdleTimerDisabled = true
    }
    static func release(_ id:UUID) {
        guard leases.remove(id) != nil else { return }
        if leases.isEmpty { UIApplication.shared.isIdleTimerDisabled = original }
    }
}
struct CaptureAwakeModifier:ViewModifier {
    @Environment(\.scenePhase) private var phase
    @State private var id = UUID()
    func body(content:Content) -> some View {
        content.onAppear { if phase == .active { CaptureAwake.acquire(id) } }
            .onDisappear { CaptureAwake.release(id) }
            .onChange(of:phase) { _,value in if value == .active { CaptureAwake.acquire(id) } else { CaptureAwake.release(id) } }
    }
}
#endif
