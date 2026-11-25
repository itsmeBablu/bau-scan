#if os(iOS)
import SwiftUI

/// Small capture HUD. The existing recorder owns audio, never the ARSession.
struct LiveScanNotes: View {
    let reference: ProjectReference
    let persistence: CapturePersistence
    let workspace: RenovationWorkspace?
    let projectID: UUID?
    var position: () -> TechnicalPoint3?
    var pose: () -> [Double]?
    var roomID: () -> UUID? = { nil }
    var level: () -> Int? = { nil }
    @State private var recorder = NoteAudioRecorder()
    @State private var holding = false
    @State private var pin: TechnicalPoint3?
    @State private var text = ""
    @State private var editing = false
    @State private var message: String?
    @State private var busy = false
    @State private var pending: NoteAudioRecorder.Clip?
    @State private var capturedPose: [Double]?
    @State private var capturedRoom: UUID?
    @State private var capturedLevel: Int?
    @State private var pendingMedia: ScanVoiceMedia?
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(spacing:12) {
                Image(systemName:recorder.recording ? "mic.fill" : "mic")
                    .foregroundStyle(recorder.recording ? Color.red : Color.primary)
                    .frame(width:48,height:48).background(.regularMaterial,in:Circle())
                    .contentShape(Circle())
                    .onLongPressGesture(minimumDuration:0.18,pressing:{ pressed in
                        holding = pressed
                        if !pressed { recorder.stop() }
                    }) {
                        guard !busy else { return }
                        capturedPose = pose(); capturedRoom = roomID(); capturedLevel = level()
                        recorder.onClip = { clip in pending = clip; saveAudio(clip) }
                        Task { if holding { await recorder.start() }; if !holding { recorder.stop() } }
                    }
                    .accessibilityLabel("Hold to record voice note")
                    .accessibilityAction(named:Text("Start recording")) {
                        capturedPose = pose(); capturedRoom = roomID(); capturedLevel = level()
                        recorder.onClip = { clip in pending = clip; saveAudio(clip) }
                        Task { await recorder.start() }
                    }
                if recorder.recording {
                    Text(Duration.seconds(recorder.elapsed).formatted(.time(pattern:.minuteSecond))).monospacedDigit()
                    Button("Stop") { recorder.stop() }
                }
                Button {
                    guard let point = position() else { message = AppLanguage.text("Aim at a tracked surface"); return }
                    pin = point; capturedPose = pose(); capturedRoom = roomID(); capturedLevel = level(); editing = true
                } label: { Image(systemName:pin == nil ? "mappin" : "mappin.circle.fill").frame(width:48,height:48) }
                    .background(.regularMaterial,in:Circle()).accessibilityLabel("Pin a note to this surface")
                if pending != nil,!recorder.recording { Button("Retry saving") { if let pending { saveAudio(pending) } } }
            }.disabled(busy)
            if recorder.recording { Text("Release to save · 60 s maximum").font(.caption) }
            else { Text("Hold mic · aim and pin").font(.caption).padding(4).background(.regularMaterial,in:Capsule()) }
            if let error = recorder.error ?? message { Text(error).font(.caption).padding(6).background(.regularMaterial,in:Capsule()) }
        }
        .sheet(isPresented:$editing) {
            NavigationStack {
                Form {
                    TextField("Note",text:$text,axis:.vertical)
                    Text("Pinned to the observed scan surface. Verify alignment after recovery.").font(.caption)
                    Button("Save note") { saveText() }.disabled(busy || text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                }.navigationTitle("Pinned note")
                .toolbar { ToolbarItem(placement:.cancellationAction) { Button("Cancel") { editing = false } } }
            }.interactiveDismissDisabled(busy)
        }
        .onDisappear { recorder.stop(partial:true) }
    }
    private func note(owner:UUID) -> ARNote {
        var note = ARNote(projectID:owner,reference:reference,number:1,level:capturedLevel,
            roomID:capturedRoom,position:pin,planPosition:nil,language:Locale.current.identifier)
        note.text = text
        return note
    }
    private func owner() throws -> UUID {
        guard let workspace else { return projectID ?? ProjectIndex.unsortedID }
        var result: UUID?
        workspace.change { result = try $0.voiceNotesProject(for:reference,preferredProjectID:projectID) }
        guard let result else { throw CocoaError(.fileWriteUnknown) }; return result
    }
    private func saveAudio(_ clip:NoteAudioRecorder.Clip) {
        guard !busy else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let owner = try owner()
                if pendingMedia == nil {
                    var value = note(owner:owner)
                    value.audioFileName = value.stem+".m4a"; value.audioDuration = clip.duration; value.partial = clip.partial
                    pendingMedia = ScanVoiceMedia(note:value,audio:clip.data,pose:capturedPose,capturedAt:Date())
                }
                guard let media = pendingMedia else { return }
                let value = media.note
                let outbox = try VoiceNoteRecovery.root()
                try await Task.detached(priority:.utility) { try VoiceNoteRecovery.stage(value,audio:clip.data,at:outbox) }.value
                try await persistence.write(media,key:"voice-"+value.id.uuidString,latest:false,media:true)
                let root = workspace?.notesRoot ?? StorageLocation.local().documentsURL
                try await Task.detached(priority:.utility) {
                    try VoiceNoteRecovery.recover(projectID:owner,from:outbox,to:root,references:[reference])
                }.value
                pending = nil; pendingMedia = nil; message = AppLanguage.text("Voice note saved")
            } catch { message = error.localizedDescription }
        }
    }
    private func saveText() {
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let owner = try owner()
                let value = note(owner:owner)
                try await persistence.write(ScanVoiceMedia(note:value,audio:nil,pose:capturedPose,capturedAt:Date()),key:"note-"+value.id.uuidString,latest:false,media:true)
                let root = workspace?.notesRoot ?? StorageLocation.local().documentsURL
                try await Task.detached(priority:.utility) {
                    try ARNoteStore.update(root:root,projectID:owner) { index in
                        var copy = value; copy.number = try index.nextNumber(roomID:copy.roomID); index.notes.append(copy)
                    }
                }.value
                text = ""; editing = false; message = AppLanguage.text("Pinned note saved")
            } catch { message = error.localizedDescription }
        }
    }
}
#endif
