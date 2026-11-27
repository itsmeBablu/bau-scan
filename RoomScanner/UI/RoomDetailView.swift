import SwiftUI

/// Room detail view: 2D Plan / 3D Viewer / Measurements tabs, export (⌘E),
/// titre renommable.
struct RoomDetailView: View {
    @Environment(RoomStore.self) private var store
    let record: RoomRecord
    @State private var plan: FloorPlan?
    @State private var loadError: String?
    @State private var actionError: String?
    /// `-RoomScannerInitialTab viewer|measures` et `-RoomScannerInitialViewerMode 2d|ar` au lancement (captures, essais).
    @State private var tab: Tab = {
        switch UserDefaults.standard.string(forKey: "RoomScannerInitialTab") { case "viewer": .viewer; case "measures": .measures; default: .plan }
    }()
    @State private var renaming = false
    @State private var exporting = false
    @State private var showingStudio = false
    @State private var showingVoiceNotes = false
    @State private var newName = ""
    @State private var viewerState: ViewerState = {
        let s = ViewerState()
        switch UserDefaults.standard.string(forKey: "RoomScannerInitialViewerMode") { case "2d": s.mode = .twoD; case "ar": s.mode = .ar; default: break }
        s.showDimensions = UserDefaults.standard.bool(forKey: "RoomScannerInitialDimensions")
        return s
    }()

    typealias Tab = ScanDetailTab

    private var currentRecord: RoomRecord { store.records.first { $0.id == record.id } ?? record }

    var body: some View {
        Group {
            if let plan {
                content(plan)
            } else if let loadError {
                ContentUnavailableView(loadError, systemImage: "exclamationmark.triangle")
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge:.top) { if currentRecord.incomplete == true { Text("Partial scan · not fully scanned").font(.caption).padding(8).frame(maxWidth:.infinity).dsMaterial() } }
        .navigationTitle(currentRecord.name)
        .scanWorkspaceFocus()
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ScanDetailToolbar(ready:plan != nil,export:{ exporting = true },
                              design:{ viewerState.mode = .threeD; showingStudio = true },
                              rename:{ newName = currentRecord.name; renaming = true })
        }
        .sheet(isPresented: $showingVoiceNotes) {
            ScanVoiceNotesSheet(reference: .init(kind: .room,itemID: record.id,library: store.isCloud ? "icloud" : "local"),location: store.location)
        }
        .sheet(isPresented: $exporting) {
            if let plan { ExportSheet(record: currentRecord, plan: plan, packageURL: store.packageURL(for: currentRecord)).environment(store) }
        }
        .studioPresentation(isPresented: $showingStudio) {
            if let plan {
                let scan = try? RoomPackage.readScan(from: store.packageURL(for: currentRecord))
                NavigationStack { StudioProjectView(seed: .seed(house: House(room: plan),source: .room,id: currentRecord.id,scans: scan.map { [$0] } ?? []),storageRoot: store.location.documentsURL) }
            }
        }
        .alert("detail.rename", isPresented: $renaming) {
            TextField("detail.rename.placeholder", text: $newName)
            Button("common.ok") { rename() }
            Button("common.cancel", role: .cancel) {}
        }
        .task(id: record.id) { load() }
        .alert("Error",isPresented:Binding(get:{ actionError != nil },set:{ if !$0 { actionError = nil } })) {
            Button("OK") { actionError = nil }
        } message: { Text(actionError ?? "") }
    }

    @ViewBuilder private func content(_ plan: FloorPlan) -> some View {
        VStack(spacing: 0) {
            ScanDetailTabPicker(selection:$tab)
            .padding(.horizontal)
            .padding(.vertical, 8)
            switch tab {
            case .plan:
                #if os(macOS)
                Plan2DView(house: House(room: plan), packageURL: store.packageURL(for: currentRecord))
                    .onDrag { DragExportProvider.provider(subject: ExportSubject(record: currentRecord, plan: plan, packageURL: store.packageURL(for: currentRecord)), format: .pdf) }
                    .help("mac.dragHint")
                #else
                Plan2DView(house: House(room: plan), packageURL: store.packageURL(for: currentRecord))
                #endif
            case .viewer:
                VStack(spacing: 0) {
                    ViewerView(house: House(room: plan), state: viewerState,photoPackageURL:store.packageURL(for:currentRecord))
                    ViewerControls(state: viewerState, usdzURL: RoomPackage.usdzURL(in: store.packageURL(for: currentRecord)),onVoiceNote: { showingVoiceNotes = true })
                }
            case .measures: MeasuresView(plan: plan,onRename: { newName = currentRecord.name; renaming = true })
            case .photos:
                HousePhotosTabView(house: House(room: plan), packageURL: store.packageURL(for: currentRecord))
            }
        }
        #if os(macOS)
        .background {
            Group {
                ScanDetailKeyboardShortcuts(selection:$tab)
                Button("") { viewerState.resetToken += 1 }.keyboardShortcut("0", modifiers: .command)
            }
            .opacity(0)
            .allowsHitTesting(false)
        }
        #endif
    }

    private func load() {
        do { plan = try store.plan(for: currentRecord) } catch { loadError = error.localizedDescription }
    }

    private func rename() {
        do {
            try store.rename(.room(currentRecord), to: newName)
            load()
        } catch {
            actionError = error.localizedDescription
        }
    }
}

/// Structured list of measurements (area, perimeter, height, walls, openings, objects).
struct MeasuresView: View {
    let plan: FloorPlan
    var onRename: (() -> Void)? = nil
    @AppStorage("measurementUnit") private var appUnit: MeasurementUnit = .both
    @Environment(\.projectPreferences) private var projectPreferences
    @Environment(\.locale) private var locale
    private var unit:MeasurementUnit { ProjectPreferenceResolution.unit(projectPreferences,appDefault:appUnit) }
    private var m: RoomMeasurements { RoomMeasurements(plan: plan) }

    var body: some View {
        List {
            Section("measures.summary") {
                if let onRename { Button(action: onRename) { LabeledContent("Room name",value: plan.name) } }
                row("measures.area", MeasurementFormat.squareMeters(m.floorArea,locale:locale))
                row("measures.perimeter", MeasurementFormat.length(m.perimeter, unit:unit,locale:locale))
                row("measures.ceiling", ceilingText)
            }
            Section("measures.walls") {
                ForEach(Array(m.walls.enumerated()), id: \.element.id) { i, w in
                    row(String(localized:"measures.wall \(i + 1)",locale:locale),
                        "\(MeasurementFormat.length(w.length, unit:unit,locale:locale)) × \(MeasurementFormat.length(w.height, unit:unit,locale:locale))", w.confidence)
                }
            }
            if !m.openings.isEmpty {
                Section("measures.openings") {
                    ForEach(m.openings) { o in row(openingName(o.kind), openingText(o), o.confidence) }
                }
            }
            if !m.objects.isEmpty {
                Section("measures.objects") {
                    ForEach(m.objects) { o in
                        row(ObjectNaming.localizedName(o.category),
                            "\(MeasurementFormat.length(o.width, unit:unit,locale:locale)) × \(MeasurementFormat.length(o.depth, unit:unit,locale:locale)) × \(MeasurementFormat.length(o.height, unit:unit,locale:locale))", o.confidence)
                    }
                }
            }
        }
    }

    private var ceilingText: String {
        let r = m.ceilingHeight
        return abs(r.upperBound - r.lowerBound) < 0.02
            ? MeasurementFormat.length(r.lowerBound, unit:unit,locale:locale)
            : "\(MeasurementFormat.length(r.lowerBound, unit:unit,locale:locale)) – \(MeasurementFormat.length(r.upperBound, unit:unit,locale:locale))"
    }

    private func openingName(_ kind: Opening.Kind) -> String {
        switch kind {
        case .door: AppLanguage.text("opening.door")
        case .window: AppLanguage.text("opening.window")
        case .opening: AppLanguage.text("opening.opening")
        }
    }

    private func openingText(_ o: RoomMeasurements.OpeningMeasure) -> String {
        var t = "\(MeasurementFormat.length(o.width, unit:unit,locale:locale)) × \(MeasurementFormat.length(o.height, unit:unit,locale:locale))"
        if o.kind == .window { t += " · " + String(localized:"measures.sill \(MeasurementFormat.length(o.sillHeight, unit:unit,locale:locale))",locale:locale) }
        return t
    }

    private func row(_ title: LocalizedStringKey, _ value: String, _ confidence: Confidence? = nil) -> some View { row(Text(title), value, confidence) }
    private func row(_ title: String, _ value: String, _ confidence: Confidence? = nil) -> some View { row(Text(title), value, confidence) }
    private func row(_ title: Text, _ value: String, _ confidence: Confidence?) -> some View {
        HStack {
            title
            Spacer()
            Text(value).foregroundStyle(.secondary).monospacedDigit()
            if let confidence, confidence != .high {
                Image(systemName: confidence == .medium ? "questionmark.circle" : "exclamationmark.circle")
                    .foregroundStyle(confidence == .medium ? .orange : .red)
                    .accessibilityLabel(Text(confidence == .medium ? "confidence.medium" : "confidence.low"))
            }
        }
    }
}
