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
    @State private var tab = AppTab.house
    @State private var scanningTechnical = false
    @State private var pendingItem: LibraryItem?
    @State private var savedTechnicalID: UUID?
    @State private var technicalRefresh = 0
    private enum AppTab: Hashable { case house, technical, capture, profile, settings }
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
        applicationContent
            .environment(store)
            .tint(.blue)
            .task { await store.activateCloudIfAvailable() }
            .onOpenURL { url in
                if TechnicalGoogleAIAccount.handle(url) { return }
                if url.pathExtension == "technicalroom" { technicalImport = url; showingTechnicalImport = true; return }
                guard [FileLayout.packageExtension, FileLayout.housePackageExtension].contains(url.pathExtension) else { return }
                do { try store.importAny(from: url) } catch { importError = error.localizedDescription }
            }
            .sheet(isPresented: $showingTechnicalImport, onDismiss: { technicalImport = nil; savedTechnicalID = nil; technicalRefresh += 1 }) { TechnicalRoomLibraryView(initialSelection: savedTechnicalID, importURL: technicalImport) }
            .alert("cloud.importFailed", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("common.ok") { importError = nil }
            } message: { Text(importError ?? "") }
    }
    @ViewBuilder private var applicationContent: some View {
        #if os(iOS)
        TabView(selection: $tab) {
            RoomListView(pendingItem: $pendingItem,includeTechnicalRooms: false)
                .tabItem { Label("House",systemImage: "house.fill") }.tag(AppTab.house)
            TechnicalRoomLibraryView(embedded: true,onRequestScan: { scanningTechnical = true },refreshToken: technicalRefresh)
                .tabItem { Label("Technik",systemImage: "wrench.and.screwdriver.fill") }.tag(AppTab.technical)
            CaptureHomeView(onSaved: { item in
                pendingItem = item; tab = .house
            },onTechnicalSaved: { id in
                savedTechnicalID = id; technicalRefresh += 1; tab = .technical; showingTechnicalImport = true
            })
                .tabItem { Label("Capture",systemImage: "viewfinder") }.tag(AppTab.capture)
            WorkspaceProfileView()
                .tabItem { Label("Profile",systemImage: "person.crop.circle.fill") }.tag(AppTab.profile)
            SettingsView(embedded: true)
                .tabItem { Label("Settings",systemImage: "gearshape.fill") }.tag(AppTab.settings)
        }
        .fullScreenCover(isPresented: $scanningTechnical,onDismiss: {
            technicalRefresh += 1
            if savedTechnicalID != nil { showingTechnicalImport = true }
        }) {
            TechnicalRoomScanView(onSaved: { savedTechnicalID = $0 })
        }
        #else
        RoomListView()
        #endif
    }

}

#Preview {
    RootView()
}

#if os(iOS)
private struct CaptureHomeView: View {
    let onSaved: (LibraryItem) -> Void
    let onTechnicalSaved: (UUID) -> Void
    @Environment(RoomStore.self) private var store
    @State private var mode: ScanMode?
    @State private var savedItem: LibraryItem?
    @State private var savedTechnical: UUID?
    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading,spacing: 12) {
                        Image(systemName: "viewfinder").font(.system(size: 38,weight: .light)).foregroundStyle(.tint)
                        Text("Start with your space").font(.title2.bold())
                        Text("Capture the existing building, then explore changes in Studio.").foregroundStyle(.secondary)
                    }.padding(.vertical,16)
                }
                Section("New scan") {
                    choice(.house,title: "House",subtitle: "One continuous walkthrough across rooms",icon: "house.fill")
                    choice(.room,title: "Room",subtitle: "A floor plan and model of one room",icon: "square.split.bottomrightquarter.fill")
                    choice(.technicalRoom,title: "Technik Room",subtitle: "Equipment, pipes, ducts and photo evidence",icon: "wrench.and.screwdriver.fill")
                }
                Section {
                    Label("Your original scan stays separate from Studio edits.",systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !ScanCoordinator.isSupported {
                        Label("Scanning requires a compatible LiDAR device.",systemImage: "info.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.listStyle(.insetGrouped).navigationTitle("Capture")
        }
        .fullScreenCover(item: $mode,onDismiss: {
            if let savedItem { self.savedItem = nil; onSaved(savedItem) }
            if let savedTechnical { self.savedTechnical = nil; onTechnicalSaved(savedTechnical) }
        }) { mode in
            if mode == .technicalRoom {
                TechnicalRoomScanView(onSaved: { savedTechnical = $0 })
            } else {
                ScanView(mode: mode,onSaved: { savedItem = $0 }).environment(store)
            }
        }
    }
    private func choice(_ value: ScanMode,title: String,subtitle: String,icon: String) -> some View {
        Button { mode = value } label: {
            HStack(spacing: 16) {
                Image(systemName: icon).font(.title2).foregroundStyle(.tint).frame(width: 44,height: 48)
                VStack(alignment: .leading,spacing: 4) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
            }.padding(.vertical,8).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!ScanCoordinator.isSupported)
    }
}

private struct WorkspaceProfileView: View {
    @AppStorage("profile.displayName") private var displayName = ""
    @AppStorage("profile.organisation") private var organisation = ""
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill").font(.system(size: 72,weight: .light)).foregroundStyle(.secondary)
                        Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Your workspace" : displayName).font(.title2.bold())
                        Text(organisation.isEmpty ? "dWalkScan" : organisation).font(.subheadline).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical,20)
                }
                Section("Details") {
                    TextField("Name",text: $displayName).textContentType(.name)
                    TextField("Organisation",text: $organisation).textContentType(.organizationName)
                }
                Section {
                    Label("Profile details are stored on this device.",systemImage: "iphone")
                    Text("Google account and AI connections are managed in Settings.")
                }.font(.footnote).foregroundStyle(.secondary)
            }.navigationTitle("Profile")
        }
    }
}
#endif
