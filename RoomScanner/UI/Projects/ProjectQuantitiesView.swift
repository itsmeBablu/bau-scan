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
                Text("Extra material for cuts and offcuts. Measured areas stay unchanged.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Sum of listed survey quantities") {
                LabeledContent { Text(MeasurementFormat.squareMeters(quantities.reduce(0){$0+$1.floorArea},locale:locale)) } label: { Label("Floor area",systemImage:DS.Symbol.floorArea) }
                LabeledContent { Text(MeasurementFormat.squareMeters(quantities.reduce(0){$0+$1.wallAreaNet},locale:locale)) } label: { Label("Net wall area",systemImage:DS.Symbol.wallArea) }
                Text("This sum is not a deduplicated building total.").font(.caption)
            }
            ForEach(Array((report?.scans ?? []).enumerated()),id:\.offset) { _,scan in
                if let house = scan.house {
                    ForEach(house.allRooms) { room in
                        Section(scan.title+" · "+RoomNaming.displayName(room.name,label:room.label,locale:locale)) {
                            ForEach(metrics(RenovationQuantities(room))) { metric in
                                LabeledContent {
                                    Text(metric.value).monospacedDigit().multilineTextAlignment(.trailing)
                                } label: {
                                    Label { Text(LocalizedStringKey(metric.key)) } icon: {
                                        if metric.key == "Windows" { DSWindowFrameIcon() }
                                        else { Image(systemName:metric.icon) }
                                    }
                                }
                                .font(.subheadline)
                                .listRowInsets(EdgeInsets(top:12,leading:12,bottom:12,trailing:12))
                            }
                        }
                    }
                    if !scan.pins.isEmpty { Section(scan.title) { ForEach(scan.pins) { Label($0.text,systemImage:"mappin") } } }
                } else {
                    Section(scan.title) {
                        ForEach(Array(scan.detailLines.enumerated()),id:\.offset) { Label($0.element,systemImage:"wrench.and.screwdriver").font(.subheadline) }
                    }
                }
            }
            if let report { ForEach(report.unresolved,id:\.self) { Text($0).foregroundStyle(.secondary) } }
            if let error { Text(error).foregroundStyle(DS.ColorToken.error.color) }
        }.listStyle(.plain)
            .listRowInsets(EdgeInsets(top:12,leading:12,bottom:12,trailing:12))
            .contentMargins(.horizontal,0,for:.scrollContent)
            .navigationTitle("Quantities").task {
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
    private struct Metric:Identifiable {
        let key:String; let icon:String; let value:String
        var id:String { key }
    }
    private func metrics(_ q:RenovationQuantities) -> [Metric] {
        func area(_ value:Double) -> String { MeasurementFormat.squareMeters(value,locale:locale) }
        func length(_ value:Double) -> String { MeasurementFormat.meters(value,locale:locale) }
        return [
            .init(key:"Floor area (m²)",icon:DS.Symbol.floorArea,value:area(q.floorArea)),
            .init(key:"Net wall area (m²)",icon:DS.Symbol.wallArea,value:area(q.wallAreaNet)),
            .init(key:"Projected ceiling area (m²)",icon:DS.Symbol.ceilingArea,value:area(q.ceilingProjectedArea)),
            .init(key:"Perimeter (m)",icon:DS.Symbol.perimeter,value:length(q.perimeter)),
            .init(key:"Height min (m)",icon:DS.Symbol.minimumHeight,value:length(q.heightMin)),
            .init(key:"Height max (m)",icon:DS.Symbol.maximumHeight,value:length(q.heightMax)),
            .init(key:"Volume min–max (m³)",icon:DS.Symbol.volume,value:String(format:"%.2f – %.2f",locale:locale,q.volumeMin,q.volumeMax)),
            .init(key:"Doors",icon:DS.Symbol.door,value:String(q.doors)),
            .init(key:"Windows",icon:DS.Symbol.window,value:String(q.windows)),
            .init(key:"Other openings",icon:DS.Symbol.otherOpening,value:String(q.otherOpenings)),
            .init(key:"Unhosted openings (not subtracted)",icon:DS.Symbol.unhostedOpening,value:String(q.unhostedOpenings)),
            .init(key:"Waste allowance",icon:DS.Symbol.wasteAllowance,value:String(format:"%.0f%%",locale:locale,wastePercent)),
            .init(key:"Flooring incl. waste (m²)",icon:DS.Symbol.flooring,value:area(q.flooring(wastePercent:wastePercent))),
            .init(key:"Paint area incl. waste (m²)",icon:DS.Symbol.paintArea,value:area(q.paintArea(wastePercent:wastePercent)))
        ]
    }
}
