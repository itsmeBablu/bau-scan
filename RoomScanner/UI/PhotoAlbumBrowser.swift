import SwiftUI

/// Virtual albums keep original JPEGs and library-scoped photo identities intact.
enum PhotoAlbumGrouping {
    struct Floor:Identifiable {
        let id:String
        let name:String
        let rooms:[Room]
        var photos:[ProjectPhotoAsset] { rooms.flatMap(\.photos) }
    }
    struct Room:Identifiable {
        let id:String
        let name:String
        let photos:[ProjectPhotoAsset]
    }
    static func floors(_ assets:[ProjectPhotoAsset],summaries:[String:ProjectScanSummary],organization:[String:ScanOrganization],locale:Locale,floorNames:[Int:String] = [:]) -> [Floor] {
        let groups = Dictionary(grouping:assets) { asset -> String in
            let story = summaries[asset.reference.id]?.roomDetails.first { $0.id == asset.photo.roomID }?.story
            let org = organization[asset.reference.id]
            let level = story.flatMap { org?.storyLevels?[$0] ?? (summaries[asset.reference.id]?.stories == 1 ? org?.level : nil) ?? $0 } ?? org?.level
            return (org?.buildingName ?? "")+"|"+(level.map(String.init) ?? "unknown")
        }
        return groups.map { key,photos in
            let first = photos[0],org = organization[first.reference.id]
            let story = summaries[first.reference.id]?.roomDetails.first { $0.id == first.photo.roomID }?.story
            let level = story.flatMap { org?.storyLevels?[$0] ?? (summaries[first.reference.id]?.stories == 1 ? org?.level : nil) ?? $0 } ?? org?.level
            let levelName = level.map { floorNames[$0] ?? StoryNaming.localizedName(for:$0,locale:locale) } ?? AppLanguage.text("Unassigned level",locale:locale)
            let rooms = Dictionary(grouping:photos) { $0.reference.id+":"+($0.photo.roomID?.uuidString ?? "unknown") }
                .map { id,values in Room(id:id,name:values[0].roomName,photos:values.sorted { ($0.photo.capturedAt ?? .distantPast) > ($1.photo.capturedAt ?? .distantPast) }) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            return Floor(id:key,name:[org?.buildingName,levelName].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator:" · "),rooms:rooms)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

struct PhotoAlbumBrowser:View {
    let assets:[ProjectPhotoAsset]
    let summaries:[String:ProjectScanSummary]
    var organization:[String:ScanOrganization] = [:]
    var floorNames:[Int:String] = [:]
    @Environment(\.locale) private var locale
    private var floors:[PhotoAlbumGrouping.Floor] { PhotoAlbumGrouping.floors(assets,summaries:summaries,organization:organization,locale:locale,floorNames:floorNames) }
    var body:some View {
        LazyVStack(alignment:.leading,spacing:20) {
            NavigationLink {
                PhotoRoomGrid(photos:assets.sorted { ($0.photo.capturedAt ?? .distantPast) > ($1.photo.capturedAt ?? .distantPast) },title:AppLanguage.text("Recent photos"))
            } label: { Label("Recent photos",systemImage:"clock").font(.headline) }
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150))],spacing:20) {
                ForEach(floors) { floor in
                    NavigationLink {
                        ScrollView {
                            LazyVGrid(columns:[GridItem(.adaptive(minimum:150))],spacing:20) {
                                ForEach(floor.rooms) { room in
                                    NavigationLink { PhotoRoomGrid(photos:room.photos,title:room.name) } label: {
                                        PhotoAlbumCover(title:room.name,symbol:"folder",photos:room.photos)
                                    }.buttonStyle(.plain)
                                }
                            }.padding()
                        }.navigationTitle(floor.name)
                    } label: { PhotoAlbumCover(title:floor.name,symbol:"square.stack",photos:floor.photos) }.buttonStyle(.plain)
                }
            }
        }
    }
}

private struct PhotoAlbumCover:View {
    let title:String
    let symbol:String
    let photos:[ProjectPhotoAsset]
    var body:some View {
        VStack(alignment:.leading,spacing:8) {
            if let first = photos.first { ProjectPhotoThumbnail(asset:first).frame(height:140).clipped().clipShape(RoundedRectangle(cornerRadius:DS.Radius.card)) }
            Label(title,systemImage:symbol).font(.headline).foregroundStyle(.primary)
            Text(String(photos.count)).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth:.infinity,alignment:.leading).contentShape(Rectangle())
    }
}

private struct PhotoRoomGrid:View {
    let photos:[ProjectPhotoAsset]
    let title:String
    @State private var selected:ProjectPhotoAsset?
    var body:some View {
        ScrollView {
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150))],spacing:16) {
                ForEach(photos) { photo in
                    Button { selected = photo } label: {
                        VStack(alignment:.leading,spacing:6) {
                            ProjectPhotoThumbnail(asset:photo).frame(height:140).clipped().clipShape(RoundedRectangle(cornerRadius:DS.Radius.panel))
                            Text(photo.title).font(.caption).foregroundStyle(.primary)
                        }
                    }.buttonStyle(.plain)
                }
            }.padding()
        }.navigationTitle(title)
            .sheet(item:$selected) { photo in ProjectPhotoGallery(assets:photos,initial:photo.id) }
    }
}
