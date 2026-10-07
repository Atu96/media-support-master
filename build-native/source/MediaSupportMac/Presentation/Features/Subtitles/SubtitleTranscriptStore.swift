import Foundation

/// Trọng tâm chỉnh transcript: undo/redo + apply segments + wrap text.
///
/// `SubtitleViewModel` giữ `@Published segments` (façade UI) và ủy quyền
/// mọi mutate qua store này — tránh logic edit rải rác / God-object phình thêm.
///
/// Timeline sau này: chỉ gọi `SRTSegmentEditor.move/trim*` rồi `apply`.
@MainActor
final class SubtitleTranscriptStore {
    private let history = SubtitleEditHistory()

    private(set) var canUndo = false
    private(set) var canRedo = false

    // MARK: - History

    func resetHistory() {
        history.reset()
        syncFlags()
    }

    /// Ghi undo (tuỳ chọn) rồi trả về `updated` — caller gán vào `@Published segments`.
    func apply(_ updated: [SRTSegment], current: [SRTSegment], recordUndo: Bool = true) -> [SRTSegment] {
        if recordUndo {
            history.record(before: current)
        }
        // History chạy đồng bộ trên MainActor nên flags có hiệu lực ngay trong action.
        syncFlags()
        return updated
    }

    func undo(current: [SRTSegment]) -> [SRTSegment]? {
        guard let restored = history.undo(current: current) else { return nil }
        syncFlags()
        return restored
    }

    func redo(current: [SRTSegment]) -> [SRTSegment]? {
        guard let restored = history.redo(current: current) else { return nil }
        syncFlags()
        return restored
    }

    private func syncFlags() {
        canUndo = history.canUndo
        canRedo = history.canRedo
    }

    // MARK: - Text + wrap

    /// Auto-wrap 1 chuỗi theo style + cỡ chữ (font lớn → siết effective max).
    func autoWrapText(_ raw: String, wrapStyle: SubtitleWrapStyle, fontSize: Int) -> String {
        let style = wrapStyle.clamped()
        return SubtitleWrapStyle.wrapText(
            raw,
            style: style,
            forceTwoLines: false,
            fontSize: fontSize
        )
    }

    /// Cập nhật text 1 cue. Enter là quyết định biên tập nên không auto-wrap lại
    /// khi focus rời editor; engine/QC chỉ đo và cảnh báo phần không vừa.
    func updatingText(
        in segments: [SRTSegment],
        id: Int,
        text: String,
        wrapStyle: SubtitleWrapStyle,
        fontSize: Int
    ) -> [SRTSegment]? {
        guard let idx = segments.firstIndex(where: { $0.id == id }) else { return nil }
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: .whitespaces)
        guard segments[idx].text != normalized else { return nil }
        var updated = segments
        updated[idx] = SRTSegmentEditor.withText(segments[idx], text: normalized)
        return updated
    }

    /// Áp wrap lại toàn bộ; `nil` = không cue nào đổi.
    func rewrappingAll(
        _ segments: [SRTSegment],
        wrapStyle: SubtitleWrapStyle,
        fontSize: Int
    ) -> [SRTSegment]? {
        guard !segments.isEmpty else { return nil }
        var any = false
        let updated: [SRTSegment] = segments.map { seg in
            let w = autoWrapText(seg.text, wrapStyle: wrapStyle, fontSize: fontSize)
            if w != seg.text { any = true }
            return SRTSegmentEditor.withText(seg, text: w)
        }
        return any ? updated : nil
    }

    // MARK: - Structural edit (ủy SRTSegmentEditor)

    func merging(
        _ segments: [SRTSegment],
        ids: Set<Int>,
        wrapStyle: SubtitleWrapStyle,
        fontSize: Int
    ) -> [SRTSegment]? {
        guard var merged = SRTSegmentEditor.mergeAdjacent(in: segments, ids: ids),
              let firstSelectedIndex = segments.firstIndex(where: { ids.contains($0.id) }),
              merged.indices.contains(firstSelectedIndex) else { return nil }
        let cue = merged[firstSelectedIndex]
        let wrappedText = autoWrapText(cue.text, wrapStyle: wrapStyle, fontSize: fontSize)
        merged[firstSelectedIndex] = SRTSegmentEditor.withText(cue, text: wrappedText)
        return merged
    }

    func splitting(_ segments: [SRTSegment], id: Int, languageCode: String) -> [SRTSegment]? {
        SRTSegmentEditor.split(in: segments, id: id, languageCode: languageCode)
    }

    func deleting(_ segments: [SRTSegment], id: Int) -> [SRTSegment]? {
        SRTSegmentEditor.delete(in: segments, id: id)
    }

    func deleting(_ segments: [SRTSegment], ids: Set<Int>) -> [SRTSegment]? {
        SRTSegmentEditor.delete(in: segments, ids: ids)
    }

    // MARK: - Timing (móng timeline — chưa gắn UI)

    func moving(_ segments: [SRTSegment], id: Int, delta: Double) -> [SRTSegment]? {
        SRTSegmentEditor.move(in: segments, id: id, delta: delta)
    }

    func trimmingStart(_ segments: [SRTSegment], id: Int, newStart: Double) -> [SRTSegment]? {
        SRTSegmentEditor.trimStart(in: segments, id: id, newStart: newStart)
    }

    func trimmingEnd(_ segments: [SRTSegment], id: Int, newEnd: Double) -> [SRTSegment]? {
        SRTSegmentEditor.trimEnd(in: segments, id: id, newEnd: newEnd)
    }
}
