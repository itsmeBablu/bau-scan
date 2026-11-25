import SwiftUI
#if os(iOS)
import AVFoundation
#endif
struct VoiceDiagnosticsView: View {
    @AppStorage("voice.lastStopReason") private var last = "No recording yet"
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("Voice diagnostics").font(.headline)
            Text(AppLanguage.text(last)).font(.caption)
            #if os(iOS)
            Text(AVAudioApplication.shared.recordPermission == .granted ? "Microphone allowed" : AVAudioApplication.shared.recordPermission == .denied ? "Microphone denied" : "Microphone not requested").font(.caption).foregroundStyle(.secondary)
            #endif
        }
    }
}
