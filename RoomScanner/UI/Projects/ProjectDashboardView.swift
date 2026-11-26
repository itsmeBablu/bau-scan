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
    private var project: RenovationProject? { workspace.project(projectID) }
    private var entries: [ProjectLibraryEntry] { project?.references.compactMap(workspace.entry).map { workspace.localizedEntry($0,locale:locale) } ?? [] }
    private var sources: [ProjectLibraryEntry] { entries.filter { !$0.isDesign } }
    private var plans: [ProjectLibraryEntry] { sources.filter { $0.reference.kind == .house || $0.reference.kind == .room } }
    private var summaries: [ProjectScanSummary] { plans.compactMap { workspace.scanSummaries[$0.id] } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Spacing.xl) {
                if let project {
                    VStack(alignment: .leading, spacing: DS.Spacing.s) {
                        Text(project.isUnsorted ? AppLanguage.text("Unsorted") : project.name).font(.largeTitle.bold())
                        let address = [project.details?.street, project.details?.postcode, project.details?.city].compactMap { $0 }.filter { !$0.isEmpty }
                        if !address.isEmpty { Text(address.joined(separator: " · ")).foregroundStyle(.secondary) }
                        Text(project.modifiedAt, style: .date).font(.subheadline).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: DS.Spacing.l) {
                        DSSectionHeader(title: "Overview", action: { showingStatistics = true })
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 130), alignment: .leading)], spacing: DS.Spacing.l) {
                            DSStatCell(title: "Scanned area (sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.floorArea }, locale: locale))
                            DSStatCell(title: "Wall area (net sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.wallAreaNet }, locale: locale))
                            DSStatCell(title: "Scanned floors (sum)", value: String(summaries.reduce(0) { $0 + $1.stories }))
                            DSStatCell(title: "Rooms", value: String(summaries.reduce(0) { $0 + $1.rooms }))
                        }
                        Text("Separate scans may overlap. Areas are scan totals, not a registered building area. Net wall area subtracts hosted openings; shared room faces remain counted.")
                            .font(.caption).foregroundStyle(.secondary)
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
                                                ProjectCover(url: entry.url.appendingPathComponent("thumbnail.png"), size: DS.Size.thumbnail)
                                            }.frame(width: DS.Size.thumbnail)
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
        .sheet(isPresented: $showingStatistics) {
            NavigationStack {
                List {
                    LabeledContent("Scans", value: String(sources.count))
                    LabeledContent("Technik", value: String(sources.filter { $0.reference.kind == .technicalRoom }.count))
                    LabeledContent("Studio designs", value: String(entries.filter(\.isDesign).count))
                    LabeledContent("Wall area (gross sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.wallAreaGross }, locale: locale))
                    LabeledContent("Wall area (net sum)", value: MeasurementFormat.squareMeters(summaries.reduce(0) { $0 + $1.wallAreaNet }, locale: locale))
                    Text("Capture-derived data: device validation pending.").font(.caption)
                }.navigationTitle("Overview")
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showingStatistics = false } } }
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

/// Existing conflict-aware project notes editor, separated from the overview.
struct ProjectWrittenNotesView: View {
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var notes = ""
    @State private var baseline = ""
    @State private var message: String?
    var body: some View {
        Form {
            TextEditor(text: $notes).frame(minHeight: 240).accessibilityLabel("Project notes")
            Button("Save notes") {
                if workspace.note(notes, projectID: projectID, expected: baseline) { baseline = notes }
                else { message = workspace.error }
            }.disabled(notes == baseline || notes.count > 50_000)
        }.navigationTitle("Project notes")
            .onAppear { if notes == baseline { notes = workspace.project(projectID)?.notes ?? ""; baseline = notes } }
            .alert("Notes not saved", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("Load latest notes (discard draft)", role: .destructive) { notes = workspace.project(projectID)?.notes ?? notes; baseline = notes; message = nil }
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
}
