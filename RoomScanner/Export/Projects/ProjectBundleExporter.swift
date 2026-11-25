import Foundation

/// Organized, self-describing handoff; every failed or unavailable output is listed.
enum ProjectBundleExporter {
    struct Record: Codable { var sourceID: String; var path: String; var status: String; var detail: String? }
    struct Manifest: Codable {
        var schemaVersion = 1
        var deviceValidationPending = true
        var projectID: UUID
        var records: [Record]
        var photos: [SurveyPhotoArchiveWriter.Entry]
    }
    static func write(project: RenovationProject, index: ProjectIndex, entries: [ProjectLibraryEntry], locale: Locale, to destination: URL,includeDetails:Bool = false) async throws {
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent("project-bundle-"+UUID().uuidString,isDirectory:true)
        let root = staging.appendingPathComponent(ArchivePath.component(project.name,fallback:"Project"),isDirectory:true)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:staging) }
        try await files(project:project,index:index,entries:entries,locale:locale,in:root,includeDetails:includeDetails)
        try ArchiveExporter.zip(directory:root,to:destination)
    }
    static func files(project: RenovationProject, index: ProjectIndex, entries: [ProjectLibraryEntry], locale: Locale, in root: URL,includeDetails:Bool = false) async throws {
        try index.validate()
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        if includeDetails,let details = project.details { try JSONEncoder().encode(details).write(to:root.appendingPathComponent("project-details.json"),options:.atomic) }
        var manifest = Manifest(projectID:project.id,records:[],photos:[]), usedPhotoNames = Set<String>(), usedSourceNames = Set<String>()
        func directory(_ path: String) throws -> URL {
            let url = root.appendingPathComponent(path,isDirectory:true)
            try FileManager.default.createDirectory(at:url,withIntermediateDirectories:true); return url
        }
        func attempt(_ reference: ProjectReference?, path: String, _ work: () throws -> Void) {
            do { try work(); manifest.records.append(.init(sourceID:reference?.id ?? project.id.uuidString,path:path,status:"exported",detail:nil)) }
            catch { manifest.records.append(.init(sourceID:reference?.id ?? project.id.uuidString,path:path,status:"unavailable",detail:error.localizedDescription)) }
        }
        var budget = CopyBudget()
        for reference in project.references {
            guard let entry = entries.first(where:{ $0.reference == reference }) else {
                manifest.records.append(.init(sourceID:reference.id,path:"",status:"unavailable",detail:AppLanguage.text("Item unavailable",locale:locale))); continue
            }
            let title = index.displayNames?[entry.id] ?? entry.title
            let sourceName = ArchivePath.unique(ArchivePath.component(title)+"-"+reference.kind.rawValue+"-"+reference.itemID.uuidString.prefix(8)+"-"+reference.library,used:&usedSourceNames)
            let base = (entry.isDesign ? "Designs/" : "Scans/")+sourceName
            if entry.isDesign {
                do {
                    let source: SceneEditDocument.Source = reference.kind == .designHouse ? .house : reference.kind == .designRoom ? .room : .technical
                    guard let document = try SceneEditStore.read(entry.url,source:source,id:reference.itemID) else { throw CocoaError(.fileNoSuchFile) }
                    let folder = try directory(base)
                    let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
                    try encoder.encode(document).write(to:folder.appendingPathComponent("editable-design.json"))
                    try document.engineeringCSV().write(to:folder.appendingPathComponent("engineering-register.csv"))
                    var service = ExportService(); service.locale = locale
                    try service.data(for:document.plan,format:.pdf,title:document.title).write(to:folder.appendingPathComponent("floor-plans.pdf"))
                    manifest.records.append(.init(sourceID:reference.id,path:base,status:"exported",detail:nil))
                    for story in document.shell.stories {
                        for format in [StudioExporter.Format.usdz,.obj] {
                            let name = "level-\(story.index)."+(format == .obj ? "obj-with-materials.zip" : "usdz")
                            let path = base+"/Models/"+name
                            do {
                                let output = try directory(base+"/Models").appendingPathComponent(name)
                                // SceneKit design exporters own UI-bound renderer state. Await that boundary explicitly.
                                let data = try await MainActor.run { try StudioExporter.data(document,format:format,story:story.index) }
                                try data.write(to:output)
                                manifest.records.append(.init(sourceID:reference.id,path:path,status:"exported",detail:nil))
                            } catch { manifest.records.append(.init(sourceID:reference.id,path:path,status:"unavailable",detail:error.localizedDescription)) }
                        }
                    }
                } catch { manifest.records.append(.init(sourceID:reference.id,path:base,status:"unavailable",detail:error.localizedDescription)) }
                continue
            }
            attempt(reference,path:base+"/Original/"+entry.url.lastPathComponent) {
                let originals = try directory(base+"/Original")
                try budget.copyPackage(entry.url,to:originals.appendingPathComponent(entry.url.lastPathComponent))
            }
            if reference.kind == .technicalRoom {
                attempt(reference,path:base) {
                    let package = try TechnicalRoomPackage.read(from:entry.url)
                    for format in TechnicalMeshExporter.Format.allCases {
                        let category = format == .json ? "Data" : format == .dxf ? "Plans" : "Models"
                        let path = base+"/"+category+"/survey."+format.rawValue
                        attempt(reference,path:path) {
                            let folder = try directory(base+"/"+category)
                            try TechnicalMeshExporter.write(package,format:format,to:folder.appendingPathComponent("survey."+format.rawValue))
                        }
                    }
                    manifest.photos += try SurveyPhotoArchiveWriter.write(SurveyPhotoStore.images(technical:package),to:root,used:&usedPhotoNames,sourceID:reference.id)
                }
            } else {
                attempt(reference,path:base) {
                    let house: House
                    var subject: ExportSubject
                    if reference.kind == .house {
                        house = try HousePackage.readHouse(from:entry.url)
                        subject = ExportSubject(record:try HousePackage.readRecord(from:entry.url),house:house,packageURL:entry.url)
                    } else {
                        house = House(room:try RoomPackage.readPlan(from:entry.url))
                        subject = ExportSubject(record:try RoomPackage.readRecord(from:entry.url),house:house,packageURL:entry.url)
                    }
                    subject.name = title
                    let geometryPath = base+"/Data/resolved-geometry.json"
                    attempt(reference,path:geometryPath) {
                        try ResolvedGeometryExporter.data(for:house,sourceID:reference.itemID)
                            .write(to:directory(base+"/Data").appendingPathComponent("resolved-geometry.json"))
                    }
                    var service = ExportService(); service.locale = locale
                    for format in ExportService.availableFormats(for:subject) where format != .zip {
                        let category = format.group == .twoD ? "Plans" : format.group == .threeD ? "Models" : "Data"
                        let path = base+"/"+category+"/"+ExportService.fileName(for:subject,format:format)
                        attempt(reference,path:path) { _ = try service.export(subject,format:format,to:directory(base+"/"+category)) }
                    }
                    manifest.photos += try SurveyPhotoArchiveWriter.write(SurveyPhotoStore.images(from:entry.url,house:house),to:root,used:&usedPhotoNames,sourceID:reference.id)
                }
            }
        }
        let report = try ProjectReportLoader.load(project:project,entries:entries,locale:locale,pins:index.pins ?? [],checks:index.distanceChecks ?? [],wastePercent:UserDefaults.standard.object(forKey:"renovation.wastePercent") as? Double ?? 10)
        attempt(nil,path:"Reports/project-report.pdf") { try ProjectReportRenderer.pdf(report,locale:locale).write(to:directory("Reports").appendingPathComponent("project-report.pdf")) }
        attempt(nil,path:"Quantities/quantities.csv") { try ProjectQuantitiesCSV.data(report,locale:locale).write(to:directory("Quantities").appendingPathComponent("quantities.csv")) }
        try project.notes.write(to:directory("Notes").appendingPathComponent("project-notes.txt"),atomically:true,encoding:.utf8)
        var subset = index; subset.projects = [project]; subset.pins = subset.pins?.filter { $0.projectID == project.id }; subset.distanceChecks = subset.distanceChecks?.filter { $0.projectID == project.id }
        let referenceIDs = Set(project.references.map(\.id)); subset.displayNames = subset.displayNames?.filter { referenceIDs.contains($0.key) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted,.sortedKeys]
        try encoder.encode(subset).write(to:root.appendingPathComponent("project-index.json"))
        try encoder.encode(manifest).write(to:root.appendingPathComponent("manifest.json"))
        let failed = manifest.records.filter { $0.status != "exported" }
        var readme = AppLanguage.text("Project bundle: plans, models, source packages, reports, quantities, notes and numbered photos.",locale:locale)+"\n\n"
        readme += AppLanguage.text("Photos use Photos/<room-name>.<number>/. Numbering restarts at 1 in each room. Same-name collisions receive a suffix; manifest.json preserves room IDs and original numbers.",locale:locale)+"\n\n"
        readme += AppLanguage.text("Raw RoomPlan USDZ is not cleaned. Scan coordinates are not GPS. Device validation pending. Review manifest.json for missing or failed outputs; unavailable geometry is never invented.",locale:locale)+"\n\n"
        readme += AppLanguage.text("Multiple levels are separated into level files. Design files may use local floor datums. Review each level README before combining elevations.",locale:locale)+"\n\n"
        readme += failed.map { "\($0.sourceID): \($0.path) — \($0.detail ?? "")" }.joined(separator:"\n")
        try readme.write(to:root.appendingPathComponent("README.txt"),atomically:true,encoding:.utf8)
    }
    private struct CopyBudget {
        var bytes: Int64 = 0
        mutating func copyPackage(_ source: URL,to destination: URL) throws {
            try RoomPackage.coordinatedRead(at:source) { folder in
                let root = folder.standardizedFileURL.resolvingSymlinksInPath()
                guard (try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])).isDirectory == true,
                      (try folder.resourceValues(forKeys:[.isSymbolicLinkKey])).isSymbolicLink != true,
                      let files = FileManager.default.enumerator(at:folder,includingPropertiesForKeys:[.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey]) else { throw CocoaError(.fileReadCorruptFile) }
                var size: Int64 = 0, count = 0
                for case let file as URL in files {
                    let info = try file.resourceValues(forKeys:[.isSymbolicLinkKey,.isRegularFileKey,.fileSizeKey])
                    guard info.isSymbolicLink != true,file.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root.path+"/") else { throw CocoaError(.fileReadCorruptFile) }
                    count += 1
                    if info.isRegularFile == true { size += Int64(info.fileSize ?? 0) }
                    guard count <= 100_000,size <= 2_147_483_648,bytes+size <= 2_147_483_648 else { throw CocoaError(.fileWriteOutOfSpace) }
                }
                try FileManager.default.copyItem(at:folder,to:destination); bytes += size
            }
        }
    }
}
