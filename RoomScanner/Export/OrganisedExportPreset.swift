import Foundation

enum OrganisedExportPreset: String, CaseIterable, Identifiable {
    case complete = "Complete Project"
    case engineering = "Engineering / BIM Package"
    case technical = "Technical Room Package"
    case plans = "Floor Plans Only"
    case models = "3D Models Only"
    case photos = "Photos Only"
    case backup = "Native Backup"
    case custom = "Custom Export"
    var id: String { rawValue }

    static func matching(_ options: OrganisedExportService.Options) -> Self {
        func flags(_ value: OrganisedExportService.Options) -> [Bool] {
            [value.includePlans,value.includeModels,value.includeTechnicalRoom,value.includePhotos,value.includeSourcePhotos,value.includeStudio,value.includeNativePackages,value.includeIFC,value.includeArchitectureIFC,value.photosOnly]
        }
        return allCases.first { preset in
            guard preset != .custom else { return false }
            var expected = options; preset.apply(to:&expected)
            return flags(expected) == flags(options)
        } ?? .custom
    }

    func apply(to options: inout OrganisedExportService.Options) {
        guard self != .custom else { return }
        options.photosOnly = self == .photos
        options.includePlans = [.complete,.engineering,.plans].contains(self)
        options.includeModels = [.complete,.models].contains(self)
        options.includeTechnicalRoom = [.complete,.engineering,.technical,.backup].contains(self)
        options.includePhotos = [.complete,.technical,.photos].contains(self)
        options.includeSourcePhotos = [.complete,.photos].contains(self)
        options.includeStudio = [.complete,.backup].contains(self)
        options.includeNativePackages = [.complete,.backup].contains(self)
        options.includeIFC = [.complete,.engineering,.technical].contains(self)
        options.includeArchitectureIFC = [.complete,.engineering].contains(self)
    }
}
