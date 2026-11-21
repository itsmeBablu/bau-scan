import SwiftUI
import Observation
import GoogleSignIn
import GoogleSignInSwift
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Authentication is isolated from House capture and never contains the Gemini API key.
@Observable @MainActor
final class TechnicalGoogleAIAccount {
    static let shared = TechnicalGoogleAIAccount()
    private(set) var email: String?
    private(set) var busy = false
    var error: String?
    var signedIn: Bool { email != nil }
    static var configured: Bool {
        let bundle = Bundle.main
        guard let client = bundle.object(forInfoDictionaryKey: "GIDClientID") as? String,
              let server = bundle.object(forInfoDictionaryKey: "GIDServerClientID") as? String,
              !client.isEmpty,!server.isEmpty else { return false }
        let types = bundle.object(forInfoDictionaryKey: "CFBundleURLTypes") as? [[String:Any]] ?? []
        return configurationIsValid(client: client,server: server,schemes: types.flatMap { $0["CFBundleURLSchemes"] as? [String] ?? [] })
    }
    static func configurationIsValid(client: String,server: String,schemes: [String]) -> Bool {
        guard client.hasSuffix(".apps.googleusercontent.com"),server.hasSuffix(".apps.googleusercontent.com") else { return false }
        return schemes.contains(client.split(separator: ".").reversed().joined(separator: "."))
    }
    static func handle(_ url: URL) -> Bool {
        guard configured else { return false }
        return GIDSignIn.sharedInstance.handle(url)
    }
    private func configure() throws {
        guard Self.configured,
              let client = Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String,
              let server = Bundle.main.object(forInfoDictionaryKey: "GIDServerClientID") as? String else { throw AuthError.setupRequired }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: client,serverClientID: server)
    }
    enum AuthError: LocalizedError {
        case setupRequired, windowUnavailable, signInRequired
        var errorDescription: String? {
            switch self {
            case .setupRequired: "Google AI is not configured in this build. Add the Google OAuth client IDs, redirect scheme and service URL using the setup guide. You can continue scanning offline."
            case .windowUnavailable: "Return to the app window and try signing in again."
            case .signInRequired: "Sign in with Google before sending selected scan images."
            }
        }
    }
    func restore() async {
        guard Self.configured,!busy,!signedIn else { return }
        do {
            try configure()
            if GIDSignIn.sharedInstance.hasPreviousSignIn() {
                let user = try await GIDSignIn.sharedInstance.restorePreviousSignIn()
                email = user.profile?.email
            }
        } catch { email = nil }
    }
    func signIn() async {
        guard !busy else { return }; busy = true
        defer { busy = false }
        do {
            try configure()
            #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { throw AuthError.windowUnavailable }
            var controller = root
            while let next = controller.presentedViewController { controller = next }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: controller)
            #else
            guard let window = NSApp.keyWindow else { throw AuthError.windowUnavailable }
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: window)
            #endif
            email = result.user.profile?.email
        } catch { self.error = error.localizedDescription }
    }
    func idToken() async throws -> String {
        try configure()
        guard let user = GIDSignIn.sharedInstance.currentUser else { throw AuthError.signInRequired }
        let refreshed = try await user.refreshTokensIfNeeded()
        guard let token = refreshed.idToken?.tokenString else { throw AuthError.signInRequired }
        return token
    }
    func signOut() { GIDSignIn.sharedInstance.signOut(); email = nil }
    func photosAccessToken() async throws -> String {
        try configure()
        guard var user = GIDSignIn.sharedInstance.currentUser else { throw AuthError.signInRequired }
        let scope = "https://www.googleapis.com/auth/photoslibrary.appendonly"
        if !(user.grantedScopes ?? []).contains(scope) {
            #if os(iOS)
            guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first(where: { $0.activationState == .foregroundActive }),
                  let root = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { throw AuthError.windowUnavailable }
            var controller = root
            while let next = controller.presentedViewController { controller = next }
            let result = try await user.addScopes([scope],presenting: controller)
            #else
            guard let window = NSApp.keyWindow else { throw AuthError.windowUnavailable }
            let result = try await user.addScopes([scope],presenting: window)
            #endif
            user = result.user
        }
        guard (user.grantedScopes ?? []).contains(scope) else { throw AuthError.signInRequired }
        let refreshed = try await user.refreshTokensIfNeeded()
        return refreshed.accessToken.tokenString
    }
}

struct TechnicalGoogleAIConnection: View {
    @State private var account = TechnicalGoogleAIAccount.shared
    var body: some View {
        VStack(alignment: .leading,spacing: 10) {
            if let email = account.email {
                Text("Signed in as \(email)").font(.caption)
                Button("Sign out of Google") { account.signOut() }
            } else {
                GoogleSignInButton { Task { await account.signIn() } }.frame(maxWidth: 240).disabled(account.busy)
            }
            if account.busy { ProgressView("Signing in…") }
            if !TechnicalGoogleAIAccount.configured {
                Text("Google project setup is required for this build. Offline scanning remains available.").font(.caption).foregroundStyle(.secondary)
            }
        }
        .task { await account.restore() }
        .alert("Google sign-in",isPresented: Binding(get: { account.error != nil },set: { if !$0 { account.error = nil } })) {
            Button("OK") { account.error = nil }
        } message: { Text(account.error ?? "") }
    }
}

/// Status only: scan/review screens never initiate authentication or keychain restoration.
struct TechnicalGoogleAIStatus: View {
    @State private var account = TechnicalGoogleAIAccount.shared
    var body: some View {
        Label(account.signedIn ? "Google connected" : "Google not connected",systemImage: account.signedIn ? "checkmark.circle" : "person.crop.circle")
            .font(.caption).foregroundStyle(.secondary)
        if !account.signedIn { Text("Connect Google in Settings → Google account & AI.").font(.caption).foregroundStyle(.secondary) }
    }
}

struct GoogleAccountSettingsView: View {
    @AppStorage("technical.googleAI.serviceURL") private var endpoint = ""
    @AppStorage("technical.googleAI.enabled") private var enabled = false
    var body: some View {
        Form {
            Section("Google account") { TechnicalGoogleAIConnection() }
            Section("AI recognition") {
                Toggle("Google AI mode",isOn: $enabled)
                Text("Scanning and offline recognition work without Google. Images stay local until you choose them and confirm sending in MEP review.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Connection") {
                TextField("HTTPS Google AI service URL",text: $endpoint).autocorrectionDisabled()
                Text("Configure the service URL here. The Gemini API key stays on the backend.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).navigationTitle("Google account & AI")
            .onAppear { if endpoint.isEmpty { endpoint = Bundle.main.object(forInfoDictionaryKey: "TechnicalGoogleAIServiceURL") as? String ?? "" } }
    }
}
