// 自检：不开界面、不碰麦克风，直接拿一个 WAV 走一遍"该用哪只耳朵"的完整流程。
// 用途：在让人真的去按热键之前，先证明鉴权、请求、路由这三段是对的。
//
//   DictationTurbo --selftest a.wav [b.wav …]
//
// 任意 WAV 都行（不要求 16 kHz / 单声道），它会自己转。
import Foundation

enum SelfTest {
    static func run(paths: [String]) {
        guard !paths.isEmpty else {
            FileHandle.standardError.write(Data("用法：DictationTurbo --selftest <某个.wav> [更多.wav]\n".utf8))
            exit(2)
        }
        var bad = 0
        for path in paths {
            guard let raw = FileManager.default.contents(atPath: path) else {
                print("✗ 读不到文件：\(path)"); bad += 1; continue
            }
            let wav: Data
            if let parsed = Engines.pcm(fromWav: raw) {
                let pcm = Engines.normalize(parsed.pcm, sampleRate: parsed.sampleRate, channels: parsed.channels)
                print("音频：\(path)  \(parsed.sampleRate) Hz / \(parsed.channels) 声道 → \(pcm.count / 32) 毫秒")
                wav = Engines.wav(fromPCM: pcm)
            } else {
                print("音频：\(path)  （不是 WAV，当作裸 16 kHz 单声道 PCM 试一把）")
                wav = Engines.wav(fromPCM: raw)
            }

            let sem = DispatchSemaphore(value: 0)
            var done = false
            let t0 = Date()
            Engines.route(wav) { text, who in
                let dt = String(format: "%.2f", Date().timeIntervalSince(t0))
                print("  用时：\(dt) 秒")
                print("  引擎：\(who)")
                print("  文字：\(text ?? "（空）")")
                if text == nil { bad += 1 }
                done = true
                sem.signal()
            }
            if sem.wait(timeout: .now() + 120) == .timedOut || !done {
                FileHandle.standardError.write(Data("✗ 超时：2 分钟没等到结果（多半是 VoiceStudio 没开）\n".utf8))
                bad += 1
            }
        }
        exit(bad == 0 ? 0 : 1)
    }
}
