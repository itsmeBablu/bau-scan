import Foundation

/// Explicit local project export. Never uploads media or changes source notes.
enum VoiceNotesExporter {
    static func export(root: URL,projectID: UUID,references: [ProjectReference],includeAudio: Bool,to destination: URL) throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("voice-export-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:staging) }
        let library = includeAudio ? try ARNoteStore.read(root:root,projectID:projectID) : ARNoteStore.Library(index:try ARNoteStore.index(root:root,projectID:projectID),audio:[:])
        let allowed = Set(references),notes = library.index.notes.filter { allowed.contains($0.reference) }
        var records: [[String:Any]] = [],items: [[String:Any]] = []
        func write(_ data: Data,path: String) throws {
            try Task.checkCancellation()
            let target = staging.appendingPathComponent(path)
            try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
            try data.write(to:target)
            items.append(["path":path,"bytes":data.count,"sha256":try ExportChecksum.sha256(target)])
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        for original in notes {
            var note = original
            // Transcripts are excluded from this first export path; text is user-editable.
            note.transcript = nil
            note.transcriptState = .unavailable
            if !includeAudio { note.audioFileName = nil; note.audioDuration = nil; note.partial = nil }
            let folder = "notes/"+note.id.uuidString,stem = folder+"/"+note.stem
            try write(encoder.encode(note),path:stem+".json")
            try write(Data(((note.title ?? "")+"\n"+note.text).utf8),path:stem+".txt")
            var record: [String:Any] = ["id":note.id.uuidString,"projectID":projectID.uuidString,"sourceID":note.reference.id,
                "title":note.title ?? "","description":note.text,"timestamp":ISO8601DateFormatter().string(from:note.createdAt),
                "jsonFile":stem+".json","textFile":stem+".txt","deviceValidationPending":true,"accuracyMm":NSNull()]
            if includeAudio,let filename = note.audioFileName {
                guard let data = library.audio[note.id] else { throw CocoaError(.fileNoSuchFile) }
                let path = folder+"/"+filename
                try write(data,path:path)
                record["audioFile"] = path; record["durationSeconds"] = note.audioDuration
                record["format"] = "M4A/AAC"; record["bytes"] = data.count
                record["sha256"] = try ExportChecksum.sha256(staging.appendingPathComponent(path))
            }
            records.append(record)
        }
        try write(JSONSerialization.data(withJSONObject:["schemaVersion":1,"projectID":projectID.uuidString,"notes":records],options:[.prettyPrinted,.sortedKeys]),path:"voice-notes-index.json")
        let keys = ["id","projectID","sourceID","title","description","timestamp","audioFile","durationSeconds","format","bytes","sha256","jsonFile","textFile"]
        func cell(_ value: Any) -> String {
            let text = value is NSNull ? "" : String(describing:value)
            let safe = !(value is NSNumber) && ["=","+","-","@"].contains(String(text.trimmingCharacters(in:.whitespacesAndNewlines).prefix(1))) ? "'"+text : text
            return "\""+safe.replacingOccurrences(of:"\"",with:"\"\"")+"\""
        }
        let rows: [[Any]] = [keys.map { $0 as Any }]+records.map { record in keys.map { record[$0] ?? NSNull() } }
        try write(Data((rows.map { $0.map(cell).joined(separator:",") }.joined(separator:"\r\n")+"\r\n").utf8),path:"voice-notes-index.csv")
        try write(Data("Local voice notes. Scan coordinates are not GPS. Device validation pending. Transcripts excluded. Unresolved source references are omitted. Not a native scan backup.\n".utf8),path:"README.txt")
        let manifest: [String:Any] = ["schemaVersion":1,"projectID":projectID.uuidString,"audioIncluded":includeAudio,"items":items,
            "unresolvedNoteIDs":library.index.notes.filter { !allowed.contains($0.reference) }.map { $0.id.uuidString }]
        try JSONSerialization.data(withJSONObject:manifest,options:[.prettyPrinted,.sortedKeys]).write(to:staging.appendingPathComponent("manifest.json"))
        try ArchiveExporter.zip(directory:staging,to:destination)
    }
}
