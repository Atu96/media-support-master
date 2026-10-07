import AppKit
import SwiftUI

/// NSTextView hai chiều — Cmd+C / Cmd+V hoạt động native khi focus.
struct AppNSTextArea: NSViewRepresentable {
    @Binding var text: String
    var fontSize: CGFloat = 13

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
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
        textView.usesFindBar = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = NSFont.systemFont(ofSize: fontSize)
        textView.textColor = NSColor.labelColor
        textView.backgroundColor = .clear
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.string = text
        // Cho phép Cmd+C/V khi focus (cần kèm Edit menu First Responder).
        textView.allowsCharacterPickerTouchBarItem = false
        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if !context.coordinator.isEditing, textView.string != text {
            textView.string = text
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        weak var textView: NSTextView?
        var isEditing = false

        init(text: Binding<String>) {
            _text = text
        }

        func textDidBeginEditing(_ notification: Notification) {
            isEditing = true
        }

        func textDidChange(_ notification: Notification) {
            isEditing = true
            if let textView {
                text = textView.string
            }
        }

        func textDidEndEditing(_ notification: Notification) {
            isEditing = false
            if let textView {
                text = textView.string
            }
        }
    }
}
