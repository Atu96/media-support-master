import Foundation

@MainActor
final class SubtitleEditHistory {
    private var undoStack: [[SRTSegment]] = []
    private var redoStack: [[SRTSegment]] = []
    /// Giới hạn vừa đủ cho một phiên chỉnh kỹ nhưng không giữ media/audio.
    /// 36 snapshot cue đủ cho một lượt chỉnh liên tục và giữ RAM ổn định,
    /// kể cả SRT dài nhiều nghìn cue. Qua ngưỡng sẽ bỏ bước cũ nhất.
    static let maximumSnapshots = 36

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    /// Chỉ gọi khi một thao tác đã hoàn tất (thả cue, lưu text, cắt/xóa/gộp).
    /// `Array`/`String` dùng copy-on-write nên giữ snapshot cue đồng bộ trên
    /// MainActor nhẹ hơn và quan trọng là không có race với Cmd Z ngay sau thao tác.
    func record(before snapshot: [SRTSegment]) {
        undoStack.append(snapshot)
        Self.trim(&undoStack)
        redoStack.removeAll(keepingCapacity: true)
    }

    func undo(current: [SRTSegment]) -> [SRTSegment]? {
        guard let previous = undoStack.popLast() else { return nil }
        redoStack.append(current)
        Self.trim(&redoStack)
        return previous
    }

    func redo(current: [SRTSegment]) -> [SRTSegment]? {
        guard let next = redoStack.popLast() else { return nil }
        undoStack.append(current)
        Self.trim(&undoStack)
        return next
    }

    func reset() {
        undoStack.removeAll(keepingCapacity: false)
        redoStack.removeAll(keepingCapacity: false)
    }

    private static func trim(_ stack: inout [[SRTSegment]]) {
        let overflow = stack.count - Self.maximumSnapshots
        guard overflow > 0 else { return }
        stack.removeFirst(overflow)
    }
}
