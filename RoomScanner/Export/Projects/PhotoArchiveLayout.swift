import Foundation

/// One export-only hierarchy shared by selection, all-photo and complete ZIPs.
struct PhotoArchiveLayout {
    struct Paths { let image:String; let camera:String }
    private struct FloorScope:Hashable { let building:String?; let level:ProjectScanGrouping.LevelKey }
    private struct RoomScope:Hashable { let floor:String; let source:String; let room:UUID? }
    private var buildings:[String?:String] = [:]
    private var usedBuildings = Set<String>()
    private var floors:[FloorScope:String] = [:]
    private var usedFloors:[String:Set<String>] = [:]
    private var rooms:[RoomScope:String] = [:]
    private var usedRooms:[String:Set<String>] = [:]
    private var usedImages:[String:Set<String>] = [:]

    mutating func paths(photo:SurveyPhoto,roomName:String,sourceID:String,organization:ScanOrganization?,summary:ProjectScanSummary?,locale:Locale) throws -> Paths {
        try organization?.validate()
        let building = organization?.buildingName
        if buildings[building] == nil {
            buildings[building] = ArchivePath.unique(ArchivePath.component(building ?? AppLanguage.text("Unassigned building",locale:locale)),used:&usedBuildings)
        }
        var level = ProjectScanGrouping.LevelKey(number:organization?.level,otherName:organization?.otherLevelName)
        if let summary,summary.stories > 1 {
            let story = summary.roomDetails.first { $0.id == photo.roomID }?.story
            level = .init(number:story.flatMap { organization?.storyLevels?[$0] },otherName:nil)
        }
        let scope = FloorScope(building:building,level:level),buildingPath = "Photos/"+(buildings[building] ?? "")
        if floors[scope] == nil {
            let label = level.number.map { String($0)+"."+StoryNaming.localizedName(for:$0,locale:locale) } ?? level.otherName ?? AppLanguage.text("Unassigned level",locale:locale)
            floors[scope] = buildingPath+"/"+ArchivePath.unique(ArchivePath.component(label),used:&usedFloors[buildingPath,default:[]])
        }
        guard let floor = floors[scope] else { throw CocoaError(.fileWriteUnknown) }
        let roomScope = RoomScope(floor:floor,source:sourceID,room:photo.roomID)
        if rooms[roomScope] == nil {
            let base = ArchivePath.component(roomName)
            func fold(_ name:String) -> String { name.folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX")) }
            var name = base,suffix = 2
            while usedRooms[floor,default:[]].contains(fold(name)) { name = base+" \(suffix)"; suffix += 1 }
            usedRooms[floor,default:[]].insert(fold(name)); rooms[roomScope] = floor+"/"+name
        }
        guard let folder = rooms[roomScope],let name = folder.components(separatedBy:"/").last else { throw CocoaError(.fileWriteUnknown) }
        let stem = ArchivePath.unique(name+".\(photo.number)",used:&usedImages[folder,default:[]])
        return Paths(image:folder+"/"+stem+".jpg",camera:folder+"/"+stem+".camera.json")
    }
}
