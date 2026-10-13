import Foundation
import Combine

@MainActor
protocol DubbingProviderCatalogClient {
    func googleVoices() async throws -> [DubbingCloudVoice]
    func maziaoVoices() async throws -> [MaziaoVoiceDescriptor]
    func elevenVoices() async throws -> [DubbingCloudVoice]
    func maziaoAccount() async throws -> MaziaoAccountSnapshot
    func elevenQuota() async throws -> ElevenLabsQuotaSnapshot
}

@MainActor
protocol DubbingProviderCredentialClient {
    func save(_ key: String, provider: DubbingSpeechProvider) async throws
    func delete(provider: DubbingSpeechProvider) async throws
}

/// Catalog/usage/credential lifecycle owner. Session remains the selection facade.
@MainActor
final class DubbingProviderCoordinator: ObservableObject {
    @Published var hasGoogleCredential = false
    @Published var hasElevenLabsCredential = false
    @Published var hasMaziaoCredential = false
    @Published private(set) var googleVoices: [DubbingCloudVoice] = []
    @Published private(set) var maziaoVoices: [MaziaoVoiceDescriptor] = []
    @Published private(set) var elevenVoices: [DubbingCloudVoice] = []
    @Published private(set) var isRefreshingGoogleVoices = false
    @Published private(set) var isRefreshingMaziaoVoices = false
    @Published private(set) var isRefreshingElevenVoices = false
    @Published private(set) var googleVoiceCatalogError = ""
    @Published private(set) var maziaoVoiceCatalogError = ""
    @Published private(set) var elevenVoiceCatalogError = ""
    @Published var maziaoAccount: MaziaoAccountSnapshot?
    @Published var elevenQuota: ElevenLabsQuotaSnapshot?
    @Published private(set) var isRefreshingMaziaoAccount = false
    @Published private(set) var isRefreshingElevenQuota = false
    @Published private(set) var maziaoAccountError = ""
    @Published private(set) var elevenQuotaError = ""
    var didUpdateCatalog: ((DubbingSpeechProvider) -> Void)?
    var persistMaziao: (MaziaoAccountSnapshot?) -> Void = { _ in }
    var persistEleven: (ElevenLabsQuotaSnapshot?) -> Void = { _ in }
    private let client: DubbingProviderCatalogClient
    private let credentials: DubbingProviderCredentialClient
    private let google = DubbingRefreshCoordinator<[DubbingCloudVoice]>()
    private let maziao = DubbingRefreshCoordinator<[MaziaoVoiceDescriptor]>()
    private let eleven = DubbingRefreshCoordinator<[DubbingCloudVoice]>()
    private let account = DubbingRefreshCoordinator<MaziaoAccountSnapshot>()
    private let quota = DubbingRefreshCoordinator<ElevenLabsQuotaSnapshot>()
    private var mutations: [DubbingSpeechProvider: UUID] = [:]

    init(client: DubbingProviderCatalogClient, credentials: DubbingProviderCredentialClient) {
        self.client = client
        self.credentials = credentials
    }

    func hasCredential(_ provider: DubbingSpeechProvider) -> Bool {
        switch provider {
        case .googleCloud: hasGoogleCredential
        case .maziao: hasMaziaoCredential
        case .elevenLabs: hasElevenLabsCredential
        case .appleOffline: true
        }
    }

    func invalidate(_ provider: DubbingSpeechProvider) {
        switch provider {
        case .googleCloud: google.invalidate()
        case .maziao: maziao.invalidate(); account.invalidate()
        case .elevenLabs: eleven.invalidate(); quota.invalidate()
        case .appleOffline: break
        }
    }

    func setCredentialAvailability(_ available: Bool, provider: DubbingSpeechProvider) {
        switch provider {
        case .googleCloud: hasGoogleCredential = available
        case .maziao: hasMaziaoCredential = available
        case .elevenLabs: hasElevenLabsCredential = available
        case .appleOffline: break
        }
        if !available { invalidate(provider); clearCatalog(provider) }
    }

    func changeCredential(_ key: String?, provider: DubbingSpeechProvider) async throws {
        let token = UUID()
        mutations[provider] = token
        invalidate(provider)
        defer { if mutations[provider] == token { mutations.removeValue(forKey: provider) } }
        if let key { try await credentials.save(key, provider: provider) }
        else { try await credentials.delete(provider: provider) }
        guard mutations[provider] == token else { throw CancellationError() }
        setCredentialAvailability(key?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false, provider: provider)
        clearCatalog(provider)
        switch provider {
        case .maziao: maziaoAccount = nil; maziaoAccountError = ""; persistMaziao(nil)
        case .elevenLabs: elevenQuota = nil; elevenQuotaError = ""; persistEleven(nil)
        default: break
        }
    }

    func clearCatalog(_ provider: DubbingSpeechProvider) {
        invalidate(provider)
        switch provider {
        case .googleCloud: googleVoices = []; googleVoiceCatalogError = ""
        case .maziao: maziaoVoices = []; maziaoVoiceCatalogError = ""
        case .elevenLabs: elevenVoices = []; elevenVoiceCatalogError = ""
        case .appleOffline: break
        }
    }

    func updateGoogle(_ voices: [DubbingCloudVoice]) { googleVoices = voices; googleVoiceCatalogError = ""; didUpdateCatalog?(.googleCloud) }
    func updateMaziao(_ voices: [MaziaoVoiceDescriptor]) { maziaoVoices = voices; maziaoVoiceCatalogError = ""; didUpdateCatalog?(.maziao) }
    func updateEleven(_ voices: [DubbingCloudVoice]) { elevenVoices = voices; elevenVoiceCatalogError = ""; didUpdateCatalog?(.elevenLabs) }

    func refreshCatalog(_ provider: DubbingSpeechProvider) async {
        guard hasCredential(provider), mutations[provider] == nil else { return }
        switch provider {
        case .googleCloud:
            googleVoiceCatalogError = ""
            await google.run(operation: { [client] in try await client.googleVoices() },
                loading: { [weak self] in self?.isRefreshingGoogleVoices = $0 },
                publish: { [weak self] in self?.updateGoogle($0) },
                failure: { [weak self] in self?.catalogFailure($0, provider: provider) })
        case .maziao:
            maziaoVoiceCatalogError = ""
            await maziao.run(operation: { [client] in try await client.maziaoVoices() },
                loading: { [weak self] in self?.isRefreshingMaziaoVoices = $0 },
                publish: { [weak self] in self?.updateMaziao($0) },
                failure: { [weak self] in self?.catalogFailure($0, provider: provider) })
        case .elevenLabs:
            elevenVoiceCatalogError = ""
            await eleven.run(operation: { [client] in try await client.elevenVoices() },
                loading: { [weak self] in self?.isRefreshingElevenVoices = $0 },
                publish: { [weak self] in self?.updateEleven($0) },
                failure: { [weak self] in self?.catalogFailure($0, provider: provider) })
        case .appleOffline: break
        }
    }

    func refreshUsage(_ provider: DubbingSpeechProvider) async {
        guard hasCredential(provider), mutations[provider] == nil else { return }
        switch provider {
        case .maziao:
            maziaoAccountError = ""
            await account.run(operation: { [client] in try await client.maziaoAccount() },
                loading: { [weak self] in self?.isRefreshingMaziaoAccount = $0 },
                publish: { [weak self] value in self?.maziaoAccount = value; self?.persistMaziao(value) },
                failure: { [weak self] in self?.usageFailure($0, provider: provider) })
        case .elevenLabs:
            elevenQuotaError = ""
            await quota.run(operation: { [client] in try await client.elevenQuota() },
                loading: { [weak self] in self?.isRefreshingElevenQuota = $0 },
                publish: { [weak self] value in self?.elevenQuota = value; self?.persistEleven(value) },
                failure: { [weak self] in self?.usageFailure($0, provider: provider) })
        default: break
        }
    }

    private func catalogFailure(_ error: Error, provider: DubbingSpeechProvider) {
        markMissingCredential(error, provider: provider)
        switch provider {
        case .googleCloud: googleVoiceCatalogError = error.localizedDescription
        case .maziao: maziaoVoiceCatalogError = error.localizedDescription
        case .elevenLabs: elevenVoiceCatalogError = error.localizedDescription
        default: break
        }
    }

    private func usageFailure(_ error: Error, provider: DubbingSpeechProvider) {
        markMissingCredential(error, provider: provider)
        if provider == .maziao { maziaoAccountError = error.localizedDescription }
        else { elevenQuotaError = error.localizedDescription }
    }

    private func markMissingCredential(_ error: Error, provider: DubbingSpeechProvider) {
        if let error = error as? DubbingError, case .missingCredential = error {
            setCredentialAvailability(false, provider: provider)
        }
    }
}
