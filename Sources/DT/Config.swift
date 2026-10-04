// 配置、路径、凭证 —— 所有"上哪儿找服务、我怎么证明我是谁"的事都在这里。
import Foundation
import CryptoKit

/// 用户可调项。写在 ~/.dictation-turbo/config.json，缺什么就用默认值。
/// 全部可以留空 —— 不写这个文件它照样能跑。
struct Settings {
    /// 传给 VoiceStudio 的语言提示。默认 auto：让它自己判断，
    /// 这样一次听写里中德英混着说也没关系（这本来就是它主打的用法）。
    var languageHint = "auto"
    /// 两次 Control 之间小于这个秒数才算「双击」
    var doubleTapSeconds: TimeInterval = 0.35
    /// 中文再用 DSH 的 SenseVoice 复核一遍（简体 + 全角标点，实测更准）。
    /// 没装 DSH 的机器上这一条会自动跳过，不影响使用。
    var chineseViaDSH = true
    /// 全程最响都没到这个音量，就当没说人话，不送识别。
    /// 教训：静音/底噪送进去也会被硬猜出一串东西来。
    var minPeak: Float = 0.03
    /// 录得比这还短，当误触丢掉（秒）
    var minRecordSeconds: TimeInterval = 0.35
    /// 最长录这么久就自动收工（秒），免得按了忘记关
    var maxRecordSeconds: TimeInterval = 120
    /// DSH 窗口在前台时，让路给页面版插件（装了那个插件才有意义）
    var yieldToDSHPage = true

    static func load() -> Settings {
        var s = Settings()
        let path = Config.dir + "/config.json"
        guard let data = FileManager.default.contents(atPath: path),
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            return s
        }
        if let v = obj["language"] as? String, !v.isEmpty { s.languageHint = v }
        if let v = obj["doubleTapSeconds"] as? Double, v > 0.05 { s.doubleTapSeconds = v }
        if let v = obj["chineseViaDSH"] as? Bool { s.chineseViaDSH = v }
        if let v = obj["minPeak"] as? Double { s.minPeak = Float(v) }
        if let v = obj["minRecordSeconds"] as? Double { s.minRecordSeconds = v }
        if let v = obj["maxRecordSeconds"] as? Double, v > 1 { s.maxRecordSeconds = v }
        if let v = obj["yieldToDSHPage"] as? Bool { s.yieldToDSHPage = v }
        Config.log("已读入 config.json")
        return s
    }
}

enum Config {
    /// 所有自己的东西都放这一个目录：日志、锁、配置。
    static let dir = NSHomeDirectory() + "/.dictation-turbo"
    static let logPath = dir + "/dictation.log"
    static let lockPath = dir + "/dictation.lock"
    static let configPath = dir + "/config.json"

    /// 运行时可调整的设置（菜单里能改的就改这里）
    static var settings = Settings.load()

    static var version: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "dev"
    }

    // MARK: - 两个本机服务

    /// VoiceStudio —— 这只耳朵是必须的（646 种语言都靠它）。
    static var vsBase: String {
        ProcessInfo.processInfo.environment["DT_VS_BASE"] ?? "http://127.0.0.1:3900"
    }

    /// DSH —— 可选的中文增强，没有它照样能用。
    static var dshAuthority: String {
        ProcessInfo.processInfo.environment["DT_DSH_AUTHORITY"] ?? "127.0.0.1:19387"
    }
    /// 想彻底不要 DSH 那条路：设 DT_NO_DSH=1
    static var dshAllowed: Bool {
        ProcessInfo.processInfo.environment["DT_NO_DSH"] == nil
    }
    /// DSH 在前台 = 页面版插件的地盘
    static let dshBundleID = "com.deepseek.dsh"

    // MARK: - DSH 鉴权

    private static func b64url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// 算出访问 DSH 要带的 Cookie。
    /// 用 ~/.dsh/.credentials.yaml 里 browser-session 的密钥，对一段 JSON 做 HMAC-SHA256。
    /// 算不出来就返回 nil —— 调用方当"DSH 不可用"处理，不影响主流程。
    static func dshCookie() -> String? {
        let path = NSHomeDirectory() + "/.dsh/.credentials.yaml"
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        let pattern = "client-connection/browser-session:[\\s\\S]*?secret:\\s*(\\S+)"
        guard let re = try? NSRegularExpression(pattern: pattern),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let r = Range(m.range(at: 1), in: text) else { return nil }

        var s = String(text[r])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while s.count % 4 != 0 { s += "=" }
        guard let secret = Data(base64Encoded: s), secret.count == 32 else { return nil }

        let name = "dsh-auth-" + b64url(Data(SHA256.hash(data: Data(dshAuthority.utf8))))
        let now = Date().timeIntervalSince1970 * 1000
        // 字段顺序要和 Node 那边一致：version, authority, issuedAt, expiresAt
        let json = "{\"version\":1,\"authority\":\"\(dshAuthority)\",\"issuedAt\":\(Int(now)),\"expiresAt\":\(Int(now) + 86400000)}"
        let body = b64url(Data(json.utf8))
        let key = SymmetricKey(data: secret)
        let mac = HMAC<SHA256>.authenticationCode(for: Data(body.utf8), using: key)
        return "\(name)=v1.\(body).\(b64url(Data(mac)))"
    }

    // MARK: - 落盘

    static func ensureDir() {
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    }

    /// 一行一日志。超过 1 MB 就砍掉前一半 —— 这东西是常驻的，
    /// 不设上限的话跑一年能长到几百兆。
    static func log(_ message: String) {
        ensureDir()
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(stamp)] \(message)\n"
        let fm = FileManager.default

        if let attrs = try? fm.attributesOfItem(atPath: logPath),
           let size = attrs[.size] as? Int, size > 1_000_000,
           let whole = try? String(contentsOfFile: logPath, encoding: .utf8) {
            let keep = String(whole.suffix(400_000))
            try? ("[日志已轮转]\n" + keep).write(toFile: logPath, atomically: true, encoding: .utf8)
        }

        if let h = FileHandle(forWritingAtPath: logPath) {
            h.seekToEndOfFile()
            h.write(Data(line.utf8))
            h.closeFile()
        } else {
            try? line.write(toFile: logPath, atomically: true, encoding: .utf8)
        }
    }
}
