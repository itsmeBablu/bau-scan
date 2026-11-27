import SwiftUI

/// Settings: iCloud Drive, 'dWalkScan' folder, measurements (mm / m), updates (Mac), about.
struct SettingsView: View {
    @AppStorage(PDFPhotoPolicy.preferenceKey) private var pdfPhotos = PDFPhotoPolicy.defaultValue
    @AppStorage("evidence.2d.photos") private var photos2D = false
    @AppStorage("evidence.2d.audio") private var audio2D = false
    @AppStorage("evidence.2d.pins") private var pins2D = false
    @AppStorage("evidence.3d.photos") private var photos3D = true
    @AppStorage("evidence.3d.audio") private var audio3D = true
    @AppStorage("evidence.3d.pins") private var pins3D = true
    var embedded = false
    var includesProfile = false
    @AppStorage(AppLanguage.preferenceKey) private var language = AppLanguage.system.rawValue
    @AppStorage("renovation.proDetails") private var proDetails = false
    @AppStorage("ui.appearance") private var appearance = "system"
    @AppStorage("ui.projects.layout") private var projectLayout = "grid"
    @AppStorage("profile.displayName") private var displayName = ""
    @AppStorage("profile.organisation") private var organisation = ""
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CloudAvailability.preferenceKey) private var useICloud = false
    @AppStorage("scan.experimentalRelocalization") private var experimentalRelocalization = false
    @AppStorage("measurementUnit") private var unit: MeasurementUnit = .both
    @AppStorage(ScanPhotoPolicy.preferenceKey) private var cameraPhotos = true
    @AppStorage(ScanPerformance.preferenceKey) private var scanPerformance = ScanPerformance.balanced.rawValue
    #if os(iOS) && canImport(RoomPlan)
    @AppStorage(ScanCoordinator.radiatorPreferenceKey) private var detectRadiators = true
    #endif
    #if os(macOS)
    @Environment(UpdaterController.self) private var updater
    @State private var autoCheck = true
    #endif

    private var version: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(v) (\(b))"
    }

    var body: some View {
        #if os(iOS)
        NavigationStack {
            form
                .navigationTitle(includesProfile ? Text("Profile") : Text("settings.title"))
                .navigationBarTitleDisplayMode(embedded ? .large : .inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { if !embedded { Button("common.close") { dismiss() } } } }
        }
        #else
        NavigationStack { form }.frame(width: 480).frame(minHeight: 420)
        #endif
    }

    private var form: some View {
        Form {
            Section("Privacy") {
                GoogleAIConsentToggle()
                NavigationLink("Project data and deletion") { ProjectPrivacyView() }
                Text("Scans stay on this device unless you enable iCloud, share a file or explicitly send selected images for AI processing.").font(.caption)
            }
            Section("Display") {
                Picker("Appearance",selection:$appearance) {
                    Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
                }
                Picker("Projects layout",selection:$projectLayout) {
                    Text("List").tag("list"); Text("Grid").tag("grid")
                }
                Toggle("Pro details",isOn:$proDetails)
                Text("Show pipe designations, systems, provenance and structured schema exports. Existing data is always retained.").font(.caption).foregroundStyle(.secondary)
            }
            Section("2D visibility") {
                Toggle("Photos",isOn:$photos2D)
                Toggle("Voice notes",isOn:$audio2D)
                Toggle("Pins",isOn:$pins2D)
            }
            Section("3D visibility") {
                Toggle("Photos",isOn:$photos3D)
                Toggle("Voice notes",isOn:$audio3D)
                Toggle("Pins",isOn:$pins3D)
            }
            Section("Language") {
                Picker("Language",selection:$language) {
                    Text("System").tag(AppLanguage.system.rawValue)
                    Text("English").tag(AppLanguage.english.rawValue)
                    Text("Deutsch").tag(AppLanguage.german.rawValue)
                }
            }
            Section("PDF reports") {
                Toggle("Include photos in PDF reports", isOn: $pdfPhotos)
                Text("Photo ZIP folders are exported separately, even when PDF photos are disabled.").font(.caption).foregroundStyle(.secondary)
            }
            Section { DisclosureGroup("Advanced") {
                VoiceDiagnosticsView()
                #if DEBUG
                NavigationLink("Design system") { DesignSystemGallery() }
                #endif
            } }
            Section("Capture") {
                Toggle("Experimental recovery alignment",isOn:$experimentalRelocalization)
                Text("Read-only world-map test. Recovered and new rooms are never merged automatically.").font(.caption).foregroundStyle(.secondary)
                Toggle("Camera photos during scanning",isOn:$cameraPhotos)
                Picker("Scan performance",selection:$scanPerformance) {
                    ForEach(ScanPerformance.allCases,id:\.rawValue) { Text(AppLanguage.text($0.rawValue)).tag($0.rawValue) }
                }
                Text("Performance changes the live preview. Saved scan evidence keeps the same capture settings.").font(.caption).foregroundStyle(.secondary)
            }
            if includesProfile {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.fill").dsIcon(.hero,weight:.light).foregroundStyle(.secondary)
                        Text(displayName.isEmpty ? "Your workspace" : displayName).font(.title2.bold())
                        if !organisation.isEmpty { Text(organisation).font(.subheadline).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity).padding(.vertical,16)
                    TextField("Name",text: $displayName)
                    TextField("Organisation",text: $organisation)
                } footer: { Text("Workspace details are stored on this device. Google account details appear below after sign-in.") }
                Section("Google account") {
                    TechnicalGoogleAIConnection()
                    NavigationLink { GoogleAccountSettingsView() } label: { Label("AI & photo connections",systemImage: "sparkles") }
                }
            } else {
                Section("Accounts") {
                    NavigationLink { GoogleAccountSettingsView() } label: { Label("Google account & AI",systemImage: "person.crop.circle") }
                }
            }
            Section {
                #if !ROOMSCANNER_LOCAL_ONLY
                Toggle("settings.icloud.toggle", isOn: $useICloud)
                    .disabled(!store.allowsCloud)
                    .onChange(of: useICloud) { _, on in Task { await store.setCloudEnabled(on) } }
                #endif
                LabeledContent("settings.icloud.status") {
                    Label(store.isCloud ? "cloud.title.icloud" : "cloud.title.local", systemImage: store.isCloud ? "checkmark.icloud" : "internaldrive")
                        .foregroundStyle(.secondary)
                }
                #if !ROOMSCANNER_LOCAL_ONLY
                if !CloudAvailability.isSignedIn { Text("cloud.status.localNoAccount").font(.footnote).foregroundStyle(.secondary) }
                #endif
                Button { openLibraryFolder() } label: { Label("settings.openFolder", systemImage: "folder") }
            } header: { Text("settings.icloud.header") } footer: { Text("settings.icloud.footer") }

            #if os(iOS) && canImport(RoomPlan)
            Section {
                Toggle("Automatically detect radiators (Heizkörper)", isOn: $detectRadiators)
            } header: {
                Text("House scanning")
            } footer: {
                Text("During your next House scan, include the whole radiator and the wall beside it. Review possible radiators in House Options → Radiators.")
            }
            #endif

            Section {
                Picker("settings.measurements.unit", selection: $unit) {
                    Text("settings.unit.both").tag(MeasurementUnit.both)
                    Text("settings.unit.millimeters").tag(MeasurementUnit.millimeters)
                    Text("settings.unit.meters").tag(MeasurementUnit.meters)
                }
            } header: {
                Text("settings.measurements.header")
            } footer: {
                Text("settings.measurements.footer")
            }

            #if os(macOS)
            Section("settings.updates.header") {
                Toggle("settings.updates.auto", isOn: $autoCheck)
                    .disabled(!updater.isConfigured)
                    .onChange(of: autoCheck) { _, on in if updater.isConfigured { updater.automaticallyChecksForUpdates = on } }
                LabeledContent("settings.updates.last") {
                    Text(updater.lastUpdateCheckDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? AppLanguage.text("settings.updates.never")).foregroundStyle(.secondary)
                }
                Button("mac.menu.checkForUpdates") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                if !updater.isConfigured { Text("settings.updates.devBuild").font(.footnote).foregroundStyle(.secondary) }
            }
            .onAppear { updater.refresh(); if updater.isConfigured { autoCheck = updater.automaticallyChecksForUpdates } }
            #endif

            Section("settings.about.header") {
                HStack(spacing: 14) {
                    BrandLogoView(size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("dWalkScan").font(.headline)
                        Text("Babu Reddy").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)

                LabeledContent("settings.about.version") {
                    Text(version)
                }
                // Redirect to GitHub repo only — project website is ignored and not redirected
                Link(destination: URL(string: "https://github.com/itsmeBablu/bau-scan")!) {
                    Label("settings.about.source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .formStyle(.grouped)
    }

    private func openLibraryFolder() {
        try? store.location.prepare()
        #if os(macOS)
        NSWorkspace.shared.open(store.location.documentsURL)
        #else
        // Files app opens folder via shareddocuments:// URL scheme.
        var comps = URLComponents(url: store.location.documentsURL, resolvingAgainstBaseURL: false)
        comps?.scheme = "shareddocuments"
        if let url = comps?.url { UIApplication.shared.open(url) }
        #endif
    }
}
