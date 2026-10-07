import AppKit
import UniformTypeIdentifiers

enum FilePickerHelper {
    static func pickFile(allowedTypes: [UTType], onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = allowedTypes
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    static func pickDirectory(onPick: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Chọn"
        panel.message = "Chọn thư mục lưu backup dự án"
        if panel.runModal() == .OK, let url = panel.url {
            onPick(url)
        }
    }

    static func pickFiles(allowedTypes: [UTType], onPick: @escaping ([URL]) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = allowedTypes
        if panel.runModal() == .OK {
            onPick(panel.urls)
        }
    }

    static var srtType: UTType {
        UTType(filenameExtension: "srt") ?? .plainText
    }

    static var mediaTypes: [UTType] {
        [.movie, .audio, .mpeg4Movie, .quickTimeMovie]
    }

    static var videoTypes: [UTType] {
        [.movie, .mpeg4Movie, .quickTimeMovie, .avi]
    }
}