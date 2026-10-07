import AppKit
import SwiftUI

struct SettingsToolsPanel: View {
    @ObservedObject private var updates=ToolUpdateManager.shared
    @ObservedObject private var engine=MediaEngineService.shared
    @AppStorage("msm.tools.autoUpdate") private var autoUpdate=true
    @AppStorage("msm.whisper.cpuOnly") private var cpuOnly=false
    @State private var installing=false
    @State private var templateMessage=""
    var body: some View {
        ScrollView {
            VStack(alignment:.leading,spacing:14) {
                tile {
                    Text("Công cụ tích hợp").font(AppFont.sectionTitle)
                    Text("XML, khớp kịch bản và nhận diện ngôn ngữ chạy bằng công cụ trong ứng dụng.")
                        .font(AppFont.body).foregroundStyle(AppTheme.mutedText)
                    Text(L10n.string(updates.message)).font(AppFont.caption)
                    if updates.busy { ProgressView().controlSize(.small) }
                    Toggle("Tự cập nhật công cụ khi ứng dụng rảnh",isOn:$autoUpdate)
                        .font(AppFont.body)
                    HStack {
                        AppPillButton(title:"Kiểm tra cập nhật",icon:"arrow.clockwise",tint:AppTheme.accentBlue,
                                      filled:false,disabled:updates.busy || engine.isRunning) {
                            Task { await updates.update() }
                        }
                        AppPillButton(title:"Phục hồi công cụ trước đó",icon:"arrow.uturn.backward",tint:AppTheme.accentBlue,
                                      filled:false,disabled:updates.busy || engine.isRunning) { updates.rollback() }
                    }
                    Text("Model lớn chỉ tải khi bạn chọn. Cập nhật lỗi vẫn giữ công cụ đang dùng.")
                        .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
                }
                tile {
                    Text("Mẫu phụ đề Final Cut").font(AppFont.sectionTitle)
                    Text("Mẫu được cài trong thư mục Motion của bạn. Mẫu đã có sẽ được giữ nguyên.")
                        .font(AppFont.body).foregroundStyle(AppTheme.mutedText)
                    AppPillButton(title:installing ? "Đang cài mẫu…" : "Cài mẫu Final Cut",icon:"square.and.arrow.down",
                                  tint:AppTheme.accentBlue,filled:false,disabled:installing || engine.isRunning) { install() }
                    if !templateMessage.isEmpty { Text(L10n.string(templateMessage)).font(AppFont.caption) }
                }
                tile {
                    Text("Xử lý âm thanh").font(AppFont.sectionTitle)
                    Toggle("Chỉ dùng CPU",isOn:$cpuOnly).font(AppFont.body)
                    Text("Mặc định ứng dụng tự chọn tăng tốc theo độ dài âm thanh. Bật tùy chọn này để không dùng GPU.")
                        .font(AppFont.caption).foregroundStyle(AppTheme.mutedText)
                }
            }.padding(.bottom,8)
        }.task { await updates.checkIfDue() }
    }
    private func tile<Content:View>(@ViewBuilder _ content:()->Content)->some View {
        VStack(alignment:.leading,spacing:12,content:content).frame(maxWidth:.infinity,alignment:.leading)
            .padding(14).background(AppTileSurface())
    }
    private func install() {
        installing=true
        Task {
            do {
                _ = try await Task.detached(priority:.utility) { try MotionTemplateInstaller.resolveOrInstall() }.value
                templateMessage="Mẫu Final Cut đã sẵn sàng"
            } catch { templateMessage="Không thể cài mẫu Final Cut" }
            installing=false
        }
    }
}
