import Foundation

enum TechnicalGooglePhotos {
    enum Failure: LocalizedError {
        case upload
        var errorDescription: String? { "Google Photos could not save this image. The local scan photo is still available. Check the Google Photos API configuration and account permission before retrying." }
    }
    /// A user explicitly requests each copy. The link is private to its owning Google account.
    static func upload(_ photo: TechnicalCaptureKeyframe, token: String) async throws -> URL {
        try photo.validate()
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 120
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var upload = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/uploads")!)
        upload.httpMethod = "POST"
        upload.setValue("Bearer \(token)",forHTTPHeaderField: "Authorization")
        upload.setValue("application/octet-stream",forHTTPHeaderField: "Content-Type")
        upload.setValue("image/jpeg",forHTTPHeaderField: "X-Goog-Upload-Content-Type")
        upload.setValue("raw",forHTTPHeaderField: "X-Goog-Upload-Protocol")
        let (data,response) = try await session.upload(for: upload,from: photo.jpegData)
        guard (response as? HTTPURLResponse)?.statusCode == 200,data.count < 16_384,
              let uploadToken = String(data: data,encoding: .utf8),!uploadToken.isEmpty else { throw Failure.upload }
        var create = URLRequest(url: URL(string: "https://photoslibrary.googleapis.com/v1/mediaItems:batchCreate")!)
        create.httpMethod = "POST"
        create.setValue("Bearer \(token)",forHTTPHeaderField: "Authorization")
        create.setValue("application/json",forHTTPHeaderField: "Content-Type")
        create.httpBody = try JSONSerialization.data(withJSONObject: ["newMediaItems": [[
            "description": "dWalkScan technical room survey photo",
            "simpleMediaItem": ["fileName": "dWalkScan-\(photo.id.uuidString).jpg","uploadToken": uploadToken]
        ]]])
        let (created,createdResponse) = try await session.data(for: create)
        guard (createdResponse as? HTTPURLResponse)?.statusCode == 200,created.count < 1_048_576,
              let object = try JSONSerialization.jsonObject(with: created) as? [String:Any],
              let results = object["newMediaItemResults"] as? [[String:Any]],let first = results.first,
              let status = first["status"] as? [String:Any],(status["code"] as? Int ?? 0) == 0,
              let media = first["mediaItem"] as? [String:Any],let link = media["productUrl"] as? String,
              let url = URL(string: link),url.scheme == "https",url.host == "photos.google.com" else { throw Failure.upload }
        return url
    }
}
