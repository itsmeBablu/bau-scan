import SwiftUI

/// Settings: iCloud Drive, 'dWalkScan' folder, measurements (mm / m), updates (Mac), about.
struct SettingsView: View {
    @Environment(RoomStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(CloudAvailability.preferenceKey) private var useICloud = true
    @AppStorage("measurementUnit") private var unit: MeasurementUnit = .both
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
                .navigationTitle("settings.title")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } } }
        }
        #else
        form.frame(width: 480).frame(minHeight: 420)
        #endif
    }

    private var form: some View {
        Form {
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

            Section("settings.measurements.header") {
                Picker("settings.measurements.unit", selection: $unit) {
                    Text("settings.unit.both").tag(MeasurementUnit.both)
                    Text("settings.unit.millimeters").tag(MeasurementUnit.millimeters)
                    Text("settings.unit.meters").tag(MeasurementUnit.meters)
                }
            } footer: {
                Text("settings.measurements.footer")
            }

            #if os(macOS)
            Section("settings.updates.header") {
                Toggle("settings.updates.auto", isOn: $autoCheck)
                    .disabled(!updater.isConfigured)
                    .onChange(of: autoCheck) { _, on in if updater.isConfigured { updater.automaticallyChecksForUpdates = on } }
                LabeledContent("settings.updates.last") {
                    Text(updater.lastUpdateCheckDate.map { $0.formatted(date: .abbreviated, time: .shortened) } ?? String(localized: "settings.updates.never")).foregroundStyle(.secondary)
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

                LabeledContent("settings.about.version", value: version)
                // Redirect to GitHub repo only — project website is ignored and not redirected
                Link(destination: URL(string: "https://github.com/itsmeBablu/d-walk-scan")!) {
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
