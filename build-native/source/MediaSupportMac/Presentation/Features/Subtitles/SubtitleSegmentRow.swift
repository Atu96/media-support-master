import SwiftUI

struct SubtitleSegmentRow: View, Equatable {
    let segment: SRTSegment
    let isPlaybackActive: Bool
    let isSelected: Bool
    let isEditing: Bool
    let onRowTap: () -> Void
    let onRowDoubleTap: () -> Void
    let onEditCommit: (String) -> Void
    let onEditCancel: () -> Void
    var onEditLiveChange: ((String) -> Void)?
    let onContextSplit: () -> Void
    let onContextMerge: () -> Void
    let onContextDelete: () -> Void
    let canSplit: Bool
    let canMerge: Bool
    let canDelete: Bool

    static func == (lhs: SubtitleSegmentRow, rhs: SubtitleSegmentRow) -> Bool {
        lhs.segment == rhs.segment
            && lhs.isPlaybackActive == rhs.isPlaybackActive
            && lhs.isSelected == rhs.isSelected
            && lhs.isEditing == rhs.isEditing
            && lhs.canSplit == rhs.canSplit
            && lhs.canMerge == rhs.canMerge
            && lhs.canDelete == rhs.canDelete
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(segment.startLabel)
                .font(AppFont.mono)
                .foregroundStyle(isPlaybackActive ? AppTheme.accentGreen : AppTheme.accentBlue)
                .frame(width: 72, alignment: .leading)

            if isEditing {
                editBox
            } else {
                Text(segment.text.isEmpty ? " " : segment.text)
                    .font(.system(size: 14, weight: isPlaybackActive || isSelected ? .semibold : .regular))
                    .foregroundStyle(isPlaybackActive ? AppTheme.headlineText : AppTheme.bodyText)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(rowBackground)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onRowDoubleTap)
        .onTapGesture(count: 1, perform: onRowTap)
        .contextMenu {
            Button("Gộp timecode", action: onContextMerge)
                .disabled(!canMerge)
        }
    }

    private var editBox: some View {
        ZStack(alignment: .topLeading) {
            AppFieldSurface(radius: 8)
            SubtitleNSTextEditor(
                initialText: segment.text,
                onCommit: onEditCommit,
                onCancel: onEditCancel,
                onLiveChange: onEditLiveChange
            )
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .frame(minHeight: 68, maxHeight: 120)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppTheme.accentBlue.opacity(0.65), lineWidth: 1.25)
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var rowBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(
                isEditing
                    ? AppTheme.accentBlue.opacity(0.1)
                    : (isSelected
                        ? AppTheme.accentBlue.opacity(0.2)
                        : (isPlaybackActive ? AppTheme.accentGreen.opacity(0.14) : Color.clear))
            )
    }
}

extension SRTSegment: Equatable {
    static func == (lhs: SRTSegment, rhs: SRTSegment) -> Bool {
        lhs.id == rhs.id
            && lhs.index == rhs.index
            && lhs.timing == rhs.timing
            && lhs.startSeconds == rhs.startSeconds
            && lhs.endSeconds == rhs.endSeconds
            && lhs.text == rhs.text
    }
}
