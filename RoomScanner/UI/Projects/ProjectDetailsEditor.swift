import SwiftUI

struct ProjectDetailsEditor:View {
    let projectID:UUID
    var settings = false
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var details = ProjectDetails()
    @State private var saved = false
    @State private var appSettings = false
    private var parties:Binding<[ProjectParty]> { Binding(get:{ details.parties ?? [] },set:{ details.parties = $0 }) }
    private var preferences:Binding<ProjectPreferences> { Binding(get:{ details.preferences ?? .init() },set:{ details.preferences = $0 }) }
    var body:some View {
        Form {
            if settings {
                Section("Project defaults") {
                    Picker("Language",selection:preferences.language.text) { Text("Use app default").tag(""); ForEach(["system","en","de"],id:\.self) { Text($0).tag($0) } }
                    Picker("Units",selection:preferences.units.text) { Text("Use app default").tag(""); Text("Meters").tag("m"); Text("Millimeters").tag("mm"); Text("Both").tag("both") }
                    Picker("Export default",selection:preferences.exportFormat.text) { Text("Use app default").tag(""); ForEach(["pdf","dxf","json","usdzParametric"],id:\.self) { Text($0 == "usdzParametric" ? "USDZ" : $0.uppercased()).tag($0) } }
                    Toggle("Voice notes",isOn:Binding(get:{ preferences.wrappedValue.voice ?? true },set:{ preferences.wrappedValue.voice = $0 }))
                    Toggle("Photos",isOn:Binding(get:{ preferences.wrappedValue.photos ?? true },set:{ preferences.wrappedValue.photos = $0 }))
                    Picker("Storage location",selection:preferences.storage.text) { Text("Use app default").tag(""); Text("Local").tag("local"); Text("iCloud").tag("icloud") }
                    Text("Defaults apply to future scans. Existing files are not moved.").font(.caption)
                }
                Section { VoiceDiagnosticsView() }
                Section {
                    Button("App settings") { appSettings = true }
                    NavigationLink("Project data and deletion") { ProjectPrivacyView() }
                }
            } else {
                Section("Project details") {
                    TextField("Street",text:$details.street.text)
                    TextField("Postcode",text:$details.postcode.text)
                    TextField("City",text:$details.city.text)
                    TextField("Notes",text:$details.notes.text,axis:.vertical)
                }
                Section("Project parties") {
                    ForEach(parties) { party in ProjectPartyEditor(party:party) }.onDelete { details.parties?.remove(atOffsets:$0) }
                    Button("Add party",systemImage:"person.badge.plus") { details.parties = (details.parties ?? [])+[ProjectParty()] }.disabled((details.parties?.count ?? 0) >= 100)
                }
                Section { NavigationLink("Notes, measurements and exports") { RenovationProjectPage(projectID:projectID,onScan:{}) } }
            }
            Section {
                Button("Save project details") {
                    workspace.change { index in
                        guard let i = index.projects.firstIndex(where:{ $0.id == projectID }),details.valid else { throw CocoaError(.fileWriteUnknown) }
                        index.projects[i].details = details; index.projects[i].modifiedAt = Date()
                    }; saved = workspace.error == nil
                }.disabled(!details.valid)
                if saved { Label("Saved",systemImage:"checkmark.circle") }
            }
        }.onAppear { details = workspace.project(projectID)?.details ?? .init() }
            .onChange(of:details) { _,_ in saved = false }
            .sheet(isPresented:$appSettings) { SettingsView(includesProfile:true) }
    }
}
private struct ProjectPartyEditor:View {
    @Binding var party:ProjectParty
    var body:some View {
        DisclosureGroup(party.name ?? AppLanguage.text("New party")) {
            Picker("Role",selection:$party.role.text) { ForEach(ProjectParty.roles,id:\.self) { Text(AppLanguage.text($0)).tag($0) } }
            TextField("Name",text:$party.name.text)
            TextField("Company",text:$party.company.text)
            TextField("Phone",text:$party.phone.text)
            TextField("Email",text:$party.email.text)
            TextField("Notes",text:$party.notes.text,axis:.vertical)
        }
    }
}
private extension Binding where Value == String? {
    var text:Binding<String> { Binding<String>(get:{ wrappedValue ?? "" },set:{ wrappedValue = $0 }) }
}
