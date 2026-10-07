import AppKit
import SwiftUI

/// NSTextView native — liveChange → preview; commit khi rời dòng.
struct SubtitleNSTextEditor: NSViewRepresentable {
    let initialText: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void
    var onLiveChange: ((String) -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(
            initialText: initialText,
            onCommit: onCommit,
            onCancel: onCancel,
            onLiveChange: onLiveChange
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        // Giữ cuộn trackpad/chuột, không hiện scrollbar nặng trên glass UI.
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false

        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.string = initialText
        context.coordinator.textView = textView
        context.coordinator.onLiveChange = onLiveChange

        DispatchQueue.main.async {
            textView.window?.makeFirstResponder(textView)
        }

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.onLiveChange = onLiveChange
        if !context.coordinator.isEditing, textView.string != initialText {
            textView.string = initialText
        }
    }

    static func dismantleNSView(_ scrollView: NSScrollView, coordinator: Coordinator) {
        coordinator.commitIfNeeded()
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        let initialText: String
        let onCommit: (String) -> Void
        let onCancel: () -> Void
        var onLiveChange: ((String) -> Void)?
        weak var textView: NSTextView?
        var isEditing = false
        var skipCommit = false
        private var didCommit = false

        init(
            initialText: String,
            onCommit: @escaping (String) -> Void,
            onCancel: @escaping () -> Void,
            onLiveChange: ((String) -> Void)?
        ) {
            self.initialText = initialText
            self.onCommit = onCommit
            self.onCancel = onCancel
            self.onLiveChange = onLiveChange
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
            didCommit = false
            if let textView {
                onLiveChange?(textView.string)
            }
        }

        func textDidChange(_ notification: Notification) {
            isEditing = true
            if let textView {
                onLiveChange?(textView.string)
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            commitIfNeeded()
        }

        func commitIfNeeded() {
            guard !skipCommit, !didCommit, let textView else { return }
            didCommit = true
            onCommit(textView.string)
        }

        func cancelEditing() {
            skipCommit = true
            didCommit = true
            textView?.string = initialText
            textView?.window?.makeFirstResponder(nil)
            onCancel()
        }

        func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
                cancelEditing()
                return true
            }
            let standardEdit: [Selector] = [
                #selector(NSText.copy(_:)),
                #selector(NSText.cut(_:)),
                #selector(NSText.paste(_:)),
                #selector(NSText.selectAll(_:)),
                Selector(("undo:")),
                Selector(("redo:")),
            ]
            if standardEdit.contains(commandSelector) {
                return false
            }
            return false
        }
    }
}
