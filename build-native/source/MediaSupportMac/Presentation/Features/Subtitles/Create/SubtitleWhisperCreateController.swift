import Foundation
import SwiftUI

/// Job + % tab **Tạo sub tự động**.
///
/// UX (đã dò UI):
/// - % từ log thật; trần 95 khi engine chạy
/// - Engine xong → parse nền → **gán segments + tắt inFlight ngay** (không sleep kịch)
/// - UI `SubtitleCreateView` hiện cue ngay khi `!segments.isEmpty` (không chờ `!jobUI`)
@MainActor
final class SubtitleWhisperCreateController {
    private unowned let session: SubtitleCreateSession

    private var progressTicker: Task<Void, Never>?
    private var lastRealPercent = 0
    private var lastRealAt = Date()

    private let engineCap = 95
    private let loadPhasePercent = 93

    init(session: SubtitleCreateSession) {
        self.session = session
    }

    var isRunning: Bool {
        session.engine.isRunning
            && session.runner.currentJobTitle?.contains("Chép lời") == true
    }

    func run() {
        let defaults = UserDefaults.standard
        let useOffline = defaults.bool(forKey: "msm.offlineWhisper.useForNextRun")
            && OfflineWhisperModelManager.isModelReady
        if useOffline {
            defaults.set(false, forKey: "msm.offlineWhisper.useForNextRun")
        }
        run(usingOffline: useOffline)
    }

    func runOffline() {
        guard OfflineWhisperModelManager.isModelReady else { return }
        run(usingOffline: true)
    }

    private func run(usingOffline: Bool) {
        guard let draft = session.whisperDraftMediaURL else { return }
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
            session.isWhisperJobInFlight = true
            beginProgressTracking()

            let started = Date()
            session.attachPreviewVideo()
            if usingOffline {
                await session.engine.runOfflineWhisperSRT(
                    for: mediaURL,
                    sourceLang: session.sourceLang
                )
            } else {
                await session.engine.runWhisperSRT(for: mediaURL, sourceLang: session.sourceLang)
                session.presentWhisperCloudAlertIfNeeded()
            }
            session.refreshEngineStatus()

            // Phase nạp — 1 mốc, không ramp.
            setProgressAtLeast(loadPhasePercent)
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

            // Trả MainActor: gán cue + tắt job **cùng lúc** — UI hiện sub, % tắt (CreateView).
            endProgressTracking()

            if let srt = finish.srtURL {
                session.srtURL = srt
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    session.segments = finish.segments
                    session.whisperComplete = true
                    session.whisperProgressPercent = 100
                    session.isWhisperJobInFlight = false
                }
                session.activeTranscriptVariant = .original
                session.resetEditHistory()
                if finish.warning == "vault" {
                    session.runner.appendLog("⚠️ Không copy SRT vào backup vault")
                }

                let elapsed = Date().timeIntervalSince(started)
                let lang = ProjectBackupStore.languageRecord(for: mediaURL)?.language ?? "auto"
                let langLabel = session.languageDisplayName(lang)
                session.completionSummary =
                    "\(session.segments.count) đoạn • \(String(format: "%.1f", elapsed))s • \(langLabel)"
                session.runner.appendLog("✓ Chép lời hoàn tất — \(session.completionSummary)")

                // Persist không chặn hiển thị.
                session.persistProjectSession()
            } else {
                session.whisperProgressPercent = 100
                session.isWhisperJobInFlight = false
                if !exitOK {
                    session.runner.appendLog("✗ Chép lời thất bại — không có SRT")
                }
            }

            session.syncPreferencesContext()
        }
    }

    func clearLiveState() {
        endProgressTracking()
        session.whisperProgressPercent = 0
        session.isWhisperJobInFlight = false
    }

    // MARK: - Progress

    private func beginProgressTracking() {
        lastRealPercent = 0
        lastRealAt = Date()
        session.whisperProgressPercent = 0
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
        applyRealProgress(percent)
    }

    private func applyRealProgress(_ percent: Int) {
        let p = min(engineCap, max(0, percent))
        if p > lastRealPercent {
            lastRealPercent = p
            lastRealAt = Date()
        }
        if p > session.whisperProgressPercent {
            session.whisperProgressPercent = p
        }
    }

    private func setProgressAtLeast(_ percent: Int) {
        let p = min(100, max(0, percent))
        if p > session.whisperProgressPercent {
            session.whisperProgressPercent = p
        }
        if p > lastRealPercent {
            lastRealPercent = p
            lastRealAt = Date()
        }
    }

    private func startSmoothTicker() {
        progressTicker?.cancel()
        progressTicker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300_000_000)
                guard let self, !Task.isCancelled else { return }
                guard self.session.isWhisperJobInFlight else { return }
                self.tickSmoothProgress()
            }
        }
    }

    private func tickSmoothProgress() {
        guard session.engine.isRunning || isRunning else { return }

        let now = Date()
        let stalled = now.timeIntervalSince(lastRealAt)
        guard stalled >= 0.45 else { return }

        let mediaDur = max(0, session.preview.duration)
        let whisperBudget: TimeInterval = {
            if mediaDur > 2 {
                return min(120, max(10, mediaDur * 0.35 + 6))
            }
            return 22
        }()

        let floor = lastRealPercent
        let softCap: Int
        if floor < 14 {
            softCap = 14
        } else if floor < 86 {
            softCap = 85
        } else {
            softCap = engineCap
        }

        guard floor < softCap else { return }

        let budget: TimeInterval = floor < 14 ? 8 : (floor < 86 ? whisperBudget : 14)
        let fill = min(1.0, stalled / budget)
        let eased = 1 - pow(1 - fill, 1.4)
        let expected = floor + Int(Double(softCap - floor) * eased)

        if expected > session.whisperProgressPercent {
            session.whisperProgressPercent = min(softCap, expected)
        }
    }
}
