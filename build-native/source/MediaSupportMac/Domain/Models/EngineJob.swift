import Foundation

struct EngineJob: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let executable: String
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL?
}