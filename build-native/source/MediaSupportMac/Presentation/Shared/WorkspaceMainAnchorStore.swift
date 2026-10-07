import AppKit
import SwiftUI

/// Cột workspace chính (Media/Preview/Tóm tắt/Sub) — mép phải = mép phải khung preview & transcript.
@MainActor
final class WorkspaceMainAnchorStore: ObservableObject {
    static let shared = WorkspaceMainAnchorStore()

    private(set) var screenFrame: CGRect = .zero
    private(set) var leftX: CGFloat = 0
    private(set) var rightX: CGFloat = 0
    private(set) var topY: CGFloat = 0
    private(set) var bottomY: CGFloat = 0
    private(set) var width: CGFloat = 0
    private(set) var height: CGFloat = 0

    private init() {}

    func update(frameOnScreen: CGRect) {
        guard frameOnScreen.width > 40, frameOnScreen.height > 40 else { return }

        let changed =
            abs(rightX - frameOnScreen.maxX) > 0.5
            || abs(topY - frameOnScreen.maxY) > 0.5
            || abs(bottomY - frameOnScreen.minY) > 0.5
            || abs(leftX - frameOnScreen.minX) > 0.5
            || abs(width - frameOnScreen.width) > 0.5
            || abs(height - frameOnScreen.height) > 0.5

        screenFrame = frameOnScreen
        leftX = frameOnScreen.minX
        rightX = frameOnScreen.maxX
        bottomY = frameOnScreen.minY
        topY = frameOnScreen.maxY
        width = frameOnScreen.width
        height = frameOnScreen.height

        // Kéo dãn app / splitter → panel font/màu (nếu đang mở) bám mép phải.
        if changed {
            SystemPanelAnchor.repositionVisiblePanels()
        }
    }

    var isValid: Bool {
        rightX > leftX && topY > bottomY && height > 40
    }
}

/// Báo cáo khung cột main (bên trái slide Kiểu sub) ra tọa độ màn hình.
struct WorkspaceMainFrameAnchorReporter: NSViewRepresentable {
    func makeNSView(context: Context) -> AnchorView {
        AnchorView()
    }

    func updateNSView(_ nsView: AnchorView, context: Context) {
        nsView.report()
    }

    final class AnchorView: NSView {
        private var resizeObserver: NSObjectProtocol?
        private var moveObserver: NSObjectProtocol?

        override var isFlipped: Bool { true }

        deinit {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
            }
            if let moveObserver {
                NotificationCenter.default.removeObserver(moveObserver)
            }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            detachWindowObservers()
            attachWindowObservers()
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

        private func attachWindowObservers() {
            guard let window else { return }
            resizeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
            moveObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didMoveNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                self?.report()
            }
        }

        private func detachWindowObservers() {
            if let resizeObserver {
                NotificationCenter.default.removeObserver(resizeObserver)
                self.resizeObserver = nil
            }
            if let moveObserver {
                NotificationCenter.default.removeObserver(moveObserver)
                self.moveObserver = nil
            }
        }

        func report() {
            guard let window, bounds.width > 40, bounds.height > 40 else { return }
            let rectInWindow = convert(bounds, to: nil)
            let rectOnScreen = window.convertToScreen(rectInWindow)
            WorkspaceMainAnchorStore.shared.update(frameOnScreen: rectOnScreen)
        }
    }
}
