import Foundation

struct EngineStatus: Equatable {
    let isReady: Bool
    let issues: [String]
}