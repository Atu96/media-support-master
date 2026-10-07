import AppKit
import SwiftUI

@MainActor
enum SystemPanelAnchor {
    /// Tránh re-pin liên tục khi kéo resize (gộp ~1 frame).
    private static var pendingReposition = false
    /// Kéo splitter/panel là tương tác trực tiếp. Không được di chuyển bảng Font/Màu
    /// theo từng pixel vì AppKit sẽ làm khung SwiftUI bị chớp.
    private static var isInteractiveResizeInProgress = false
    private static var needsRepositionAfterInteractiveResize = false

    static func setInteractiveResizeInProgress(_ isInProgress: Bool) {
        guard isInteractiveResizeInProgress != isInProgress else { return }
        isInteractiveResizeInProgress = isInProgress

        guard !isInProgress else { return }
        // Khi thả chuột, neo lại đúng một lần để các bảng hệ thống vẫn khớp.
        if needsRepositionAfterInteractiveResize {
            needsRepositionAfterInteractiveResize = false
            repositionVisiblePanels()
        }
    }

    static func presentBesideBurnPanel(_ panel: NSPanel) {
        presentWhenAnchored(panel, attempt: 0)
    }

    /// Gọi khi app resize / splitter / slide đổi — panel font/màu (nếu đang mở) bám theo mép phải preview+sub.
    static func repositionVisiblePanels() {
        if isInteractiveResizeInProgress {
            needsRepositionAfterInteractiveResize = true
            return
        }
        if pendingReposition { return }
        pendingReposition = true
        DispatchQueue.main.async {
            pendingReposition = false
            repositionVisiblePanelsNow()
        }
    }

    static func repositionVisiblePanelsNow() {
        let font = NSFontPanel.shared
        if font.isVisible {
            pinBesideWorkspace(font)
        }
        let color = NSColorPanel.shared
        if color.isVisible {
            pinBesideWorkspace(color)
        }
    }

    private static func presentWhenAnchored(_ panel: NSPanel, attempt: Int) {
        NSApp.keyWindow?.displayIfNeeded()
        let burn = BurnPanelAnchorStore.shared
        let main = WorkspaceMainAnchorStore.shared
        if main.isValid || burn.isValid {
            pinBesideWorkspace(panel)
            panel.orderFront(nil)
            for delay in [0.03, 0.08, 0.15, 0.25] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    pinBesideWorkspace(panel)
                }
            }
            return
        }
        if attempt < 40 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                presentWhenAnchored(panel, attempt: attempt + 1)
            }
            return
        }
        pinBesideWorkspace(panel)
        panel.orderFront(nil)
    }

    /// Font: chiều cao = cột preview+sub; mép phải = mép phải preview/sub.
    /// Màu: sát cùng mép phải, mép trên theo burn.
    private static func pinBesideWorkspace(_ panel: NSPanel) {
        let burn = BurnPanelAnchorStore.shared
        let main = WorkspaceMainAnchorStore.shared

        let burnLeftX = burn.leftX
        let burnTopY = burn.topY > 0 ? burn.topY : (burn.bottomY + burn.panelHeight)
        let burnBottomY = burn.bottomY

        panel.layoutIfNeeded()

        if let placed = SystemPanelLayoutStore.layout(
            for: panel,
            burnLeftX: burnLeftX > 0 ? burnLeftX : main.rightX,
            burnTopY: burnTopY > 0 ? burnTopY : main.topY,
            burnBottomY: burnBottomY > 0 ? burnBottomY : main.bottomY,
            burnButtonCenterX: burn.burnButtonCenterX,
            burnPanelWidth: burn.panelWidth
        ) {
            panel.setFrame(placed, display: true, animate: false)
            return
        }

        if main.isValid, panel is NSFontPanel {
            let frame = SystemPanelLayoutStore.fontPanelFrameMatchingWorkspace(
                mainRightX: main.rightX,
                mainTopY: main.topY,
                mainBottomY: main.bottomY,
                preferredWidth: preferredSize(for: panel).width
            )
            panel.setFrame(frame, display: true, animate: false)
            return
        }

        let size = preferredSize(for: panel)
        if burnLeftX > 0, burnTopY > burnBottomY {
            let frame = SystemPanelLayoutStore.panelFrameTopAligned(
                burnLeftX: burnLeftX,
                burnTopY: burnTopY,
                width: size.width,
                height: size.height
            )
            panel.setFrame(frame, display: true, animate: false)
            return
        }

        fallbackBottomRight(panel)
    }

    private static func preferredSize(for panel: NSPanel) -> NSSize {
        let preset = SystemPanelLayoutStore.referencePreset
        if panel is NSFontPanel, let font = preset.font {
            return NSSize(width: font.width, height: font.height)
        }
        if panel is NSColorPanel, let color = preset.color {
            return NSSize(width: color.width, height: color.height)
        }
        if panel is NSFontPanel {
            return NSSize(width: 454, height: 931)
        }
        if panel is NSColorPanel {
            return NSSize(width: 232, height: 290)
        }
        let current = panel.frame.size
        return NSSize(
            width: max(current.width, 220),
            height: max(current.height, 260)
        )
    }

    private static func fallbackBottomRight(_ panel: NSPanel) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        panel.layoutIfNeeded()
        var frame = panel.frame
        frame.size = preferredSize(for: panel)
        let host = window.frame
        frame.origin.x = host.maxX - frame.width - 14
        frame.origin.y = host.minY + 14
        panel.setFrame(frame, display: true, animate: false)
    }

    static func dismissColorPanel() {
        LocalColorPanelSession.shared.close()
    }

    static func dismissFontPanel() {
        NSFontPanel.shared.orderOut(nil)
    }
}
