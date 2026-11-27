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
    @Environment(\.openURL) private var openURL
    @State private var showingSourcePrompt = false
    @State private var sourcePassword = ""
    @State private var wrongSourcePassword = false
    @State private var googleAccount = TechnicalGoogleAIAccount.shared
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
        Group {
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
        .environment(\.locale,(AppLanguage(rawValue:language) ?? .system).locale)
        .dsAppTheme()
        .sheet(isPresented: $showingSourcePrompt) {
            sourcePasswordSheet
                .environment(\.locale,(AppLanguage(rawValue:language) ?? .system).locale)
                .dsAppTheme()
        }
    }

    private var form: some View {
        Form {
            Section("Privacy") {
                GoogleAIConsentToggle()
                AIARModeStatusRow()
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
                        GoogleProfileAvatarView(url: googleAccount.avatarURL, size: DS.IconSize.hero.rawValue) {
                            Image(systemName: "person.crop.circle.fill")
                                .dsIcon(.hero, weight: .light)
                                .foregroundStyle(DS.ColorToken.textSecondary.color)
                        }
                        if let name = Self.workspaceDisplayName(saved: displayName, googleName: googleAccount.displayName) {
                            Text(verbatim: name).font(.title2.bold())
                        } else {
                            Text("Your workspace").font(.title2.bold())
                        }
                        if !organisation.isEmpty { Text(organisation).font(.subheadline).foregroundStyle(.secondary) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .task { await googleAccount.restore() }
                    TextField("Name", text: $displayName, prompt: googleAccount.displayName.map { Text(verbatim: $0) })
                    TextField("Organisation", text: $organisation)
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
                ProjectStorageList(location: store.location, refreshKey: storageTaskID)
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
                VStack(spacing: DS.Spacing.m) {
                    BrandLogoView(size: DS.Size.aboutLogo)
                    VStack(spacing: DS.Spacing.xs) {
                        Text("dWalkScan")
                            .font(DS.Typography.title3.weight(.semibold))
                        Text("Babu Reddy Kanala")
                            .font(DS.Typography.subheadline)
                            .foregroundStyle(DS.ColorToken.textSecondary.color)
                    }
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.vertical, DS.Spacing.m)

                LabeledContent("settings.about.version") {
                    Text(version)
                }
                Link(destination: Self.websiteURL) {
                    Label("settings.about.website", systemImage: "globe")
                }
                Button {
                    sourcePassword = ""
                    wrongSourcePassword = false
                    showingSourcePrompt = true
                } label: {
                    Label("settings.about.source", systemImage: "chevron.left.forwardslash.chevron.right")
                }
            }
        }
        .formStyle(.grouped)
    }

    private static let websiteURL = URL(string: "https://wed-walk-scan.vercel.app/")!
    private static let sourceURL = URL(string: "https://github.com/itsmeBablu/bau-scan")!

    static func canOpenSourceRepository(password: String) -> Bool {
        password.trimmingCharacters(in: .whitespacesAndNewlines) == "7416"
    }

    static func workspaceDisplayName(saved: String, googleName: String?) -> String? {
        let custom = saved.trimmingCharacters(in: .whitespacesAndNewlines)
        if !custom.isEmpty { return custom }
        let accountName = googleName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return accountName.isEmpty ? nil : accountName
    }

    private var sourcePasswordSheet: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $sourcePassword)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .onChange(of: sourcePassword) { _, newValue in
                            if !newValue.isEmpty { wrongSourcePassword = false }
                        }
                        .onSubmit { submitSourcePassword() }
                    if wrongSourcePassword {
                        Label("Incorrect password", systemImage: "exclamationmark.triangle")
                            .font(DS.Typography.caption)
                            .foregroundStyle(DS.ColorToken.error.color)
                    }
                } footer: {
                    Text("Enter the password to open the GitHub repository.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("settings.about.source")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        sourcePassword = ""
                        wrongSourcePassword = false
                        showingSourcePrompt = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Open") { submitSourcePassword() }
                        .disabled(sourcePassword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        #if os(iOS)
        .presentationDetents([.height(260), .medium])
        #else
        .frame(minWidth: 340, minHeight: 210)
        #endif
    }

    private func submitSourcePassword() {
        guard Self.canOpenSourceRepository(password: sourcePassword) else {
            wrongSourcePassword = true
            sourcePassword = ""
            return
        }
        sourcePassword = ""
        wrongSourcePassword = false
        showingSourcePrompt = false
        openURL(Self.sourceURL)
    }

    private var storageTaskID: String {
        store.location.documentsURL.path + "|\(store.isCloud)|\(store.records.count)|\(store.houseRecords.count)"
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

private struct ProjectStorageList: View {
    let location: StorageLocation
    let refreshKey: String
    @Environment(\.locale) private var locale
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var entries: [ProjectStorageEntry] = []
    @State private var loading = true
    @State private var showAll = false
    @State private var expandedProjects: Set<UUID> = []

    private static let compactThreshold = 3
    private static let compactScrollHeight: CGFloat = 152
    private static let expandedScrollHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.s) {
            HStack(spacing: DS.Spacing.s) {
                Text("Projects")
                    .font(DS.Typography.subheadline.weight(.semibold))
                    .foregroundStyle(DS.ColorToken.textSecondary.color)
                Spacer(minLength: DS.Spacing.s)
                if entries.count > Self.compactThreshold {
                    Button {
                        withAnimation(DS.Motion.animation(reduceMotion: reduceMotion)) {
                            showAll.toggle()
                        }
                    } label: {
                        Text(showAll ? "Show less" : "Show all")
                            .dsBadge()
                            .frame(minHeight: DS.Size.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            if loading && entries.isEmpty {
                ProgressView()
                    .controlSize(.small)
            } else if entries.isEmpty {
                Text("No projects yet")
                    .font(DS.Typography.caption)
                    .foregroundStyle(DS.ColorToken.textSecondary.color)
            } else if !showAll && entries.count > Self.compactThreshold {
                ScrollView(.vertical) {
                    rows
                }
                .frame(height: expandedProjects.isEmpty ? Self.compactScrollHeight : Self.expandedScrollHeight)
            } else {
                rows
            }
        }
        .padding(.vertical, DS.Spacing.xs)
        .task(id: refreshKey) {
            await reload()
        }
    }

    private var rows: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                let isExpanded = expandedProjects.contains(entry.id)
                VStack(alignment: .leading, spacing: DS.Spacing.xs) {
                    Button {
                        withAnimation(DS.Motion.animation(reduceMotion: reduceMotion)) {
                            if isExpanded { expandedProjects.remove(entry.id) }
                            else { expandedProjects.insert(entry.id) }
                        }
                    } label: {
                        HStack(spacing: DS.Spacing.s) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(DS.Typography.caption.weight(.semibold))
                                .foregroundStyle(DS.ColorToken.accent.color)
                                .frame(width: DS.Spacing.l)
                            Text(entry.displayName(locale: locale))
                                .font(DS.Typography.body)
                                .foregroundStyle(DS.ColorToken.textPrimary.color)
                                .lineLimit(2)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: DS.Spacing.s)
                            Text(entry.formattedBytes)
                                .font(DS.Typography.subheadline)
                                .monospacedDigit()
                                .foregroundStyle(DS.ColorToken.textSecondary.color)
                        }
                        .frame(minHeight: DS.Size.minimumTouchTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(entry.displayName(locale: locale)))
                    .accessibilityValue(Text(verbatim: entry.formattedBytes))
                    .accessibilityHint(Text("Project details"))

                    if isExpanded {
                        DSFlowLayout(spacing: DS.Spacing.s, lineSpacing: DS.Spacing.s) {
                            DSMetricBadge(title: "Layouts", value: String(entry.layouts), tone: .sky)
                            DSMetricBadge(title: "Floors", value: String(entry.floors), tone: .lavender)
                            DSMetricBadge(title: "Total area", value: MeasurementFormat.squareMeters(entry.totalAreaM2, locale: locale), tone: .butter)
                            DSMetricBadge(title: "Approved", value: String(entry.approvedCount), tone: .mint)
                            DSMetricBadge(title: "Accepted", value: String(entry.acceptedCount), tone: .peach)
                        }
                        .padding(.leading, DS.Spacing.xl)
                        .padding(.bottom, DS.Spacing.s)
                    }
                }
                if index < entries.count - 1 {
                    Divider()
                }
            }
        }
    }

    private func reload() async {
        loading = entries.isEmpty
        defer { loading = false }
        let active = location
        let local = RootView.hasForcedRoot ? active.documentsURL : StorageLocation.local().documentsURL
        var roots = ["local": local]
        if active.kind == .iCloud { roots["icloud"] = active.documentsURL }
        let connected = roots, currentLocale = locale
        let loaded = try? await BackgroundWork.run(priority: .utility) {
            try ProjectStorageUsage.load(roots: connected, catalogueRoot: local, locale: currentLocale)
        }
        guard !Task.isCancelled, let loaded else { return }
        entries = loaded
    }
}
