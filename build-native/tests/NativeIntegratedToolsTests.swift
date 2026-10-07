import AVFoundation
import CryptoKit
import Foundation

// Isolated test paths; never access application preferences, Keychain or providers.
enum AppPaths {
    static let runtimeRoot=FileManager.default.temporaryDirectory.appendingPathComponent("msm-test-unused-root")
}
enum OfflineWhisperError:Error { case noAudio,cannotPrepareAudio,engineMissing,modelNotInstalled,engineFailed(String) }

@main
enum NativeIntegratedToolsTests {
    static func main() async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent("msm-integrated-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        try testAlignment()
        if let path=ProcessInfo.processInfo.environment["MSM_NATIVE_TRANSCRIPT_FIXTURES"] {
            let directory=URL(fileURLWithPath:path)
            for lang in ["vi","ko","zh"] {
                let text=try String(contentsOf:directory.appendingPathComponent(lang+".txt"),encoding:.utf8)
                let transcript=try WhisperTimestampDecoder.decode(Data(contentsOf:directory.appendingPathComponent(lang+".json")))
                let result=try NativeScriptAligner.align(script:text,tokens:transcript.tokens,language:lang)
                try expect(result.map(\.text).joined()==text,"Real timestamp fixture changed script")
            }
            print("✓ Real Whisper timestamp fixtures: VI/KO/ZH preserve original script")
        }
        try testDecoder()
        try testToolUpdates(root:root.appendingPathComponent("tools"))
        try testTemplate(root:root)
        try await testAudio(root:root)
        try await testProcessCancellation()
        try testXML(root:root)
        print("✓ Native integrated tools: alignment/decoder/signature/rollback/template/audio/cancellation/XML passed")
    }
    static func expect(_ condition:Bool,_ message:String) throws {
        if !condition { throw NSError(domain:"NativeToolsTest",code:1,userInfo:[NSLocalizedDescriptionKey:message]) }
    }
    static func rejects(_ operation:()->Void) { operation() }
    static func testAlignment() throws {
        for (lang,text) in [("vi","Xin chào bạn. Đây là kiểm tra thời gian."),("en","Hello world. This is a timing test."),
                            ("ko","안녕하세요 반갑습니다 오늘은 자막 테스트입니다"),("zh","你好世界今天我们测试字幕时间"),
                            ("ja","こんにちは世界今日は字幕の時間を確認します")] {
            let chars=Array(text)
            let tokens=chars.enumerated().map { SpeechWordTimestamp(text:String($0.element),startSeconds:Double($0.offset)*0.15,endSeconds:Double($0.offset+1)*0.15) }
            let result=try NativeScriptAligner.align(script:text,tokens:tokens,language:lang)
            try expect(result.map(\.text).joined()==text,"Original text changed: \(lang)")
            try expect(result.allSatisfy { $0.endSeconds>$0.startSeconds },"Invalid aligned span")
        }
        let repeated="hello hello hello"
        let tokens=[0,1,2].map { SpeechWordTimestamp(text:"hello ",startSeconds:Double($0)*2,endSeconds:Double($0)*2+1) }
        let aligned=try NativeScriptAligner.align(script:repeated,tokens:tokens,language:"en")
        try expect(aligned.map(\.startSeconds)==[0,2,4],"Repeated word matched backwards")
        do { _ = try NativeScriptAligner.align(script:"Entirely different script",tokens:tokens,language:"en");throw NSError(domain:"accepted mismatch",code:1) }
        catch is NativeScriptAlignmentError {}
        let longScript=Array(repeating:"hello timing world ",count:900).joined()
        var longTokens:[SpeechWordTimestamp]=[]
        for i in 0..<900 {
            longTokens.append(.init(text:i==450 ? "hello taming world " : "hello timing world ",
                                    startSeconds:Double(i)*2,endSeconds:Double(i)*2+1.8))
        }
        let long=try NativeScriptAligner.align(script:longScript,tokens:longTokens,language:"en")
        try expect(long.map(\.text).joined()==longScript,"Long script lost text")
    }
    static func testDecoder() throws {
        let valid=Data(#"{"result":{"language":"en"},"transcription":[{"text":" hello world","offsets":{"from":0,"to":1000},"tokens":[{"text":" hello","id":1,"offsets":{"from":0,"to":400}},{"text":" world","id":2,"offsets":{"from":500,"to":1000}}]}]}"#.utf8)
        let result=try WhisperTimestampDecoder.decode(valid)
        try expect(result.tokens.count==2 && result.tokens[1].startSeconds==0.5,"Whisper milliseconds decoded incorrectly")
        let broken=String(decoding:valid,as:UTF8.self).replacingOccurrences(of:" hello world",with:" missing text")
        try expect(try WhisperTimestampDecoder.decode(Data(broken.utf8)).tokens.isEmpty,"Mismatched token timestamps accepted")
        let language=try WhisperTimestampDecoder.language(from:"whisper_full: auto-detected language: vi (p = 0.97)")
        try expect(language.code=="vi" && language.confidence==0.97,"Language confidence lost")
        do { _=try WhisperTimestampDecoder.language(from:"auto-detected language: en (p = 0.20)");throw NSError(domain:"accepted low confidence",code:1) }
        catch is NativeScriptAlignmentError {}
    }
    static func testToolUpdates(root:URL) throws {
        let fm=FileManager.default,key=Curve25519.Signing.PrivateKey(),version="0.2.2"
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        func package(_ number:String) throws -> (URL,VerifiedToolManifest,Data) {
            let stage=root.appendingPathComponent("stage-\(number)")
            try fm.createDirectory(at:stage,withIntermediateDirectories:true)
            var files:[VerifiedToolManifest.File]=[]
            for path in VerifiedToolManifest.requiredPaths.sorted() {
                let url=stage.appendingPathComponent(path)
                try fm.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true)
                var data=Data("payload-\(number)".utf8)
                if path.hasSuffix("whisper-cli") { data=Data([0xcf,0xfa,0xed,0xfe,0x0c,0,0,1])+data }
                try data.write(to:url)
                files.append(.init(path:path,url:URL(string:"https://github.com/Atu96/media-support-master/releases/download/tools-\(number)/file")!,bytes:data.count,sha256:try VerifiedToolManifest.sha256(url)))
            }
            let m=VerifiedToolManifest(version:number,minimumAppVersion:version,architecture:"arm64",files:files)
            let payload=try JSONEncoder().encode(m)
            let envelope=try JSONEncoder().encode(VerifiedToolManifest.Envelope(payload:payload,signature:key.signature(for:payload)))
            _=try VerifiedToolManifest.verify(envelope,publicKey:key.publicKey.rawRepresentation,appVersion:version)
            return (stage,m,envelope)
        }
        let one=try package("20261007.1"),two=try package("20261007.2")
        try VerifiedToolStore.activate(envelope:one.2,manifest:one.1,stage:one.0,root:root)
        try VerifiedToolStore.activate(envelope:two.2,manifest:two.1,stage:two.0,root:root)
        try VerifiedToolStore.rollback(root:root,publicKey:key.publicKey.rawRepresentation,appVersion:version)
        let current=try VerifiedToolManifest.verify(Data(contentsOf:root.appendingPathComponent("active.json")),publicKey:key.publicKey.rawRepresentation,appVersion:version)
        try expect(current.version=="20261007.1","Rollback did not restore previous version")
        do { _=try VerifiedToolManifest.verify(one.2,publicKey:Curve25519.Signing.PrivateKey().publicKey.rawRepresentation,appVersion:version);throw NSError(domain:"wrong key accepted",code:1) }
        catch is CocoaError {}
        let damaged=root.appendingPathComponent("20261007.1/offline-whisper/bin/whisper-cli")
        try Data("corrupt".utf8).write(to:damaged)
        do { try one.1.validateFiles(in:root.appendingPathComponent("20261007.1"));throw NSError(domain:"damaged tool accepted",code:1) }
        catch is CocoaError {}
        let traversal=VerifiedToolManifest(version:"../escape",minimumAppVersion:version,architecture:"arm64",files:one.1.files)
        let payload=try JSONEncoder().encode(traversal)
        let signed=try JSONEncoder().encode(VerifiedToolManifest.Envelope(payload:payload,signature:key.signature(for:payload)))
        do { _=try VerifiedToolManifest.verify(signed,publicKey:key.publicKey.rawRepresentation,appVersion:version);throw NSError(domain:"path escape accepted",code:1) }
        catch is CocoaError {}
    }
    static func testTemplate(root:URL) throws {
        let source=root.appendingPathComponent("template-source"),destination=root.appendingPathComponent("template-install")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        try "<ozml/>".write(to:source.appendingPathComponent("Phu de nen den.moti"),atomically:true,encoding:.utf8)
        let url=try MotionTemplateInstaller.install(source:source,destination:destination)
        try "<ozml edited=\"true\"/>".write(to:url,atomically:true,encoding:.utf8)
        _=try MotionTemplateInstaller.install(source:source,destination:destination)
        try expect(try String(contentsOf:url,encoding:.utf8).contains("edited"),"Existing user template overwritten")
    }
    static func testAudio(root:URL) async throws {
        let input=root.appendingPathComponent("stereo.wav"),output=root.appendingPathComponent("mono.wav")
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        var file:AVAudioFile?=try AVAudioFile(forWriting:input,settings:format.settings)
        let pcm=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:48000)!
        pcm.frameLength=48000
        for i in 0..<48000 { let value=Float(sin(Double(i)*2*Double.pi*440/48000)*0.1);pcm.floatChannelData![0][i]=value;pcm.floatChannelData![1][i]=value }
        try file!.write(from:pcm);file=nil
        try await NativeAudioPreparation.extract(media:input,output:output)
        let mono=try AVAudioFile(forReading:output)
        try expect(mono.fileFormat.sampleRate==16000 && mono.fileFormat.channelCount==1,"Native audio format incorrect")
        try expect(abs(Double(mono.length)/16000-1)<0.03,"Native audio lost duration")
    }
    static func testProcessCancellation() async throws {
        let start=Date()
        let job=Task { try await NativeWhisperProcess.run(executable:URL(fileURLWithPath:"/bin/sh"),arguments:["-c","exec sleep 30"],progress:{_ in}) }
        try await Task.sleep(for:.milliseconds(200));job.cancel()
        do { _=try await job.value;throw NSError(domain:"process did not cancel",code:1) } catch is CancellationError {}
        try expect(Date().timeIntervalSince(start)<4,"Cancellation blocked for too long")
    }
    static func testXML(root:URL) throws {
        let invalid=SRTSegment(id:1,index:1,timing:"invalid",startSeconds:0,endSeconds:Double.greatestFiniteMagnitude,text:"invalid")
        do {
            _=try NativeFCPXMLExporter.render(segments:[invalid],name:"invalid",style:SubtitleBurnStyle(),templateURL:URL(fileURLWithPath:"/tmp/template.moti"))
            throw NSError(domain:"overflow time accepted",code:1)
        } catch is CocoaError {}
        let directory=CommandLine.arguments.count>1 ? URL(fileURLWithPath:CommandLine.arguments[1]) : root.appendingPathComponent("xml")
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let text="Việt & <Anh> \"Hàn\"\n中文 日本語 한국어 👩🏽‍💻"
        let cue=SRTSegment(id:1,index:1,timing:"00:00:00,125 --> 00:00:15,875",startSeconds:0.125,endSeconds:15.875,text:text)
        for fps in ["24","25","30","48","60","2997","2398"] {
            for mode in 0..<3 {
                var style=SubtitleBurnStyle();style.fps=fps;style.fontName="PingFangSC-Regular"
                style.fontSize=mode==1 ? 72 : 54;style.marginBottom=mode==1 ? 92 : 48
                style.boxEnabled=mode != 2;style.boxOpacity=0.65;style.boxColorHex="#0000FF";style.boxMaxWidthPercent=73;style.boxCornerRadius=11
                style.outlineEnabled=true;style.outlineWidth=5;style.outlineColorHex="#00FF00";style.outlineOpacity=0.8
                style.shadowEnabled=true;style.shadowDistance=7;style.shadowOpacity=0.75
                style.fadeInEnabled=true;style.fadeOutEnabled=true;style.fadeInMs=200;style.fadeOutMs=300
                if mode==2 { style.textTransition = .leftToRight;style.visualEffect = .goldenSweep }
                let xml=try NativeFCPXMLExporter.render(segments:[cue],name:"sample",style:style,templateURL:URL(fileURLWithPath:"/tmp/template.moti"))
                let stem="\(fps)-\(mode)"
                try xml.write(to:directory.appendingPathComponent(stem+".fcpxml"),atomically:true,encoding:.utf8)
                try JSONEncoder().encode(style.fcpxmlCLIArgs).write(to:directory.appendingPathComponent(stem+".json"))
                try SRTDocument.renderSRT([cue]).write(to:directory.appendingPathComponent(stem+".srt"),atomically:true,encoding:.utf8)
            }
        }
    }
}
