import SwiftUI

/// Read-only entry point. Uses catalogue summaries and existing thumbnails only;
/// opening a dashboard never decodes a scan or generates an export.
struct RenovationProjectPage: View {
    let projectID: UUID
    var onScan: () -> Void
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @State private var editing = false
    @State private var showingStatistics = false
    @State private var editingFloors = false
    @State private var roomToRename:RoomSelection?
    @State private var newRoomName = ""
    @State private var mutationError:String?
    private struct RoomSelection:Identifiable { let entry:ProjectLibraryEntry; let room:ProjectScanSummary.Room; var id:String { entry.id+room.id.uuidString } }

    private var project: RenovationProject? { workspace.project(projectID) }
    private var entries: [ProjectLibraryEntry] { project?.references.compactMap(workspace.entry).map { workspace.localizedEntry($0,locale:locale) } ?? [] }
    private var sources: [ProjectLibraryEntry] { entries.filter { !$0.isDesign } }
    private var plans: [ProjectLibraryEntry] { sources.filter { $0.reference.kind == .house || $0.reference.kind == .room } }
    private var summaries: [ProjectScanSummary] { plans.compactMap { workspace.scanSummaries[$0.id] } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                UnfinishedScansView(projectID:projectID)
                if let project {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name).font(.largeTitle.bold())
                        let address = [project.details?.street, project.details?.postcode, project.details?.city].compactMap { $0 }.filter { !$0.isEmpty }
                        if !address.isEmpty { Text(address.joined(separator: " · ")).foregroundStyle(.secondary) }
                        Text(project.modifiedAt, style: .date).font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.l) {
                        DSSectionHeader(title: "Overview", action: { showingStatistics = true })
                        DSStatGrid {
                            DSStatCell(title: "Scanned area (sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.floorArea }, locale: locale))
                            DSStatCell(title: "Wall area (net sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.wallAreaNet }, locale: locale))
                            DSStatCell(title: "Scanned floors (sum)", value: String(summaries.reduce(0) { $0 + $1.stories }))
                            DSStatCell(title: "Rooms", value: String(summaries.reduce(0) { $0 + $1.rooms }))
                        }
                        Text("Separate scans may overlap. Areas are scan totals, not a registered building area. Net wall area subtracts hosted openings; shared room faces remain counted.")
                            .font(.caption).foregroundStyle(.secondary)
                        DisclosureGroup("Floors & rooms") { roomDetails }
                        Button("Edit floors",systemImage:"building.2.crop.circle") { editingFloors = true }
                        if summaries.count < plans.count { Label("Some scan measurements are unavailable", systemImage: "exclamationmark.triangle").font(.caption) }
                    }.dsCard()
                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        DSSectionHeader(title: "Floor plans")
                        if plans.isEmpty {
                            Text("No scans yet").foregroundStyle(.secondary)
                            Button("Scan your space", systemImage: "viewfinder", action: onScan).dsProminentControl()
                        } else {
                            ScrollView(.horizontal) {
                                LazyHStack(alignment: .top, spacing: DS.Spacing.l) {
                                    ForEach(plans) { entry in
                                        NavigationLink(value: entry.reference) {
                                            DSThumbnailCard(title: workspace.title(entry,locale:locale)) {
                                                ProjectCover(url: entry.url.appendingPathComponent("thumbnail.png"), size: 200)
                                            }.frame(width: 200)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    ProjectRecentEvidenceView(projectID:projectID)
                    VStack(alignment: .leading, spacing: DS.Spacing.m) {
                        DSSectionHeader(title: "Reports & exports")
                        NavigationLink { ProjectDeliverablesView(projectID: projectID) } label: { dashboardRow("Project report and exports", symbol: "doc.richtext") }
                        NavigationLink { ProjectQuantitiesView(projectID: projectID) } label: { dashboardRow("Quantities", symbol: "ruler") }
                        NavigationLink { ProjectVerificationView(projectID: projectID) } label: { dashboardRow("Verify with a known distance", symbol: "checkmark.seal") }
                    }.dsCard()
                    let missing = project.references.filter { workspace.entry($0) == nil }
                    if !missing.isEmpty {
                        VStack(alignment: .leading, spacing: DS.Spacing.s) {
                            Text("Unavailable items").font(.headline)
                            ForEach(missing) { Label($0.itemID.uuidString, systemImage: "icloud.slash").font(.caption) }
                        }
                    }
                } else { ContentUnavailableView("Item unavailable", systemImage: "folder.badge.questionmark") }
            }.padding(DS.Spacing.l).frame(maxWidth: 1000, alignment: .leading).frame(maxWidth: .infinity)
        }
        .toolbar { ToolbarItem { Button("Edit", systemImage: "pencil") { editing = true } } }
        .sheet(isPresented: $editing) {
            NavigationStack {
                ProjectDetailsEditor(projectID:projectID,onClose:{ editing = false }).environment(workspace).navigationTitle("Project details")
            }
        }
        .sheet(isPresented:$editingFloors) { ProjectFloorEditor(projectID:projectID) }
        .sheet(item:$roomToRename) { selected in
            NavigationStack {
                Form { TextField("Room name",text:$newRoomName) }
                    .navigationTitle("Rename room")
                    .toolbar {
                        ToolbarItem(placement:.cancellationAction) { Button("Cancel") { roomToRename = nil } }
                        ToolbarItem(placement:.confirmationAction) { Button("Save") {
                            Task {
                                do { try await workspace.renameRoom(selected.entry,roomID:selected.room.id,to:newRoomName); roomToRename = nil }
                                catch { mutationError = error.localizedDescription }
                            }
                        }.disabled(newRoomName.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || newRoomName.count > 120) }
                    }
                    .alert("Unable to rename room",isPresented:Binding(get:{ mutationError != nil },set:{ if !$0 { mutationError = nil } })) { Button("OK") { mutationError = nil } } message:{ Text(mutationError ?? "") }
            }
        }
        .sheet(isPresented: $showingStatistics) {
            NavigationStack {
                List {
                    LabeledContent("Scans", value: String(sources.count))
                    LabeledContent("Technik", value: String(sources.filter { $0.reference.kind == .technicalRoom }.count))
                    LabeledContent("Studio designs", value: String(entries.filter(\.isDesign).count))
                    LabeledContent("Wall area (gross sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.wallAreaGross }, locale: locale))
                    LabeledContent("Wall area (net sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.wallAreaNet }, locale: locale))
                    roomDetails
                    Text("Capture-derived data: device validation pending.").font(.caption)
                }.navigationTitle("Overview")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingStatistics = false } } }
            }
        }
    }
    private var roomDetails:some View {
        ForEach(plans) { entry in
            if let summary = workspace.scanSummaries[entry.id] {
                DisclosureGroup(workspace.title(entry,locale:locale)) {
                    ForEach(Array(Set(summary.roomDetails.map(\.story))).sorted(),id:\.self) { story in
                        let mapped = workspace.organization(for:entry.reference)?.storyLevels?[story] ?? workspace.organization(for:entry.reference)?.level ?? story
                        DisclosureGroup(workspace.floorName(mapped,projectID:projectID,locale:locale)) {
                            ForEach(summary.roomDetails.filter { $0.story == story }) { room in
                                VStack(alignment:.leading,spacing:DS.Spacing.xs) {
                                    HStack {
                                        Text(room.name).font(.subheadline.weight(.semibold)); Spacer()
                                        Text(MeasurementFormat.squareMeters(room.area,locale:locale)).monospacedDigit().font(.subheadline)
                                        Button { newRoomName = room.name; roomToRename = .init(entry:entry,room:room) } label:{ Image(systemName:"pencil") }
                                            .accessibilityLabel("Rename room")
                                    }
                                    Text(room.elements.keys.sorted().map { "\(room.elements[$0] ?? 0) \($0)" }.joined(separator:" · ")).font(.caption).foregroundStyle(.secondary)
                                    HStack {
                                        Label(String(room.doors),systemImage:"door.left.hand.closed")
                                        Label(String(room.windows),systemImage:"window.vertical.closed")
                                    }.font(.caption).foregroundStyle(.secondary)
                                }.padding(.vertical,DS.Spacing.xs)
                            }
                        }
                    }
                }
            }
        }
    }
    private func dashboardRow(_ title: LocalizedStringKey, symbol: String) -> some View {
        HStack {
            Label(title, systemImage: symbol)
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
        }.frame(minHeight: DS.Size.minimumTouchTarget).contentShape(Rectangle())
    }
}
