import SwiftUI

struct ProjectDetailsEditor:View {
    let projectID:UUID
    var settings = false
    var onClose:(()->Void)? = nil
    @Environment(RenovationWorkspace.self) private var workspace
    @State private var details = ProjectDetails()
    @State private var baseline:ProjectDetails?
    @State private var loaded = false
    @State private var message:String?
    @State private var confirmingClose = false
    @State private var saved = false
    @State private var appSettings = false
    @State private var expandedParty:UUID?
    private var parties:Binding<[ProjectParty]> { Binding(get:{ details.parties ?? [] },set:{ details.parties = $0 }) }
    private var preferences:Binding<ProjectPreferences> { Binding(get:{ details.preferences ?? .init() },set:{ details.preferences = $0 }) }
    var body:some View {
        Form {
            if settings {
                Section("Project defaults") {
                    Picker("Language",selection:preferences.language.text) { Text("Use app default").tag(""); ForEach(["system","en","de"],id:\.self) { Text($0).tag($0) } }
                    Text("Defaults apply to future scans. Existing files are not moved.").font(.caption)
                }
                Section("Measurement") {
                    Picker("Units",selection:preferences.units.text) { Text("Use app default").tag(""); Text("Meters").tag("m"); Text("Millimeters").tag("mm"); Text("Both").tag("both") }
                }
                Section("Capture defaults") {
                    Toggle("Voice notes",isOn:Binding(get:{ preferences.wrappedValue.voice ?? true },set:{ preferences.wrappedValue.voice = $0 }))
                    Toggle("Photos",isOn:Binding(get:{ preferences.wrappedValue.photos ?? true },set:{ preferences.wrappedValue.photos = $0 }))
                }
                Section("Export defaults") {
                    Picker("Export default",selection:preferences.exportFormat.text) { Text("Use app default").tag(""); ForEach(["pdf","dxf","json","usdzParametric"],id:\.self) { Text($0 == "usdzParametric" ? "USDZ" : $0.uppercased()).tag($0) } }
                }
                Section("Storage and recovery") {
                    Picker("Storage location",selection:preferences.storage.text) { Text("Use app default").tag(""); Text("Local").tag("local"); Text("iCloud").tag("icloud") }
                }
                Section {
                    Button("App settings") { appSettings = true }
                    DisclosureGroup("Advanced") {
                        VoiceDiagnosticsView()
                        NavigationLink("Project data and deletion") { ProjectPrivacyView(projectID:projectID) }
                    }
                }
            } else {
                Section("Project details") {
                    TextField("Street",text:$details.street.text)
                    TextField("Postcode",text:$details.postcode.text)
                    TextField("City",text:$details.city.text)
                    TextField("Notes",text:$details.notes.text,axis:.vertical)
                }
                Section("Project parties") {
                    ForEach(parties) { party in ProjectPartyEditor(party:party,expanded:$expandedParty) }.onDelete { details.parties?.remove(atOffsets:$0) }
                    Button("Add party",systemImage:"person.badge.plus") {
                        let party = ProjectParty()
                        details.parties = (details.parties ?? [])+[party]
                        expandedParty = party.id
                    }.disabled((details.parties?.count ?? 0) >= 100)
                }
            }
            Section {
                Button("Save project details") {
                    _ = save()
                }.disabled(!details.valid)
                if saved { Label("Saved",systemImage:"checkmark.circle") }
            }
        }.onAppear { if !loaded { reload(); loaded = true } }
            .onChange(of:details) { _,_ in saved = false }
            .sheet(isPresented:$appSettings) { SettingsView(includesProfile:true).projectPreferenceScope(nil) }
            .interactiveDismissDisabled(onClose != nil && dirty)
            .toolbar {
                if onClose != nil { ToolbarItem(placement:.confirmationAction) {
                    Button("Done") { if dirty { confirmingClose = true } else { onClose?() } }
                } }
            }
            .confirmationDialog("Save project changes before closing?",isPresented:$confirmingClose,titleVisibility:.visible) {
                Button("Save and close") { if save() { onClose?() } }
                Button("Discard unsaved edits",role:.destructive) { onClose?() }
                Button("Cancel",role:.cancel) {}
            }
            .alert("Project details not saved",isPresented:Binding(get:{ message != nil },set:{ if !$0 { message = nil } })) {
                Button("Reload latest details (discard draft)",role:.destructive) { reload(); message = nil }
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
    private var dirty:Bool { details != (baseline ?? .init()) }
    private func save() -> Bool {
        do { try workspace.saveDetails(details,projectID:projectID,expected:baseline); baseline = details; saved = true; return true }
        catch { saved = false; message = error.localizedDescription; return false }
    }
    private func reload() { baseline = workspace.project(projectID)?.details; details = baseline ?? .init(); saved = false }
}
private struct ProjectPartyEditor:View {
    @Binding var party:ProjectParty
    @Binding var expanded:UUID?
    private var otherDetails:Binding<[ProjectParty.CustomDetail]> {
        Binding(get:{ party.otherDetails ?? [] },set:{ party.otherDetails = $0.isEmpty ? nil : $0 })
    }
    var body:some View {
        DisclosureGroup(party.name.flatMap { $0.isEmpty ? nil : $0 } ?? party.role ?? AppLanguage.text("New party"),isExpanded:Binding(get:{ expanded == party.id },set:{ expanded = $0 ? party.id : nil })) {
            Picker("Role",selection:$party.role.text) { Text("Role").tag(""); ForEach(ProjectParty.roles,id:\.self) { Text(AppLanguage.text($0)).tag($0) } }
            TextField("Name",text:$party.name.text)
            TextField("Company",text:$party.company.text)
            TextField("Branch",text:$party.branch.text)
            TextField("Address",text:$party.address.text,axis:.vertical)
            TextField("Website",text:$party.website.text)
            TextField("Phone",text:$party.phone.text)
            TextField("Email",text:$party.email.text)
            TextField("Notes",text:$party.notes.text,axis:.vertical)
            Text("Other details")
                .font(DS.Typography.caption)
                .foregroundStyle(DS.ColorToken.textSecondary.color)
            ForEach(otherDetails) { $detail in
                HStack(alignment:.top,spacing:DS.Spacing.s) {
                    VStack(alignment:.leading,spacing:DS.Spacing.xs) {
                        TextField("Key",text:$detail.key)
                            .font(DS.Typography.subheadline.weight(.medium))
                        TextField("Value",text:$detail.value,axis:.vertical)
                    }
                    Button(role:.destructive) {
                        let targetID = detail.id
                        var updated = otherDetails.wrappedValue
                        updated.removeAll { $0.id == targetID }
                        otherDetails.wrappedValue = updated
                    } label: {
                        Label("Remove detail",systemImage:"minus.circle")
                            .labelStyle(.iconOnly)
                            .frame(minWidth:DS.Size.minimumTouchTarget,minHeight:DS.Size.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(DS.ColorToken.error.color)
                }
            }
            Button("Add detail",systemImage:"plus.circle") {
                otherDetails.wrappedValue.append(.init())
            }
            .disabled((party.otherDetails?.count ?? 0) >= 50)
        }
    }
}
private extension Binding where Value == String? {
    var text:Binding<String> { Binding<String>(get:{ wrappedValue ?? "" },set:{ wrappedValue = $0 }) }
}
