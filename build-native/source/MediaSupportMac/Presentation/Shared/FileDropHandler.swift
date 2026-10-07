import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum FileDropKind {
    case media
    case srt
    case video
    case subtitleSource

    func accepts(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        switch self {
        case .media:
            return FileDropHandler.mediaExtensions.contains(ext)
        case .srt:
            return ext == "srt"
        case .video:
            return FileDropHandler.videoExtensions.contains(ext)
        case .subtitleSource:
            return FileDropHandler.mediaExtensions.contains(ext) || ext == "srt"
        }
    }
}

enum FileDropHandler {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "mkv", "m4v", "avi", "webm", "ts", "mts", "m2ts"
    ]

    static let audioExtensions: Set<String> = [
        "mp3", "wav", "m4a", "aac", "flac", "ogg", "wma", "aiff", "caf"
    ]

    static var mediaExtensions: Set<String> {
        videoExtensions.union(audioExtensions)
    }

    @MainActor
    static func process(
        _ providers: [NSItemProvider],
        kind: FileDropKind,
        multiple: Bool,
        onURLs: @escaping ([URL]) -> Void
    ) -> Bool {
        let fileProviders = providers.filter {
            $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
        }
        guard !fileProviders.isEmpty else { return false }

        let group = DispatchGroup()
        var collected: [URL] = []
        let lock = NSLock()

        let limit = multiple ? fileProviders.count : 1
        for provider in fileProviders.prefix(limit) {
            group.enter()
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                defer { group.leave() }
                guard let url = resolveURL(from: item), kind.accepts(url) else { return }
                lock.lock()
                collected.append(url)
                lock.unlock()
            }
        }

        group.notify(queue: .main) {
            let unique = dedupe(collected)
            guard !unique.isEmpty else { return }
            onURLs(multiple ? unique : [unique[0]])
        }

        return true
    }

    private static func resolveURL(from item: NSSecureCoding?) -> URL? {
        if let url = item as? URL {
            return url
        }
        if let data = item as? Data {
            return URL(dataRepresentation: data, relativeTo: nil)
        }
        return nil
    }

    private static func dedupe(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { seen.insert($0.path).inserted }
    }
}

// MARK: - Drop zone wrapper

struct AppDropZone<Content: View>: View {
    let kind: FileDropKind
    var allowsMultiple: Bool = false
    let onURLs: ([URL]) -> Void
    @ViewBuilder var content: () -> Content

    @State private var isTargeted = false

    var body: some View {
        content()
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                        .stroke(AppTheme.accentBlue, lineWidth: 2)
                        .background(
                            RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous)
                                .fill(AppTheme.accentBlue.opacity(0.08))
                        )
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                FileDropHandler.process(providers, kind: kind, multiple: allowsMultiple, onURLs: onURLs)
            }
    }
}

struct AppFileDropField: View {
    let label: String
    let placeholder: String
    let filename: String?
    let chooseTitle: String
    let dropKind: FileDropKind
    let onChoose: () -> Void
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(L10n.string(label))
                .font(AppFont.label)
                .foregroundStyle(AppTheme.mutedText)
            HStack(spacing: 10) {
                Image(systemName: isTargeted ? "arrow.down.doc.fill" : "doc.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(isTargeted ? AppTheme.accentBlue : AppTheme.accentBlue.opacity(0.85))
                Text(L10n.string(displayText))
                    .font(AppFont.body)
                    .foregroundStyle(filename == nil ? AppTheme.mutedText : AppTheme.headlineText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: 8)
                AppPillButton(title: chooseTitle, icon: "folder", tint: AppTheme.accentBlue, action: onChoose)
                    // Tên file dài phải nhường chỗ; nút đổi/chọn luôn đủ icon + chữ.
                    .fixedSize(horizontal: true, vertical: false)
            }
            .padding(.horizontal, 12)
            .frame(height: AppTheme.rowHeight)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.fieldRadius, style: .continuous)
                    .fill(isTargeted ? AppTheme.accentBlue.opacity(0.06) : AppTheme.inputFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.fieldRadius, style: .continuous)
                    .stroke(
                        isTargeted ? AppTheme.accentBlue : AppTheme.divider,
                        lineWidth: isTargeted ? 1.5 : 0.75
                    )
            )
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                FileDropHandler.process(providers, kind: dropKind, multiple: false) { urls in
                    if let url = urls.first { onDrop(url) }
                }
            }
        }
    }

    private var displayText: String {
        if isTargeted { return "Thả tệp vào đây" }
        return filename ?? placeholder
    }
}

// MARK: - Chrome ô kéo thả (dùng chung)

private enum AppDropZoneChrome {
    static let cornerRadius: CGFloat = 12
    static let dashPattern: [CGFloat] = [8, 5]

    static func videoFormats(_ formats: String = "mp4 · mov · m4v · mkv · webm") -> String { formats }

    @ViewBuilder
    static func frame<Content: View>(
        isTargeted: Bool,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(
                        isTargeted
                            ? AppTheme.accentBlue.opacity(0.1)
                            : Color.white.opacity(0.48)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(
                        isTargeted ? AppTheme.accentBlue : AppTheme.accentBlue.opacity(0.38),
                        style: StrokeStyle(lineWidth: isTargeted ? 2 : 1.25, dash: dashPattern)
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    static func bannerRow(
        isTargeted: Bool,
        icon: String,
        headline: String,
        formats: String,
        chooseTitle: String,
        onChoose: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: isTargeted ? "arrow.down.circle.fill" : icon)
                .font(.system(size: 20, weight: .light))
                .foregroundStyle(isTargeted ? AppTheme.accentBlue : AppTheme.accentBlue.opacity(0.72))
                .symbolEffect(.bounce, value: isTargeted)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.string(isTargeted ? "Thả vào khung này" : headline))
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.headlineText)
                    .lineLimit(1)
                Text(L10n.string(formats))
                    .font(.system(size: 11))
                    .foregroundStyle(AppTheme.mutedText)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            AppPillButton(
                title: chooseTitle,
                icon: "plus",
                tint: AppTheme.accentBlue,
                filled: false,
                action: onChoose
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

// MARK: - Khối kéo thả media (tab Tạo sub)

struct AppMediaDropZone: View {
    let filename: String?
    let dropKind: FileDropKind
    var compact: Bool = false
    /// Giãn drop zone theo chiều dọc khung cha.
    var fillVertical: Bool = false
    var emptyIcon: String = "film.stack"
    var emptyTitle: String? = nil
    var emptyFormats: String? = nil
    let onChoose: () -> Void
    let onDrop: (URL) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            dropArea
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            FileDropHandler.process(providers, kind: dropKind, multiple: false) { urls in
                if let url = urls.first { onDrop(url) }
            }
        }
    }

    private var dropArea: some View {
        VStack(spacing: compact ? 8 : 14) {
            if fillVertical { Spacer(minLength: 0) }

            Image(systemName: isTargeted ? "arrow.down.circle.fill" : emptyIcon)
                .font(.system(size: compact ? 22 : 32, weight: .light))
                .foregroundStyle(isTargeted ? AppTheme.accentBlue : AppTheme.accentBlue.opacity(0.55))
                .symbolEffect(.bounce, value: isTargeted)

            if let filename {
                Text(filename)
                    .font(compact ? AppFont.label : AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                    .multilineTextAlignment(.center)
                    .lineLimit(compact ? 1 : 2)
                    .frame(maxWidth: .infinity)
            } else if let emptyTitle {
                Text(L10n.string(emptyTitle))
                    .font(compact ? AppFont.label : AppFont.body)
                    .foregroundStyle(AppTheme.headlineText)
                    .multilineTextAlignment(.center)
                if let emptyFormats {
                    Text(L10n.string(emptyFormats))
                        .font(AppFont.caption)
                        .foregroundStyle(AppTheme.mutedText)
                        .multilineTextAlignment(.center)
                }
            }

            AppPillButton(
                title: "Chọn tệp",
                icon: "folder",
                tint: AppTheme.accentBlue,
                filled: false,
                action: onChoose
            )

            if fillVertical { Spacer(minLength: 0) }
        }
        .frame(maxWidth: .infinity, maxHeight: fillVertical ? .infinity : nil)
        .padding(.vertical, fillVertical ? 16 : (compact ? 14 : 28))
        .padding(.horizontal, compact ? 14 : 20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isTargeted ? AppTheme.accentBlue.opacity(0.07) : Color.white.opacity(0.55))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    isTargeted ? AppTheme.accentBlue : AppTheme.tileStroke,
                    style: StrokeStyle(lineWidth: isTargeted ? 2 : 1, dash: filename == nil ? [7, 5] : [])
                )
        )
    }
}
