import AppKit
import SwiftUI

/// Panel phải — font/màu/burn + chữ/dòng (rule tạo sub & ngắt từng cue).
struct SubtitleBurnSlideContent: View {
    @ObservedObject var viewModel: SubtitleViewModel
    /// Inspector Timeline đã có header cố định riêng; không vẽ lại để panel không nhảy.
    var showsHeader = true
    /// Timeline đưa thao tác xuất lên header chung; các workspace độc lập vẫn có thể hiện nút cũ.
    var showsExportControls = true

    var body: some View {
        VStack(spacing: 0) {
            if showsHeader {
                SubtitleBurnStylePanelHeader()
                    .padding(.horizontal, 22)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Divider().opacity(0.42)
            }

            GeometryReader { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        SubtitleBurnStylePanel(
                            style: $viewModel.burnStyle,
                            maxCharsPerLine: displayedMaxCharsBinding,
                            maxLines: maxLinesBinding,
                            onAutoMaxChars: applyAutomaticMaxChars,
                            canBurn: viewModel.canBurnSubtitles,
                            isRunning: viewModel.isBurningSubtitles,
                            onBurn: { viewModel.burnSubtitlesIntoVideo() },
                            isApplyingLayout: viewModel.isApplyingTranscriptLayout,
                            showsHeader: false,
                            showsExportControls: showsExportControls
                        )
                        .onChange(of: viewModel.burnStyle) { _, _ in
                            if viewModel.mediaURL != nil {
                                viewModel.persistProjectSession()
                            }
                        }
                        // Cỡ chữ lớn → ngân sách dòng hẹp → wrap lại toàn bộ cue.
                        .onChange(of: viewModel.burnStyle.fontSize) { _, _ in
                            viewModel.applyTranscriptLayoutToAllSegments(recordUndo: true)
                        }
                    }
                    .padding(12)
                    HiddenNativeScrollerConfigurator()
                        .frame(width: 1, height: 1)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AppTileSurface())
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
    }

    /// Ô UI luôn hiển thị ngân sách thực ở cỡ chữ hiện hành. Model vẫn lưu base
    /// 54pt để đổi font sau đó còn có thể rewrap đúng, không bị scale hai lần.
    private var displayedMaxCharsBinding: Binding<Int> {
        Binding(
            get: {
                SubtitleWrapStyle.effectiveMaxCharsPerLine(
                    base: viewModel.wrapStyle.maxCharsPerLine,
                    fontSize: viewModel.burnStyle.fontSize
                )
            },
            set: { newValue in
                var w = viewModel.wrapStyle
                w.maxCharsPerLine = SubtitleWrapStyle.baseMaxCharsPerLine(
                    displayed: newValue,
                    fontSize: viewModel.burnStyle.fontSize
                )
                viewModel.wrapStyle = w.clamped()
                viewModel.wrapStyle.save()
                // Đổi chữ/dòng → đặt layout và tách cue cục bộ, không dùng API.
                viewModel.applyTranscriptLayoutToAllSegments(recordUndo: true)
            }
        )
    }

    private var maxLinesBinding: Binding<Int> {
        Binding(
            get: { viewModel.wrapStyle.maxLines },
            set: { newValue in
                var w = viewModel.wrapStyle
                w.maxLines = min(2, max(1, newValue))
                viewModel.wrapStyle = w.clamped()
                viewModel.wrapStyle.save()
                // Đổi 1/2 dòng sau khi đã có SRT không gọi lại API: layout/tách cue chạy local.
                viewModel.applyTranscriptLayoutToAllSegments(recordUndo: true)
            }
        )
    }

    private func applyAutomaticMaxChars() {
        let value = SubtitleWrapStyle.recommendedMaxCharsPerLine(
            languageCode: viewModel.resolvedSubtitleLanguageCode(),
            fontSize: viewModel.burnStyle.fontSize
        )
        displayedMaxCharsBinding.wrappedValue = value
    }
}

/// Ẩn hẳn NSScroller nhưng không tắt wheel/trackpad scrolling của NSScrollView.
struct HiddenNativeScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = ScrollProbeView(frame: .zero)
        view.onAttach = { hideScroller(from: $0) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        hideScroller(from: nsView)
    }

    private func hideScroller(from view: NSView) {
        // Probe nằm trong content của ScrollView này; tìm trực tiếp ancestor để
        // không vô tình sửa scroll view khác của cửa sổ và không lệch theo layout.
        var node: NSView? = view
        while let current = node {
            if let scroll = current as? NSScrollView {
                scroll.scrollerStyle = .overlay
                scroll.autohidesScrollers = true
                scroll.hasVerticalScroller = false
                scroll.verticalScroller?.isHidden = true
                return
            }
            node = current.superview
        }
    }
}

private final class ScrollProbeView: NSView {
    var onAttach: ((NSView) -> Void)?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.onAttach?(self)
        }
    }
}
