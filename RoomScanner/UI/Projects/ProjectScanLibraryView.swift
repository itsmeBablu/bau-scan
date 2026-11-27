import SwiftUI

struct ProjectScanLibraryView: View {
    let projectID: UUID
    let technical: Bool
    var onScan:(()->Void)? = nil
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    private var compact: Bool { sizeClass == .compact }
    #else
    private var compact: Bool { false }
    #endif
    @AppStorage private var layout:String
    init(projectID:UUID,technical:Bool,onScan:(()->Void)? = nil) {
        self.projectID = projectID; self.technical = technical; self.onScan = onScan
        _layout = AppStorage(wrappedValue:"grid",technical ? "ui.technicalLibrary.layout" : "ui.houseLibrary.layout")
    }
    @State private var closedBuildings: Set<ProjectScanGrouping.BuildingKey> = []
    @State private var closedLevels: Set<LevelIdentity> = []
    private struct LevelIdentity: Hashable {
        let building: ProjectScanGrouping.BuildingKey
        let level: ProjectScanGrouping.LevelKey
    }
    private var entries: [ProjectLibraryEntry] {
        workspace.project(projectID)?.references.compactMap(workspace.entry).filter {
            technical ? $0.reference.kind == .technicalRoom : ($0.reference.kind == .house || $0.reference.kind == .room)
        } ?? []
    }
    private var buildings: [ProjectScanGrouping.Building] {
        ProjectScanGrouping.buildings(entries:entries,organization:workspace.index.scanOrganization ?? [:],locale:locale)
    }
    var body: some View {
        Group {
            if entries.isEmpty { ContentUnavailableView("No scans yet",systemImage:technical ? "wrench.and.screwdriver" : "house") }
            else if layout == "grid" {
                ScrollView { LazyVStack(alignment:.leading,spacing:DS.Spacing.l) { groups }.padding(DS.Spacing.l) }
            } else { List { groups } }
        }
        .safeAreaInset(edge:.bottom) {
            HStack {
                Spacer()
                if let onScan { Button(action:onScan) { Image(systemName:"plus").frame(width:44,height:44) }.accessibilityLabel(technical ? "Scan Technik room" : "Scan a house") }
                Menu {
                Picker("Layout",selection:$layout) {
                    Label("List",systemImage:"list.bullet").tag("list")
                    Label("Grid",systemImage:"square.grid.2x2").tag("grid")
                }.pickerStyle(.inline)
                } label: { Label("View options",systemImage:"ellipsis.circle") }
                    .labelStyle(.iconOnly).frame(width:44,height:44).accessibilityIdentifier("scan.library.options")
            }.buttonStyle(.plain).padding(.horizontal,12).padding(.vertical,4).dsMaterial(in:Capsule()).fixedSize().frame(maxWidth:.infinity,alignment:.trailing).padding(.horizontal).padding(.bottom,8)
        }
    }
    private var groups: some View {
        ForEach(buildings) { building in
            DisclosureGroup(isExpanded:Binding(get:{ !closedBuildings.contains(building.id) },set:{ expanded in
                if expanded { closedBuildings.remove(building.id) } else { closedBuildings.insert(building.id) }
            })) {
                ForEach(building.levels) { level in
                    let identity = LevelIdentity(building:building.id,level:level.id)
                    DisclosureGroup(isExpanded:Binding(get:{ !closedLevels.contains(identity) },set:{ expanded in
                        if expanded { closedLevels.remove(identity) } else { closedLevels.insert(identity) }
                    })) { scanRows(level.scans) } label: {
                        HStack {
                            Text(levelName(level.id)); Spacer()
                            Text(String(level.scans.count)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } label: {
                Label(building.id.name ?? AppLanguage.text("Unassigned building",locale:locale),systemImage:"building.2")
                    .font(.headline)
            }
        }
    }
    @ViewBuilder private func scanRows(_ scans:[ProjectLibraryEntry]) -> some View {
        if layout == "grid" {
            LazyVGrid(columns:compact ? [GridItem(.flexible()),GridItem(.flexible())] : [GridItem(.adaptive(minimum:180))],spacing:DS.Spacing.l) {
                ForEach(scans) { scanCell($0) }
            }
        } else { ForEach(scans) { scanCell($0) } }
    }
    private func scanCell(_ entry:ProjectLibraryEntry) -> some View {
        VStack(alignment:.leading,spacing:DS.Spacing.s) {
            ProjectEntryRow(entry:entry,card:layout == "grid").buttonStyle(.plain)
            if entry.reference.kind == .house,let summary = workspace.scanSummaries[entry.id] {
                DisclosureGroup("Rooms") {
                    ForEach(summary.roomDetails) { room in
                        HStack(alignment:.top) {
                            VStack(alignment:.leading) {
                                Text(room.name)
                                let mapped = workspace.organization(for:entry.reference)?.storyLevels?[room.story]
                                Text(mapped.map { workspace.floorName($0,projectID:projectID,locale:locale) } ?? AppLanguage.text("Unassigned level",locale:locale))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(MeasurementFormat.squareMeters(room.area,locale:locale)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }.font(.subheadline)
            }
        }
    }
    private func levelName(_ key:ProjectScanGrouping.LevelKey) -> String {
        if let level = key.number { return workspace.floorName(level,projectID:projectID,locale:locale) }
        return key.otherName ?? AppLanguage.text("Unassigned level",locale:locale)
    }
}
