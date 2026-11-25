import Foundation

enum NoteTranscriptPolicy {
    static func apply(to note: inout ARNote,state: ARNote.TranscriptState,text: String?) throws {
        if state == .done {
            guard let text else { throw CocoaError(.fileReadCorruptFile) }
            note.transcript = String(text.prefix(16_000))
            if note.text.isEmpty { note.text = String(text.prefix(16_000)) }
            if note.retainAudio == false { note.audioFileName = nil; note.audioDuration = nil; note.partial = nil }
        }
        note.transcriptState = state
        try note.validate()
    }
}
