import AppKit
import Foundation
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

    var selectedModel: ModelInfo? { catalog.first { $0.id == selectedModelID } }
    var preset: StylePreset? { StylePreset.all.first { $0.id == presetID } }
    var isInstalled: Bool { modelStatuses.first { $0.id == selectedModelID }?.installed == true }
    var installedModels: [ModelInfo] { catalog.filter(isInstalled) }
    var canGenerate: Bool {
        !operation.isBusy && isInstalled && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
            self.status = wasCancelling ? "Cancelled. Your completed images are safe." : "Worker stopped"
            if let error { self.errorMessage = error }
            if wasCancelling { self.refresh() }
        }
    }

    func start() {
        guard !started else { return }
        started = true
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
        if let preset {
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
        send(action: "generate", operation: .generating, values: values)
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
        worker.shutdown()
    }

    func newImage() {
        selection = nil
        prompt = ""
        seedText = ""
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
            }
        case "done":
            let finishedOperation = operation
            let finishedModel = catalog.first { $0.id == busyModelID }
            operation = .idle
            progress = nil
            activeRequestID = nil
            busyModelID = nil
            status = event.message ?? "Ready"
            if finishedOperation == .generating { scheduleUnload() }
            // A first download becomes the active model so Generate is ready.
            if finishedOperation == .downloading, !isInstalled, let finishedModel {
                select(finishedModel)
            }
        case "error":
            operation = .idle
            progress = nil
            activeRequestID = nil
            busyModelID = nil
            errorMessage = event.message ?? "Something went wrong. Please try again."
            status = "Ready to try again"
        default: break
        }
    }

    private func scheduleUnload() {
        idleUnload = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(120)) }
            catch { return }
            guard let self, !self.operation.isBusy else { return }
            self.send(action: "unload", operation: .unloading)
        }
    }
}
