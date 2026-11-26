import SwiftUI

/// Project prose and scan/room-linked written notes share the existing stores.
/// No audio is loaded here; a combined text+audio record keeps both fields.
struct ProjectWrittenNotesView:View {
    let projectID:UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    @State private var notes = ""
    @State private var baseline = ""
    @State private var message:String?
    @State private var values:[ARNote] = []
    @State private var query = ""
    @State private var editing:ARNote?
    @State private var deleting:ARNote?
    @State private var creating = false
    @State private var confirmingClose = false
    private var sources:[ProjectLibraryEntry] { workspace.project(projectID)?.references.compactMap(workspace.entry).filter { !$0.isDesign } ?? [] }
    private var shown:[ARNote] {
        let allowed = Set(sources.map(\.reference))
        return values.filter { allowed.contains($0.reference) && (!$0.text.isEmpty || ($0.title?.isEmpty == false)) &&
            (query.isEmpty || $0.text.localizedCaseInsensitiveContains(query) || ($0.title ?? "").localizedCaseInsensitiveContains(query)) }
            .sorted { ($0.modifiedAt ?? $0.createdAt) > ($1.modifiedAt ?? $1.createdAt) }
    }
    var body:some View {
        Form {
            Section("Project notes") {
                TextEditor(text:$notes).frame(minHeight:160).accessibilityLabel("Project notes")
                Button("Save notes") {
                    if workspace.note(notes,projectID:projectID,expected:baseline) { baseline = notes }
                    else { message = workspace.error }
                }.disabled(notes == baseline || notes.count > 50_000)
            }
            Section("Written notes") {
                ForEach(shown) { note in
                    Button { editing = note } label: {
                        VStack(alignment:.leading,spacing:DS.Spacing.xs) {
                            Text(note.title ?? note.stem).font(.headline)
                            if !note.text.isEmpty { Text(note.text).font(.subheadline).lineLimit(3) }
                            Text(workspace.entry(note.reference).map { workspace.title($0,locale:locale) } ?? note.reference.itemID.uuidString)
                                .font(.caption).foregroundStyle(.secondary)
                            if let level = note.level { Text(StoryNaming.localizedName(for:level,locale:locale)).font(.caption).foregroundStyle(.secondary) }
                            if note.audioFileName != nil { Label("Also has audio",systemImage:"waveform").font(.caption).foregroundStyle(.secondary) }
                        }
                    }.buttonStyle(.plain).contextMenu {
                        Button("Edit",systemImage:"pencil") { editing = note }
                        Button("Delete written text",systemImage:"trash",role:.destructive) { deleting = note }
                    }
                }
                if shown.isEmpty { Text("No written notes yet").foregroundStyle(.secondary) }
            }
        }.navigationTitle("Written notes").searchable(text:$query,prompt:"Search written notes")
            .toolbar {
                ToolbarItem { Button("New written note",systemImage:"square.and.pencil") { creating = true }.disabled(sources.isEmpty) }
                ToolbarItem(placement:.confirmationAction) { Button("Done") { if notes != baseline { confirmingClose = true } else { dismiss() } } }
            }
            #if os(iOS)
            .navigationBarBackButtonHidden(notes != baseline)
            #endif
            .interactiveDismissDisabled(notes != baseline)
            .confirmationDialog("Close note with unsaved changes?",isPresented:$confirmingClose,titleVisibility:.visible) {
                Button("Save and close") {
                    if workspace.note(notes,projectID:projectID,expected:baseline) { baseline = notes; dismiss() }
                    else { message = workspace.error }
                }
                Button("Discard unsaved edits",role:.destructive) { dismiss() }
                Button("Keep editing",role:.cancel) {}
            }
            .task(id:projectID.uuidString+workspace.notesRoot.path) {
                if notes == baseline { notes = workspace.project(projectID)?.notes ?? ""; baseline = notes }
                await reload()
            }
            .sheet(item:$editing) { note in NoteTextEditor(note:note) { changed in try await save(changed,expected:note) } }
            .sheet(isPresented:$creating) {
                WrittenNoteComposer(projectID:projectID,entries:sources,summaries:workspace.scanSummaries,organization:workspace.index.scanOrganization ?? [:]) { note in
                    try await save(note,expected:nil)
                }
            }
            .confirmationDialog("Delete written text?",isPresented:Binding(get:{ deleting != nil },set:{ if !$0 { deleting = nil } }),titleVisibility:.visible) {
                Button("Delete written text",role:.destructive) { if let deleting { removeText(deleting) }; deleting = nil }
                Button("Cancel",role:.cancel) { deleting = nil }
            } message: { Text("Audio and transcripts are kept. A text-only note is removed; combined notes keep their audio.") }
            .alert("Notes not saved",isPresented:Binding(get:{ message != nil },set:{ if !$0 { message = nil } })) {
                Button("Load latest notes (discard draft)",role:.destructive) { notes = workspace.project(projectID)?.notes ?? notes; baseline = notes; message = nil; Task { await reload() } }
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
    private func reload() async {
        let root = workspace.notesRoot
        do {
            let loaded = try await Task.detached(priority:.utility) { try ARNoteStore.index(root:root,projectID:projectID).notes }.value
            guard !Task.isCancelled,root == workspace.notesRoot else { return }; values = loaded
        } catch { if !Task.isCancelled { message = error.localizedDescription } }
    }
    private func save(_ note:ARNote,expected:ARNote?) async throws {
        let root = workspace.notesRoot
        guard workspace.project(projectID)?.references.contains(note.reference) == true else { throw CocoaError(.fileNoSuchFile) }
        var changed = note; changed.modifiedAt = Date()
        do {
            _ = try await Task.detached(priority:.utility) { try ARNoteStore.upsertText(changed,root:root,expected:expected) }.value
            await reload()
        } catch { await reload(); throw error }
    }
    private func removeText(_ note:ARNote) {
        let root = workspace.notesRoot
        Task {
            do {
                _ = try await Task.detached(priority:.utility) { try ARNoteStore.removeWrittenText(note,root:root) }.value
                await reload()
            } catch { message = error.localizedDescription }
        }
    }
}

private struct WrittenNoteComposer:View {
    let projectID:UUID
    let entries:[ProjectLibraryEntry]
    let summaries:[String:ProjectScanSummary]
    let organization:[String:ScanOrganization]
    let save:(ARNote) async throws -> Void
    @State private var referenceID = ""
    @State private var roomID:UUID?
    @State private var title = ""
    @State private var text = ""
    @State private var saving = false
    @State private var error:String?
    @Environment(\.locale) private var locale
    @Environment(\.dismiss) private var dismiss
    private var entry:ProjectLibraryEntry? { entries.first { $0.id == referenceID } }
    var body:some View {
        NavigationStack {
            Form {
                Picker("Associated scan",selection:$referenceID) {
                    ForEach(entries) { Text($0.title).tag($0.id) }
                }
                if let entry,let summary = summaries[entry.id] {
                    Picker("Room",selection:$roomID) {
                        Text("Entire scan").tag(UUID?.none)
                        ForEach(summary.roomDetails) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
                TextField("Title",text:$title)
                TextEditor(text:$text).frame(minHeight:160).accessibilityLabel("Written note")
                if let error { Text(error).font(.caption).foregroundStyle(DS.ColorToken.error.color) }
            }.disabled(saving).navigationTitle("New written note")
                .toolbar {
                    ToolbarItem(placement:.cancellationAction) { Button("Cancel") { dismiss() }.disabled(saving) }
                    ToolbarItem(placement:.confirmationAction) { Button("Save") { commit() }.disabled(saving || entry == nil || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || text.count > 16_000 || title.count > 200) }
                }
        }.onAppear { referenceID = entries.first?.id ?? "" }
            .onChange(of:referenceID) { _,_ in roomID = nil }
            .interactiveDismissDisabled(saving || !text.isEmpty || !title.isEmpty)
    }
    private func commit() {
        guard let entry else { return }; saving = true
        let value = organization[entry.id],story = summaries[entry.id]?.roomDetails.first { $0.id == roomID }?.story
        let level = (summaries[entry.id]?.stories ?? 0) > 1 ? story.flatMap { value?.storyLevels?[$0] } : value?.level
        var note = ARNote(projectID:projectID,reference:entry.reference,number:1,level:level,roomID:roomID,position:nil,planPosition:nil,language:locale.identifier)
        note.title = title.isEmpty ? nil : title; note.text = text
        Task {
            defer { saving = false }
            do { try await save(note); dismiss() } catch { self.error = error.localizedDescription }
        }
    }
}
