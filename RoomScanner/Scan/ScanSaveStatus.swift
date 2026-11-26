import SwiftUI

struct ScanSaveStatus: View {
    let persistence: CapturePersistence
    var body: some View {
        if persistence.failure != nil || persistence.savedAt != nil {
        HStack(spacing:6) {
            if persistence.failure != nil {
                Label("Saving failed · draft retained",systemImage:"exclamationmark.triangle.fill").foregroundStyle(DS.ColorToken.warning.color)
            } else if let saved = persistence.savedAt {
                Image(systemName:"checkmark.circle")
                Text("Saved")
                Text(saved,format:.dateTime.hour().minute())
            }
        }.font(.caption.weight(.medium)).padding(8).dsMaterial(in:Capsule())
            .accessibilityElement(children:.combine)
        }
    }
}
