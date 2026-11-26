import Foundation

/// Promotion is serialized and idempotent: an existing final package wins over
/// any older draft. Completion is recorded only after package and catalogue save.
actor ScanSessionRecovery {
    static let shared = ScanSessionRecovery()
    struct MissingGeometry:LocalizedError {
        var hasEvidence = false
        var errorDescription:String? {
            AppLanguage.text(hasEvidence ? "No room geometry was saved. Recovered notes are available in the project's voice notes. The scan draft has been kept." : "No room geometry was saved. The scan draft has been kept.")
        }
    }
    func promote(_ session:ScanSession,store:ScanSessionStore,documents:URL) async throws -> ProjectReference {
        let reference = ProjectReference(kind:session.kind == .house ? .house : session.kind == .room ? .room : .technicalRoom,itemID:session.id,library:"local")
        if try await store.read(session.id).state == .completed { return reference }
        try await store.setState(session.id,.finalizing)
        do {
            try await store.removeOrphans(session.id)
            let entries = try await store.entries(session.id)
            // Salvage evidence before attempting geometry promotion. An early
            // camera failure must not make completed voice notes unrecoverable.
            let owner = session.projectID ?? ProjectIndex.unsortedID
            _ = try ProjectIndexStore.update(root:documents) { index in
                if !index.projects.contains(where:{ $0.id == owner }) { index.projects.append(.init(id:owner,name:owner == ProjectIndex.unsortedID ? "Unsorted" : AppLanguage.text("Recovered project"),isUnsorted:owner == ProjectIndex.unsortedID)) }
                try index.assign(reference,to:owner)
            }
            for entry in entries where entry.key.hasPrefix("voice-") || entry.key.hasPrefix("note-") {
                let value = try JSONDecoder().decode(ScanVoiceMedia.self,from:await store.payload(session.id,entry:entry))
                if let audio = value.audio {
                    let outbox = try VoiceNoteRecovery.root()
                    try VoiceNoteRecovery.stageRevision(value.note,audio:audio,at:outbox)
                    try VoiceNoteRecovery.recover(projectID:value.note.projectID,from:outbox,to:documents,references:[value.note.reference])
                } else {
                    _ = try ARNoteStore.upsertText(value.note,root:documents)
                }
            }
            if session.kind == .technical {
                let target = documents.appendingPathComponent("TechnicalRooms/\(session.id.uuidString).technicalroom")
                if FileManager.default.fileExists(atPath:target.path) { _ = try TechnicalRoomPackage.readManifest(from:target) }
                else {
                    let state = try await store.latestValues(session.id,prefix:"technical-state").last.map { try JSONDecoder().decode(TechnicalSessionState.self,from:$0.data) }
                    let journal = try await TechnicalSessionDeltaWriter.recover(store:store,id:session.id)
                    guard !journal.meshes.isEmpty else { throw MissingGeometry(hasEvidence:entries.contains { $0.key.hasPrefix("voice-") || $0.key.hasPrefix("note-") }) }
                    var evidence = TechnicalCaptureEvidence()
                    for entry in entries where entry.key.hasPrefix("technical-photo-") || entry.key.hasPrefix("keyframe-") {
                        let frame = try JSONDecoder().decode(TechnicalCaptureKeyframe.self,from:await store.payload(session.id,entry:entry))
                        if frame.userPhoto == true { try evidence.append(frame) } else { try? evidence.append(frame) }
                    }
                    let map = try await store.latestValues(session.id,prefix:"world-map").last.map { try JSONDecoder().decode(Data.self,from:$0.data) }
                    var manifest = TechnicalRoomManifest(id:session.id,name:AppLanguage.text("Recovered Technik Room"))
                    manifest.incomplete = true
                    var document = state?.document ?? .init(room:.capturedShell(id:session.id,notes:""))
                    document.room.id = session.id
                    let package = TechnicalRoomPackage(manifest:manifest,document:document,alignment:state?.alignment ?? .init(),journal:journal,worldMapData:map,thumbnailPNG:nil,evidence:evidence)
                    try package.write(to:target)
                }
            } else {
                let location = StorageLocation(kind:.local,documentsURL:documents)
                let target = session.kind == .house ? location.housePackageURL(for:session.id) : location.packageURL(for:session.id)
                if FileManager.default.fileExists(atPath:target.path) {
                    if session.kind == .house { _ = try HousePackage.readRecord(from:target) } else { _ = try RoomPackage.readRecord(from:target) }
                } else {
                    let rooms = try await store.latestValues(session.id,prefix:"room-").map { try JSONDecoder().decode(PersistedRoom.self,from:$0.data) }
                    guard !rooms.isEmpty else { throw MissingGeometry(hasEvidence:entries.contains { $0.key.hasPrefix("voice-") || $0.key.hasPrefix("note-") }) }
                    var photos:[SurveyPhoto] = [],assets:[UUID:Data] = [:]
                    for entry in entries where entry.key.hasPrefix("photo-") {
                        let value = try JSONDecoder().decode(ScanPhotoMedia.self,from:await store.payload(session.id,entry:entry))
                        photos.append(value.photo); assets[value.photo.id] = value.jpeg
                    }
                    if session.kind == .house {
                        let extras = Dictionary(uniqueKeysWithValues:rooms.map { ($0.scan.id,HousePackage.RoomExtras(capturedRoomData:$0.raw,usdzData:nil,usdzMeshData:nil)) })
                        var package = try HousePackage.assemble(structure:.init(id:session.id,rooms:rooms.map(\.scan)),name:AppLanguage.text("Recovered House"),capturedStructureData:nil,usdzData:nil,roomExtras:extras)
                        package.record.incomplete = true; package.surveyPhotos = photos; package.surveyPhotoAssets = assets
                        try package.write(to:target)
                    } else {
                        let room = rooms[0]
                        var scan = room.scan; scan.id = session.id
                        let plan = FloorPlanBuilder().build(from:scan,name:AppLanguage.text("Recovered Room"))
                        var record = RoomRecord(plan:plan); record.incomplete = true
                        var package = RoomPackage(record:record,plan:plan,scan:scan,capturedRoomData:room.raw,usdzData:nil,usdzMeshData:nil,thumbnailPNG:room.thumbnail)
                        package.surveyPhotos = photos; package.surveyPhotoAssets = assets; try package.write(to:target)
                    }
                }
            }
            try await store.setState(session.id,.completed)
            return reference
        } catch { try? await store.setState(session.id,.failed); throw error }
    }
}
