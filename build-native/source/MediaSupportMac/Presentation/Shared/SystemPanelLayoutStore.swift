import AppKit
import Foundation

/// Vị trí panel hệ thống — width ưu tiên; height font runtime = chiều cao cột preview+sub.
struct SystemPanelLayoutPreset: Codable, Equatable {
    struct PanelLayout: Codable, Equatable {
        var offsetX: CGFloat
        var offsetY: CGFloat
        var width: CGFloat
        var height: CGFloat
    }

    var font: PanelLayout?
    var color: PanelLayout?
}

@MainActor
enum SystemPanelLayoutStore {
    static let storageKey = "msm.systemPanelLayout"

    /// Gap giữa mép phải panel font và mép phải khung preview/sub (mép trái slide Kiểu sub).
    static let sideGap: CGFloat = 0

    /// Width font 454 — height runtime khớp cột workspace (preview + sub).
    static let referencePreset = SystemPanelLayoutPreset(
        font: .init(offsetX: -454, offsetY: 0, width: 454, height: 931),
        color: .init(offsetX: -232, offsetY: 0, width: 232, height: 290)
    )

    static func applyReferencePreset(force: Bool = true) {
        if !force, load() != nil { return }
        save(referencePreset)
        writeSupportFile(referencePreset)
    }

    private static func writeSupportFile(_ preset: SystemPanelLayoutPreset) {
        let fileURL = supportDirectory().appendingPathComponent("panel-layout.json")
        if let data = try? JSONEncoder().encode(preset) {
            try? FileManager.default.createDirectory(at: supportDirectory(), withIntermediateDirectories: true)
            try? data.write(to: fileURL)
        }
    }

    /// Font: mép phải = mép phải preview/sub; mép trên/dưới = top/bottom cột workspace.
    static func fontPanelFrameMatchingWorkspace(
        mainRightX: CGFloat,
        mainTopY: CGFloat,
        mainBottomY: CGFloat,
        preferredWidth: CGFloat
    ) -> NSRect {
        let height = max(120, mainTopY - mainBottomY)
        let width = preferredWidth > 0 ? preferredWidth : 454
        let frame = NSRect(
            x: mainRightX - sideGap - width,
            y: mainBottomY,
            width: width,
            height: height
        )
        return clampToVisibleScreen(frame)
    }

    /// Màu: mép trên = mép trên burn (hoặc main top); sát mép phải preview/sub; giữ height preset.
    static func colorPanelFrameBesideWorkspace(
        mainRightX: CGFloat,
        burnTopY: CGFloat,
        preferredWidth: CGFloat,
        preferredHeight: CGFloat
    ) -> NSRect {
        let width = preferredWidth > 0 ? preferredWidth : 232
        let height = preferredHeight > 0 ? preferredHeight : 290
        let topY = burnTopY > 0 ? burnTopY : (WorkspaceMainAnchorStore.shared.topY)
        let frame = NSRect(
            x: mainRightX - sideGap - width,
            y: topY - height,
            width: width,
            height: height
        )
        return clampToVisibleScreen(frame)
    }

    /// Fallback cũ: top-align burn, trái burn.
    static func panelFrameTopAligned(
        burnLeftX: CGFloat,
        burnTopY: CGFloat,
        width: CGFloat,
        height: CGFloat,
        gap: CGFloat = 8
    ) -> NSRect {
        let frame = NSRect(
            x: burnLeftX - width - gap,
            y: burnTopY - height,
            width: width,
            height: height
        )
        return clampToVisibleScreen(frame)
    }

    static func clampToVisibleScreen(_ frame: NSRect) -> NSRect {
        var f = frame
        let screen = NSScreen.screens.first { NSMouseInRect(NSPoint(x: f.midX, y: f.midY), $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let visible = screen?.visibleFrame else { return f }

        if f.width > visible.width - 8 {
            f.size.width = visible.width - 8
        }
        if f.height > visible.height - 8 {
            f.size.height = visible.height - 8
            f.origin.y = visible.minY + 4
        }
        if f.maxX > visible.maxX {
            f.origin.x = visible.maxX - f.width - 4
        }
        if f.minX < visible.minX {
            f.origin.x = visible.minX + 4
        }
        if f.maxY > visible.maxY {
            f.origin.y = visible.maxY - f.height
        }
        if f.minY < visible.minY {
            f.origin.y = visible.minY + 4
        }
        return f
    }

    static func load() -> SystemPanelLayoutPreset? {
        if let data = UserDefaults.standard.data(forKey: storageKey),
           let preset = try? JSONDecoder().decode(SystemPanelLayoutPreset.self, from: data) {
            return preset
        }
        let fileURL = supportDirectory().appendingPathComponent("panel-layout.json")
        guard let data = try? Data(contentsOf: fileURL),
              let preset = try? JSONDecoder().decode(SystemPanelLayoutPreset.self, from: data) else {
            return nil
        }
        return preset
    }

    private static func supportDirectory() -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Media Support Master", isDirectory: true)
    }

    static func save(_ preset: SystemPanelLayoutPreset) {
        guard let data = try? JSONEncoder().encode(preset) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func captureFromCurrentPanels() -> SystemPanelLayoutPreset? {
        let main = WorkspaceMainAnchorStore.shared
        let burn = BurnPanelAnchorStore.shared
        guard main.isValid || burn.isValid else { return nil }

        var preset = SystemPanelLayoutPreset()
        let refX = main.isValid ? main.rightX : burn.leftX
        let refY = main.isValid ? main.bottomY : burn.topY

        let fontPanel = NSFontPanel.shared
        if fontPanel.isVisible {
            let frame = fontPanel.frame
            preset.font = .init(
                offsetX: frame.origin.x - refX,
                offsetY: frame.origin.y - refY,
                width: frame.width,
                height: frame.height
            )
        }

        let colorPanel = NSColorPanel.shared
        if colorPanel.isVisible {
            let frame = colorPanel.frame
            preset.color = .init(
                offsetX: frame.origin.x - refX,
                offsetY: frame.origin.y - refY,
                width: frame.width,
                height: frame.height
            )
        }

        guard preset.font != nil || preset.color != nil else { return nil }
        save(preset)
        writeSupportFile(preset)
        return preset
    }

    static func layout(
        for panel: NSPanel,
        burnLeftX: CGFloat,
        burnTopY: CGFloat,
        burnBottomY: CGFloat,
        burnButtonCenterX: CGFloat,
        burnPanelWidth: CGFloat
    ) -> NSRect? {
        let preset = load() ?? referencePreset
        let main = WorkspaceMainAnchorStore.shared

        if panel is NSFontPanel {
            let width = preset.font?.width ?? referencePreset.font?.width ?? 454
            if main.isValid {
                return fontPanelFrameMatchingWorkspace(
                    mainRightX: main.rightX,
                    mainTopY: main.topY,
                    mainBottomY: main.bottomY,
                    preferredWidth: width
                )
            }
            // Fallback: top-align burn, height preset
            let height = preset.font?.height ?? 931
            return panelFrameTopAligned(
                burnLeftX: burnLeftX,
                burnTopY: burnTopY,
                width: width,
                height: height
            )
        }

        if panel is NSColorPanel {
            let width = preset.color?.width ?? 232
            let height = preset.color?.height ?? 290
            if main.isValid {
                return colorPanelFrameBesideWorkspace(
                    mainRightX: main.rightX,
                    burnTopY: burnTopY > 0 ? burnTopY : main.topY,
                    preferredWidth: width,
                    preferredHeight: height
                )
            }
            return panelFrameTopAligned(
                burnLeftX: burnLeftX,
                burnTopY: burnTopY,
                width: width,
                height: height
            )
        }
        return nil
    }
}
