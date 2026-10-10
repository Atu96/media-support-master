import AVFoundation
import SwiftUI

struct SubtitleOCRConfigurationView: View {
    let media: URL
    @ObservedObject var controller: SubtitleOCRCreateController
    let canRun: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var region = SubtitleOCRRegion.lower
    @State private var image: CGImage?
    @State private var duration = 0.0
    @State private var sampleTime = 0.0
    @State private var accurateTiming = false
    @State private var frameError = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Lấy sub từ video", systemImage: "text.viewfinder")
                    .font(AppFont.sectionTitle)
                Spacer()
                Text(media.lastPathComponent).font(AppFont.caption).foregroundStyle(AppTheme.mutedText).lineLimit(1)
            }
            Text("Kéo trên hình để chọn vùng phụ đề. Ngôn ngữ được tự nhận diện; kết quả thành cue để dịch và lồng tiếng.")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
            Text("Tự nhận diện: Việt, Anh, Nhật, Hàn, Trung")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
            selectionPreview.frame(height: 280)
                .background(.black, in: RoundedRectangle(cornerRadius: 10))
                .disabled(controller.isRunning)
            HStack {
                Text("Khung hình xem trước").font(AppFont.caption)
                Slider(value: $sampleTime, in: 0...max(0.01, duration - 0.05))
                    .disabled(controller.isRunning || duration <= 0)
                Text(SRTTimecode.format(sampleTime)).font(.system(size: 11, design: .monospaced))
            }
            HStack {
                Button("Vùng phía dưới") { region = .lower }.disabled(controller.isRunning)
                Spacer()
                Toggle("Quét kỹ hơn", isOn: $accurateTiming).toggleStyle(.switch).controlSize(.small)
                    .disabled(controller.isRunning)
            }
            Text("Quét cục bộ, không cần key. Quét kỹ hơn lấy nhiều khung hình hơn; chữ quá ngắn hoặc mờ có thể cần sửa lại.")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
            if controller.isRunning {
                ProgressView(value: Double(controller.percent), total: 100)
                Text(L10n.format("Đang quét %d%% · %d cue", controller.percent, controller.cueCount)).font(AppFont.caption)
            } else if !controller.message.isEmpty {
                Text(controller.message).font(AppFont.caption).foregroundStyle(controller.succeeded ? AppTheme.accentGreen : AppTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !frameError.isEmpty {
                Text(frameError).font(AppFont.caption).foregroundStyle(AppTheme.accentOrange)
            }
            HStack {
                Button(controller.succeeded ? "Xong" : "Đóng") { dismiss() }
                Spacer()
                if controller.isRunning {
                    Button("Dừng quét") { controller.cancel() }.buttonStyle(.bordered)
                } else {
                    Button("Quét phụ đề") { controller.run(media: media, region: region, interval: accurateTiming ? 0.25 : 0.5) }
                        .buttonStyle(.borderedProminent).tint(AppTheme.accentBlue)
                        .disabled(!canRun || image == nil)
                }
            }
        }
        .padding(20)
        .frame(width: 620)
        .background(AppTileSurface())
        .onAppear { controller.prepare() }
        .task {
            let asset = AVURLAsset(url: media)
            duration = (try? await asset.load(.duration).seconds) ?? 0
            sampleTime = min(2, max(0, duration / 4))
        }
        .task(id: sampleTime) { await loadFrame() }
        .onDisappear { controller.cancel() }
    }

    @ViewBuilder
    private var selectionPreview: some View {
        if let image {
            GeometryReader { geometry in
                let scale = min(geometry.size.width / Double(image.width), geometry.size.height / Double(image.height))
                let size = CGSize(width: Double(image.width) * scale, height: Double(image.height) * scale)
                let rect = region.rect
                ZStack(alignment: .topLeading) {
                    Image(decorative: image, scale: 1).resizable().frame(width: size.width, height: size.height)
                    Rectangle().fill(AppTheme.accentBlue.opacity(0.12))
                        .overlay(Rectangle().stroke(AppTheme.accentBlue, lineWidth: 2))
                        .frame(width: rect.width * size.width, height: rect.height * size.height)
                        .offset(x: rect.minX * size.width, y: rect.minY * size.height)
                        .allowsHitTesting(false)
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 3).onChanged { drag in
                    region = SubtitleOCRRegion.selection(from: drag.startLocation, to: drag.location, size: size)
                })
                .frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityLabel("Vùng chữ cần quét")
            }
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func loadFrame() async {
        do {
            try await Task.sleep(for: .milliseconds(100))
            let frame = try await SubtitleOCRService.previewImage(media: media, time: sampleTime)
            try Task.checkCancellation()
            image = frame
            frameError = ""
        } catch {
            guard !Task.isCancelled else { return }
            frameError = L10n.string("Không đọc được khung hình để lấy phụ đề.")
        }
    }
}
