import SwiftUI

struct ProjectVerificationView: View {
    struct Candidate: Identifiable { var id: String { reference.id+element.uuidString }; var reference: ProjectReference; var element: UUID; var label: String; var meters: Double }
    let projectID: UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @State private var candidates: [Candidate] = []
    @State private var selected: String?
    @State private var referenceMeters = 1.0
    @State private var method = ""
    @State private var error: String?
    private var candidate: Candidate? { candidates.first { $0.id == selected } }
    private var valid: Bool { referenceMeters.isFinite && referenceMeters > 0 && referenceMeters <= 100_000 && !method.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty && candidate != nil }
    var body: some View {
        Form {
            Section("Verify with a known distance") {
                Picker("Scan dimension",selection:$selected) { ForEach(candidates) { Text($0.label).tag(Optional($0.id)) } }
                TextField("Reference length (m)",value:$referenceMeters,format:.number.locale(locale))
                TextField("Method and measurement reference",text:$method)
                if let candidate {
                    LabeledContent("Scan length",value:MeasurementFormat.meters(candidate.meters,locale:locale))
                    if valid {
                        LabeledContent("Absolute difference",value:MeasurementFormat.millimeters(abs(candidate.meters-referenceMeters),locale:locale))
                        LabeledContent("Signed deviation",value:String(format:"%+.2f%%",locale:locale,(candidate.meters-referenceMeters)/referenceMeters*100))
                    }
                }
                Button("Save distance check") {
                    guard valid,let candidate else { return }
                    let check = ProjectDistanceCheck(projectID:projectID,reference:candidate.reference,elementID:candidate.element,label:candidate.label,referenceMeters:referenceMeters,observedMeters:candidate.meters,method:method)
                    workspace.change { if $0.distanceChecks == nil { $0.distanceChecks = [] }; $0.distanceChecks?.append(check) }
                }.disabled(!valid)
                Text("This check applies only to the selected dimension. It does not calibrate the scan or establish a general accuracy rating. Device validation pending.").font(.caption)
            }
            Section("Saved checks") {
                ForEach((workspace.index.distanceChecks ?? []).filter { $0.projectID == projectID }) { check in
                    VStack(alignment:.leading) {
                        Text(check.label).font(.headline)
                        Text(MeasurementFormat.meters(check.referenceMeters,locale:locale)+" → "+MeasurementFormat.meters(check.observedMeters,locale:locale))
                        Text(MeasurementFormat.millimeters(check.absoluteErrorMeters,locale:locale)+" · "+check.method).font(.caption)
                    }.swipeActions { Button("Delete",role:.destructive) { workspace.change { $0.distanceChecks?.removeAll { $0.id == check.id } } } }
                }
            }
            if let error { Text(error).foregroundStyle(DS.ColorToken.error.color) }
        }.navigationTitle("Distance check").task { await load() }
    }
    private func load() async {
        guard let project = workspace.project(projectID) else { return }
        let entries = project.references.compactMap(workspace.entry).filter { !$0.isDesign }, locale = locale
        do {
            candidates = try await Task.detached {
                var values: [Candidate] = []
                for entry in entries {
                    if entry.reference.kind == .technicalRoom {
                        let package = try TechnicalRoomPackage.read(from:entry.url)
                        for pipe in package.document.effectiveRoom.pipeRuns {
                            values.append(.init(reference:entry.reference,element:pipe.id,label:entry.title+" · "+AppLanguage.text("Pipe",locale:locale)+" "+String(pipe.id.uuidString.prefix(8)),meters:package.document.correctedLength(pipe.length.value)))
                        }
                    } else {
                        let house: House
                        if entry.reference.kind == .house { house = try HousePackage.readHouse(from:entry.url) } else { house = House(room:try RoomPackage.readPlan(from:entry.url)) }
                        for room in house.allRooms { for (i,wall) in room.walls.enumerated() {
                            values.append(.init(reference:entry.reference,element:wall.id,label:entry.title+" · "+room.name+" · "+AppLanguage.text("Wall",locale:locale)+" \(i+1)",meters:wall.length))
                        } }
                    }
                }
                return values.filter { $0.meters.isFinite && $0.meters > 0 }
            }.value
            selected = candidates.first?.id
        } catch { self.error = error.localizedDescription }
    }
}
