import Foundation

enum ProjectReportLoader {
    /// Runs on a worker. Every referenced source remains read-only.
    static func load(project: RenovationProject, entries: [ProjectLibraryEntry], locale: Locale, generatedAt: Date = Date(), pins: [ProjectPin] = [], checks: [ProjectDistanceCheck] = [], wastePercent: Double = 0) throws -> ProjectReport {
        var report = ProjectReport(name:project.name,generatedAt:generatedAt,notes:project.notes,scans:[],photos:[],unresolved:[])
        report.wastePercent = wastePercent.isFinite ? min(100,max(0,wastePercent)) : 0
        var photoIDs = Set<UUID>(), photoBytes = 0
        func appendPhotos(_ images: [SurveyPhotoImage]) {
            for image in images where !photoIDs.contains(image.id) {
                guard report.photos.count < 100,photoBytes+image.jpegData.count <= 64*1_048_576 else {
                    let warning = AppLanguage.text("PDF photo budget reached. The complete ZIP photo folders retain all available photos.",locale:locale)
                    if !report.unresolved.contains(warning) { report.unresolved.append(warning) }; return
                }
                report.photos.append(.init(number:image.photo.number,room:image.roomName,jpeg:image.jpegData))
                photoIDs.insert(image.id); photoBytes += image.jpegData.count
            }
        }
        for check in checks where check.projectID == project.id {
            report.notes += "\n"+check.label+": "+MeasurementFormat.meters(check.referenceMeters,locale:locale)+" → "+MeasurementFormat.meters(check.observedMeters,locale:locale)+" · "+MeasurementFormat.millimeters(check.absoluteErrorMeters,locale:locale)+" · "+check.method
        }
        for reference in project.references where !reference.kind.rawValue.hasPrefix("design") {
            guard let entry = entries.first(where:{ $0.reference == reference }) else {
                report.unresolved.append(AppLanguage.text("Item unavailable",locale:locale)+": "+reference.itemID.uuidString); continue
            }
            do {
                if reference.kind == .technicalRoom {
                    let package = try TechnicalRoomPackage.read(from:entry.url)
                    let room = package.document.effectiveRoom
                    var lines = [AppLanguage.text("Equipment",locale:locale)+": \(room.equipment.count)",AppLanguage.text("Pipes & ducts",locale:locale)+": \(room.pipeRuns.count+package.document.ducts.count)"]
                    lines += room.equipment.map { "\($0.name.value) · \(MeasurementFormat.meters($0.size.value.x,locale:locale)) × \(MeasurementFormat.meters($0.size.value.y,locale:locale)) × \(MeasurementFormat.meters($0.size.value.z,locale:locale))" }
                    lines += room.pipeRuns.map { AppLanguage.text($0.medium.value.rawValue,locale:locale)+" · "+MeasurementFormat.meters(package.document.correctedLength($0.length.value),locale:locale) }
                    lines += package.document.ducts.map { duct in
                        let points = package.document.points(for:.duct(duct.id))
                        let length = zip(points,points.dropFirst()).reduce(0) { $0+$1.0.distance(to:$1.1) }
                        return AppLanguage.text("Duct",locale:locale)+" · "+MeasurementFormat.meters(package.document.correctedLength(length),locale:locale)
                    }
                    report.scans.append(.init(title:entry.title,house:nil,detailLines:lines))
                    appendPhotos(SurveyPhotoStore.images(technical:package))
                } else {
                    let house: House
                    if reference.kind == .house { house = try HousePackage.readHouse(from:entry.url) }
                    else { house = House(room:try RoomPackage.readPlan(from:entry.url)) }
                    let quantities = house.allRooms.flatMap { ProjectQuantitiesCSV.lines(RenovationQuantities($0),locale:locale,wastePercent:report.wastePercent) }
                    let sourcePins = pins.filter { $0.projectID == project.id && $0.reference == reference }
                    let sourcePhotos = try SurveyPhotoStore.images(from:entry.url,house:house)
                    let pinNotes = sourcePins.map { pin in
                        let photo = sourcePhotos.first { $0.id == pin.photoID }
                        return pin.text+" · "+AppLanguage.text(pin.status.rawValue,locale:locale)+(photo.map { " → "+$0.roomName+" · "+AppLanguage.text("Photo",locale:locale)+" \($0.photo.number)" } ?? "")
                    }
                    report.scans.append(.init(title:entry.title,house:house,detailLines:quantities+pinNotes,pins:sourcePins))
                    appendPhotos(sourcePhotos)
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
        guard supportedExtensions.contains(suffix) else { throw CocoaError(.fileWriteInvalidFileName) }
        let directory = try prepareDirectory(root:root,projectID:projectID)
        let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension(suffix)
        try data.write(to:file,options:.atomic); return file
    }
    static func files(root: URL, projectID: UUID) throws -> [URL] {
        let dir = directory(root:root,projectID:projectID)
        guard FileManager.default.fileExists(atPath:dir.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at:dir,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.contentModificationDateKey]).filter {
            let info = try $0.resourceValues(forKeys:[.isRegularFileKey,.isSymbolicLinkKey])
            return info.isRegularFile == true && info.isSymbolicLink != true && !$0.lastPathComponent.hasPrefix(".") && supportedExtensions.contains($0.pathExtension.lowercased())
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
