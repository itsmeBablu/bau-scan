import SwiftUI

struct ProjectRecentEvidenceView: View {
    let projectID:UUID
    @Environment(RenovationWorkspace.self) private var workspace
    @Environment(\.locale) private var locale
    @State private var summary = ProjectEvidenceSummaryCache.Summary()
    @State private var selected:ProjectPhotoAsset?
    private var project:RenovationProject? { workspace.project(projectID) }
    var body:some View {
        VStack(alignment:.leading,spacing:DS.Spacing.xl) {
            VStack(alignment:.leading,spacing:DS.Spacing.m) {
                HStack {
                    Text("Recent photos").font(.headline); Spacer()
                    NavigationLink { ProjectPhotosView(projectID:projectID) } label: { Text("See All") }
                }
                if summary.photos.isEmpty { Text("No project photos yet").foregroundStyle(.secondary) }
                else {
                    ScrollView(.horizontal) {
                        LazyHStack(alignment:.top,spacing:DS.Spacing.m) {
                            ForEach(summary.photos) { asset in
                                Button { selected = asset } label: {
                                    VStack(alignment:.leading,spacing:DS.Spacing.xs) {
                                        ProjectPhotoThumbnail(asset:asset).frame(width:DS.Size.thumbnail,height:DS.Size.thumbnail)
                                            .clipShape(RoundedRectangle(cornerRadius:DS.Radius.thumbnail))
                                        Text(asset.title).font(.caption).lineLimit(2).frame(width:DS.Size.thumbnail,alignment:.leading)
                                    }
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            VStack(alignment:.leading,spacing:DS.Spacing.m) {
                HStack {
                    Text("Recent voice notes").font(.headline); Spacer()
                    NavigationLink { ProjectVoiceNotesView(projectID:projectID) } label: { Text("See All") }
                }
                if summary.voices.isEmpty { Text("No voice notes yet").foregroundStyle(.secondary) }
                ForEach(summary.voices) { note in
                    InlineVoiceNoteRow(note:note,root:workspace.notesRoot,
                        subtitle:workspace.entry(note.reference).map { workspace.title($0,locale:locale) } ?? note.reference.itemID.uuidString)
                }
            }.dsCard()
            VStack(alignment:.leading,spacing:DS.Spacing.m) {
                Text("Project notes").font(.headline)
                if let text = project?.notes,!text.isEmpty { Text(text).lineLimit(3).foregroundStyle(.secondary) }
                NavigationLink { ProjectWrittenNotesView(projectID:projectID) } label: { Label("Project notes",systemImage:"note.text") }
                NavigationLink { ProjectPinsView(projectID:projectID) } label: { Label("Notes & task pins",systemImage:"mappin") }
                HStack {
                    Label(String(summary.photoCount),systemImage:"photo").accessibilityLabel("Photos")
                    Label(String(summary.voiceCount),systemImage:"waveform").accessibilityLabel("Voice notes")
                    Label(String(summary.writtenCount),systemImage:"note.text").accessibilityLabel("Written notes")
                }.font(.caption).foregroundStyle(.secondary)
                ForEach(Array(Set(summary.warnings)).sorted(),id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
            }.dsCard()
        }
        .task(id:projectID.uuidString+workspace.notesRoot.path+String(workspace.catalogueRevision)+locale.identifier) {
            let entries = project?.references.compactMap(workspace.entry).map { workspace.localizedEntry($0,locale:locale) } ?? []
            let root = workspace.notesRoot,summaries = workspace.scanSummaries
            do {
                let result = try await ProjectEvidenceSummaryCache.shared.summary(projectID:projectID,entries:entries,notesRoot:root,summaries:summaries)
                guard !Task.isCancelled else { return }; summary = result
            } catch { if !Task.isCancelled { summary = .init(warnings:[error.localizedDescription]) } }
        }
        .sheet(item:$selected) { asset in ProjectPhotoGallery(assets:summary.photos,initial:asset.id) }
    }
}
