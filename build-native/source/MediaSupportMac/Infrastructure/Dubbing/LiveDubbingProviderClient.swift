import Foundation

@MainActor
struct LiveDubbingProviderCatalogClient: DubbingProviderCatalogClient {
    func googleVoices() async throws -> [DubbingCloudVoice] { try await GoogleVoiceCatalogAPI.voices() }
    func maziaoVoices() async throws -> [MaziaoVoiceDescriptor] { try await MaziaoAPIClient.voices() }
    func elevenVoices() async throws -> [DubbingCloudVoice] { try await ElevenLabsVoiceCatalogAPI.voices() }
    func maziaoAccount() async throws -> MaziaoAccountSnapshot { try await MaziaoAPIClient.account(persistUsage: false) }
    func elevenQuota() async throws -> ElevenLabsQuotaSnapshot { try await ElevenLabsQuotaService.refresh(persistUsage: false) }
}

@MainActor
struct LiveDubbingProviderCredentialClient: DubbingProviderCredentialClient {
    func save(_ key: String, provider: DubbingSpeechProvider) async throws {
        switch provider {
        case .googleCloud: try await DubbingCredentialAccess.shared.saveGoogle(key)
        case .maziao: try await DubbingCredentialAccess.shared.saveMaziao(key)
        case .elevenLabs: try await DubbingCredentialAccess.shared.saveElevenLabs(key)
        case .appleOffline: break
        }
    }
    func delete(provider: DubbingSpeechProvider) async throws {
        switch provider {
        case .googleCloud: try await DubbingCredentialAccess.shared.deleteGoogle()
        case .maziao: try await DubbingCredentialAccess.shared.deleteMaziao()
        case .elevenLabs: try await DubbingCredentialAccess.shared.deleteElevenLabs()
        case .appleOffline: break
        }
    }
}
