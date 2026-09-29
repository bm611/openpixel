import AppKit
import Foundation
import ImageIO
import Observation
import UniformTypeIdentifiers

@Observable
@MainActor
final class AppStore {
    var catalog: [ModelInfo] = []
    var modelStatuses: [ModelStatus] = []
    var history: [GeneratedImage] = []
    var selection: GeneratedImage?
    var operation: Operation = .idle
    var status = "Ready when you are"
    var stage = ""
    var progress: Double?
    var downloadDetail: String?
    var errorMessage: String?
    var showModels = false
    var showLibrary = false
    var showImageInfo = false
    /// The model a download or removal is acting on, which may differ from the selection.
    var busyModelID: String?
    var prompt: String {
        didSet { UserDefaults.standard.set(prompt, forKey: "prompt") }
    }
    var aspect: AspectRatio {
        didSet { UserDefaults.standard.set(aspect.rawValue, forKey: "aspect") }
    }
    var steps: Int {
        didSet { UserDefaults.standard.set(steps, forKey: "steps") }
    }
    var seedText = ""
    /// Imported PNG copies of images to edit, in the order they were attached.
    var references: [URL] = []
    static let maxReferences = 3
    var presetID: String? {
        didSet { UserDefaults.standard.set(presetID, forKey: "preset") }
    }
    var selectedModelID: String {
        didSet { UserDefaults.standard.set(selectedModelID, forKey: "selectedModel") }
    }
    let memoryGB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
    let paths = AppPaths()
    @ObservationIgnored private var worker: WorkerClient!
    @ObservationIgnored private var activeRequestID: String?
    @ObservationIgnored private var started = false
    @ObservationIgnored private var idleUnload: Task<Void, Never>?
    @ObservationIgnored private var memoryPressure: DispatchSourceMemoryPressure?
    @ObservationIgnored private var underMemoryPressure = false
    @ObservationIgnored private var hasLoadedModel = false
    /// The prompt cleared on Generate, restored if the image never arrives.
    @ObservationIgnored private var submittedPrompt: String?

    var selectedModel: ModelInfo? { catalog.first { $0.id == selectedModelID } }
    var preset: StylePreset? { StylePreset.all.first { $0.id == presetID } }
    var isInstalled: Bool { modelStatuses.first { $0.id == selectedModelID }?.installed == true }
    var installedModels: [ModelInfo] { catalog.filter(isInstalled) }
    var canEditImages: Bool { selectedModel?.supportsEditing == true }
    /// A style plus an attached image is a complete request: restyle it, no prompt needed.
    var isRestyle: Bool {
        preset != nil && !references.isEmpty && prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canGenerate: Bool {
        !operation.isBusy && isInstalled
            && (!prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRestyle)
            && (references.isEmpty || canEditImages)
    }

    init() {
        let defaults = UserDefaults.standard
        prompt = defaults.string(forKey: "prompt") ?? ""
        aspect = AspectRatio(rawValue: defaults.string(forKey: "aspect") ?? "") ?? .square
        let storedSteps = defaults.integer(forKey: "steps")
        steps = (1...8).contains(storedSteps) ? storedSteps : 4
        selectedModelID = defaults.string(forKey: "selectedModel") ?? "flux2-klein-4b"
        presetID = defaults.string(forKey: "preset")
        worker = WorkerClient(paths: paths)
        worker.onEvent = { [weak self] event in self?.receive(event) }
        worker.onExit = { [weak self] error in
            guard let self else { return }
            let wasCancelling = self.operation == .cancelling
            self.operation = .idle
            self.progress = nil
            self.activeRequestID = nil
            self.busyModelID = nil
            self.hasLoadedModel = false
            self.idleUnload?.cancel()
            self.status = wasCancelling ? "Cancelled. Your completed images are safe." : "Worker stopped"
            if let error { self.errorMessage = error }
            self.restoreSubmittedPrompt()
            if wasCancelling { self.refresh() }
        }
    }

    func start() {
        guard !started else { return }
        started = true
        let pressure = DispatchSource.makeMemoryPressureSource(
            eventMask: [.normal, .warning, .critical], queue: .main
        )
        pressure.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pressure = self.memoryPressure else { return }
                self.underMemoryPressure = pressure.data.contains(.warning) || pressure.data.contains(.critical)
                if self.underMemoryPressure, self.hasLoadedModel, !self.operation.isBusy {
                    self.send(action: "unload", operation: .unloading)
                }
            }
        }
        memoryPressure = pressure
        pressure.resume()
        // Imported references are only needed while attached.
        try? FileManager.default.removeItem(at: paths.inputs)
        do {
            guard let url = Bundle.main.resourceURL?.appendingPathComponent("Worker/catalog.json") else {
                throw AppFailure.message("The model catalog is missing.")
            }
            catalog = try JSONDecoder().decode([ModelInfo].self, from: Data(contentsOf: url))
            if selectedModel == nil { selectedModelID = catalog.first?.id ?? "" }
            refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func refresh() {
        guard !operation.isBusy else { return }
        send(action: "status", operation: .refreshing)
    }

    func isInstalled(_ model: ModelInfo) -> Bool {
        modelStatuses.first { $0.id == model.id }?.installed == true
    }

    func hasPartialDownload(_ model: ModelInfo) -> Bool {
        modelStatuses.first { $0.id == model.id }?.partial == true && !isInstalled(model)
    }

    func select(_ model: ModelInfo) {
        guard !operation.isBusy else { return }
        selectedModelID = model.id
        steps = model.defaultSteps
    }

    func download(_ model: ModelInfo) {
        send(action: "download", operation: .downloading, modelID: model.id)
    }

    func removeModel(_ model: ModelInfo) {
        send(action: "remove", operation: .removing, modelID: model.id)
    }

    func generate() {
        guard canGenerate else { return }
        if prompt.count > 4000 {
            errorMessage = "Keep your prompt under 4,000 characters."
            return
        }
        // The style is appended so the saved prompt reproduces the image on its own.
        var fullPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if let preset, isRestyle {
            let subject = references.count == 1 ? "this image" : "these images"
            fullPrompt = "Restyle \(subject) as \(preset.style). "
                + "Keep the same subject, composition, and pose."
        } else if let preset {
            fullPrompt += fullPrompt.hasSuffix(".") || fullPrompt.hasSuffix(",") ? " " : ", "
            fullPrompt += preset.style
        }
        var values: [String: Any] = [
            "prompt": String(fullPrompt.prefix(4000)), "width": aspect.width, "height": aspect.height,
            "steps": steps
        ]
        let seed = seedText.trimmingCharacters(in: .whitespaces)
        if !seed.isEmpty {
            guard let number = UInt32(seed) else {
                errorMessage = "Enter a seed from 0 to 4,294,967,295, or leave it empty for a random image."
                return
            }
            values["seed"] = number
        }
        if !references.isEmpty { values["images"] = references.map(\.path) }
        let typed = prompt
        send(action: "generate", operation: .generating, values: values)
        if operation == .generating {
            submittedPrompt = typed
            prompt = ""
        }
    }

    func cancel() {
        guard operation.canCancel else { return }
        operation = .cancelling
        activeRequestID = nil
        status = "Cancelling…"
        worker.cancel()
    }

    func shutdown() {
        idleUnload?.cancel()
        memoryPressure?.cancel()
        memoryPressure = nil
        worker.shutdown()
    }

    func newImage() {
        selection = nil
        prompt = ""
        seedText = ""
        references.forEach(removeReference)
    }

    func reuse(_ image: GeneratedImage) {
        // The saved prompt already contains any style text.
        presetID = nil
        prompt = image.prompt
        selectedModelID = image.modelID
        seedText = String(image.seed)
        steps = image.steps
        aspect = AspectRatio.allCases.first { $0.width == image.width && $0.height == image.height } ?? .square
    }

    func saveImage() {
        guard let selection else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png]
        panel.nameFieldStringValue = "OpenPixel-\(selection.seed).png"
        panel.canCreateDirectories = true
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                if url.standardizedFileURL == selection.url.standardizedFileURL { return }
                try Data(contentsOf: selection.url).write(to: url, options: .atomic)
            } catch { self.errorMessage = error.localizedDescription }
        }
    }

    func revealImage() {
        guard let selection else { return }
        NSWorkspace.shared.activateFileViewerSelecting([selection.url])
    }

    // MARK: Reference images

    func chooseReferences() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        panel.message = "Choose up to \(Self.maxReferences) images to edit or combine."
        panel.prompt = "Attach"
        panel.begin { response in
            guard response == .OK else { return }
            self.attach(panel.urls)
        }
    }

    /// Imports images as bounded PNGs; the first one also sets the output shape.
    func attach(_ urls: [URL]) {
        guard !operation.isBusy else { return }
        let room = Self.maxReferences - references.count
        guard room > 0 else {
            errorMessage = "You can attach up to \(Self.maxReferences) images."
            return
        }
        if urls.count > room {
            errorMessage = "Only the first \(room) image\(room == 1 ? "" : "s") were attached. The limit is \(Self.maxReferences)."
        }
        for url in urls.prefix(room) {
            do {
                let (imported, size) = try importReference(url)
                if references.isEmpty {
                    aspect = AspectRatio.closest(width: size.width, height: size.height)
                }
                references.append(imported)
            } catch { errorMessage = error.localizedDescription }
        }
    }

    /// Starts an edit from a generated image, keeping it on screen for comparison.
    func edit(_ image: GeneratedImage) {
        guard !operation.isBusy else { return }
        references.forEach(removeReference)
        attach([image.url])
        prompt = ""
    }

    func removeReference(_ url: URL) {
        references.removeAll { $0 == url }
        try? FileManager.default.removeItem(at: url)
    }

    private func importReference(_ url: URL) throws -> (URL, (width: Int, height: Int)) {
        // Large inputs cost memory in the VAE; 1024 px keeps edits within the model's range.
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            throw AppFailure.message("OpenPixel couldn't read \(url.lastPathComponent). Try a PNG, JPEG, or HEIC image.")
        }
        try FileManager.default.createDirectory(at: paths.inputs, withIntermediateDirectories: true)
        let destinationURL = paths.inputs.appendingPathComponent("\(UUID().uuidString).png")
        guard let destination = CGImageDestinationCreateWithURL(
            destinationURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw AppFailure.message("OpenPixel couldn't prepare \(url.lastPathComponent) for editing.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AppFailure.message("OpenPixel couldn't prepare \(url.lastPathComponent) for editing.")
        }
        return (destinationURL, (image.width, image.height))
    }

    func openLibrary() { NSWorkspace.shared.open(paths.images) }
    func openLogs() { NSWorkspace.shared.open(paths.logs) }

    private func send(action: String, operation: Operation, values: [String: Any] = [:],
                      modelID: String? = nil) {
        guard !self.operation.isBusy else { return }
        idleUnload?.cancel()
        errorMessage = nil
        progress = nil
        downloadDetail = nil
        stage = ""
        self.operation = operation
        status = switch operation {
        case .downloading: "Preparing download…"
        case .generating: "Starting generation…"
        case .removing: "Removing model…"
        case .unloading: "Releasing model memory…"
        default: "Opening library…"
        }
        let requestID = UUID().uuidString
        activeRequestID = requestID
        busyModelID = modelID ?? selectedModelID
        var request = values
        request["action"] = action
        request["modelID"] = busyModelID
        request["requestID"] = requestID
        do { try worker.send(request) }
        catch {
            self.operation = .idle
            activeRequestID = nil
            busyModelID = nil
            errorMessage = error.localizedDescription
            status = "Couldn't start the worker"
        }
    }

    private func receive(_ event: WorkerEvent) {
        guard event.requestID == activeRequestID else { return }
        switch event.event {
        case "status":
            modelStatuses = event.models ?? []
            history = event.history ?? []
            if selection == nil { selection = history.first }
        case "progress":
            status = event.message ?? "Working…"
            stage = event.stage ?? ""
            progress = event.progress.map { min(max($0, 0), 1) }
            if let completed = event.completedBytes, let total = event.totalBytes {
                downloadDetail = "\(ByteCountFormatter.string(fromByteCount: completed, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
            }
        case "result":
            if let image = event.image {
                history.insert(image, at: 0)
                selection = image
                submittedPrompt = nil
            }
        case "done":
            let finishedOperation = operation
            let finishedModel = catalog.first { $0.id == busyModelID }
            operation = .idle
            progress = nil
            activeRequestID = nil
            busyModelID = nil
            status = event.message ?? "Ready"
            if finishedOperation == .generating { hasLoadedModel = true }
            if finishedOperation == .unloading || finishedOperation == .removing {
                hasLoadedModel = false
            }
            // A first download becomes the active model so Generate is ready.
            if finishedOperation == .downloading, !isInstalled, let finishedModel {
                select(finishedModel)
            }
            if hasLoadedModel {
                if underMemoryPressure {
                    send(action: "unload", operation: .unloading)
                } else {
                    scheduleUnload()
                }
            }
        case "error":
            hasLoadedModel = false
            operation = .idle
            progress = nil
            activeRequestID = nil
            busyModelID = nil
            errorMessage = event.message ?? "Something went wrong. Please try again."
            status = "Ready to try again"
            restoreSubmittedPrompt()
        default: break
        }
    }

    /// Puts a failed or cancelled prompt back, unless the user already typed a new one.
    private func restoreSubmittedPrompt() {
        if let submittedPrompt, prompt.isEmpty { prompt = submittedPrompt }
        submittedPrompt = nil
    }

    private func scheduleUnload() {
        idleUnload?.cancel()
        idleUnload = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(300)) }
            catch { return }
            guard let self, !self.operation.isBusy else { return }
            self.send(action: "unload", operation: .unloading)
        }
    }
}
