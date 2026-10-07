import AVKit
import SwiftUI

/// Bridge AVPlayer → SwiftUI — dùng chung tab Preview và cửa sổ riêng.
struct AVPlayerContainerView: NSViewRepresentable {
    let player: AVPlayer?
    /// false = điều khiển bên ngoài (tab Phụ đề), tránh overlay che nút play.
    var showsBuiltInControls: Bool = true
    /// Tắt viền focus macOS — cần khi preview có scaleEffect (zoom chỉnh thô).
    var suppressFocusRing: Bool = false

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = showsBuiltInControls ? .inline : .none
        view.videoGravity = .resizeAspect
        if suppressFocusRing {
            view.focusRingType = .none
        }
        view.player = player
        return view
    }

    func updateNSView(_ nsView: AVPlayerView, context: Context) {
        nsView.controlsStyle = showsBuiltInControls ? .inline : .none
        nsView.videoGravity = .resizeAspect
        if suppressFocusRing {
            nsView.focusRingType = .none
        }
        nsView.player = player
    }
}
