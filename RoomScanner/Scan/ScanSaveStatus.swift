import SwiftUI

struct ScanSaveStatus: View {
    let persistence: CapturePersistence
    var body: some View {
        HStack(spacing:6) {
            if persistence.failure != nil {
                Label("Saving failed · draft retained",systemImage:"exclamationmark.triangle.fill").foregroundStyle(.orange)
            } else if let saved = persistence.savedAt {
                Image(systemName:"checkmark.circle")
                Text("Saved")
                Text(saved,format:.dateTime.hour().minute())
            } else { Label("Waiting for first checkpoint",systemImage:"externaldrive") }
        }.font(.caption.weight(.medium)).padding(8).background(.regularMaterial,in:Capsule())
            .accessibilityElement(children:.combine)
    }
}
