import AppKit
import SwiftUI

extension Notification.Name {
    /// Main menu mở sheet phím tắt tại đúng Timeline workspace đang hiển thị.
    static let openTimelineShortcutSettings = Notification.Name("msm.openTimelineShortcutSettings")
}

struct TimelineSurface<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppTheme.tileFill)
    }
}

/// Zoom Timeline tự vẽ: đúng một track, không để NSSlider sinh thêm rãnh dưới.
struct TimelineZoomSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)
            let thumb: CGFloat = 16
            // Timeline editor cần cùng một thanh xử lý từ overview rất dài đến
            // chỉnh từng frame. Nội suy tuyến tính làm giá trị fit (thường < 1)
            // dính vào mép trái và trông như zoom-min. Thang log giữ cảm giác
            // zoom đều, còn value vẫn là pixels/second chính xác.
            let lower = max(0.0001, range.lowerBound)
            let upper = max(lower * 1.001, range.upperBound)
            let logSpan = log(upper / lower)
            let progress = min(1, max(0, log(max(lower, min(upper, value)) / lower) / logSpan))
            let thumbX = max(0, min(width - thumb, CGFloat(progress) * width - thumb * 0.5))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(AppTheme.divider.opacity(0.66))
                    .frame(height: 4)
                Capsule()
                    .fill(AppTheme.accentBlue)
                    .frame(width: max(thumb * 0.5, CGFloat(progress) * width), height: 4)
                Circle()
                    .fill(AppTheme.inputFill)
                    .frame(width: thumb, height: thumb)
                    .overlay(Circle().stroke(AppTheme.tileStrokeStrong, lineWidth: AppTheme.controlStrokeWidth))
                    .shadow(color: AppTheme.titleText.opacity(0.14), radius: 2, y: 1)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let fraction = min(1, max(0, gesture.location.x / width))
                        value = lower * exp(logSpan * Double(fraction))
                    }
            )
        }
        .accessibilityLabel("Zoom Timeline")
        .accessibilityValue(Text("\(Int(value.rounded()))"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(range.upperBound, value * 1.12)
            case .decrement: value = max(range.lowerBound, value / 1.12)
            @unknown default: break
            }
        }
    }
}

/// Hover nhẹ giúp icon-only toolbar dễ khám phá mà không làm giao diện chói.
struct TimelineHoverHighlight: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .fill(isHovering ? AppTheme.controlHover : Color.clear)
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}

struct TimelineTabHoverHighlight: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .overlay {
                Rectangle()
                    .fill(isHovering ? AppTheme.controlHover : Color.clear)
                    .allowsHitTesting(false)
            }
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovering)
    }
}

/// Chrome duy nhất cho các nút compact trong control strip. Normal chỉ dùng
/// chênh surface; active/focus mới tăng stroke để workspace không thành lưới hộp.
struct TimelineToolbarButtonStyle: ButtonStyle {
    var isActive = false

    func makeBody(configuration: Configuration) -> some View {
        TimelineToolbarButtonStyleBody(
            label: configuration.label,
            isPressed: configuration.isPressed,
            isActive: isActive
        )
    }
}

private struct TimelineToolbarButtonStyleBody<Label: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool
    @State private var isHovering = false

    let label: Label
    let isPressed: Bool
    let isActive: Bool

    var body: some View {
        label
            .background(
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: strokeWidth)
            }
            .contentShape(RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous))
            .opacity(isEnabled ? 1 : 0.38)
            .focusable()
            .focused($isFocused)
            .onHover { isHovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: isHovering)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.08), value: isPressed)
    }

    private var fill: Color {
        if isActive { return AppTheme.editorActiveFill }
        if isPressed { return AppTheme.controlPressed }
        if isHovering { return AppTheme.controlHover }
        return AppTheme.controlFill
    }

    private var stroke: Color {
        if isFocused { return AppTheme.focusRing }
        if isActive { return AppTheme.editorAccent.opacity(0.82) }
        return AppTheme.tileStroke.opacity(0.48)
    }

    private var strokeWidth: CGFloat {
        if isFocused { return 1.5 }
        if isActive { return AppTheme.selectedStrokeWidth }
        return AppTheme.hairlineWidth
    }
}

struct SubtitleTimelineViewportWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Ẩn riêng NSScroller ngang do AppKit dựng; clip view và cuộn trackpad vẫn nguyên.
struct TimelineHorizontalScrollerHider: NSViewRepresentable {
    var onScrollViewReady: (NSScrollView) -> Void = { _ in }

    func makeNSView(context: Context) -> TimelineScrollerProbe {
        let probe = TimelineScrollerProbe()
        probe.onWindowAttached = { attachedProbe in
            hideScroller(containing: attachedProbe)
        }
        return probe
    }

    func updateNSView(_ probe: TimelineScrollerProbe, context: Context) {
        hideScroller(containing: probe)
    }

    private func hideScroller(containing probe: TimelineScrollerProbe) {
        DispatchQueue.main.async {
            guard let window = probe.window, let root = window.contentView else { return }
            let pointInWindow = probe.convert(NSPoint(x: 0.5, y: 0.5), to: nil)
            for scrollView in scrollViews(in: root) {
                let rectInWindow = scrollView.convert(scrollView.bounds, to: nil)
                guard rectInWindow.contains(pointInWindow) else { continue }
                scrollView.scrollerStyle = .overlay
                scrollView.autohidesScrollers = true
                scrollView.hasHorizontalScroller = false
                scrollView.horizontalScroller?.isHidden = true
                onScrollViewReady(scrollView)
                break
            }
        }
    }

    private func scrollViews(in view: NSView) -> [NSScrollView] {
        let current = (view as? NSScrollView).map { [$0] } ?? []
        return current + view.subviews.flatMap(scrollViews(in:))
    }
}

final class TimelineScrollerProbe: NSView {
    var onWindowAttached: ((TimelineScrollerProbe) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        onWindowAttached?(self)
    }
}

struct TimelineRuler: View, Equatable {
    let duration: Double
    let pixelsPerSecond: Double
    let width: CGFloat

    private var minorStep: Double {
        switch pixelsPerSecond {
        case let value where value > 90: return 1
        case let value where value > 35: return 5
        case let value where value > 8: return 10
        case let value where value > 2: return 30
        default: return 60
        }
    }

    var body: some View {
        Canvas { context, _ in
            let majorStep = minorStep * 5
            var time = 0.0
            while time <= duration {
                let x = CGFloat(time * pixelsPerSecond)
                let isMajor = time.truncatingRemainder(dividingBy: majorStep) == 0
                var path = Path()
                path.move(to: CGPoint(x: x, y: 17))
                path.addLine(to: CGPoint(x: x, y: isMajor ? 2 : 10))
                context.stroke(path, with: .color(AppTheme.divider), lineWidth: AppTheme.hairlineWidth)
                if isMajor {
                    context.draw(
                        Text(String(format: "%02d:%02d", Int(time) / 60, Int(time) % 60))
                            .font(AppFont.editorMicro)
                            .foregroundStyle(AppTheme.mutedText),
                        at: CGPoint(x: x + 3, y: 8),
                        anchor: .leading
                    )
                }
                time += minorStep
            }
        }
        .frame(width: width, height: 28)
        .background(AppTheme.timelineRulerFill)
    }
}

struct SubtitleTimelineTextEditor: View {
    let cue: SRTSegment
    let onSave: (String) -> Void
    let onFinish: () -> Void
    @State private var text = ""
    @State private var committedText = ""
    @FocusState private var isFocused: Bool

    private var editorHeight: CGFloat {
        let estimatedLines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { partial, line in partial + max(1, Int(ceil(Double(line.count) / 34))) }
        return min(220, max(58, CGFloat(estimatedLines) * 21 + 16))
    }

    private func saveIfNeeded() {
        guard text != committedText else { return }
        committedText = text
        onSave(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(cue.startLabel)
                    .font(AppFont.editorTimecode)
                    .monospacedDigit()
                    .foregroundStyle(AppTheme.accentBlue)
                Text(L10n.format("Sửa cue %@ · bấm ra ngoài để lưu", String(cue.index)))
                    .font(AppFont.editorLabel)
                    .foregroundStyle(AppTheme.headlineText)
            }
            TextEditor(text: $text)
                .font(AppFont.label)
                .focused($isFocused)
                .frame(height: editorHeight)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(AppFieldSurface(radius: AppTheme.editorControlRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: AppTheme.editorControlRadius, style: .continuous)
                        .strokeBorder(isFocused ? AppTheme.focusRing : Color.clear, lineWidth: isFocused ? 1.5 : 0)
                }
                .accessibilityLabel(L10n.format("Nội dung cue %@", String(cue.index)))
                .onChange(of: isFocused) { _, focused in
                    if !focused { saveIfNeeded(); onFinish() }
                }
        }
        .onAppear {
            text = cue.text
            committedText = cue.text
            DispatchQueue.main.async { isFocused = true }
        }
        .onChange(of: cue.id) { _, _ in
            text = cue.text
            committedText = cue.text
            isFocused = true
        }
        .onDisappear { saveIfNeeded() }
    }
}

struct SubtitleScriptComposer: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Tạo sub từ văn bản")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)
            Picker("Ngôn ngữ", selection: $viewModel.scriptAlignmentLanguage) {
                ForEach(ScriptAlignmentLanguage.allCases) { Text(L10n.string($0.label)).tag($0) }
            }
            TextEditor(text: $viewModel.scriptText)
                .font(AppFont.body)
                .frame(minHeight: 240)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(AppFieldSurface(radius: AppTheme.editorFieldRadius))
                .accessibilityLabel("Văn bản dùng để tạo phụ đề")
            HStack {
                Spacer()
                Button("Hủy") { dismiss() }
                Button("Tạo sub") { viewModel.runScriptAlign(); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!viewModel.canRunScriptAlign)
            }
        }
        .padding(20)
        .frame(width: 520, height: 400)
        .background(AppShellGradient())
    }
}

struct SubtitleTimelineStyleSheet: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Kiểu phụ đề")
                    .font(AppFont.sectionTitle)
                    .foregroundStyle(AppTheme.headlineText)
                Spacer()
                Button("Xong") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            Rectangle().fill(AppTheme.divider).frame(height: AppTheme.hairlineWidth)
            SubtitleBurnSlideContent(viewModel: viewModel)
        }
        .frame(width: 420, height: 680)
        .background(AppShellGradient())
    }
}

struct TimelineShortcutSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("msm.timeline.shortcut.play") private var play = "space"
    @AppStorage("msm.timeline.shortcut.back") private var back = "j"
    @AppStorage("msm.timeline.shortcut.forward") private var forward = "l"
    @AppStorage("msm.timeline.shortcut.skim") private var skim = "s"
    @AppStorage("msm.timeline.shortcut.split") private var split = "x"
    @AppStorage("msm.timeline.shortcut.merge") private var merge = "g"
    @AppStorage("msm.timeline.shortcut.trimLeft") private var trimLeft = "option+left"
    @AppStorage("msm.timeline.shortcut.trimRight") private var trimRight = "option+right"
    @AppStorage("msm.timeline.shortcut.zoomIn") private var zoomIn = "command+plus"
    @AppStorage("msm.timeline.shortcut.zoomOut") private var zoomOut = "command+minus"
    @AppStorage("msm.timeline.shortcut.zoomFit") private var zoomFit = "shift+z"
    @AppStorage("msm.timeline.shortcut.selectAll") private var selectAll = "command+a"
    @AppStorage("msm.timeline.shortcut.delete") private var delete = "delete"
    @AppStorage("msm.timeline.shortcut.undo") private var undo = "command+z"
    @AppStorage("msm.timeline.shortcut.redo") private var redo = "command+shift+z"

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Phím tắt Timeline")
                .font(AppFont.sectionTitle)
                .foregroundStyle(AppTheme.headlineText)
            shortcutField("Phát / dừng", $play)
            shortcutField("Lùi một frame", $back)
            shortcutField("Tới một frame", $forward)
            shortcutField("Bật / tắt skimming", $skim)
            shortcutField("Xóa trái tại Skim / playhead", $trimLeft)
            shortcutField("Xóa phải tại Skim / playhead", $trimRight)
            shortcutField("Cắt cue đang chọn", $split)
            shortcutField("Gộp các cue liền kề", $merge)
            Rectangle().fill(AppTheme.divider).frame(height: AppTheme.hairlineWidth)
            shortcutField("Phóng to Timeline", $zoomIn)
            shortcutField("Thu nhỏ Timeline", $zoomOut)
            shortcutField("Xem toàn cảnh audio", $zoomFit)
            shortcutField("Chọn tất cả cue", $selectAll)
            shortcutField("Xóa cue đã chọn", $delete)
            shortcutField("Hoàn tác", $undo)
            shortcutField("Làm lại", $redo)
            Text("Bấm vào một ô rồi nhấn phím hoặc tổ hợp muốn gán. Command-click và Shift-click vẫn là thao tác chuột để chọn nhiều cue. Khi đang gõ nội dung cue, phím tắt Timeline tạm nhường cho văn bản.")
                .font(AppFont.caption)
                .foregroundStyle(AppTheme.mutedText)
            HStack {
                Button("Khôi phục mặc định") {
                    play = "space"; back = "j"; forward = "l"
                    skim = "s"; trimLeft = "option+left"; trimRight = "option+right"; split = "x"; merge = "g"
                    zoomIn = "command+plus"; zoomOut = "command+minus"; zoomFit = "shift+z"
                    selectAll = "command+a"; delete = "delete"
                    undo = "command+z"; redo = "command+shift+z"
                }
                Spacer()
                Button("Xong") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 430)
        .background(AppShellGradient())
    }

    private func shortcutField(_ label: String, _ value: Binding<String>) -> some View {
        HStack {
            Text(L10n.string(label))
                .font(AppFont.body)
                .foregroundStyle(AppTheme.bodyText)
            Spacer()
            TimelineShortcutRecorder(value: value)
                .frame(width: 128, height: 30)
                .accessibilityLabel(L10n.string(label))
        }
    }
}

/// Chuẩn lưu phím tắt dùng chung giữa recorder và local key monitor.
/// Ví dụ: `command+plus`, `command+shift+z`, `space`, `delete`.
struct TimelineShortcutSpec {
    static func matches(_ event: NSEvent, stored: String, fallback: String) -> Bool {
        storageString(for: event) == normalized(stored.isEmpty ? fallback : stored)
    }

    static func storageString(for event: NSEvent) -> String {
        var modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let key: String
        switch event.keyCode {
        case 24:
            key = "plus"
            // Trên nhiều layout, dấu + cần Shift với phím =; Shift này thuộc ký tự,
            // không phải modifier người dùng muốn gán riêng.
            modifiers.remove(.shift)
        case 27: key = "minus"
        case 49: key = "space"
        case 51, 117: key = "delete"
        case 53: key = "escape"
        default:
            key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        }

        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("control") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("command") }
        if !key.isEmpty { parts.append(key) }
        return parts.joined(separator: "+")
    }

    static func normalized(_ raw: String) -> String {
        raw.lowercased()
            .replacingOccurrences(of: "⌘", with: "command+")
            .replacingOccurrences(of: "⇧", with: "shift+")
            .replacingOccurrences(of: "⌥", with: "option+")
            .replacingOccurrences(of: "⌃", with: "control+")
            .replacingOccurrences(of: "cmd", with: "command")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "++", with: "+plus")
            .replacingOccurrences(of: "+-", with: "+minus")
    }

    static func displayName(_ raw: String) -> String {
        let parts = normalized(raw).split(separator: "+").map(String.init)
        var result = ""
        for part in parts {
            switch part {
            case "control": result += "⌃"
            case "option": result += "⌥"
            case "shift": result += "⇧"
            case "command": result += "⌘"
            case "plus": result += "+"
            case "minus": result += "−"
            case "space": result += "Space"
            case "delete": result += "⌫"
            case "escape": result += "Esc"
            default: result += part.uppercased()
            }
        }
        return result.isEmpty ? "Bấm để gán" : result
    }
}

private struct TimelineShortcutRecorder: NSViewRepresentable {
    @Binding var value: String

    func makeCoordinator() -> Coordinator { Coordinator(value: $value) }

    func makeNSView(context: Context) -> TimelineShortcutRecorderNSView {
        let view = TimelineShortcutRecorderNSView()
        view.onChange = { context.coordinator.value.wrappedValue = $0 }
        view.storedValue = value
        return view
    }

    func updateNSView(_ view: TimelineShortcutRecorderNSView, context: Context) {
        context.coordinator.value = $value
        view.storedValue = value
        view.needsDisplay = true
    }

    final class Coordinator {
        var value: Binding<String>
        init(value: Binding<String>) { self.value = value }
    }
}

private final class TimelineShortcutRecorderNSView: NSView {
    var storedValue = "" { didSet { needsDisplay = true } }
    var onChange: ((String) -> Void)?
    private var isRecording = false { didSet { needsDisplay = true } }

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        isRecording = true
    }

    override func resignFirstResponder() -> Bool {
        isRecording = false
        return super.resignFirstResponder()
    }

    override func keyDown(with event: NSEvent) { record(event) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self else { return false }
        record(event)
        return true
    }

    private func record(_ event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }
        let next = TimelineShortcutSpec.storageString(for: event)
        guard !next.isEmpty else { return }
        storedValue = next
        onChange?(next)
        window?.makeFirstResponder(nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        let shape = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 7, yRadius: 7)
        (isRecording ? NSColor.controlAccentColor.withAlphaComponent(0.18) : NSColor.controlBackgroundColor.withAlphaComponent(0.72)).setFill()
        shape.fill()
        (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).setStroke()
        shape.lineWidth = isRecording ? 1.6 : 1
        shape.stroke()

        let title = isRecording ? "Nhấn tổ hợp…" : TimelineShortcutSpec.displayName(storedValue)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .foregroundColor: isRecording ? NSColor.controlAccentColor : NSColor.labelColor
        ]
        let size = (title as NSString).size(withAttributes: attributes)
        (title as NSString).draw(
            at: NSPoint(x: max(8, (bounds.width - size.width) * 0.5), y: (bounds.height - size.height) * 0.5),
            withAttributes: attributes
        )
    }
}

/// Vùng trống của thanh trên: kéo cửa sổ như Final Cut, double-click để zoom.
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> WindowDragHandleView { WindowDragHandleView() }
    func updateNSView(_ nsView: WindowDragHandleView, context: Context) {}
}

final class WindowDragHandleView: NSView {
    private var initialMouseLocation = NSPoint.zero
    private var initialWindowOrigin = NSPoint.zero

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        if event.clickCount == 2 {
            window.performZoom(nil)
        } else {
            initialMouseLocation = NSEvent.mouseLocation
            initialWindowOrigin = window.frame.origin
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window else { return }
        let location = NSEvent.mouseLocation
        window.setFrameOrigin(NSPoint(
            x: initialWindowOrigin.x + location.x - initialMouseLocation.x,
            y: initialWindowOrigin.y + location.y - initialMouseLocation.y
        ))
    }
}
