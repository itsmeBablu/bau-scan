import SwiftUI

struct UnfinishedScansView: View {
    let projectID:UUID
    @Environment(RoomStore.self) private var library
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.scenePhase) private var phase
    @State private var sessions:[ScanSession] = []
    @State private var discard:ScanSession?
    @State private var busy = false
    @State private var message:String?
    @State private var disk:ScanSessionStore?
    #if os(iOS)
    @AppStorage("scan.experimentalRelocalization") private var experimental = false
    @State private var probing:ScanSession?
    #endif
    var body: some View {
        VStack(alignment:.leading,spacing:10) {
            if !sessions.isEmpty { Text("Unfinished scans").font(.headline) }
            ForEach(sessions) { session in
                VStack(alignment:.leading,spacing:8) {
                    HStack {
                        Image(systemName:session.kind == .technical ? "cube.transparent" : "house")
                        Text(title(session)).font(.headline)
                        Spacer(); Text(session.updated,style:.date).font(.caption)
                    }
                    Text("Recover the saved portion. New capture cannot be merged without verified alignment.").font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(session.state == .failed || session.state == .finalizing ? "Retry finishing" : "Recover") { recover(session) }
                        Button("Discard",role:.destructive) { discard = session }
                    }.buttonStyle(.bordered).disabled(busy)
                    #if os(iOS)
                    if experimental { Button("Check saved alignment (experimental)") { probing = session } }
                    #endif
                }.padding(.vertical,8)
            }
            if busy { ProgressView("Recovering scan…") }
            if let message { Text(message).font(.caption).foregroundStyle(.secondary) }
        }
        #if os(iOS)
        .fullScreenCover(item:$probing) { session in if let disk { ScanRelocalizationProbe(session:session,store:disk) } }
        #endif
        .task(id:projectID.uuidString+String(workspace.catalogueRevision)) { do { disk = try ScanSessionStore.local(); await reload() } catch { message = error.localizedDescription } }
        .onChange(of:phase) { _,value in if value == .active { Task { await reload() } } }
        .confirmationDialog("Discard unfinished scan?",isPresented:Binding(get:{ discard != nil },set:{ if !$0 { discard = nil } }),titleVisibility:.visible) {
            Button("Discard draft",role:.destructive) { if let discard { remove(discard) } }
            Button("Cancel",role:.cancel) { discard = nil }
        } message: {
            if let discard {
                Text(title(discard)+" · "+discard.id.uuidString)
                Text("Only this draft's segments, photos and session notes are deleted. Saved scans and project voice notes are kept.")
            }
        }
    }
    private func title(_ session:ScanSession) -> String {
        AppLanguage.text(session.kind == .technical ? "Technik Room" : session.kind == .house ? "House scan" : "Room scan")
    }
    private func reload() async {
        do { sessions = try await disk?.recoveryCandidates(projectID:projectID) ?? [] } catch { message = error.localizedDescription }
    }
    private func recover(_ session:ScanSession) {
        guard let disk else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                _ = try await ScanSessionRecovery.shared.promote(session,store:disk,documents:workspace.notesRoot)
                library.reload(); await workspace.reloadAndWait(location:library.location)
                await reload(); message = AppLanguage.text("Recovered as a partial scan")
            } catch { message = AppLanguage.text("Draft retained. Retry recovery.")+" "+error.localizedDescription }
        }
    }
    private func remove(_ session:ScanSession) {
        guard let disk else { return }; busy = true
        Task { @MainActor in
            defer { busy = false; discard = nil }
            do { try await disk.discard(session.id); await reload() } catch { message = error.localizedDescription }
        }
    }
}
