import SwiftUI

/// Shell layout chung 2 tab Tạo sub — chessboard + slide Kiểu sub + dock.
/// Chỉ slot nội dung khác nhau; keys layout giữ nguyên checkpoint 2026-07-07.
struct SubtitleCreateWorkspaceShell<TopLeft: View, BottomLeft: View, Preview: View, Transcript: View, Log: View>: View {
    @ObservedObject var viewModel: SubtitleViewModel

    @ViewBuilder var topLeftSlot: (_ rowHeight: CGFloat) -> TopLeft
    @ViewBuilder var bottomLeftSlot: (_ rowHeight: CGFloat) -> BottomLeft
    @ViewBuilder var previewSlot: (_ rowHeight: CGFloat) -> Preview
    @ViewBuilder var transcriptSlot: (_ rowHeight: CGFloat) -> Transcript
    @ViewBuilder var logSlot: () -> Log

    @State private var leftColumnWidth: CGFloat = SubtitleWorkspaceStorage.defaultLeftColumnWidth
    @AppStorage("msm.subtitle.editSlideOpen") private var editSlideOpen = true
    @State private var editSlideWidth: CGFloat = SubtitleWorkspaceStorage.defaultBurnSlideWidth

    private var bottomBarH: CGFloat { AppTheme.dockBarHeight }

    var body: some View {
        GeometryReader { geometry in
            let h = geometry.size.height

            ZStack(alignment: .bottomLeading) {
                WorkspaceRightSlidePanel(
                    isOpen: $editSlideOpen,
                    panelWidth: $editSlideWidth,
                    storageKey: "msm.subtitle.burnSlide",
                    railTitle: "Kiểu sub",
                    railIcon: "character.textbox",
                    isEnabled: true,
                    defaultPanelWidth: SubtitleWorkspaceStorage.defaultBurnSlideWidth
                ) {
                    WorkspaceResizableChessboard(
                        storageKey: SubtitleWorkspaceStorage.chessboardKey,
                        leftColumnWidth: $leftColumnWidth,
                        // Card Import có thêm hàng SRT + nút Đổi SRT; không cho kéo thấp tới mức cắt action.
                        minCellHeight: 196,
                        defaultLeftWidth: SubtitleWorkspaceStorage.defaultLeftColumnWidth,
                        defaultTopRowRatio: SubtitleWorkspaceStorage.defaultTopRowRatio
                    ) { metrics in
                        topLeftSlot(metrics.topRowHeight)
                    } topRight: { metrics in
                        previewSlot(metrics.topRowHeight)
                    } bottomLeft: { metrics in
                        bottomLeftSlot(metrics.bottomRowHeight)
                    } bottomRight: { metrics in
                        transcriptSlot(metrics.bottomRowHeight)
                    }
                    .frame(height: h - bottomBarH)
                } panel: {
                    SubtitleBurnSlideContent(viewModel: viewModel)
                }
                .padding(.bottom, bottomBarH)
                .frame(width: geometry.size.width, height: h, alignment: .topLeading)

                WorkspaceSplitDock(logWidth: leftColumnWidth) {
                    logSlot()
                }
                .frame(width: geometry.size.width, alignment: .bottom)
            }
        }
        .frame(minHeight: 520)
    }
}
