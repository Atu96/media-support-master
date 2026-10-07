import Foundation

struct SpeechWordTimestamp: Equatable, Sendable {
    let text: String
    let startSeconds: Double
    let endSeconds: Double
}
