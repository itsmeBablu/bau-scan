import Foundation

enum ProjectReportLoader {
    /// Runs on a worker. Every referenced source remains read-only.
    static func load(project: RenovationProject, entries: [ProjectLibraryEntry], locale: Locale, generatedAt: Date = Date(), pins: [ProjectPin] = []) throws -> ProjectReport {
        var report = ProjectReport(name:project.name,generatedAt:generatedAt,notes:project.notes,scans:[],photos:[],unresolved:[])
        for reference in project.references where !reference.kind.rawValue.hasPrefix("design") {
            guard let entry = entries.first(where:{ $0.reference == reference }) else {
                report.unresolved.append(AppLanguage.text("Item unavailable",locale:locale)+": "+reference.itemID.uuidString); continue
            }
            do {
                if reference.kind == .technicalRoom {
                    let package = try TechnicalRoomPackage.read(from:entry.url)
                    let room = package.document.effectiveRoom
                    var lines = [AppLanguage.text("Equipment",locale:locale)+": \(room.equipment.count)",AppLanguage.text("Pipes & ducts",locale:locale)+": \(room.pipeRuns.count)"]
                    lines += room.equipment.map { "\($0.name.value) · \(MeasurementFormat.meters($0.size.value.x,locale:locale)) × \(MeasurementFormat.meters($0.size.value.y,locale:locale)) × \(MeasurementFormat.meters($0.size.value.z,locale:locale))" }
                    lines += room.pipeRuns.map { "\($0.medium.value.rawValue) · \(MeasurementFormat.meters($0.length.value,locale:locale))" }
                    report.scans.append(.init(title:entry.title,house:nil,detailLines:lines))
                    report.photos += SurveyPhotoStore.images(technical:package).map { .init(number:$0.photo.number,room:$0.roomName,jpeg:$0.jpegData) }
                } else {
                    let house: House
                    if reference.kind == .house { house = try HousePackage.readHouse(from:entry.url) }
                    else { house = House(room:try RoomPackage.readPlan(from:entry.url)) }
                    let quantities = house.allRooms.flatMap { ProjectQuantitiesCSV.lines(RenovationQuantities($0),locale:locale) }
                    let sourcePins = pins.filter { $0.projectID == project.id && $0.reference == reference }
                    let pinNotes = sourcePins.map { "\($0.text) · \(AppLanguage.text($0.status.rawValue,locale:locale))" }
                    report.scans.append(.init(title:entry.title,house:house,detailLines:quantities+pinNotes,pins:sourcePins))
                    report.photos += try SurveyPhotoStore.images(from:entry.url,house:house).map { .init(number:$0.photo.number,room:$0.roomName,jpeg:$0.jpegData) }
                }
            } catch { report.unresolved.append(entry.title+": "+error.localizedDescription) }
        }
        return report
    }
}

enum ProjectArtifacts {
    static func directory(root: URL, projectID: UUID) -> URL {
        root.appendingPathComponent("Projects",isDirectory:true).appendingPathComponent(projectID.uuidString,isDirectory:true).appendingPathComponent("Exports",isDirectory:true)
    }
    static func save(_ data: Data, extension suffix: String, root: URL, projectID: UUID) throws -> URL {
        guard ["pdf","csv","zip"].contains(suffix) else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = directory(root:root,projectID:projectID)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        try data.write(to:file,options:.atomic); return file
    }
    static func files(root: URL, projectID: UUID) throws -> [URL] {
        let dir = directory(root:root,projectID:projectID)
        guard FileManager.default.fileExists(atPath:dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey]).filter {
            let info = try $0.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            return info.isRegularFile == true && info.isSymbolicLink != true && ["pdf","csv","zip"].contains($0.pathExtension)
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
