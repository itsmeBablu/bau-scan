#if os(iOS)
import SwiftUI

/// Small capture HUD. The existing recorder owns audio, never the ARSession.
typealias VoiceNoteHUD = LiveScanNotes

struct LiveScanNotes: View {
    @Environment(\.locale) private var locale
    let reference: ProjectReference
    let persistence: CapturePersistence
    let workspace: RenovationWorkspace?
    let projectID: UUID?
    var position: () -> TechnicalPoint3?
    var pose: () -> [Double]?
    var roomID: () -> UUID? = { nil }
    var level: () -> Int? = { nil }
    var borrowCaptureAudioSession = false
    var nearbyPin:(TechnicalPoint3)->ARNote? = { _ in nil }
    var selectedPin: ARNote? = nil
    var onPin: (ARNote)->Void = { _ in }
    @State private var recorder = NoteAudioRecorder()
    @State private var holding = false
    @State private var pin: TechnicalPoint3?
    @State private var text = ""
    @State private var message: String?
    @State private var busy = false
    @State private var pending: NoteAudioRecorder.Clip?
    @State private var recordingPosition:TechnicalPoint3?
    @State private var recordingPin: ARNote?
    @State private var capturedPose: [Double]?
    @State private var capturedRoom: UUID?
    @State private var capturedLevel: Int?
    @State private var pendingMedia: ScanVoiceMedia?
    @State private var pendingText: ARNote?
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            HStack(spacing:12) {
                HoldMicrophoneControl(recording:recorder.recording,start:{
                    guard !busy,pending == nil else { return }
                    let surface = position()
                    recordingPin = selectedPin ?? surface.flatMap(nearbyPin)
                    recordingPosition = recordingPin?.position ?? surface
                    holding = true; capturedPose = pose(); capturedRoom = roomID(); capturedLevel = level()
                    recorder.onClip = { clip in pending = clip; saveAudio(clip) }
                    Task { if holding { await recorder.start(preserveAudioSession:borrowCaptureAudioSession) }; if !holding { recorder.stop() } }
                },finish:{ cancel in holding = false; recorder.stop(cancel:cancel,reason:cancel ? "Recording discarded" : "User stopped recording") })
                    .frame(width:48,height:48)
                Button {
                    guard let point = position() else { message = AppLanguage.text("Aim at a tracked surface"); return }
                    pin = point; capturedPose = pose(); capturedRoom = roomID(); capturedLevel = level(); text = ""
                    do { let owner = try owner(); var value = ARNote(projectID:owner,reference:reference,number:1,level:capturedLevel,roomID:capturedRoom,position:point,planPosition:nil,language:locale.identifier); value.cameraPosition = cameraPoint(); value.title = AppLanguage.text("Pinned note",locale:locale); pendingText = value; onPin(value); saveText() } catch { message = error.localizedDescription }
                } label: { Image(systemName:pin == nil ? "mappin" : "mappin.circle.fill").frame(width:48,height:48) }
                    .dsMaterial(in:Circle()).accessibilityLabel("Pin a note to this surface")
                    .disabled(holding || recorder.recording || recorder.preparing || pending != nil)
            }.disabled(busy)
        }.frame(width:112,height:48)
        .overlay(alignment:.trailing) {
            if pending != nil,!recorder.recording,!busy {
                Button("Retry saving") { if let pending { saveAudio(pending) } }
                    .font(.caption).padding(8).dsMaterial(in:Capsule()).offset(x:110)
            }
        }
        .overlay(alignment:.top) {
            if recorder.recording {
                HStack(spacing:2) { ForEach(Array(recorder.levels.suffix(20).enumerated()),id:\.offset) { _,level in
                    Capsule().fill(.red).frame(width:3,height:max(2,level*22))
                } }.frame(width:100,height:24).dsMaterial(in:Capsule()).offset(y:-32).allowsHitTesting(false)
            }
        }
        .overlay(alignment:.bottomLeading) {
            if let error = recorder.error ?? message { Text(error).font(.caption2).lineLimit(2).frame(width:220,alignment:.leading).padding(6).dsMaterial(in:Capsule()).offset(y:45).allowsHitTesting(false) }
        }
        .overlay(alignment:.topLeading) {
            if let selectedPin,!recorder.recording {
                HStack {
                    TextField("Note",text:$text).textFieldStyle(.roundedBorder)
                    Button { pendingText = selectedPin; saveText() } label: { Image(systemName:"checkmark.circle.fill") }.accessibilityLabel("Save note")
                }.padding(8).frame(width:260).dsMaterial(in:RoundedRectangle(cornerRadius:DS.Radius.card)).offset(y:-60)
            }
        }
        .onChange(of:selectedPin) { _,value in text = value?.text ?? "" }
        .onDisappear { recorder.stop(partial:true) }
    }
    private func note(owner:UUID) -> ARNote {
        var note = ARNote(projectID:owner,reference:reference,number:1,level:recordingPin?.level ?? capturedLevel,
            roomID:recordingPin?.roomID ?? capturedRoom,position:recordingPosition ?? cameraPoint(),planPosition:nil,language:locale.identifier)
        note.anchorPinID = recordingPin?.id; note.cameraPosition = cameraPoint()
        note.text = text; note.modifiedAt = Date()
        return note
    }
    private func cameraPoint() -> TechnicalPoint3? {
        capturedPose.flatMap { $0.count == 16 ? .init(x:$0[12],y:$0[13],z:$0[14]) : nil }
    }
    private func owner() throws -> UUID {
        guard let workspace else {
            var owner:UUID?
            _ = try ProjectIndexStore.update(root:ScanVoiceNoteLibrary.root) { owner = try $0.voiceNotesProject(for:reference,preferredProjectID:projectID) }
            guard let owner else { throw CocoaError(.fileWriteUnknown) }; return owner
        }
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
                    // A recording can start before the first tracked frame.
                    // Use an observed stop position if the start had none.
                    if recordingPosition == nil { recordingPosition = position() }
                    if capturedPose == nil { capturedPose = pose(); capturedRoom = roomID(); capturedLevel = level() }
                    var value = note(owner:owner)
                    value.audioModifiedAt = value.modifiedAt
                    value.audioFileName = value.stem+".m4a"; value.audioDuration = clip.duration; value.partial = clip.partial
                    pendingMedia = ScanVoiceMedia(note:value,audio:clip.data,pose:capturedPose,capturedAt:Date())
                }
                guard let media = pendingMedia else { return }
                let value = media.note
                let root = workspace?.notesRoot ?? ScanVoiceNoteLibrary.root
                let outbox = try VoiceNoteRecovery.root()
                let saved = try await NoteSaveWorker.audioRevision(value,audio:clip.data,root:root,outbox:outbox)
                onPin(saved)
                pending = nil; pendingMedia = nil; message = AppLanguage.text("Voice note saved")
                // The project sidecar is already durable. A checkpoint must never
                // hold the microphone or project finish controls hostage.
                Task { try? await persistence.write(media,key:"voice-"+value.id.uuidString,latest:false,media:true) }
            } catch { message = error.localizedDescription }
        }
    }
    private func saveText() {
        guard !busy else { return }; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let owner = try owner()
                var value = pendingText ?? note(owner:owner); value.text = text; value.modifiedAt = Date()
                let root = workspace?.notesRoot ?? ScanVoiceNoteLibrary.root
                let saved = try await NoteSaveWorker.text(value,root:root)
                onPin(saved)
                pendingText = nil; message = AppLanguage.text("Pinned note saved")
                let media = ScanVoiceMedia(note:saved,audio:nil,pose:capturedPose,capturedAt:Date())
                Task { try? await persistence.write(media,key:"note-"+saved.id.uuidString,latest:false,media:true) }
            } catch { message = error.localizedDescription }
        }
    }
}
#endif
