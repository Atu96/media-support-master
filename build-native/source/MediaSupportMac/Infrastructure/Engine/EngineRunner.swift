import Darwin
import Foundation

/// Cảnh báo chung được sinh từ dòng lỗi trong Nhật ký. Nội dung kỹ thuật đầy đủ
/// vẫn nằm tại log; bảng giữa màn hình giúp người dùng không phải tự đi tìm lỗi.
struct EngineLogErrorAlert: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class EngineRunner: ObservableObject {
    @Published private(set) var logLines: [String] = []
    @Published private(set) var isRunning = false
    @Published private(set) var lastExitCode: Int32?
    @Published private(set) var currentJobTitle: String?
    @Published private(set) var lastCloudAlert: CloudAIErrorAlert?
    @Published private(set) var lastLogErrorAlert: EngineLogErrorAlert?

    private(set) var activeProcessPID: Int32?
    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?

    /// Gọi mỗi dòng log (Whisper progress, v.v.) — đã batch, không flood MainActor từng chunk pipe.
    var onLogLine: (@MainActor (String) -> Void)?

    /// Buffer pipe ngoài MainActor (handler pipe không isolated).
    private let pipeBuffer = PipeTextBuffer()
    /// true khi vòng flush đang chạy trên MainActor.
    private var isPipeFlushing = false
    /// Data vào lúc đang flush — bắt buộc chạy thêm 1 vòng (tránh pipe đầy → process treo).
    private var pipeFlushPending = false

    func clearLog() {
        logLines = []
        lastExitCode = nil
        lastCloudAlert = nil
        lastLogErrorAlert = nil
    }

    func dismissLastLogErrorAlert() {
        lastLogErrorAlert = nil
    }

    func appendLog(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .newlines)
        guard !trimmed.isEmpty else { return }
        appendLogLines([trimmed])
    }

    private func appendLogLines(_ lines: [String]) {
        guard !lines.isEmpty else { return }
        // MSM_PROGRESS: chỉ callback % — không nhét Nhật ký (tránh flood UI / đơ cuối job).
        var progressOnly: [String] = []
        var visible: [String] = []
        visible.reserveCapacity(lines.count)
        for line in lines {
            if line.hasPrefix("MSM_PROGRESS:") {
                progressOnly.append(line)
            } else {
                visible.append(line)
            }
        }
        if !visible.isEmpty {
            logLines.append(contentsOf: visible)
            if logLines.count > 500 {
                logLines = Array(logLines.suffix(500))
            }
            presentLogErrorIfNeeded(in: visible)
        }
        if let onLogLine {
            for line in progressOnly {
                onLogLine(line)
            }
            for line in visible {
                onLogLine(line)
            }
        }
    }

    private func presentLogErrorIfNeeded(in lines: [String]) {
        // Cloud errors đã có hướng dẫn xử lý riêng trong `CloudAIErrorAlert`.
        guard lastCloudAlert == nil, lastLogErrorAlert == nil,
              let failure = lines.first(where: isUserFacingFailure) else { return }
        let message = failure
            .replacingOccurrences(of: "✗", with: "")
            .replacingOccurrences(of: "❌", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        lastLogErrorAlert = EngineLogErrorAlert(message: message)
    }

    private func isUserFacingFailure(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasPrefix("✗")
            || trimmed.hasPrefix("❌")
            || trimmed.localizedCaseInsensitiveContains("lỗi:")
    }

    func run(_ job: EngineJob) async {
        guard !isRunning else {
            appendLog("⚠️ Đang chạy job khác — chờ xong.")
            return
        }

        isRunning = true
        currentJobTitle = job.title
        lastExitCode = nil
        lastCloudAlert = nil
        lastLogErrorAlert = nil
        appendLog("▶ \(job.title)")
        clearPipeBuffer()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: job.executable)
        process.arguments = job.arguments
        process.currentDirectoryURL = job.workingDirectory

        var env = ProcessInfo.processInfo.environment
        for (key, value) in job.environment {
            env[key] = value
        }
        if let ffmpeg = AppPaths.resolveFFmpeg() {
            env["FFMPEG"] = ffmpeg
            let dir = URL(fileURLWithPath: ffmpeg).deletingLastPathComponent().path
            env["PATH"] = "\(dir):/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        } else {
            env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (env["PATH"] ?? "")
        }
        if let bundleResources = Bundle.main.resourceURL?.path {
            env["MSM_APP_RESOURCES"] = bundleResources
        }
        env["APP_ROOT"] = AppPaths.appRoot.path
        env["TOOLS_ROOT"] = AppPaths.toolsRoot.path
        env["WHISPER_HOME"] = AppPaths.whisperHome.path
        env["PYTHONUNBUFFERED"] = "1"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        self.process = process
        self.stdoutPipe = stdout
        self.stderrPipe = stderr

        let buffer = pipeBuffer
        // Đọc pipe càng sớm càng tốt — không drop flush (tránh pipe 64KB đầy → child block mãi).
        stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // data rỗng = EOF; vẫn schedule drain.
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                buffer.append(text)
            } else if !data.isEmpty, let text = String(data: data, encoding: .isoLatin1) {
                buffer.append(text)
            }
            Task { @MainActor [weak self] in
                self?.schedulePipeFlush()
            }
        }

        stderr.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let text = String(data: data, encoding: .utf8) {
                buffer.append(text)
            } else if !data.isEmpty, let text = String(data: data, encoding: .isoLatin1) {
                buffer.append(text)
            }
            Task { @MainActor [weak self] in
                self?.schedulePipeFlush()
            }
        }

        do {
            // Chờ process thoát qua terminationHandler — nhả MainActor trong lúc job chạy.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                var resumed = false
                let resumeOnce: (Result<Void, Error>) -> Void = { result in
                    guard !resumed else { return }
                    resumed = true
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }
                process.terminationHandler = { _ in
                    resumeOnce(.success(()))
                }
                do {
                    try process.run()
                    self.activeProcessPID = process.processIdentifier
                    SystemResourceMonitor.shared.setEnginePID(process.processIdentifier)
                } catch {
                    process.terminationHandler = nil
                    resumeOnce(.failure(error))
                }
            }
            lastExitCode = process.terminationStatus
        } catch {
            lastCloudAlert = CloudAIErrorClassifier.alert(for: error)
            appendLog("✗ Lỗi: \(error.localizedDescription)")
            lastExitCode = -1
        }

        stdout.fileHandleForReading.readabilityHandler = nil
        stderr.fileHandleForReading.readabilityHandler = nil

        // Nạp nốt data còn trong pipe (đọc lặp tới hết), rồi flush UI.
        for _ in 0..<32 {
            let residualStdout = Self.readAvailableText(from: stdout)
            let residualStderr = Self.readAvailableText(from: stderr)
            if residualStdout.isEmpty && residualStderr.isEmpty { break }
            if !residualStdout.isEmpty { pipeBuffer.append(residualStdout) }
            if !residualStderr.isEmpty { pipeBuffer.append(residualStderr) }
        }
        await drainPipeBufferToCompletion()

        if let code = lastExitCode, code != -1 {
            appendLog(code == 0 ? "✓ Hoàn tất" : "✗ Thoát mã \(code)")
        }

        isRunning = false
        currentJobTitle = nil
        activeProcessPID = nil
        SystemResourceMonitor.shared.setEnginePID(nil)
        self.process = nil
        self.stdoutPipe = nil
        self.stderrPipe = nil
    }

    // MARK: - Pipe batching

    private func clearPipeBuffer() {
        _ = pipeBuffer.takeAll()
        isPipeFlushing = false
        pipeFlushPending = false
    }

    /// Gọi từ readabilityHandler — không được drop khi đang flush.
    private func schedulePipeFlush() {
        if isPipeFlushing {
            pipeFlushPending = true
            return
        }
        isPipeFlushing = true
        Task { @MainActor [weak self] in
            await self?.runPipeFlushLoop()
        }
    }

    /// Xả buffer → log/% ; lặp nếu có data mới trong lúc emit.
    private func runPipeFlushLoop() async {
        // Không sleep dài ở đây — pipe 64KB đầy sẽ làm whisper block.
        repeat {
            pipeFlushPending = false
            while true {
                let chunk = pipeBuffer.takeAll()
                if chunk.isEmpty { break }
                await emitPipeChunk(chunk)
            }
        } while pipeFlushPending || pipeBuffer.hasData

        isPipeFlushing = false
        // Race: data vào sau hasData check, trước clear isPipeFlushing
        if pipeFlushPending || pipeBuffer.hasData {
            schedulePipeFlush()
        }
    }

    private func ensurePipeFlushLoop() async {
        // API cũ — map sang schedule + chờ một nhịp drain.
        schedulePipeFlush()
        // Cho vòng Task flush chạy
        for _ in 0..<20 {
            if !isPipeFlushing && !pipeFlushPending && !pipeBuffer.hasData { break }
            try? await Task.sleep(nanoseconds: 5_000_000)
            if !isPipeFlushing && pipeBuffer.hasData {
                schedulePipeFlush()
            }
        }
        // Drain sync phần còn
        while pipeBuffer.hasData {
            let chunk = pipeBuffer.takeAll()
            if chunk.isEmpty { break }
            await emitPipeChunk(chunk)
        }
    }

    private func emitPipeChunk(_ chunk: String) async {
        // Hỗ trợ cả \\r (whisper progress) lẫn \\n.
        let normalized = chunk
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return }

        // Ưu tiên MSM_PROGRESS — UI % mượt; bỏ bớt spam log whisper.
        let progressLines = lines.filter { $0.hasPrefix("MSM_PROGRESS:") }
        let otherLines = lines.filter { line in
            if line.hasPrefix("MSM_PROGRESS:") { return false }
            // Whisper hay dump token/debug — không nhét hết vào UI log (đơ MainActor).
            if line.hasPrefix("whisper_") { return false }
            if line.contains("ggml_") { return false }
            if line.hasPrefix("system_info:") { return false }
            return true
        }

        if !progressLines.isEmpty {
            // Emit TỪNG mốc % tăng dần trong batch (không chỉ max) — % chạy thật.
            var lastEmitted = -1
            let sorted = progressLines.compactMap { line -> (Int, String)? in
                let raw = line.dropFirst("MSM_PROGRESS:".count).trimmingCharacters(in: .whitespaces)
                guard let v = Int(raw) else { return nil }
                return (v, line)
            }.sorted { $0.0 < $1.0 }
            for (v, line) in sorted where v > lastEmitted {
                appendLogLines([line])
                lastEmitted = v
            }
        }

        // Log thường: batch nhỏ + yield để không block pipe drain.
        let batchSize = 48
        var index = 0
        while index < otherLines.count {
            let end = min(index + batchSize, otherLines.count)
            appendLogLines(Array(otherLines[index..<end]))
            index = end
            if index < otherLines.count {
                await Task.yield()
            }
        }
    }

    /// Sau khi process thoát — chờ vòng flush xong + xả nốt buffer.
    private func drainPipeBufferToCompletion() async {
        await ensurePipeFlushLoop()
        let leftover = pipeBuffer.takeAll()
        if !leftover.isEmpty {
            await emitPipeChunk(leftover)
        }
    }

    private static func readAvailableText(from pipe: Pipe) -> String {
        let data = pipe.fileHandleForReading.availableData
        guard !data.isEmpty else { return "" }
        if let text = String(data: data, encoding: .utf8) { return text }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    func runTask(title: String, operation: @escaping () async throws -> Void) async {
        guard !isRunning else {
            appendLog("⚠️ Đang chạy job khác — chờ xong.")
            return
        }

        isRunning = true
        currentJobTitle = title
        lastExitCode = nil
        lastCloudAlert = nil
        lastLogErrorAlert = nil
        appendLog("▶ \(title)")

        do {
            try await operation()
            lastExitCode = 0
            appendLog("✓ Hoàn tất")
        } catch {
            lastCloudAlert = CloudAIErrorClassifier.alert(for: error)
            appendLog("✗ Lỗi: \(error.localizedDescription)")
            lastExitCode = -1
        }

        isRunning = false
        currentJobTitle = nil
    }

    func cancel() {
        process?.terminate()
    }

    /// Thoát app — dừng pipe, kill job engine và mọi process con.
    func shutdownForQuit() {
        clearPipeBuffer()
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe = nil
        stdoutPipe = nil

        if let process {
            if process.isRunning {
                Self.terminateProcessTree(rootPID: process.processIdentifier)
            }
            process.terminate()
        }
        process = nil
        activeProcessPID = nil
        isRunning = false
        currentJobTitle = nil
        SystemResourceMonitor.shared.setEnginePID(nil)
    }

    private static func terminateProcessTree(rootPID: pid_t) {
        var queue = [rootPID]
        var visited = Set<pid_t>()
        while let pid = queue.first {
            queue.removeFirst()
            guard pid > 0, visited.insert(pid).inserted else { continue }
            for child in SystemResourceMonitor.childPIDs(of: pid) {
                queue.append(child)
            }
        }
        for pid in visited.sorted(by: >) {
            kill(pid, SIGTERM)
        }
        usleep(80_000)
        for pid in visited {
            if kill(pid, 0) == 0 {
                kill(pid, SIGKILL)
            }
        }
    }
}

/// Buffer text từ pipe — thread-safe, không dính MainActor.
private final class PipeTextBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = ""

    var hasData: Bool {
        lock.lock()
        defer { lock.unlock() }
        return !storage.isEmpty
    }

    func append(_ text: String) {
        lock.lock()
        storage.append(text)
        lock.unlock()
    }

    func takeAll() -> String {
        lock.lock()
        defer { lock.unlock() }
        let text = storage
        storage = ""
        return text
    }
}
