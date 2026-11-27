import Foundation

enum VoiceNoteDisplayName {
    static func title(_ note:ARNote,summary:ProjectScanSummary?,locale:Locale) -> String {
        if let title = note.title,!title.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty { return title }
        let rooms = summary?.roomDetails ?? []
        let spatial = note.position.flatMap { point in rooms.first {
            ($0.captureID == note.roomID || $0.id == note.roomID) && Polygon2D.contains($0.polygon,.init(x:point.x,y:-point.z))
        } }
        guard let room = spatial ?? rooms.first(where:{ $0.id == note.roomID }) ?? (rooms.count == 1 ? rooms.first : nil) else { return note.stem }
        return room.name+" · "+MeasurementFormat.squareMeters(room.area,locale:locale)+" · "+String(note.number)
    }
}
