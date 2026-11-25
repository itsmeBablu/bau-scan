import Foundation

/// ZIP 'all': every available export format + `README.txt`, dependency-free —
/// `NSFileCoordinator` with `.forUploading` produces a ZIP archive of a directory
/// on both iOS and macOS.
enum ArchiveExporter {
    enum ArchiveError: LocalizedError {
        case coordination(Error), noArchive
        var errorDescription: String? {
            switch self {
            case .coordination(let e): e.localizedDescription
            case .noArchive: "Archive ZIP non produite."
            }
        }
    }

    /// Compresses `directory` into `destination` (overwritten).
    static func zip(directory: URL, to destination: URL,move: ((URL,URL) throws -> Void)? = nil) throws {
        try Task.checkCancellation()
        try SafePackageRead.validate(directory)
        try ExportManifestValidation.validate(in:directory)
        guard !destination.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(directory.standardizedFileURL.resolvingSymlinksInPath().path+"/") else { throw CocoaError(.fileWriteInvalidFileName) }
        let staging = try PackageReplacement.staging(for:destination)
        defer { try? FileManager.default.removeItem(at:staging) }
        var coordinationError: NSError?
        var copyError: Error?
        var produced = false
        NSFileCoordinator().coordinate(readingItemAt: directory, options: .forUploading, error: &coordinationError) { zipURL in
            do {
                try Task.checkCancellation()
                try FileManager.default.copyItem(at:zipURL,to:staging)
                try ZIPDirectoryValidator.validate(staging)
                produced = true
            } catch { copyError = error }
        }
        if let coordinationError { throw ArchiveError.coordination(coordinationError) }
        if let copyError { throw ArchiveError.coordination(copyError) }
        guard produced else { throw ArchiveError.noArchive }
        try Task.checkCancellation()
        try RoomPackage.coordinatedWrite(at:destination,options:.forReplacing) { try PackageReplacement.commit(staging,to:$0,move:move) }
    }

    /// Archive README.txt: room, measurements, file inventory and intended usage.
    static func readme(record: RoomRecord, plan: FloorPlan, files: [(name: String, format: ExportFormat)], locale: Locale = AppLanguage.locale) -> String {
        readme(subject: ExportSubject(record: record, house: House(room: plan), packageURL: nil), files: files, locale: locale)
    }

    /// Subject README.txt: a room provides detailed measurements, a house its stories and rooms.
    static func readme(subject: ExportSubject, files: [(name: String, format: ExportFormat)], locale: Locale = AppLanguage.locale) -> String {
        let df = DateFormatter(); df.locale = locale; df.dateStyle = .long; df.timeStyle = .short
        let scanned = String(localized:"readme.scannedOn \(df.string(from: subject.createdAt))",locale:locale)
        var body: [String] = [scanned]
        if subject.kind == .room, let plan = subject.house.allRooms.first {
            let m = RoomMeasurements(plan: plan)
            let r = m.ceilingHeight
            let ceiling = abs(r.upperBound - r.lowerBound) < 0.02 ? MeasurementFormat.meters(r.lowerBound, locale: locale)
                : "\(MeasurementFormat.meters(r.lowerBound, locale: locale)) – \(MeasurementFormat.meters(r.upperBound, locale: locale))"
            body.append(String(localized:"readme.area \(MeasurementFormat.squareMeters(m.floorArea, locale: locale)) \(MeasurementFormat.meters(m.perimeter, locale: locale)) \(ceiling)",locale:locale))
            body.append(String(localized:"readme.counts \(plan.walls.count) \(m.doors.count) \(m.windows.count) \(plan.objects.count)",locale:locale))
        } else {
            let hm = HouseMeasurements(house: subject.house)
            body.append(String(localized:"readme.house \(hm.roomCount) \(hm.storyCount) \(MeasurementFormat.squareMeters(hm.floorArea, locale: locale))",locale:locale))
            for story in subject.house.stories {
                let names = story.rooms.map { "\($0.name) (\(MeasurementFormat.squareMeters(RoomMeasurements(plan: $0).floorArea, locale: locale)))" }.joined(separator: ", ")
                body.append("  \(StoryNaming.localizedName(for: story.index)) : \(names)")
            }
        }
        var s = "dWalkScan — \(subject.name)\n" + String(repeating: "=", count: 11 + subject.name.count) + "\n\n"
        s += body.joined(separator: "\n") + "\n\n" + AppLanguage.text("readme.files",locale:locale) + "\n"
        if files.contains(where:{ $0.format.isRoomPlanScan }) {
            s += AppLanguage.text("USDZ: RoomPlan scan (not cleaned). Original captured assets.",locale:locale)+"\n\n"
        }
        for f in files {
            s += "  \(f.name)\n      \(AppLanguage.text(f.format.descriptionKey,locale:locale))\n"
        }
        s += "\n\(AppLanguage.text("readme.units",locale:locale))\n\(AppLanguage.text("readme.footer",locale:locale))\n"
        return s
    }
}
