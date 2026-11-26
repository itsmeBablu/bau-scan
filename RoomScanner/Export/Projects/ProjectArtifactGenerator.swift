import Foundation

enum ProjectArtifactGenerator {
    struct Result { let url:URL; let reused:Bool }
    struct SourceChanged:LocalizedError {
        var errorDescription:String? { AppLanguage.text("Project sources changed while exporting. No new artifact was saved. Review the project and generate again.") }
    }
    static func generate(kind:ProjectExportKind,project:RenovationProject,index:ProjectIndex,entries:[ProjectLibraryEntry],locale:Locale,unit:MeasurementUnit,includeDetails:Bool,wastePercent:Double,root:URL) async throws -> Result {
        let request = try await ProjectExportRequest.make(project:project,index:index,entries:entries,kind:kind,locale:locale,unit:unit,includeDetails:includeDetails,wastePercent:wastePercent)
        try checkMetadata(request,root:root)
        if let existing = try ProjectArtifactIndex.lookup(request,root:root) { return Result(url:existing,reused:true) }
        let scratch = try ExportService.scratchDirectory(),file = scratch.appendingPathComponent(kind.fileStem+"."+kind.suffix)
        defer { try? FileManager.default.removeItem(at:scratch) }
        switch kind {
        case .report,.quantities:
            let report = try ProjectReportLoader.load(project:project,entries:entries,locale:locale,pins:index.pins ?? [],checks:index.distanceChecks ?? [],wastePercent:wastePercent)
            let data:Data
            if kind == .quantities { data = ProjectQuantitiesCSV.data(report,locale:locale) }
            else { data = try ProjectReportRenderer.pdf(report,locale:locale,unit:unit) }
            try data.write(to:file,options:.atomic)
        case .photos:
            try SurveyPhotoArchiveWriter.archive(project:project,entries:entries,locale:locale,to:file)
        case .complete:
            try await ProjectBundleExporter.write(project:project,index:index,entries:entries,locale:locale,to:file,includeDetails:includeDetails,unit:unit,wastePercent:wastePercent)
        }
        try Task.checkCancellation(); try checkMetadata(request,root:root)
        let latest = try await ProjectExportRequest.make(project:project,index:index,entries:entries,kind:kind,locale:locale,unit:unit,includeDetails:includeDetails,wastePercent:wastePercent)
        guard latest == request else { throw SourceChanged() }
        try checkMetadata(request,root:root)
        return Result(url:try ProjectArtifactIndex.publish(file,request:request,projectName:project.name,root:root),reused:false)
    }
    private static func checkMetadata(_ request:ProjectExportRequest,root:URL) throws {
        let current = try ProjectIndexStore.read(root:root)
        guard let project = current.projects.first(where:{ $0.id == request.projectID }),
              try ProjectExportRequest.metadata(project:project,index:current) == request.metadataDigest else { throw SourceChanged() }
    }
}
