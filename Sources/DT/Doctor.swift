// 体检：一条命令把"为什么它不工作"定位到具体哪一段。
//
//   DictationTurbo --doctor
//
// 每一行都写成人话 —— 会读这个输出的，多半是正在着急的人，
// 或者是替他排查的 AI agent。别让它们猜。
import Cocoa
import AVFoundation

enum Doctor {
    /// 把一个异步调用变成同步等待（体检是命令行，慢一点没关系）
    private static func wait(_ body: (@escaping () -> Void) -> Void, seconds: TimeInterval = 8) {
        let sem = DispatchSemaphore(value: 0)
        body { sem.signal() }
        _ = sem.wait(timeout: .now() + seconds)
    }

    private static func shell(_ path: String, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        do { try p.run() } catch { return "" }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func run() {
        print("")
        print("Dictation Turbo \(Config.version)  体检报告")
        print("=".padding(toLength: 46, withPad: "=", startingAt: 0))

        // ① 系统
        let osv = ProcessInfo.processInfo.operatingSystemVersion
        print("① 系统：macOS \(osv.majorVersion).\(osv.minorVersion).\(osv.patchVersion)")
        print("   记录：\(Config.logPath)")

        // ② 辅助功能权限（双击 Control 全靠它）
        if HotkeyMonitor.hasPermission {
            print("② 辅助功能权限：✅ 已给")
        } else {
            print("② 辅助功能权限：❌ 还没给")
            print("   → 打开「系统设置 → 隐私与安全性 → 辅助功能」，把 Dictation Turbo 勾上。")
            print("     菜单里点「① 授予辅助功能权限…」也能直接跳过去。")
        }

        // ③ 签名（决定"改一次代码要不要重新授权"）
        let bin = Bundle.main.executablePath ?? CommandLine.arguments[0]
        let sig = shell("/usr/bin/codesign", ["-dv", "--verbose=2", bin])
        if sig.contains("Dictation Turbo Local Signing") {
            print("③ 代码签名：✅ 本地固定证书（以后重新编译不用再授权）")
        } else if sig.contains("Signature=adhoc") {
            print("③ 代码签名：⚠️ ad-hoc（每次重新编译都会丢授权）")
            print("   → 跑一次 tools/make-signing-identity.sh 造个固定证书，然后重新 ./build.sh。")
        } else {
            print("③ 代码签名：看不出来（可能没签名，本机照样能跑）")
        }

        // ④ VoiceStudio —— 必须的那只耳朵
        var vsOK = false
        wait { done in
            Engines.voiceStudioHealth { ok, detail in
                vsOK = ok
                print(ok ? "④ VoiceStudio（必须）：✅ 在跑，\(detail)"
                         : "④ VoiceStudio（必须）：❌ \(detail)")
                done()
            }
        }
        if !vsOK {
            print("   → 没装就先装 VoiceStudio；装了没起来，就把它打开。")
            print("     没有它，这个工具一句都转不出来。")
        }

        // ⑤ DSH —— 可选的中文增强
        wait { done in
            Engines.dshHealth { ok, detail in
                print(ok ? "⑤ DSH（可选·中文增强）：✅ \(detail)"
                         : "⑤ DSH（可选·中文增强）：➖ \(detail)")
                print("     （没有它不影响使用，只是中文少了层校对）")
                done()
            }
        }

        // ⑥ 麦克风
        let mic = AVCaptureDevice.authorizationStatus(for: .audio)
        switch mic {
        case .authorized: print("⑥ 麦克风权限：✅ 已给")
        case .denied:     print("⑥ 麦克风权限：❌ 被拒 —— 去「隐私与安全性 → 麦克风」勾上")
        case .notDetermined: print("⑥ 麦克风权限：➖ 还没问过（第一次录音时会弹窗）")
        default: print("⑥ 麦克风权限：➖ 状态未知")
        }

        // ⑦ 开机自启
        let plist = NSHomeDirectory() + "/Library/LaunchAgents/com.jieda.dictation-turbo.plist"
        if FileManager.default.fileExists(atPath: plist) {
            let n = getuid()
            let out = shell("/bin/launchctl", ["print", "gui/\(n)/com.jieda.dictation-turbo"])
            print(out.isEmpty ? "⑦ 开机自启：⚠️ 装了 plist 但没在 launchd 里"
                              : "⑦ 开机自启：✅ 已装")
        } else {
            print("⑦ 开机自启：➖ 没装（想装：./install.sh --autostart）")
        }

        print("")
        print("⑧ 最近 5 条记录：")
        if let whole = try? String(contentsOfFile: Config.logPath, encoding: .utf8) {
            let lines = whole.split(separator: "\n").suffix(5)
            if lines.isEmpty { print("   （空的，还没用过）") }
            for l in lines { print("   \(l)") }
        } else {
            print("   （还没有记录文件）")
        }
        print("")
        exit(0)
    }
}
