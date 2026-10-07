import Foundation
import SwiftUI

/// Job + % tab **Khớp văn bản gốc** (align chữ người dùng với timing media).
/// Cùng pattern Whisper: progress thật + inFlight giữ overlay tới khi có cue.
@MainActor
final class SubtitleScriptCreateController {
    private unowned let session: SubtitleCreateSession

    private var progressTicker: Task<Void, Never>?
    private var lastRealPercent = 0
    private var lastRealAt = Date()
    private let engineCap = 95

    init(session: SubtitleCreateSession) {
        self.session = session
    }

    var isRunning: Bool {
        session.engine.isRunning
            && session.runner.currentJobTitle?.contains("Align kịch bản") == true
    }

    func run() {
        guard let draft = session.scriptDraftMediaURL else { return }
        let script = session.scriptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !script.isEmpty else { return }
        let selectedLanguage = session.scriptAlignmentLanguage
        let language = session.effectiveScriptAlignmentLanguage
        let wrapStyle = session.wrapStyle
        let burnStyle = session.burnStyle
        let containerWidth = session.subtitleLayoutContainerWidth

        Task {
            if !session.isActiveProject(draft) {
                session.setMediaURL(draft)
            }
            guard let mediaURL = session.mediaURL else { return }

            session.whisperComplete = false
            session.translateComplete = false
            session.activeTranscriptVariant = .original
            ProjectBackupStore.clearTranslatedTranscript(for: mediaURL)
            session.exportMessage = ""
            session.segments = []
            session.resetEditHistory()
            session.transcriptSummary = ""
            session.isScriptAlignJobInFlight = true
            beginProgressTracking()

            let scriptFile = FileManager.default.temporaryDirectory
                .appendingPathComponent("msm-kichban-\(UUID().uuidString).txt")
            defer { try? FileManager.default.removeItem(at: scriptFile) }

            do {
                try script.write(to: scriptFile, atomically: true, encoding: .utf8)
            } catch {
                session.runner.appendLog("❌ Không ghi được file kịch bản tạm")
                endProgressTracking()
                session.isScriptAlignJobInFlight = false
                return
            }

            let started = Date()
            session.attachPreviewVideo()
            let languageLog = selectedLanguage == .auto
                ? "Tự nhận diện → \(language.label)"
                : language.label
            session.runner.appendLog("▶ Canh kịch bản · \(languageLog)")
            await session.engine.runScriptAlignSRT(
                for: mediaURL,
                scriptFile: scriptFile,
                language: language
            )
            session.refreshEngineStatus()

            setProgressAtLeast(92)
            await Task.yield()

            let coLocatedSRT = ProjectBackupStore.coLocatedSRT(for: mediaURL)
            let exitOK = session.runner.lastExitCode == 0

            let finish = await Task.detached(priority: .userInitiated) {
                SubtitleCreateJobFinisher.ingestAndParse(
                    coLocatedSRT: coLocatedSRT,
                    media: mediaURL,
                    exitOK: exitOK
                )
            }.value

            endProgressTracking()

            if let srt = finish.srtURL {
                session.srtURL = srt
                let laidOut = await Task.detached(priority: .userInitiated) {
                    SubtitleTranscriptPostProcessor.format(
                        finish.segments,
                        sourceLanguage: language.rawValue,
                        style: wrapStyle,
                        fontSize: burnStyle.fontSize,
                        fontName: burnStyle.fontName,
                        containerWidth: containerWidth,
                        maximumSpeechGap: 0.45,
                        coalescesSpeechChunks: false
                    )
                }.value
                if !laidOut.isEmpty {
                    try? SRTDocument.renderSRT(laidOut).write(
                        to: srt,
                        atomically: true,
                        encoding: .utf8
                    )
                }
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    session.segments = laidOut.isEmpty ? finish.segments : laidOut
                    session.whisperComplete = true
                    session.scriptAlignProgressPercent = 100
                    session.isScriptAlignJobInFlight = false
                }
                session.activeTranscriptVariant = .original
                session.sourceLang = language.rawValue
                session.resetEditHistory()
                if finish.warning == "vault" {
                    session.runner.appendLog("⚠️ Không copy SRT vào backup vault")
                }

                let elapsed = Date().timeIntervalSince(started)
                session.completionSummary =
                    "\(session.segments.count) đoạn • \(String(format: "%.1f", elapsed))s • \(language.label)"
                session.runner.appendLog("✓ Align kịch bản hoàn tất — \(session.completionSummary)")
                session.persistProjectSession()
            } else {
                session.scriptAlignProgressPercent = 100
                session.isScriptAlignJobInFlight = false
                if !exitOK {
                    session.runner.appendLog("✗ Align kịch bản thất bại — không có SRT")
                }
            }
            session.syncPreferencesContext()
        }
    }

    func clearLiveState() {
        endProgressTracking()
        session.scriptAlignProgressPercent = 0
        session.isScriptAlignJobInFlight = false
    }

    // MARK: - Progress

    private func beginProgressTracking() {
        lastRealPercent = 0
        lastRealAt = Date()
        session.scriptAlignProgressPercent = 0
        session.runner.onLogLine = { [weak self] line in
            self?.handleLogLine(line)
        }
        startSmoothTicker()
    }

    private func endProgressTracking() {
        progressTicker?.cancel()
        progressTicker = nil
        session.runner.onLogLine = nil
    }

    private func handleLogLine(_ line: String) {
        guard let percent = WhisperProgressParser.percent(from: line) else { return }
        let p = min(engineCap, max(0, percent))
        if p > lastRealPercent {
            lastRealPercent = p
            lastRealAt = Date()
        }
        if p > session.scriptAlignProgressPercent {
            session.scriptAlignProgressPercent = p
        }
    }

    private func setProgressAtLeast(_ percent: Int) {
        let p = min(100, max(0, percent))
        if p > session.scriptAlignProgressPercent {
            session.scriptAlignProgressPercent = p
        }
        if p > lastRealPercent {
            lastRealPercent = p
            lastRealAt = Date()
        }
    }

    /// Nội suy nhẹ khi log đứng (Whisper dài) — không vượt engineCap.
    private func startSmoothTicker() {
        progressTicker?.cancel()
        progressTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.session.isScriptAlignJobInFlight else { return }
                self.tickSmooth()
            }
        }
    }

    private func tickSmooth() {
        guard session.engine.isRunning || isRunning else { return }
        let stalled = Date().timeIntervalSince(lastRealAt)
        guard stalled >= 0.5 else { return }
        let floor = lastRealPercent
        let softCap: Int
        if floor < 12 {
            softCap = 12
        } else if floor < 72 {
            softCap = 72
        } else {
            softCap = engineCap
        }
        guard floor < softCap else { return }
        let mediaDur = max(0, session.preview.duration)
        let budget: TimeInterval = mediaDur > 2 ? min(90, max(12, mediaDur * 0.4 + 5)) : 20
        let fill = min(1.0, stalled / budget)
        let eased = 1 - pow(1 - fill, 1.35)
        let expected = floor + Int(Double(softCap - floor) * eased)
        if expected > session.scriptAlignProgressPercent {
            session.scriptAlignProgressPercent = min(softCap, expected)
        }
    }
}
