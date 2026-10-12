import AppKit

@main
@MainActor
enum MediaSupportMacLauncher {
    static func main() {
        if Bundle.main.object(forInfoDictionaryKey: "MediaSupportBuildChannel") as? String == "test",
           ProcessInfo.processInfo.environment["MSM_ALLOW_PAID_MAZIAO_PROBE"] == "1",
           let path = ProcessInfo.processInfo.environment["MSM_MAZIAO_CONTEXT_PROBE_DIR"] {
            Task {
                do { try await NativeMaziaoPipelineProbe.runContextContrast(directory: URL(fileURLWithPath: path)); exit(0) }
                catch { print("MAZIAO_CONTEXT_PROBE_FAILED: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey: "MediaSupportBuildChannel") as? String == "test",
           let path = ProcessInfo.processInfo.environment["MSM_SUBTITLE_COMPARISON_SMOKE_DIR"] {
            Task {
                do { try await NativeSubtitleComparisonSmoke.run(directory: URL(fileURLWithPath: path)); exit(0) }
                catch { print("COMPARISON_SMOKE_FAILED: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey: "MediaSupportBuildChannel") as? String == "test",
           ProcessInfo.processInfo.environment["MSM_ALLOW_PAID_MAZIAO_PROBE"] == "1",
           let path = ProcessInfo.processInfo.environment["MSM_MAZIAO_PIPELINE_PROBE_DIR"] {
            Task {
                do { try await NativeMaziaoPipelineProbe.run(directory: URL(fileURLWithPath: path)); exit(0) }
                catch { print("MAZIAO_PROBE_FAILED: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey: "MediaSupportBuildChannel") as? String == "test",
           let path = ProcessInfo.processInfo.environment["MSM_SUBTITLE_OCR_SMOKE_DIR"] {
            Task {
                do { try await NativeSubtitleOCRSmoke.run(directory: URL(fileURLWithPath: path)); exit(0) }
                catch { print("OCR_SMOKE_FAILED: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey: "MediaSupportBuildChannel") as? String == "test",
           let path = ProcessInfo.processInfo.environment["MSM_DUBBING_OPTIMIZATION_SMOKE_DIR"] {
            Task {
                do { try await NativeDubbingOptimizationSmoke.run(directory: URL(fileURLWithPath: path)); exit(0) }
                catch { print("DUBBING_SMOKE_FAILED: \(error.localizedDescription)"); exit(1) }
            }
            RunLoop.main.run()
            return
        }
        if Bundle.main.object(forInfoDictionaryKey:"MediaSupportBuildChannel") as? String == "test",
           let path=ProcessInfo.processInfo.environment["MSM_INTEGRATED_TOOLS_SMOKE_DIR"] {
            Task {
                do { try await NativeIntegratedToolsSmoke.run(directory:URL(fileURLWithPath:path));exit(0) }
                catch { print("NATIVE_SMOKE_FAILED: \(error.localizedDescription)");exit(1) }
            }
            RunLoop.main.run()
            return
        }
        AppLanguagePreference.prepareForLaunch()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
