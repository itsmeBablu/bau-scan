import Foundation

struct ProjectReport {
    struct Scan {
        var title: String
        var house: House?
        var detailLines: [String]
        var pins: [ProjectPin] = []
    }
    struct Photo {
        var number: Int
        var room: String
        var jpeg: Data
    }
    var name: String
    var generatedAt: Date
    var notes: String
    var details: ProjectDetails? = nil
    var scans: [Scan]
    var photos: [Photo]
    var unresolved: [String]
    var wastePercent = 0.0
}
