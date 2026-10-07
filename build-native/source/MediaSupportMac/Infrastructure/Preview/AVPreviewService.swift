import AVFoundation
import Foundation

/// AVPlayer-backed preview — scrub ngay khi pause, duration load khi item sẵn sàng.
@MainActor
final class AVPreviewService: ObservableObject, MediaPreviewServing {
    static let shared = AVPreviewService()

    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoaded = false
    @Published private(set) var isPlaying = false
    @Published private(set) var duration: Double = 0
    @Published private(set) var currentTime: Double = 0
    /// Preview chạy theo timecode SRT, không có video/audio thật.
    @Published private(set) var isTimelineOnlyPreview = false

    private(set) var player: AVPlayer?
    private var timeObserver: Any?
    private var statusObservation: NSKeyValueObservation?
    private var lastPublishedTime: Double = -1
    private var pendingSeekToken: UInt = 0
    /// Trong lúc chốt một cue, không để time observer ghi đè currentTime bằng
    /// frame skim/seek cũ vừa bị huỷ.
    private var isManualSeekInFlight = false
    /// Skimming không được gọi nhiều `player.seek` đồng thời: chỉ giữ frame mới nhất.
    private var queuedSkimSeconds: Double?
    private var latestSkimSeconds: Double?
    private var skimSeekInFlight = false
    private var skimDispatchPending = false
    private var skimRequestGeneration: UInt = 0
    private var lastSkimDispatchTime: TimeInterval = 0
    /// Skim chỉ đổi frame render, không đổi currentTime/playhead đã chốt.
    private var isSkimPreviewing = false
    private var primeTask: Task<Void, Never>?
    private var timelinePlaybackTask: Task<Void, Never>?

    private init() {}

    func clear() {
        cancelSkimRequests()
        primeTask?.cancel()
        primeTask = nil
        timelinePlaybackTask?.cancel()
        timelinePlaybackTask = nil
        statusObservation?.invalidate()
        statusObservation = nil
        teardownObserver()
        currentURL = nil
        isLoaded = false
        isPlaying = false
        duration = 0
        currentTime = 0
        isTimelineOnlyPreview = false
        lastPublishedTime = -1
    }

    func load(url: URL) {
        cancelSkimRequests()
        primeTask?.cancel()
        timelinePlaybackTask?.cancel()
        timelinePlaybackTask = nil
        statusObservation?.invalidate()
        teardownObserver()

        currentURL = url
        isTimelineOnlyPreview = false
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        // Giữ cơ chế đệm mặc định của AVFoundation. Tắt nó khiến playback local
        // dễ hụt frame khi SwiftUI đang phải cập nhật timeline.
        player?.automaticallyWaitsToMinimizeStalling = true
        player?.actionAtItemEnd = .pause
        isLoaded = true
        isPlaying = false
        duration = 0
        lastPublishedTime = 0
        currentTime = 0

        observeTime()
        observeItemReadiness(item)
        primeTask = Task { @MainActor in
            await self.primePlayback(item: item)
        }
    }

    /// Nạp timecode của SRT như một preview độc lập. Không mượn video trước đó.
    func loadTimeline(duration: Double) {
        clear()
        currentURL = nil
        isLoaded = true
        isTimelineOnlyPreview = true
        self.duration = max(0.01, duration)
        currentTime = 0
        lastPublishedTime = 0
    }

    func play() {
        guard isLoaded else { return }
        if let player {
            player.play()
        } else if isTimelineOnlyPreview {
            startTimelinePlayback()
        }
        isPlaying = true
    }

    func pause() {
        player?.pause()
        timelinePlaybackTask?.cancel()
        timelinePlaybackTask = nil
        isPlaying = false
    }

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func seek(seconds: Double) {
        seek(seconds: seconds, playAfter: false)
    }

    func seek(seconds: Double, playAfter: Bool, precise: Bool = false) {
        cancelSkimRequests()
        let upper = duration > 0 ? duration : max(seconds, 0)
        let clamped = max(0, min(seconds, upper))

        if !playAfter, !precise, abs(clamped - currentTime) < 0.12 {
            return
        }

        publishTime(clamped, minDelta: 0)

        guard let player else {
            if playAfter { play() }
            return
        }

        // Các click/shortcut mới luôn quan trọng hơn seek cũ.
        player.currentItem?.cancelPendingSeeks()

        if !playAfter {
            player.pause()
            isPlaying = false
        }

        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        let tolerance = precise
            ? CMTime.zero
            : CMTime(seconds: 0.12, preferredTimescale: 600)

        pendingSeekToken &+= 1
        let token = pendingSeekToken
        isManualSeekInFlight = true

        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor in
                guard let self, token == self.pendingSeekToken else { return }
                self.isManualSeekInFlight = false
                guard finished else { return }
                self.publishTime(clamped, minDelta: 0)
                if playAfter { self.play() }
            }
        }
    }

    /// Seek nhanh cho tab chỉnh sửa — tolerance vừa, phản hồi UI sớm.
    func seekForEdit(seconds: Double) {
        cancelSkimRequests()
        let clamped = max(0, seconds)

        guard let player else {
            publishTime(clamped, minDelta: 0)
            return
        }

        player.currentItem?.cancelPendingSeeks()
        player.pause()
        isPlaying = false

        pendingSeekToken &+= 1
        let token = pendingSeekToken
        isManualSeekInFlight = true

        // Publish sớm để highlight/preview không chờ seek xong.
        publishTime(clamped, minDelta: 0)

        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        // Click/chọn cue là thao tác chốt: cần frame đúng timecode, không dùng
        // tolerance rộng vốn có thể để preview kẹt ở frame Skim vừa trước đó.
        let tolerance = CMTime.zero
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self] finished in
            Task { @MainActor in
                guard let self, token == self.pendingSeekToken else { return }
                self.isManualSeekInFlight = false
                guard finished else { return }
                self.publishTime(clamped, minDelta: 0)
            }
        }
    }

    /// Preview khi skim: chuột có thể gửi hàng trăm sự kiện/giây, nhưng UI và
    /// decoder chỉ nhận tối đa một yêu cầu mỗi nhịp màn hình. Cả hai luôn dùng
    /// vị trí mới nhất, không tạo hàng seek chờ đợi.
    func skimForPreview(seconds: Double) {
        let upper = duration > 0 ? duration : max(seconds, 0)
        let clamped = max(0, min(seconds, upper))
        isSkimPreviewing = true
        latestSkimSeconds = clamped
        scheduleLatestSkim()
    }

    private func scheduleLatestSkim() {
        guard !skimDispatchPending else { return }
        skimDispatchPending = true
        let generation = skimRequestGeneration
        let elapsed = ProcessInfo.processInfo.systemUptime - lastSkimDispatchTime
        let delay = max(0, (1.0 / 60.0) - elapsed)

        Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            }
            guard let self, generation == self.skimRequestGeneration else { return }
            self.skimDispatchPending = false
            guard let seconds = self.latestSkimSeconds else { return }

            self.latestSkimSeconds = nil
            self.lastSkimDispatchTime = ProcessInfo.processInfo.systemUptime
            self.player?.pause()
            self.isPlaying = false
            self.queuedSkimSeconds = seconds
            self.drainSkimQueue()

            // Nếu chuột đã đi tiếp trong lúc xử lý frame này, xếp đúng một
            // nhịp tiếp theo thay vì để sự kiện chuột dồn thành hàng đợi.
            if self.latestSkimSeconds != nil {
                self.scheduleLatestSkim()
            }
        }
    }

    private func cancelSkimRequests() {
        skimRequestGeneration &+= 1
        isSkimPreviewing = false
        latestSkimSeconds = nil
        queuedSkimSeconds = nil
        skimDispatchPending = false
    }

    private func drainSkimQueue() {
        guard !skimSeekInFlight, let seconds = queuedSkimSeconds else { return }
        queuedSkimSeconds = nil
        guard let player else {
            return
        }

        skimSeekInFlight = true
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        let tolerance = CMTime(seconds: 0.18, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: tolerance, toleranceAfter: tolerance) { [weak self, weak player] finished in
            Task { @MainActor in
                guard let self else { return }
                self.skimSeekInFlight = false
                guard self.player === player else { return }
                self.drainSkimQueue()
            }
        }
    }

    private func primePlayback(item: AVPlayerItem) async {
        await waitUntilReady(item)
        refreshDuration(from: item)
        showFrame(at: 0)
    }

    private func waitUntilReady(_ item: AVPlayerItem) async {
        for _ in 0..<120 {
            if Task.isCancelled { return }
            if item.status == .readyToPlay { return }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func observeItemReadiness(_ item: AVPlayerItem) {
        statusObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, item.status == .readyToPlay else { return }
                self.refreshDuration(from: item)
                if self.currentTime == 0, !self.isPlaying {
                    self.showFrame(at: 0)
                }
            }
        }
    }

    private func refreshDuration(from item: AVPlayerItem) {
        let seconds = item.duration.seconds
        if seconds.isFinite, seconds > 0 {
            duration = seconds
            return
        }
        Task { @MainActor in
            do {
                let assetDuration = try await item.asset.load(.duration)
                let value = assetDuration.seconds
                if value.isFinite, value > 0 {
                    self.duration = value
                }
            } catch {
                // Giữ duration hiện tại nếu asset chưa sẵn sàng.
            }
        }
    }

    private func showFrame(at seconds: Double) {
        seek(seconds: seconds, playAfter: false, precise: true)
    }

    private func startTimelinePlayback() {
        timelinePlaybackTask?.cancel()
        let startTime = currentTime
        let startedAt = Date()
        timelinePlaybackTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 33_333_333)
                guard let self, self.isTimelineOnlyPreview, self.isPlaying else { return }

                let next = min(self.duration, startTime + Date().timeIntervalSince(startedAt))
                self.publishTime(next, minDelta: 0)
                if next >= self.duration {
                    self.isPlaying = false
                    self.timelinePlaybackTask = nil
                    return
                }
            }
        }
    }

    private func publishTime(_ seconds: Double, minDelta: Double = 1.0 / 60.0) {
        guard abs(seconds - lastPublishedTime) >= minDelta else { return }
        lastPublishedTime = seconds
        currentTime = seconds
    }

    private func observeTime() {
        guard let player else { return }
        // Video do AVPlayerView render hoàn toàn native. Timeline chỉ cần 30 Hz
        // để playhead mượt nhưng không ép SwiftUI dựng lại waveform 60 lần/giây.
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [weak self] time in
            Task { @MainActor in
                guard let self else { return }
                let seconds = time.seconds
                let playing = player.rate > 0

                if let item = player.currentItem {
                    let itemDuration = item.duration.seconds
                    if itemDuration.isFinite, itemDuration > 0, itemDuration != self.duration {
                        self.duration = itemDuration
                    }
                }

                if playing || (!self.isSkimPreviewing && !self.isManualSeekInFlight) {
                    self.publishTime(seconds)
                }

                if self.isPlaying != playing {
                    self.isPlaying = playing
                }
            }
        }
    }

    private func teardownObserver() {
        if let timeObserver, let player {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        player?.pause()
        player = nil
    }
}
