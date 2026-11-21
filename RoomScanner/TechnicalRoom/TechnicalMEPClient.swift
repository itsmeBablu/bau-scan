import Foundation
import CryptoKit
import ImageIO
import CoreGraphics

/// Providers receive images only following an explicit user action in the review screen.
enum TechnicalMEPClient {
    enum Failure: LocalizedError {
        case configuration, response, quota, unavailable
        var errorDescription: String? {
            switch self {
            case .configuration: "Configure an HTTPS Google AI service and sign in with Google. The Gemini API key belongs on the service, not in the app."
            case .response: "The AI service returned invalid or mismatched image regions. No results were saved."
            case .quota: "AI quota or rate limit reached. Try later or use local geometry detection."
            case .unavailable: "The AI service is unavailable or not configured. Local geometry detection is still available."
            }
        }
    }
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    static func analyse(frame: TechnicalCaptureKeyframe, endpoint: URL, token: String) async throws -> [TechnicalMEPSuggestion] {
        guard endpoint.scheme == "https", endpoint.host != nil, endpoint.user == nil, endpoint.password == nil,
              endpoint.query == nil, endpoint.fragment == nil, !token.isEmpty, !token.contains("\n"), !token.contains("\r") else { throw Failure.configuration }
        try frame.validate()
        let digest = SHA256.hash(data: frame.jpegData).map { String(format: "%02x",$0) }.joined()
        struct Request: Encodable {
            let schemaVersion = 1
            let frameID: UUID
            let imageSHA256: String
            let imageJPEG: Data
            let maskWidth: Int
            let maskHeight: Int
        }
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/segment"))
        request.httpMethod = "POST"
        request.setValue("application/json",forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(token)",forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(Request(frameID: frame.id,imageSHA256: digest,imageJPEG: frame.jpegData,
                                                            maskWidth: frame.depth.width,maskHeight: frame.depth.height))
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 120; config.timeoutIntervalForResource = 150
        config.httpShouldSetCookies = false; config.urlCredentialStorage = nil
        let session = URLSession(configuration: config,delegate: NoRedirects(),delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (data,response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw Failure.response }
        if http.statusCode == 429 { throw Failure.quota }
        guard http.statusCode == 200 else { throw Failure.unavailable }
        guard data.count <= 4 * 1_048_576 else { throw Failure.response }
        let result = try JSONDecoder().decode(TechnicalMEPMaskResponse.self,from: data)
        guard result.schemaVersion == 1, result.frameID == frame.id, result.imageSHA256 == digest,
              !result.model.isEmpty, result.model.count <= 100, result.instances.count <= 24 else { throw Failure.response }
        let colors = try imageColors(frame)
        var suggestions: [TechnicalMEPSuggestion] = []
        for instance in result.instances {
            try Task.checkCancellation()
            let mask = try instance.pixels(expectedWidth: frame.depth.width,expectedHeight: frame.depth.height)
            let samples = try TechnicalMEPDepthPoints.samples(frame: frame,mask: mask,colors: colors)
            var fitted = try TechnicalMEPFitter.detect(samples,kind: instance.kind,evidenceIDs: [frame.id],modelScore: instance.score)
            for i in fitted.indices { fitted[i].method = "\(result.model):\(fitted[i].method)"; try fitted[i].validate() }
            suggestions += fitted
        }
        return suggestions
    }
    static func imageColors(_ frame: TechnicalCaptureKeyframe) throws -> [TechnicalPoint3?] {
        guard let source = CGImageSourceCreateWithData(frame.jpegData as CFData,nil),
              let image = CGImageSourceCreateImageAtIndex(source,0,nil), image.width == frame.jpegWidth,
              image.height == frame.jpegHeight else { throw Failure.response }
        let w = frame.depth.width, h = frame.depth.height
        var bytes = [UInt8](repeating: 0,count: w*h*4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress,width: w,height: h,bitsPerComponent: 8,bytesPerRow: w*4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image,in: CGRect(x: 0,y: 0,width: w,height: h))
            return true
        }
        guard drawn else { throw Failure.response }
        return (0..<w*h).map { .init(x: Double(bytes[$0*4])/255,y: Double(bytes[$0*4+1])/255,z: Double(bytes[$0*4+2])/255) }
    }
}
