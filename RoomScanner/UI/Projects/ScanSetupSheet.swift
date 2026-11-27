#if os(iOS)
import SwiftUI

struct ProjectScanRequest:Identifiable {
    let id = UUID()
    let projectID:UUID?
    let mode:ScanMode
}

/// Prepared on disk before presenting either scanner. Does not own a camera/session.
struct PreparedProjectCapture: Identifiable {
    let mode: ScanMode
    let projectID: UUID?
    let persistence: CapturePersistence
    let location:StorageLocation
    var id: UUID { persistence.id }
}

struct ScanSetupSheet: View {
    let workspace: RenovationWorkspace
    let defaultLocation:StorageLocation
    let onPrepared: (PreparedProjectCapture) -> Void
    private let fixedProjectID:UUID?
    @State private var projectID: UUID?
    private let mode: ScanMode
    @State private var organization: ScanOrganization
    @State private var preparing = false
    @State private var confirmingCollision = false
    @State private var message: String?
    @Environment(\.dismiss) private var dismiss

    init(workspace: RenovationWorkspace, projectID: UUID?, mode: ScanMode, defaultLocation:StorageLocation, onPrepared: @escaping (PreparedProjectCapture) -> Void) {
        self.workspace = workspace; self.defaultLocation = defaultLocation; self.onPrepared = onPrepared
        fixedProjectID = projectID
        _projectID = State(initialValue: projectID.flatMap { workspace.project($0)?.isUnsorted == true ? nil : $0 })
        self.mode = mode
        _organization = State(initialValue: .init(kind: mode == .technicalRoom ? .technicalRoom : mode == .house ? .house : .room))
    }
    private var collisions: [ProjectReference] {
        workspace.index.numberCollisions(for: organization, projectID: projectID ?? ProjectIndex.unsortedID)
    }
    private var nextNumber: Int? {
        workspace.index.suggestedNumber(for: organization, projectID: projectID ?? ProjectIndex.unsortedID)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Save to project") {
                    if let fixedProjectID {
                        LabeledContent("Project",value:workspace.project(fixedProjectID)?.name ?? AppLanguage.text("Unsorted"))
                    } else {
                    Picker("Project", selection: $projectID) {
                        Text("Unsorted").tag(UUID?.none)
                        ForEach(workspace.index.projects.filter { !$0.isUnsorted }) { project in
                            Text(project.name).tag(Optional(project.id))
                        }
                    }
                    }
                    LabeledContent("Scan",value:AppLanguage.text(mode == .technicalRoom ? "Technik" : "House"))
                }
                ScanOrganizationFields(value: $organization)
                if let nextNumber { Section { Button("Suggest next number") { organization.number = nextNumber } } }
                Section("Before you start") {
                    if mode == .technicalRoom { Text("Technical room capture saves locally. Project storage defaults apply to House scans.").font(.caption) }
                    Text("Use good light. Clear access to walls and installations. Move slowly and avoid reflective surfaces.")
                    Text("Device validation pending. Verify critical dimensions independently.").font(.caption)
                    if !ScanCoordinator.isSupported { Text("LiDAR capture is unavailable on this device. You can still open saved projects and designs.") }
                }
                if preparing { ProgressView("Preparing scan…") }
            }
            .disabled(preparing)
            .navigationTitle("New scan")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(preparing) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") { if collisions.isEmpty { start() } else { confirmingCollision = true } }
                        .disabled(preparing || !ScanCoordinator.isSupported || (try? organization.validate()) == nil)
                }
            }
            .confirmationDialog("This number is already used here", isPresented: $confirmingCollision, titleVisibility: .visible) {
                if let nextNumber { Button("Use next available number") { organization.number = nextNumber; start() } }
                Button("Keep both") { start() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("Existing scans are kept. Choose another number or keep both labels.") }
            .alert("New scan", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
        }
        .interactiveDismissDisabled(preparing)
        .projectPreferenceScope(projectID.map { workspace.project($0)?.details?.preferences ?? .init() })
    }
    private func start() {
        guard !preparing else { return }
        preparing = true
        let mode = mode, projectID = fixedProjectID ?? projectID, organization = organization
        Task {
            defer { preparing = false }
            do {
                try organization.validate()
                if let projectID, workspace.project(projectID) == nil { throw CocoaError(.fileNoSuchFile) }
                let preferences = projectID.flatMap { workspace.project($0)?.details?.preferences }
                var location = defaultLocation
                if mode == .technicalRoom { location = RootView.hasForcedRoot ? defaultLocation : .local() }
                else if preferences?.storage == "local" { location = RootView.hasForcedRoot ? defaultLocation : .local() }
                else if preferences?.storage == "icloud",defaultLocation.kind != .iCloud {
                    message = AppLanguage.text("Connect iCloud in App settings before scanning into it."); return
                }
                let disk = CapturePersistence(kind: mode == .technicalRoom ? .technical : mode == .house ? .house : .room,
                                              projectID: projectID, organization: organization)
                try await disk.prepare()
                onPrepared(.init(mode: mode, projectID: projectID, persistence: disk,location:location))
                dismiss()
            } catch { message = error.localizedDescription }
        }
    }
}
#endif
