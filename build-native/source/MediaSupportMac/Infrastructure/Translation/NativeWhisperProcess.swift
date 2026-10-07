import Darwin
import Foundation

enum NativeWhisperProcess {
    static func run(executable: URL, arguments: [String], timeout: TimeInterval = 7200,
                    progress: @escaping @Sendable (String) -> Void) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) {
            let log = FileManager.default.temporaryDirectory.appendingPathComponent("msm-whisper-\(UUID().uuidString).log")
            FileManager.default.createFile(atPath: log.path, contents: nil)
            let handle = try FileHandle(forWritingTo: log)
            defer { try? handle.close(); try? FileManager.default.removeItem(at: log) }
            let reader = try FileHandle(forReadingFrom: log)
            defer { try? reader.close() }
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            // Transcript output lives in JSON; never forward speech text into logs.
            process.standardOutput = FileHandle.nullDevice
            process.standardError = handle
            process.standardInput = FileHandle.nullDevice
            try Task.checkCancellation()
            try process.run()
            let deadline = Date().addingTimeInterval(timeout)
            defer { stop(process) }
            var pending = ""
            var tail = ""
            func drain() throws {
                let data = try reader.read(upToCount: 65536) ?? Data()
                let text = String(decoding: data, as: UTF8.self)
                tail = String((tail + text).suffix(32768))
                pending += text
                let lines = pending.components(separatedBy: .newlines)
                pending = String((lines.last ?? "").suffix(4096))
                for line in lines.dropLast() {
                    if line.contains("progress ="), let n = line.split(separator:" ").first(where: { $0.hasSuffix("%") }),
                       let pct = Int(n.dropLast()) {
                        progress("MSM_PROGRESS:\(min(90,max(15,15+pct*75/100)))")
                    }
                }
            }
            while process.isRunning {
                try Task.checkCancellation()
                guard Date() < deadline else { throw URLError(.timedOut) }
                try drain()
                try await Task.sleep(for:.milliseconds(150))
            }
            try drain()
            try Task.checkCancellation()
            guard process.terminationStatus == 0 else { throw OfflineWhisperError.engineFailed(String(tail.suffix(1800))) }
            return tail
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
    private static func stop(_ process:Process) {
        guard process.isRunning else { return }
        process.terminate()
        let limit=Date().addingTimeInterval(2)
        while process.isRunning && Date()<limit { Thread.sleep(forTimeInterval:0.05) }
        if process.isRunning { kill(process.processIdentifier,SIGKILL) }
        process.waitUntilExit()
    }
}
