import SwiftUI
import ImageIO

struct TechnicalMEPReviewView: View {
    @Binding var package: TechnicalRoomPackage
    let persist: (TechnicalRoomPackage) async throws -> TechnicalRoomPackage
    @AppStorage("technical.googleAI.serviceURL") private var endpoint = ""
    @AppStorage("technical.googleAI.enabled") private var aiEnabled = false
    @State private var account = TechnicalGoogleAIAccount.shared
    @State private var selection: Set<UUID> = []
    @State private var selectedObject: UUID?
    @State private var editing: TechnicalMEPSuggestion?
    @State private var localKind = TechnicalMEPKind.pipe
    @State private var job: Task<Void,Never>?
    @State private var busy = false
    @State private var jobUsesGoogle = false
    @State private var message = ""
    @State private var error: String?
    @State private var confirmSending = false

    var body: some View {
        Form {
            Section {
                Text("Detect visible geometry, review each result, then keep the objects you need. Sizes are estimates; DN, contents and hidden connections remain unknown.")
                    .font(.caption).foregroundStyle(.secondary)
                if busy { ProgressView(message); Button("Cancel") { job?.cancel() } }
                else if !message.isEmpty { Text(message).font(.caption) }
            }
            Section("Offline detection") {
                Picker("Look for",selection: $localKind) {
                    Text("Pipes / cylinders").tag(TechnicalMEPKind.pipe)
                    Text("Round ducts").tag(TechnicalMEPKind.roundDuct)
                }
                Text("Works offline. Finds cylinder-shaped candidates; it cannot determine their function.").font(.caption).foregroundStyle(.secondary)
                Button("Find candidates in saved mesh") { detectLocal() }
                    .disabled(busy || TechnicalSavedMeshGeometry.latest(in: package.journal.meshes) == nil)
            }
            Section("Google AI mode") {
                Toggle("Google AI mode",isOn: $aiEnabled)
                if aiEnabled {
                TechnicalGoogleAIStatus()
                Text("Select up to five viewpoints for Gemini recognition. Nothing is sent automatically. If free quota is unavailable, local detection still works.")
                    .font(.caption).foregroundStyle(.secondary)
                if package.evidence.keyframes.isEmpty {
                    Text("This survey has no calibrated camera images. Make a new scan for AI image recognition; local mesh detection can still be used.")
                        .font(.callout)
                } else {
                    DisclosureGroup("Choose images (\(selection.count) selected, maximum 5)") {
                        ForEach(package.evidence.keyframes) { frame in
                            Toggle(isOn: Binding(get: { selection.contains(frame.id) },set: { on in
                                if on && selection.count < 5 { selection.insert(frame.id) } else { selection.remove(frame.id) }
                            })) {
                                HStack {
                                    TechnicalEvidenceThumbnail(frame: frame).frame(width: 85,height: 64).clipped()
                                    Text("Depth confidence coverage \(Int(frame.confidentDepthFraction*100))%")
                                        .font(.caption)
                                }
                            }.disabled(!selection.contains(frame.id) && selection.count >= 5)
                        }
                    }
                    Button("Send selected images and analyse…") { confirmSending = true }
                        .disabled(busy || !aiEnabled || !account.signedIn || selection.isEmpty || endpoint.isEmpty)
                }
                } else {
                    Text("Off. Scanning, photos and offline detection work without Google sign-in.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if !package.recognition.suggestions.isEmpty {
                Section("Review candidates") {
                    TechnicalSavedScanView(package: package,selectedSuggestion: selectedObject)
                        .frame(height: 280).listRowInsets(EdgeInsets())
                    ForEach(package.recognition.suggestions) { item in
                        VStack(alignment: .leading,spacing: 8) {
                            Button { selectedObject = item.id } label: {
                                Label("\(item.kind.title) · \(item.status.rawValue)",systemImage: selectedObject == item.id ? "scope" : "cube")
                            }
                            Text("Length \(item.length,specifier: "%.3f") m · section \(item.width,specifier: "%.3f") × \(item.height,specifier: "%.3f") m")
                                .font(.caption)
                            Text("\(item.supportCount) supporting points · original fit residual \(item.residualMetres*1000,specifier: "%.1f") mm. Accuracy unverified.")
                                .font(.caption2).foregroundStyle(.secondary)
                            if let score = item.modelScore { Text("Model score \(score,specifier: "%.2f") — not measurement accuracy").font(.caption2) }
                            HStack {
                                Button("Edit") { editing = item }
                                Button("Accept") { update(item.id,status: .accepted) }.disabled(item.status == .accepted)
                                Button("Reject") { update(item.id,status: .rejected) }.disabled(item.status == .rejected)
                            }.buttonStyle(.bordered).disabled(busy)
                        }.padding(.vertical,4)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if selection.isEmpty,let first = package.evidence.keyframes.first { selection = [first.id] }
            if endpoint.isEmpty { endpoint = Bundle.main.object(forInfoDictionaryKey: "TechnicalGoogleAIServiceURL") as? String ?? "" }
        }
        .onDisappear { job?.cancel() }
        .onChange(of: aiEnabled) { _, enabled in
            if !enabled { confirmSending = false; if jobUsesGoogle { job?.cancel() } }
        }
        .onChange(of: account.signedIn) { _, signedIn in if !signedIn && jobUsesGoogle { job?.cancel() } }
        .sheet(item: $editing) { item in
            TechnicalMEPEditor(item: item) { edited in saveEdit(edited) }
        }
        .confirmationDialog("Send \(selection.count) camera images?",isPresented: $confirmSending,titleVisibility: .visible) {
            Button("Send and analyse") { detectAI() }
        } message: { Text("Images will be sent to \(endpoint). Its configured AI provider may also process them. Depth stays on this device; returned image regions are fitted to local depth. API quota may be consumed.") }
        .alert("MEP recognition",isPresented: Binding(get: { error != nil },set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func detectLocal() {
        guard let snapshot = TechnicalSavedMeshGeometry.latest(in: package.journal.meshes) else { return }
        let kind = localKind
        run(message: "Analysing saved geometry…") {
            let worker = Task.detached(priority: .userInitiated) {
                let mesh = try TechnicalSavedMeshGeometry(snapshot: snapshot,reference: nil)
                return try TechnicalMEPFitter.detect(TechnicalMEPFitter.samples(mesh: mesh),kind: kind)
            }
            return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        }
    }
    private func detectAI() {
        guard aiEnabled,account.signedIn else { error = "Enable Google AI mode and sign in before sending images."; return }
        guard let url = URL(string: endpoint),url.scheme == "https" else { error = TechnicalMEPClient.Failure.configuration.localizedDescription; return }
        let frames = package.evidence.keyframes.filter { selection.contains($0.id) }
        run(message: "Recognising selected images…",usingGoogle: true) {
            let accessToken = try await account.idToken()
            let worker = Task.detached(priority: .userInitiated) {
                var results: [TechnicalMEPSuggestion] = []
                for frame in frames {
                    try Task.checkCancellation()
                    results += try await TechnicalMEPClient.analyse(frame: frame,endpoint: url,token: accessToken)
                }
                return results
            }
            return try await withTaskCancellationHandler(operation: { try await worker.value },onCancel: { worker.cancel() })
        }
    }
    private func run(message: String,usingGoogle: Bool = false,operation: @escaping () async throws -> [TechnicalMEPSuggestion]) {
        guard !busy else { return }; busy = true; jobUsesGoogle = usingGoogle; self.message = message
        job = Task { @MainActor in
            defer { busy = false; job = nil; jobUsesGoogle = false }
            do {
                let results = try await operation()
                try Task.checkCancellation()
                var value = package
                let old = value.recognition.suggestions.count
                value.recognition.merge(results)
                try value.recognition.validate()
                package = try await persist(value)
                selectedObject = results.first?.id
                let added = value.recognition.suggestions.count-old
                self.message = results.isEmpty ? "No supported 3D candidates found. Try more viewpoints or manual annotation." : "Added \(added) \(added == 1 ? "candidate" : "candidates") for review."
            } catch is CancellationError { self.message = "Analysis cancelled; existing results kept." }
            catch { self.error = error.localizedDescription; self.message = "Analysis did not finish; existing results kept." }
        }
    }
    private func update(_ id: UUID,status: TechnicalMEPSuggestion.Status) {
        guard let item = package.recognition.suggestions.first(where: { $0.id == id }) else { return }
        var copy = item; copy.status = status; saveEdit(copy)
    }
    private func saveEdit(_ item: TechnicalMEPSuggestion) {
        guard !busy else { return }; busy = true
        job = Task { @MainActor in
            defer { busy = false; job = nil }
            do {
                var value = package
                guard let i = value.recognition.suggestions.firstIndex(where: { $0.id == item.id }) else { return }
                try item.validate(); value.recognition.suggestions[i] = item
                package = try await persist(value)
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct TechnicalEvidenceThumbnail: View {
    let frame: TechnicalCaptureKeyframe
    @State private var image: CGImage?
    var body: some View {
        Group { if let image { Image(decorative: image,scale: 1).resizable().scaledToFit() } else { ProgressView() } }
            .task(id: frame.id) {
                if let source = CGImageSourceCreateWithData(frame.jpegData as CFData,nil) {
                    image = CGImageSourceCreateThumbnailAtIndex(source,0,[kCGImageSourceCreateThumbnailFromImageAlways: true,kCGImageSourceThumbnailMaxPixelSize: 200] as CFDictionary)
                }
            }
    }
}

private struct TechnicalMEPEditor: View {
    @State var item: TechnicalMEPSuggestion
    let onSave: (TechnicalMEPSuggestion) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var error: String?
    var body: some View {
        NavigationStack {
            Form {
                Text("Visible outer dimensions only. Insulation may hide the actual pipe. Material settings change rendering, not the measured evidence.").font(.caption)
                Picker("Type",selection: $item.kind) { ForEach(TechnicalMEPKind.allCases,id: \.self) { Text($0.title).tag($0) } }
                TextField("Width / outer diameter (m)",value: $item.width,format: .number)
                if item.kind == .rectangularDuct { TextField("Section height (m)",value: $item.height,format: .number) }
                Picker("Material appearance",selection: $item.material) { ForEach(TechnicalMEPMaterial.allCases,id: \.self) { Text($0.rawValue).tag($0) } }
                DisclosureGroup("Edit endpoints (original scan coordinates, m)") {
                    TextField("Start X",value: $item.start.x,format: .number)
                    TextField("Start Y",value: $item.start.y,format: .number)
                    TextField("Start Z",value: $item.start.z,format: .number)
                    TextField("End X",value: $item.end.x,format: .number)
                    TextField("End Y",value: $item.end.y,format: .number)
                    TextField("End Z",value: $item.end.z,format: .number)
                }
                if let error { Text(error).foregroundStyle(.red) }
            }
            .navigationTitle("Review MEP element")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    do {
                        if item.kind != .rectangularDuct { item.height = item.width }
                        let axis = MEPVector.unit(MEPVector.sub(item.end,item.start))
                        let base = abs(axis.y) < 0.9 ? TechnicalPoint3(x: 0,y: 1,z: 0) : .init(x: 1,y: 0,z: 0)
                        item.crossAxis = MEPVector.unit(MEPVector.cross(axis,base))
                        item.geometrySource = .entered
                        try item.validate(); onSave(item); dismiss()
                    } catch { self.error = error.localizedDescription }
                } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 400,minHeight: 400)
        #endif
    }
}
