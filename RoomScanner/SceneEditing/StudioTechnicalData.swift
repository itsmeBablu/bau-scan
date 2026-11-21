import SwiftUI

struct StudioEquipmentData: Codable,Equatable {
    enum Source: String,Codable,CaseIterable { case nameplate, manufacturer, calculation }
    var manufacturer = ""
    var model = ""
    var source = Source.nameplate
    var reference = ""
    var outputKW: Double?
    var volumeLitres: Double?
    var flowM3PerHour: Double?
    var ratedPressureBar: Double?
    var frontServiceClearanceM: Double?
    var notes = ""
    func validate() throws {
        let values = [outputKW,volumeLitres,flowM3PerHour,ratedPressureBar,frontServiceClearanceM].compactMap { $0 }
        guard values.allSatisfy({ $0.isFinite && $0 >= 0 && $0 <= 1e9 }),manufacturer.count <= 120,model.count <= 120,reference.count <= 1200,notes.count <= 2000,
              values.isEmpty || !reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SceneEditDocument.Failure.invalid }
    }
}

struct StudioTechnicalDataView: View {
    @State var data: StudioEquipmentData
    let save: (StudioEquipmentData) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Section("Equipment data · not inferred from LiDAR") {
                    TextField("Manufacturer",text: $data.manufacturer)
                    TextField("Model / type",text: $data.model)
                    Picker("Data source",selection: $data.source) { ForEach(StudioEquipmentData.Source.allCases,id: \.self) { Text($0.rawValue.capitalized).tag($0) } }
                    TextField("Nameplate / datasheet / calculation reference",text: $data.reference,axis: .vertical)
                    TextField("Heating / cooling output (kW)",value: $data.outputKW,format: .number)
                    TextField("Tank capacity (litres)",value: $data.volumeLitres,format: .number)
                    TextField("Design flow (m³/h)",value: $data.flowM3PerHour,format: .number)
                    TextField("Rated pressure (bar)",value: $data.ratedPressureBar,format: .number)
                    TextField("Required front service clearance (m)",value: $data.frontServiceClearanceM,format: .number)
                    TextField("Notes",text: $data.notes,axis: .vertical)
                    Text("Capacity, DN, wall thickness and service requirements cannot be established from an external scan. Record the actual operating conditions and manufacturer instructions. Object-envelope collision checks do not verify service clearances or installation compliance.").font(.caption).foregroundStyle(.secondary)
                }
                StudioGermanReferences()
                if let error { Text(error).foregroundStyle(.red) }
            }.formStyle(.grouped).navigationTitle("Technical equipment")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save") {
                        do { try data.validate(); try save(data); dismiss() } catch { self.error = "Enter a valid value and its source reference before saving." }
                    } }
                }
        }
        #if os(macOS)
        .frame(minWidth: 520,minHeight: 600)
        #endif
    }
}

struct StudioGermanReferences: View {
    var body: some View {
        Section("German planning references") {
            Text("Use the applicable edition and scope for the project. These links identify planning references; the app does not reproduce the standards or certify compliance. Manufacturer instructions, local utility requirements and the relevant Landesbauordnung/Feuerungsverordnung also need project-specific review.").font(.caption).foregroundStyle(.secondary)
            reference("DIN EN 12828 · water-based heating design","https://www.dinmedia.de/de/norm/din-en-12828/203258170")
            reference("DIN EN 12831-1 · design heat load","https://www.dinmedia.de/de/norm/din-en-12831-1/261292587")
            reference("VDI 2050 series · technical plant rooms","https://www.vdi.de/mitgliedschaft/vdi-richtlinien/seite?tx_vdiguidelines_guidelinelist%5Bfilter%5D%5BsearchTerm%5D=2050")
            reference("VDI 2035 · heating-water quality","https://www.vdi.de/mitgliedschaft/vdi-richtlinien/unsere-richtlinien-highlights/vdi-2035")
            reference("VDI 6022 · ventilation hygiene","https://www.vdi.de/mitgliedschaft/vdi-richtlinien/unsere-richtlinien-highlights/vdi-6022")
            reference("DVGW · drinking-water installation / W 551 series","https://www.dvgw.de/themen/wasser/trinkwasser-installation")
            Text("DIN 18012 concerns building service connection facilities; it is not a universal equipment-room sizing rule. Check the current edition, utility requirements and whether the facility is within its scope.").font(.caption)
        }
    }
    private func reference(_ title: String,_ url: String) -> some View { Link(title,destination: URL(string: url)!) }
}
