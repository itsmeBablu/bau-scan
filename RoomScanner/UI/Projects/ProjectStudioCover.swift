import SwiftUI
import SceneKit

/// Visible Studio cards render derived design previews; no preview is written
/// into the original package. The bounded cache is disposable presentation data.
struct ProjectStudioCover:View {
    let entry:ProjectLibraryEntry
    @State private var image:CGImage?
    private var key:String { entry.id+entry.root.path+entry.date.description }
    var body:some View {
        Group {
            if let image { Image(decorative:image,scale:1).resizable().scaledToFit() }
            else { Image(systemName:"cube.transparent").font(.title2).foregroundStyle(.secondary) }
        }.frame(maxWidth:.infinity).frame(height:160)
            .background(DS.ColorToken.card.color,in:RoundedRectangle(cornerRadius:DS.Radius.small))
            .task(id:key) {
                image = nil
                if let cached = StudioCoverCache.images[key] { image = cached; return }
                do {
                    let entry = entry
                    let document = try await BackgroundWork.run {
                        let source:SceneEditDocument.Source
                        switch entry.reference.kind {
                        case .house,.designHouse: source = .house
                        case .room,.designRoom: source = .room
                        case .technicalRoom,.designTechnical: source = .technical
                        }
                        if let saved = try SceneEditStore.read(SceneEditStore.url(root:entry.root,source:source,id:entry.reference.itemID),source:source,id:entry.reference.itemID) { return saved }
                        if source == .technical { return try SceneEditDocument.technical(TechnicalRoomPackage.read(from:entry.url)) }
                        let house = source == .house ? try HousePackage.readHouse(from:entry.url) : House(room:try RoomPackage.readPlan(from:entry.url))
                        return SceneEditDocument.seed(house:house,source:source,id:entry.reference.itemID)
                    }
                    guard !Task.isCancelled else { return }
                    let view = SCNView(frame:CGRect(x:0,y:0,width:320,height:240))
                    let controller = StudioSceneController(); controller.view = view
                    controller.configure(document,story:document.shell.stories.first?.index ?? 0,cutaway:true,selected:nil,moving:false,reset:0)
                    let data = try controller.png(size:.init(width:400,height:300))
                    guard !Task.isCancelled else { return }
                    let decoded = try await PhotoThumbnailCache.shared.image(data:data,maximumPixelSize:400)
                    guard !Task.isCancelled else { return }
                    if StudioCoverCache.images.count >= 32 { StudioCoverCache.images.removeAll() }
                    StudioCoverCache.images[key] = decoded; image = decoded
                } catch { /* A failed optional preview never prevents opening the saved design. */ }
            }
    }
}

@MainActor private enum StudioCoverCache {
    static var images:[String:CGImage] = [:]
}
