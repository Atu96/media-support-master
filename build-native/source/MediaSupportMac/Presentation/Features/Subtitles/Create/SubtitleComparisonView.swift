import SwiftUI

struct SubtitleComparisonView: View {
    @ObservedObject var viewModel: SubtitleViewModel
    @ObservedObject var controller: SubtitleComparisonController
    @ObservedObject private var runner = MediaEngineService.shared.runner
    @State private var offline = false
    @State private var differencesOnly = true

    var body: some View {
        Group {
            if controller.phase == .ocr, let media = viewModel.mediaURL {
                SubtitleOCRConfigurationView(media: media, controller: viewModel.ocrCreate,
                    canRun: !runner.isRunning, forComparison: true)
            } else {
                content.padding(20).frame(width: 700)
                    .background(AppTileSurface())
            }
        }
        .onDisappear { controller.dismiss() }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "text.badge.checkmark").foregroundStyle(AppTheme.accentBlue)
                Text("Đối chiếu phụ đề").font(AppFont.sectionTitle)
                Spacer()
                if let media = viewModel.mediaURL {
                    Text(media.lastPathComponent).lineLimit(1).font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
                }
            }
            switch controller.phase {
            case .offer: offer
            case .audio: audio
            case .running:
                ProgressView()
                Text(controller.message).font(AppFont.caption).fixedSize(horizontal: false, vertical: true)
                if controller.percent > 0 { ProgressView(value: Double(controller.percent), total: 100) }
            case .review: review
            case .message:
                Text(controller.message).foregroundStyle(AppTheme.accentOrange).fixedSize(horizontal: false, vertical: true)
                if controller.failedScriptMatch {
                    Button("Khớp lại từ âm thanh") {
                        controller.dismiss()
                        viewModel.scriptCreate.run()
                    }.disabled(!OfflineWhisperModelManager.isModelReady || runner.isRunning)
                    if !OfflineWhisperModelManager.isModelReady {
                        Text("Chưa tải model Whisper Offline trong Cài đặt.").font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
                    }
                }
            case .ocr: EmptyView()
            }
            HStack {
                Button(L10n.string(controller.isRunning ? "Dừng" : "Để sau")) { controller.dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if controller.phase == .offer {
                    Button(L10n.string(controller.source == .ocr ? "Chọn vùng chữ" : "Đối chiếu bằng âm thanh")) { controller.continueOffer() }
                        .buttonStyle(.borderedProminent)
                } else if controller.phase == .audio {
                    Button("Lấy bản bổ trợ") { controller.runAudio(offline: offline) }
                        .buttonStyle(.borderedProminent)
                        .disabled(!controller.canStart || (offline ? !OfflineWhisperModelManager.isModelReady : !GroqCredentialStore.hasKey))
                } else if controller.phase == .review {
                    Button("Áp dụng lựa chọn") { controller.applyChoices() }
                        .buttonStyle(.borderedProminent)
                        .disabled(controller.candidateIDs.isEmpty || controller.isRunning || runner.isRunning)
                }
            }
        }
    }

    private var offer: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Đã lấy phụ đề. Bạn muốn kiểm tra thêm bằng nguồn khác?").font(AppFont.body)
            Text(L10n.string(controller.source == .ocr
                ? "Nếu video có phụ đề dính trong hình, quét OCR có thể giúp đối chiếu chữ, tên riêng và địa danh."
                : "Chép lời từ âm thanh để đối chiếu từ bị thiếu hoặc nhận diện sai khi quét phụ đề. Bạn xem khác biệt và chọn trước khi áp dụng."))
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
            Text("Bản hiện có được giữ nguyên. Bạn xem khác biệt và chọn trước khi áp dụng.")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
            Toggle("Không nhắc lại", isOn: $controller.suppressOffers).controlSize(.small)
        }
    }

    private var audio: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Chọn cách nhận diện lời nói cho bản bổ trợ.").font(AppFont.body)
            Picker("Nguồn âm thanh", selection: $offline) {
                Text("Groq cloud").tag(false)
                Text("Whisper Offline").tag(true)
            }.pickerStyle(.segmented)
            Text(L10n.string(offline
                ? "Chạy cục bộ bằng model đã tải; không dùng API. Có thể tốn tài nguyên hơn OCR."
                : "Gửi âm thanh đến Groq khi bạn bấm Lấy bản bổ trợ; có sử dụng hạn mức API."))
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
            if offline && !OfflineWhisperModelManager.isModelReady {
                Text("Chưa tải model Whisper Offline trong Cài đặt.").foregroundStyle(AppTheme.accentOrange)
            } else if !offline && !GroqCredentialStore.hasKey {
                Button("Cài đặt Groq") { viewModel.openGroqSettings() }
            }
        }
    }

    private var review: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Chọn bản đúng cho từng nhóm thời gian. Mặc định giữ bản hiện có; chọn bản bổ trợ sẽ dùng cả chữ và thời gian của nhóm đó.")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
            Text("Chữ trên video có thể là bản dịch khác lời nói. Hãy kiểm tra ngôn ngữ và nghe/xem trước khi chọn.")
                .font(AppFont.caption).foregroundStyle(AppTheme.accentOrange).fixedSize(horizontal: false, vertical: true)
            Text(L10n.format("Bản hiện có: %@ · Bản bổ trợ: %@", languageName(viewModel.resolvedSubtitleLanguageCode()), languageName(controller.candidateLanguage)))
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
            HStack {
                Toggle("Chỉ hiện khác biệt", isOn: $differencesOnly).controlSize(.small)
                Spacer()
                Text(L10n.format("%d nhóm khác biệt · %d nhóm đã chọn", controller.groups.filter(\.differs).count, controller.candidateIDs.count))
                    .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
            }
            if let player = viewModel.preview.player {
                AVPlayerContainerView(player: player).frame(height: 150)
                    .background(.black, in: RoundedRectangle(cornerRadius: 10))
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(controller.groups.filter { !differencesOnly || $0.differs }) { group in
                        groupCard(group)
                    }
                }
            }.frame(height: 250)
            Text("Các cue đổi chữ cần lồng tiếng lại; cue không đổi vẫn giữ audio. Áp dụng có thể Hoàn tác.")
                .font(AppFont.caption).foregroundStyle(AppTheme.mutedText).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func languageName(_ code: String) -> String {
        Locale(identifier: L10n.interfaceLocaleIdentifier).localizedString(forLanguageCode: code)
            ?? viewModel.languageDisplayName(code)
    }

    private func groupCard(_ group: SubtitleEvidenceGroup) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("\(SRTTimecode.format(group.start)) → \(SRTTimecode.format(group.end))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(AppTheme.mutedText)
                Spacer()
                Button("Xem đoạn này") { viewModel.preview.seek(seconds: group.start, playAfter: false) }
                    .controlSize(.small)
            }
            HStack(alignment: .top, spacing: 12) {
                choice(title: "Bản hiện có", text: group.currentText,
                    chosen: !controller.candidateIDs.contains(group.id)) { controller.candidateIDs.remove(group.id) }
                choice(title: controller.source == .ocr ? "Bản OCR" : "Bản âm thanh", text: group.candidateText,
                    chosen: controller.candidateIDs.contains(group.id)) { controller.candidateIDs.insert(group.id) }
            }
        }
        .padding(12).background(AppFieldSurface(radius: 10))
    }

    private func choice(title: String, text: String, chosen: Bool, action: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Button(action: action) {
                Label(L10n.string(title), systemImage: chosen ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(chosen ? AppTheme.accentBlue : AppTheme.bodyText)
            }.buttonStyle(.plain).accessibilityValue(L10n.string(chosen ? "Đang chọn" : "Chưa chọn"))
            Text(text.isEmpty ? L10n.string("Không có cue trong nhóm này") : text)
                .font(AppFont.body).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
