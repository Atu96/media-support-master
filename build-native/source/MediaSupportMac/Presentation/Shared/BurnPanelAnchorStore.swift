import AppKit
import SwiftUI

/// Khung «Gắn sub vào video» trên màn hình (AppKit, gốc dưới-trái).
@MainActor
final class BurnPanelAnchorStore: ObservableObject {
    static let shared = BurnPanelAnchorStore()

    /// Toàn bộ AppCard burn trên màn hình.
    private(set) var screenFrame: CGRect = .zero
    private(set) var bottomY: CGFloat = 0
    private(set) var topY: CGFloat = 0
    private(set) var leftX: CGFloat = 0
    private(set) var panelWidth: CGFloat = 0
    private(set) var panelHeight: CGFloat = 0
    /// Tâm nút «Gắn sub vào video».
    private(set) var burnButtonCenterX: CGFloat = 0

    private init() {}

    func update(frameOnScreen: CGRect) {
        guard frameOnScreen.width > 8, frameOnScreen.height > 8 else { return }
        let changed =
            abs(leftX - frameOnScreen.minX) > 0.5
            || abs(bottomY - frameOnScreen.minY) > 0.5
            || abs(topY - frameOnScreen.maxY) > 0.5
            || abs(panelWidth - frameOnScreen.width) > 0.5
            || abs(panelHeight - frameOnScreen.height) > 0.5

        screenFrame = frameOnScreen
        bottomY = frameOnScreen.minY
        topY = frameOnScreen.maxY
        leftX = frameOnScreen.minX
        panelWidth = frameOnScreen.width
        panelHeight = frameOnScreen.height

        // Màu neo theo burn top — cập nhật khi slide/resize.
        if changed {
            SystemPanelAnchor.repositionVisiblePanels()
        }
    }

    /// Tương thích code cũ (mép đáy + trái + width; height thật nếu > 1).
    func update(bottomY: CGFloat, leftX: CGFloat, width: CGFloat, height: CGFloat) {
        guard width > 8 else { return }
        // Reporter 1px cũ: không ghi đè height/top nếu đã có frame đầy đủ.
        if height <= 2, panelHeight > 8 {
            self.bottomY = bottomY
            self.leftX = leftX
            self.panelWidth = width
            return
        }
        update(frameOnScreen: CGRect(x: leftX, y: bottomY, width: width, height: max(height, 1)))
    }

    func updateBurnButton(centerX: CGFloat) {
        guard centerX > 0 else { return }
        burnButtonCenterX = centerX
    }

    var isValid: Bool {
        leftX > 0 && topY > bottomY && panelWidth > 8 && panelHeight > 8
    }
}

/// Báo cáo **toàn bộ** khung burn (để neo mép trên + mép trái).
struct BurnPanelFrameAnchorReporter: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.report()
    }

    final class AnchorView: NSView {
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            report()
        }

        func report() {
            guard let window, bounds.width > 8, bounds.height > 8 else { return }
            let rectInWindow = convert(bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            BurnPanelAnchorStore.shared.update(frameOnScreen: rectOnScreen)
        }
    }
}

/// Marker 1px sát mép dưới — bổ sung, không thay frame đầy đủ.
struct BurnPanelBottomAnchorReporter: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.report()
    }

    final class AnchorView: NSView {
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window, bounds.width > 0 else { return }
            let rectInWindow = convert(bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            BurnPanelAnchorStore.shared.update(
                bottomY: rectOnScreen.minY,
                leftX: rectOnScreen.minX,
                width: rectOnScreen.width,
                height: rectOnScreen.height
            )
        }
    }
}

/// Tâm nút «Gắn sub vào video» trên màn hình.
struct BurnActionButtonAnchorReporter: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.report()
    }

    final class AnchorView: NSView {
        override var isFlipped: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            report()
        }

        override func layout() {
            super.layout()
            report()
        }

        func report() {
            guard let window, bounds.width > 0, bounds.height > 0 else { return }
            let rectInWindow = convert(bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            BurnPanelAnchorStore.shared.updateBurnButton(centerX: rectOnScreen.midX)
        }
    }
}
