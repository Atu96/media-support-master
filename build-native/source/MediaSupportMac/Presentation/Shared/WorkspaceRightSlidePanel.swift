import AppKit
import SwiftUI

/// Panel phải kiểu Final Cut — bấm rail để mở; **đẩy** nội dung chính, không phủ lên.
struct WorkspaceRightSlidePanel<Main: View, Panel: View>: View {
    @Binding var isOpen: Bool
    @Binding var panelWidth: CGFloat
    let storageKey: String
    let railTitle: String
    let railIcon: String
    var isEnabled: Bool = true
    var minPanelWidth: CGFloat = 300
    var maxPanelWidth: CGFloat = 520
    var defaultPanelWidth: CGFloat = 360
    var columnGap: CGFloat = AppTheme.workspaceColumnGap

    @ViewBuilder var main: () -> Main
    @ViewBuilder var panel: () -> Panel

    @State private var isDraggingWidth = false
    @State private var dragOriginWidth: CGFloat = 360
    @State private var didLoadLayout = false

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            main()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .layoutPriority(1)
                // Mép phải = mép phải preview + transcript — neo panel font theo chiều cao cột này.
                .background {
                    WorkspaceMainFrameAnchorReporter()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                }

            if isOpen {
                resizeHandle
                    .frame(width: columnGap)

                panel()
                    .frame(width: clampedPanelWidth, alignment: .topLeading)
                    .frame(maxHeight: .infinity, alignment: .topLeading)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .animation(.easeInOut(duration: 0.22), value: isOpen)
        .onAppear { loadLayoutIfNeeded() }
    }

    private var clampedPanelWidth: CGFloat {
        min(max(panelWidth, minPanelWidth), maxPanelWidth)
    }

    private var resizeHandle: some View {
        Color.clear
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                if hovering || isDraggingWidth {
                    NSCursor.resizeLeftRight.set()
                } else {
                    NSCursor.arrow.set()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if !isDraggingWidth {
                            isDraggingWidth = true
                            dragOriginWidth = panelWidth
                            SystemPanelAnchor.setInteractiveResizeInProgress(true)
                        }
                        let proposed = dragOriginWidth - value.translation.width
                        // Cập nhật trực tiếp, không nội suy animation trong lúc kéo.
                        // Nhờ vậy panel bám chuột như splitter của khu Import.
                        var transaction = Transaction()
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            panelWidth = min(max(proposed, minPanelWidth), maxPanelWidth)
                        }
                    }
                    .onEnded { _ in
                        isDraggingWidth = false
                        persistLayout()
                        SystemPanelAnchor.setInteractiveResizeInProgress(false)
                        NSCursor.arrow.set()
                    }
            )
    }

    private func loadLayoutIfNeeded() {
        guard !didLoadLayout else { return }
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "\(storageKey).open") != nil {
            isOpen = defaults.bool(forKey: "\(storageKey).open")
        } else {
            isOpen = true
        }
        if defaults.object(forKey: "\(storageKey).width") != nil {
            panelWidth = CGFloat(defaults.double(forKey: "\(storageKey).width"))
        } else {
            panelWidth = defaultPanelWidth
        }
        panelWidth = clampedPanelWidth
        didLoadLayout = true
    }

    private func persistLayout() {
        let defaults = UserDefaults.standard
        defaults.set(isOpen, forKey: "\(storageKey).open")
        defaults.set(Double(clampedPanelWidth), forKey: "\(storageKey).width")
    }
}
