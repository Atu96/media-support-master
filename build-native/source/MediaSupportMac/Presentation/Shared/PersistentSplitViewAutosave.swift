import AppKit
import SwiftUI

/// Gắn `autosaveName` cho NSSplitView do SwiftUI HSplitView/VSplitView tạo ra.
/// NSSplitView tự lưu divider position trong UserDefaults và tự clamp theo
/// minimum pane size khi cửa sổ đổi kích thước.
struct PersistentSplitViewAutosave: NSViewRepresentable {
    let name: String
    /// NSSplitView `isVertical == true` nghĩa là divider dọc (HSplitView).
    let splitIsVertical: Bool

    func makeNSView(context: Context) -> SplitViewAnchorView {
        let view = SplitViewAnchorView()
        view.autosaveName = name
        view.splitIsVertical = splitIsVertical
        return view
    }

    func updateNSView(_ nsView: SplitViewAnchorView, context: Context) {
        nsView.autosaveName = name
        nsView.splitIsVertical = splitIsVertical
        nsView.attachToNearestSplitView()
    }
}

final class SplitViewAnchorView: NSView {
    var splitIsVertical = true
    private weak var attachedSplitView: NSSplitView?
    private var attachedName = ""
    var autosaveName = "" {
        didSet {
            guard autosaveName != oldValue else { return }
            attachToNearestSplitView()
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachToNearestSplitView()
        // SwiftUI có thể hoàn thành cây NSSplitView sau một lượt layout.
        DispatchQueue.main.async { [weak self] in
            self?.attachToNearestSplitView()
        }
    }

    func attachToNearestSplitView() {
        guard !autosaveName.isEmpty else { return }
        var node = superview
        while let current = node {
            if let splitView = current as? NSSplitView,
               splitView.isVertical == splitIsVertical {
                configure(splitView)
                return
            }
            node = current.superview
        }

        // SwiftUI đôi khi đặt background reporter cạnh NSSplitView thay vì nằm
        // bên trong nó. Khi đó tìm trong đúng main window theo hướng divider;
        // workspace chỉ có một split ngang và một split dọc.
        if let root = window?.contentView,
           let splitView = findSplitView(in: root) {
            configure(splitView)
        }
    }

    private func findSplitView(in root: NSView) -> NSSplitView? {
        if let split = root as? NSSplitView, split.isVertical == splitIsVertical {
            return split
        }
        for child in root.subviews {
            if let match = findSplitView(in: child) { return match }
        }
        return nil
    }

    private func configure(_ splitView: NSSplitView) {
        guard attachedSplitView !== splitView || attachedName != autosaveName else { return }
        attachedSplitView = splitView
        attachedName = autosaveName
        splitView.autosaveName = autosaveName
        splitView.adjustSubviews()
        // Ghi mốc hợp lệ ngay lần đầu; các lần người dùng kéo sau đó NSSplitView
        // tiếp tục tự lưu. Đặt lại đúng vị trí hiện tại nên không gây nhảy layout.
        guard splitView.subviews.count > 1 else { return }
        let current = splitView.isVertical
            ? splitView.subviews[0].frame.maxX
            : splitView.subviews[0].frame.maxY
        splitView.setPosition(current, ofDividerAt: 0)
    }
}
