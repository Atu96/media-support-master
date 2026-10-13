import Foundation

@MainActor
enum DubbingRefactorTests {
    struct Failure: Error { let reason: String }
    private static func check(_ value: Bool, _ reason: String) throws {
        if !value { throw Failure(reason: reason) }
    }

    /// Deliberately ignores cancellation, like an already received late response.
    @MainActor private final class Gate {
        private var pending: [Int: CheckedContinuation<Int, Error>] = [:]
        private var observers: [(Int, CheckedContinuation<Void, Never>)] = []
        private(set) var count = 0
        func next() async throws -> Int {
            try await withCheckedThrowingContinuation { continuation in
                count += 1
                pending[count] = continuation
                let ready = observers.filter { $0.0 <= count }
                observers.removeAll { $0.0 <= count }
                for observer in ready { observer.1.resume() }
            }
        }
        func wait(_ count: Int) async {
            if self.count >= count { return }
            await withCheckedContinuation { observers.append((count, $0)) }
        }
        func complete(_ request: Int, _ value: Int) { pending.removeValue(forKey: request)!.resume(returning: value) }
        func fail(_ request: Int) { pending.removeValue(forKey: request)!.resume(throwing: Failure(reason: "late fixture error")) }
    }

    private final class Client: DubbingProviderCatalogClient {
        let catalog = Gate(), usage = Gate()
        func googleVoices() async throws -> [DubbingCloudVoice] { try await cloud() }
        func elevenVoices() async throws -> [DubbingCloudVoice] { try await cloud() }
        private func cloud() async throws -> [DubbingCloudVoice] {
            let value = try await catalog.next()
            return [.init(id: "fixture-\(value)", name: "Fixture", gender: "male", language: "vi")]
        }
        func maziaoVoices() async throws -> [MaziaoVoiceDescriptor] {
            let value = try await catalog.next()
            return [.init(id: "fixture-\(value)", name: "Fixture", language: "vi", gender: "male", previewURL: nil, modelID: "vieten_speech")]
        }
        func maziaoAccount() async throws -> MaziaoAccountSnapshot {
            .init(remainingCredits: try await usage.next(), updatedAt: Date(timeIntervalSince1970: 0))
        }
        func elevenQuota() async throws -> ElevenLabsQuotaSnapshot {
            .init(usedCharacters: 0, characterLimit: try await usage.next(), nextReset: nil,
                  tier: "fixture", updatedAt: Date(timeIntervalSince1970: 0))
        }
    }
    private final class Credentials: DubbingProviderCredentialClient {
        func save(_ key: String, provider: DubbingSpeechProvider) async throws { }
        func delete(provider: DubbingSpeechProvider) async throws { }
    }
    private static func ids(_ owner: DubbingProviderCoordinator, _ provider: DubbingSpeechProvider) -> [String] {
        switch provider {
        case .googleCloud: owner.googleVoices.map(\.id)
        case .maziao: owner.maziaoVoices.map(\.id)
        case .elevenLabs: owner.elevenVoices.map(\.id)
        default: []
        }
    }
    private static func loading(_ owner: DubbingProviderCoordinator, _ provider: DubbingSpeechProvider) -> Bool {
        switch provider {
        case .googleCloud: owner.isRefreshingGoogleVoices
        case .maziao: owner.isRefreshingMaziaoVoices
        case .elevenLabs: owner.isRefreshingElevenVoices
        default: false
        }
    }

    static func catalogReplacement() async throws {
        for provider in [DubbingSpeechProvider.googleCloud, .maziao, .elevenLabs] {
            let client = Client()
            let state = DubbingProviderCoordinator(client: client, credentials: Credentials())
            state.setCredentialAvailability(true, provider: provider)
            let old = Task { await state.refreshCatalog(provider) }
            await client.catalog.wait(1)
            try await state.changeCredential("synthetic-B", provider: provider)
            let newest = Task { await state.refreshCatalog(provider) }
            await client.catalog.wait(2)
            client.catalog.complete(2, 2)
            await newest.value
            client.catalog.complete(1, 1)
            await old.value
            try check(ids(state, provider) == ["fixture-2"], "late account A replaced B")
            try check(!loading(state, provider), "late completion left loading stuck")

            let deleted = Task { await state.refreshCatalog(provider) }
            await client.catalog.wait(3)
            try await state.changeCredential(nil, provider: provider)
            client.catalog.complete(3, 3)
            await deleted.value
            try check(ids(state, provider).isEmpty && !state.hasCredential(provider), "deleted key restored old catalog")

            try await state.changeCredential("synthetic-C", provider: provider)
            let failing = Task { await state.refreshCatalog(provider) }
            await client.catalog.wait(4)
            try await state.changeCredential("synthetic-D", provider: provider)
            let success = Task { await state.refreshCatalog(provider) }
            await client.catalog.wait(5)
            client.catalog.complete(5, 5); await success.value
            client.catalog.fail(4); await failing.value
            try check(ids(state, provider) == ["fixture-5"], "old failure altered accepted catalog")
            try check(state.googleVoiceCatalogError.isEmpty && state.maziaoVoiceCatalogError.isEmpty && state.elevenVoiceCatalogError.isEmpty, "old error leaked")
        }
    }

    static func usageReplacement() async throws {
        for provider in [DubbingSpeechProvider.maziao, .elevenLabs] {
            let client = Client()
            let owner = DubbingProviderCoordinator(client: client, credentials: Credentials())
            var saved: [Int] = []
            owner.persistMaziao = { if let value = $0 { saved.append(value.remainingCredits) } }
            owner.persistEleven = { if let value = $0 { saved.append(value.characterLimit) } }
            owner.setCredentialAvailability(true, provider: provider)
            let old = Task { await owner.refreshUsage(provider) }
            await client.usage.wait(1)
            try await owner.changeCredential("synthetic-B", provider: provider)
            let newest = Task { await owner.refreshUsage(provider) }
            await client.usage.wait(2)
            client.usage.complete(2, 200); await newest.value
            client.usage.complete(1, 100); await old.value
            try check(saved == [200], "stale quota reached persistent store")
            let oldFailure = Task { await owner.refreshUsage(provider) }
            await client.usage.wait(3)
            try await owner.changeCredential("synthetic-C", provider: provider)
            let success = Task { await owner.refreshUsage(provider) }
            await client.usage.wait(4)
            client.usage.complete(4, 400); await success.value
            client.usage.fail(3); await oldFailure.value
            try check(saved == [200, 400] && owner.maziaoAccountError.isEmpty && owner.elevenQuotaError.isEmpty, "stale usage error altered newer state")
            let deleted = Task { await owner.refreshUsage(provider) }
            await client.usage.wait(5)
            try await owner.changeCredential(nil, provider: provider)
            client.usage.complete(5, 500); await deleted.value
            try check(owner.maziaoAccount == nil && owner.elevenQuota == nil && saved == [200, 400], "deleted account restored usage")
        }
    }

    private static func cue(_ id: Int, _ start: Double, _ duration: Double) -> DubbingRenderedCue {
        .init(id: id, startSeconds: start, endSeconds: start + duration, audioDuration: duration,
              audioURL: URL(fileURLWithPath: "/tmp/fixture-\(id).caf"), fingerprint: "fixture-\(id)")
    }

    static func playbackParity() throws {
        var cues = (0..<2_000).map { cue($0, Double($0) * 0.1, Double($0 % 13 + 1) * 0.15) }
        cues.insert(cue(9_999, -1, 300), at: 0) // long earlier overlap must remain active
        cues.insert(cue(9_998, -1, 0), at: 0)
        cues.sort { $0.startSeconds == $1.startSeconds ? $0.id < $1.id : $0.startSeconds < $1.startSeconds }
        let snapshot = DubbingPlaybackSnapshot(cues: cues)
        for time in [-2, -1, 0, 0.1, 1, 50, 198, 299, 300, .infinity, .nan] + (0..<600).map({ Double($0) * 0.37 }) {
            let expected = cues.filter { time >= $0.startSeconds && time < $0.startSeconds + $0.playedDuration }
            try check(snapshot.activeCues(at: time) == expected, "playback interval parity failed")
        }
        let unordered = Array(cues.reversed())
        let fallback = DubbingPlaybackSnapshot(cues: unordered)
        try check(fallback.activeCues(at: 50) == unordered.filter { 50 >= $0.startSeconds && 50 < $0.startSeconds + $0.playedDuration }, "unordered fallback changed overlap/order")
    }

    static func playbackInvalidation() throws {
        let cache = DubbingPlaybackSnapshotCache()
        var rendered = Dictionary(uniqueKeysWithValues: (0..<5_000).map { ($0, cue($0, Double($0), 1)) })
        for tick in 0..<3_000 {
            let snapshot = cache.snapshot(rendered: rendered, rates: [:])
            _ = snapshot.activeCues(at: Double(tick) / 30)
        }
        try check(cache.rebuildCount == 1, "unchanged clock ticks rebuilt sorted list")
        cache.invalidate()
        let rates = ["fixture-1": 0.5]
        let slower = cache.snapshot(rendered: rendered, rates: rates)
        try check(slower.cues.first(where: { $0.id == 1 })?.playedDuration == 2, "manual rate not rebuilt")
        rendered[1] = cue(1, 100, 3); rendered.removeValue(forKey: 2)
        cache.invalidate()
        let changed = cache.snapshot(rendered: rendered, rates: [:])
        try check(changed.cues.count == 4_999 && changed.cues.first(where: { $0.id == 1 })?.startSeconds == 100, "retime/delete left stale snapshot")
        rendered.removeAll(); cache.invalidate()
        try check(cache.snapshot(rendered: rendered, rates: [:]).cues.isEmpty && cache.rebuildCount == 4, "clear left stale playback")
        print("DUBBING_PLAYBACK_WORK_CHECK cues=5000 clockTicks=3000 sortedRebuilds=1 noAPI=true")
    }

    static func jobLifecycle() async throws {
        let job = DubbingJobLifecycle(), gate = Gate()
        let old = job.begin()
        let task = Task { _ = try? await gate.next() }
        job.task = task
        await gate.wait(1)
        let new = job.begin()
        try check(task.isCancelled, "replacement did not cancel old handle")
        job.finish(old)
        try check(job.generation == new, "old finish invalidated new generation")
        gate.complete(1, 1); await task.value
        job.finish(new)
        try check(job.generation == nil && job.task == nil, "finished job retained state")
        _ = job.begin(); job.cancel()
        try check(job.generation == nil, "cancel retained generation")
    }
}
