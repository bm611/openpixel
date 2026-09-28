import AppKit
import Darwin
import Foundation

/// Owns a persistent worker. One request runs at a time; cancellation ends it.
@MainActor
final class WorkerClient {
    var onEvent: ((WorkerEvent) -> Void)?
    var onExit: ((String?) -> Void)?
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var log: FileHandle?
    private var reader: Task<Void, Never>?
    private var sessionID = UUID()
    private var cancelling = false
    private let paths: AppPaths

    init(paths: AppPaths) { self.paths = paths }

    func send(_ request: [String: Any]) throws {
        if process?.isRunning != true { try start() }
        var data = try JSONSerialization.data(withJSONObject: request)
        data.append(0x0A)
        guard let input else { throw AppFailure.message("The image worker is unavailable.") }
        try input.write(contentsOf: data)
    }

    private func start() throws {
        guard let resources = Bundle.main.resourceURL else {
            throw AppFailure.message("OpenPixel's resources are missing. Rebuild the app.")
        }
        let python = resources.appendingPathComponent("Runtime/bin/python3.12")
        let script = resources.appendingPathComponent("Worker/worker.py")
        guard FileManager.default.isExecutableFile(atPath: python.path),
              FileManager.default.fileExists(atPath: script.path) else {
            throw AppFailure.message("The bundled image runtime is missing. Run scripts/build.sh to create the complete app.")
        }
        try FileManager.default.createDirectory(at: paths.logs, withIntermediateDirectories: true)
        let logURL = paths.logs.appendingPathComponent("worker.log")
        // Bound logs between launches; generation metadata stays in the library.
        if let size = try? logURL.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           size > 2_000_000 {
            try Data().write(to: logURL)
        }
        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: nil)
        }
        log = try FileHandle(forWritingTo: logURL)
        try log?.seekToEnd()
        let task = Process()
        let stdin = Pipe()
        let stdout = Pipe()
        task.executableURL = python
        task.arguments = ["-I", "-B", "-u", script.path, "--root", paths.root.path]
        task.currentDirectoryURL = paths.root
        var environment = ProcessInfo.processInfo.environment
        for key in ["PYTHONHOME", "PYTHONPATH", "VIRTUAL_ENV"] {
            environment.removeValue(forKey: key)
        }
        task.environment = environment
        task.standardInput = stdin
        task.standardOutput = stdout
        task.standardError = log
        let currentSession = UUID()
        sessionID = currentSession
        cancelling = false
        // The read loop observes EOF after all output, avoiding exit/result races.
        task.terminationHandler = { _ in }
        try task.run()
        process = task
        input = stdin.fileHandleForWriting
        output = stdout.fileHandleForReading
        let handle = stdout.fileHandleForReading
        reader = Task { [weak self] in
            do {
                for try await line in handle.bytes.lines {
                    guard let self, self.sessionID == currentSession else { return }
                    guard let data = line.data(using: .utf8) else { continue }
                    let event = try JSONDecoder().decode(WorkerEvent.self, from: data)
                    self.onEvent?(event)
                }
                self?.didExit(session: currentSession, error: nil)
            } catch {
                self?.didExit(session: currentSession,
                              error: "The image worker stopped responding. \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        guard let process, process.isRunning else {
            didExit(session: sessionID, error: nil)
            return
        }
        cancelling = true
        process.terminate()
        let currentSession = sessionID
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, self.sessionID == currentSession,
                  let process = self.process, process.isRunning else { return }
            kill(process.processIdentifier, SIGKILL)
        }
    }

    func shutdown() {
        reader?.cancel()
        reader = nil
        sessionID = UUID()
        if let process, process.isRunning {
            // Quit must release GPU allocations even during a blocking GPU call.
            kill(process.processIdentifier, SIGKILL)
        }
        closeHandles()
        process = nil
    }

    private func didExit(session: UUID, error: String?) {
        guard sessionID == session else { return }
        let wasCancelled = cancelling
        if let process, process.isRunning { process.terminate() }
        process = nil
        reader = nil
        closeHandles()
        onExit?(wasCancelled ? nil : (error ?? "The image worker exited. Try again; it will restart automatically."))
    }

    private func closeHandles() {
        try? input?.close()
        try? output?.close()
        try? log?.close()
        input = nil
        output = nil
        log = nil
    }
}
