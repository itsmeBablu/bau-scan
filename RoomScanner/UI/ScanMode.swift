import Foundation

/// Scan target: single room (v1) or multi-room house (v2).
enum ScanMode: String, Identifiable, Hashable {
    case room, house, technicalRoom
    var id: String { rawValue }
}
