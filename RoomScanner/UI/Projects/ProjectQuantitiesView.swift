import SwiftUI

struct ProjectQuantitiesView: View {
    let projectID: UUID
    var reference:ProjectReference? = nil
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @State private var report: ProjectReport?
    @State private var error: String?
    @AppStorage("renovation.wastePercent") private var wastePercent = 10.0
    private var quantities: [RenovationQuantities] { report?.scans.flatMap { $0.house?.allRooms.map(RenovationQuantities.init) ?? [] } ?? [] }
    var body: some View {
        List {
            Section("Assumptions") {
                Text("Independent surveys may overlap. Ceiling area is projected; volume is a height-based range. Device validation pending.")
                Stepper(value:$wastePercent,in:0...100,step:1) { Text(AppLanguage.text("Waste allowance")+": "+String(format:"%.0f%%",locale:locale,wastePercent)) }
            }
            Section("Sum of listed survey quantities") {
                LabeledContent("Floor area",value:MeasurementFormat.squareMeters(quantities.reduce(0){$0+$1.floorArea},locale:locale))
                LabeledContent("Net wall area",value:MeasurementFormat.squareMeters(quantities.reduce(0){$0+$1.wallAreaNet},locale:locale))
                Text("This sum is not a deduplicated building total.").font(.caption)
            }
            ForEach(Array((report?.scans ?? []).enumerated()),id:\.offset) { _,scan in
                Section(scan.title) {
                    ForEach(Array(scan.detailLines.enumerated()),id:\.offset) { Text($0.element).font(.subheadline) }
                    ForEach(scan.house?.allRooms ?? []) { room in
                        let q = RenovationQuantities(room)
                        DisclosureGroup(room.name) {
                            ForEach(ProjectQuantitiesCSV.lines(q,locale:locale),id:\.self) { Text($0) }
                            LabeledContent("Flooring incl. waste",value:MeasurementFormat.squareMeters(q.flooring(wastePercent:wastePercent),locale:locale))
                            LabeledContent("Paint area incl. waste",value:MeasurementFormat.squareMeters(q.paintArea(wastePercent:wastePercent),locale:locale))
                        }
                    }
                }
            }
            if let report { ForEach(report.unresolved,id:\.self) { Text($0).foregroundStyle(.secondary) } }
            if let error { Text(error).foregroundStyle(DS.ColorToken.error.color) }
        }.navigationTitle("Quantities").task {
            if !wastePercent.isFinite { wastePercent = 10 }
            guard var project = workspace.project(projectID) else { return }
            if let reference { project.references = project.references.filter { $0 == reference } }
            let entries = workspace.entries.map { workspace.localizedEntry($0,locale:self.locale) }, locale = locale,selectedProject = project
            do {
                let loaded = try await BackgroundWork.run { try ProjectReportLoader.load(project:selectedProject,entries:entries,locale:locale,includePhotos:false) }
                guard !Task.isCancelled else { return }; report = loaded
            }
            catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
