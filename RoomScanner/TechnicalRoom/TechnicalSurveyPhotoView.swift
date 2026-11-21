import SwiftUI
import ImageIO

struct TechnicalSurveyPhotoView: View {
    let photo: TechnicalCaptureKeyframe
    var persistLink: ((UUID,URL) async throws -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var image: CGImage?
    @State private var busy = false
    @State private var error: String?
    @State private var remoteURL: URL?
    @State private var confirmCopy = false
    @State private var showingGooglePhotos = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    if let image { Image(decorative: image,scale: 1).resizable().scaledToFit() }
                    Text("Photo taken at this camera position. The position uses the saved scan coordinates; it is not a GPS location.").font(.caption).foregroundStyle(.secondary)
                    if let link = remoteURL ?? photo.googlePhotosURL { Link("Open in Google Photos",destination: link) }
                    if photo.googlePhotosURL == nil,persistLink != nil {
                        DisclosureGroup("Google Photos",isExpanded: $showingGooglePhotos) {
                        if showingGooglePhotos {
                        TechnicalGoogleAIConnection()
                        Button(remoteURL == nil ? "Copy to Google Photos…" : "Save Google Photos link") {
                            if remoteURL == nil { confirmCopy = true } else { copy() }
                        }.disabled(busy || !TechnicalGoogleAIAccount.shared.signedIn)
                        }
                        }.disabled(busy)
                    }
                    if busy { ProgressView("Saving Google Photos copy…") }
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                }.padding()
            }
            .navigationTitle("Scan photo")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.disabled(busy) } }
        }
        #if os(macOS)
        .frame(minWidth: 400,minHeight: 450)
        #endif
        .interactiveDismissDisabled(busy)
        .task {
            if let source = CGImageSourceCreateWithData(photo.jpegData as CFData,nil) {
                image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways: true,kCGImageSourceThumbnailMaxPixelSize: 1600] as CFDictionary)
            }
        }
        .confirmationDialog("Copy this scan photo to Google Photos?",isPresented: $confirmCopy,titleVisibility: .visible) {
            Button("Copy photo") { copy() }
        } message: { Text("Google will receive this photo. Separate Google Photos upload permission is required. A local copy remains in your scan; the Google Photos link is private to its owning account.") }
    }
    private func copy() {
        guard !busy,let persistLink else { return }; busy = true; error = nil
        Task { @MainActor in
            defer { busy = false }
            do {
                let link: URL
                if let remoteURL { link = remoteURL }
                else {
                    let token = try await TechnicalGoogleAIAccount.shared.photosAccessToken()
                    link = try await TechnicalGooglePhotos.upload(photo,token: token)
                    remoteURL = link
                }
                try await persistLink(photo.id,link)
            } catch { self.error = error.localizedDescription }
        }
    }
}
