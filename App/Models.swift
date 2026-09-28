import AppKit
import Foundation

struct ModelInfo: Decodable, Identifiable {
    let id: String
    let name: String
    let lab: String
    let subtitle: String
    let description: String
    let badge: String?
    let defaultSteps: Int
    let repo: String
    let revision: String
    let sizeBytes: Int64
    let recommendedMemoryGB: Int
    let license: String

    var downloadSize: String {
        ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }
    var sourceURL: URL { URL(string: "https://huggingface.co/\(repo)")! }
    var isNonCommercial: Bool { license.localizedCaseInsensitiveContains("non-commercial") }
}

struct ModelStatus: Decodable {
    let id: String
    let installed: Bool
    let partial: Bool
}

struct GeneratedImage: Codable, Identifiable {
    let id: String
    let modelID: String
    let modelName: String
    let modelRepo: String
    let modelRevision: String
    let runtimeVersion: String
    let prompt: String
    let seed: UInt32
    let width: Int
    let height: Int
    let steps: Int
    let createdAt: String
    let durationSeconds: Double
    let imagePath: String

    var url: URL { URL(fileURLWithPath: imagePath) }
    var dimensions: String { "\(width) × \(height)" }
}

struct WorkerEvent: Decodable {
    let event: String
    let requestID: String?
    let message: String?
    let stage: String?
    let progress: Double?
    let completedBytes: Int64?
    let totalBytes: Int64?
    let models: [ModelStatus]?
    let history: [GeneratedImage]?
    let image: GeneratedImage?
}

enum AspectRatio: String, CaseIterable, Identifiable {
    case square = "Square"
    case landscape = "Landscape"
    case portrait = "Portrait"

    var id: String { rawValue }
    var width: Int { self == .landscape ? 1024 : 768 }
    var height: Int { self == .portrait ? 1024 : 768 }
    var symbol: String {
        switch self {
        case .square: "square"
        case .landscape: "rectangle"
        case .portrait: "rectangle.portrait"
        }
    }
}

enum Operation: Equatable {
    case idle
    case refreshing
    case downloading
    case generating
    case removing
    case unloading
    case cancelling

    var isBusy: Bool { self != .idle }
    var canCancel: Bool { self == .downloading || self == .generating }
}

enum AppFailure: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): text }
    }
}

struct AppPaths {
    let root: URL
    var images: URL { root.appendingPathComponent("Images") }
    var logs: URL { root.appendingPathComponent("Logs") }

    init() {
        if let override = ProcessInfo.processInfo.environment["OPENPIXEL_DATA_DIR"] {
            root = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            root = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
                .appendingPathComponent("OpenPixel", isDirectory: true)
        }
    }
}

