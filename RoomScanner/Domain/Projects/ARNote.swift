import Foundation

/// Independent evidence. All spatial coordinates are scan-derived, never accuracy-certified.
struct ARNote: Codable, Equatable, Identifiable {
    enum TranscriptState: String, Codable { case pending, done, failed, unavailable }
    var id = UUID()
    var projectID: UUID
    var reference: ProjectReference
    var number: Int
    var level: Int?
    var roomID: UUID?
    var position: TechnicalPoint3?
    var planPosition: Point2D?
    var text = ""
    var title: String? = nil
    var status = ProjectPin.Status.open
    var createdAt = Date()
    var audioFileName: String?
    var audioDuration: Double?
    var partial: Bool? = nil
    var transcriptState = TranscriptState.unavailable
    var language: String
    var elementID: UUID? = nil
    var displayPosition: TechnicalPoint3? = nil
    var retainAudio: Bool? = nil
    var transcript: String? = nil
    var viewingPosition: TechnicalPoint3? { displayPosition ?? position }
    var positionSource: String { "scan-derived" }
    var accuracyMm: Double? { nil }
    var deviceValidationPending: Bool { true }
    var stem: String { String(format:"note-%02lld",Int64(number)) }
    var roomFolder: String { "Rooms/"+(roomID?.uuidString ?? "unassigned") }
    var jsonPath: String { roomFolder+"/"+stem+".json" }
    var audioPath: String? { audioFileName.map { roomFolder+"/"+$0 } }

    enum CodingKeys: String, CodingKey {
        case id,projectID,reference,number,level,roomID,position,planPosition,text,status,createdAt
        case audioFileName,audioDuration,partial,transcriptState,language,elementID,displayPosition,retainAudio,transcript
        case title
    }
    private enum ProvenanceKeys: String, CodingKey { case positionSource,accuracyMm,deviceValidationPending }
    func encode(to encoder: Encoder) throws {
        try validate()
        var c = encoder.container(keyedBy:CodingKeys.self)
        try c.encode(id,forKey:.id); try c.encode(projectID,forKey:.projectID); try c.encode(reference,forKey:.reference)
        try c.encode(number,forKey:.number); try c.encodeIfPresent(level,forKey:.level); try c.encodeIfPresent(roomID,forKey:.roomID)
        try c.encodeIfPresent(position,forKey:.position); try c.encodeIfPresent(planPosition,forKey:.planPosition)
        try c.encode(text,forKey:.text); try c.encode(status,forKey:.status); try c.encode(createdAt,forKey:.createdAt)
        try c.encodeIfPresent(title,forKey:.title)
        try c.encodeIfPresent(audioFileName,forKey:.audioFileName); try c.encodeIfPresent(audioDuration,forKey:.audioDuration)
        try c.encodeIfPresent(partial,forKey:.partial); try c.encode(transcriptState,forKey:.transcriptState)
        try c.encode(language,forKey:.language); try c.encodeIfPresent(elementID,forKey:.elementID)
        try c.encodeIfPresent(displayPosition,forKey:.displayPosition)
        try c.encodeIfPresent(retainAudio,forKey:.retainAudio)
        try c.encodeIfPresent(transcript,forKey:.transcript)
        var provenance = encoder.container(keyedBy:ProvenanceKeys.self)
        try provenance.encode(positionSource,forKey:.positionSource); try provenance.encodeNil(forKey:.accuracyMm)
        try provenance.encode(true,forKey:.deviceValidationPending)
    }

    func validate() throws {
        func finite(_ values: [Double]) -> Bool { values.allSatisfy { $0.isFinite && abs($0) <= 100_000 } }
        guard [.house,.room,.technicalRoom].contains(reference.kind),["local","icloud"].contains(reference.library),
              (1...10_000).contains(number),level.map({ (-1000...1000).contains($0) }) ?? true,
              position.map({ finite([$0.x,$0.y,$0.z]) }) ?? true,
              displayPosition.map({ finite([$0.x,$0.y,$0.z]) }) ?? true,
              planPosition.map({ finite([$0.x,$0.y]) }) ?? true,
              text.count <= 16_000,(title?.count ?? 0) <= 200,(transcript?.count ?? 0) <= 16_000,createdAt.timeIntervalSince1970.isFinite,
              !language.isEmpty,language.count <= 40 else { throw CocoaError(.fileReadCorruptFile) }
        if let audioFileName {
            guard audioFileName == stem+".m4a",let audioDuration,audioDuration.isFinite,
                  (0.5...60).contains(audioDuration) else { throw CocoaError(.fileReadCorruptFile) }
        } else {
            guard audioDuration == nil,partial != true,transcriptState != .pending else { throw CocoaError(.fileReadCorruptFile) }
        }
    }
    func pin() -> ProjectPin? {
        // ProjectPin remains architectural; technical notes retain their own associations.
        guard reference.kind == .house || reference.kind == .room else { return nil }
        let point = planPosition ?? position.map { Point2D(x:$0.x,y:-$0.z) }
        guard let point,let level else { return nil }
        return ProjectPin(id:id,projectID:projectID,reference:reference,story:level,position:point,text:String(text.prefix(4000)),status:status,photoID:nil,elementID:elementID)
    }
}

struct ARNoteIndex: Codable, Equatable {
    var schemaVersion = 1
    var projectID: UUID
    var notes: [ARNote] = []
    static let maximumAudioBytes = 64*1_048_576
    static let maximumClipBytes = 1_048_576
    func validate() throws {
        guard schemaVersion == 1,notes.count <= 10_000,Set(notes.map(\.id)).count == notes.count,
              Set(notes.map(\.jsonPath)).count == notes.count,notes.allSatisfy({ $0.projectID == projectID }) else { throw CocoaError(.fileReadCorruptFile) }
        for note in notes { try note.validate() }
    }
    func nextNumber(roomID: UUID?) throws -> Int {
        let last = notes.filter { $0.roomID == roomID }.map(\.number).max() ?? 0
        guard last < 10_000 else { throw CocoaError(.fileWriteOutOfSpace) }
        return last+1
    }
}
