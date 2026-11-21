import SwiftUI

/// Root screen: library with `RoomStore` injected into the environment.
struct RootView: View {
    @State private var store = RoomStore(location: RootView.initialLocation(), allowsCloud: RootView.allowsCloud)

    private static var allowsCloud: Bool {
        #if ROOMSCANNER_LOCAL_ONLY
        false
        #else
        !hasForcedRoot
        #endif
    }
    @State private var importError: String?
    @State private var technicalImport: URL?
    @State private var showingTechnicalImport = false

    static var hasForcedRoot: Bool { UserDefaults.standard.string(forKey: "RoomScannerStorageRoot") != nil }

    /// `-RoomScannerStorageRoot <path>` at launch forces a custom local root
    /// (demos, screenshots, tests); otherwise standard storage.
    static func initialLocation() -> StorageLocation {
        if let path = UserDefaults.standard.string(forKey: "RoomScannerStorageRoot") {
            return StorageLocation(kind: .local, documentsURL: URL(fileURLWithPath: path, isDirectory: true))
        }
        return .local()
    }

    var body: some View {
        RoomListView()
            .environment(store)
            .task { await store.activateCloudIfAvailable() }
            .onOpenURL { url in
                if TechnicalGoogleAIAccount.handle(url) { return }
                if url.pathExtension == "technicalroom" { technicalImport = url; showingTechnicalImport = true; return }
                guard [FileLayout.packageExtension, FileLayout.housePackageExtension].contains(url.pathExtension) else { return }
                do { try store.importAny(from: url) } catch { importError = error.localizedDescription }
            }
            .sheet(isPresented: $showingTechnicalImport) { TechnicalRoomLibraryView(importURL: technicalImport) }
            .alert("cloud.importFailed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("common.ok") { importError = nil }
            } message: { Text(importError ?? "") }
    }
}

#Preview {
    RootView()
}
