// 两只耳朵。
//
//   VoiceStudio  —— 必须的。646 种语言都靠它，中英德日法……一句一句换着说也行。
//   DSH          —— 可选的。装了 DSH 的话，中文再请它的 SenseVoice 听一遍，
//                   出来的字更准（简体字 + 全角标点）。
//
// ⚠️ 一句话说清分工（2026-10-05 改版后）：**先问 DSH**。
//    · DSH 的结果像中文  → 直接用它（中文是它最准的地方）
//    · DSH 的结果不像中文 → 多半真是外语，交 VoiceStudio 重听
//    · DSH 没装 / 没接上  → 全程 VoiceStudio
//    为什么不能反过来（先喂 VoiceStudio）：它的**自动语言检测在短句上会跑偏** ——
//    实测把中文听成过泰文，也听成过一串拉丁字母。
//    ⚠️ 另一条同样重要：**不能等 SenseVoice 自己说"听不懂"** —— 它不认识德语时**不报错**，
//       而是硬猜成中文或英文。所以判据只能是外部的：**看它给的结果里汉字够不够多**
//       （`looksChinese`，阈值 0.4）。
//
// ⚠️ 已知限制（2026-10-05 实测，两个引擎都一样）：**一句话里夹两种语言，认不出来**。
//    引擎整句只判一个语言；中文句子里的德语词会被丢掉或听岔（实测「München」→「事」）。
//    要夹着说，**只能在换语言的位置顿一下**，让它单独成段。
//    详见 ../dictation-turbo/README.md 的「双引擎方案」一节。
import Foundation

enum Engines {

    /// 专用会话：不落缓存、不写磁盘。
    /// 识别请求本来就不该被缓存；默认会话还会在 ~/Library/Caches 里建数据库。
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 120
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return URLSession(configuration: cfg)
    }()

    // MARK: - WAV 打包 / 拆包

    /// 打一个**最朴素**的 WAV：只有 RIFF + fmt + data 三个块。
    ///
    /// 为什么不用系统自带转换：afconvert 会塞 FLLR 块、ffmpeg 会塞 LIST/INFO 块，
    /// 而 DSH 的接口只收最干净的 WAV（原话：canonical 16 kHz mono PCM16 WAV）。
    /// VoiceStudio 不挑，但两边都用同一个格式最省心。
    static func wav(fromPCM pcm: Data, sampleRate: Int = 16000, channels: Int = 1) -> Data {
        var head = Data()
        func u32(_ v: Int) { var x = UInt32(v).littleEndian; withUnsafeBytes(of: &x) { head.append(contentsOf: $0) } }
        func u16(_ v: Int) { var x = UInt16(v).littleEndian; withUnsafeBytes(of: &x) { head.append(contentsOf: $0) } }
        head.append(contentsOf: Array("RIFF".utf8))
        u32(36 + pcm.count)
        head.append(contentsOf: Array("WAVE".utf8))
        head.append(contentsOf: Array("fmt ".utf8))
        u32(16); u16(1); u16(channels)
        u32(sampleRate); u32(sampleRate * channels * 2); u16(channels * 2); u16(16)
        head.append(contentsOf: Array("data".utf8))
        u32(pcm.count)
        return head + pcm
    }

    /// 从一个**任意** WAV 里把 PCM 抠出来（自检用）。
    /// 不假定"44 字节头"—— 有些工具会插附加块，写死 44 就会读错。
    static func pcm(fromWav data: Data) -> (pcm: Data, sampleRate: Int, channels: Int)? {
        guard data.count > 12,
              data.prefix(4) == Data("RIFF".utf8),
              data[8..<12] == Data("WAVE".utf8) else { return nil }
        var i = 12
        var rate = 16000, channels = 1
        while i + 8 <= data.count {
            let id = data[i..<(i + 4)]
            let size = Int(data[i + 4]) | Int(data[i + 5]) << 8 | Int(data[i + 6]) << 16 | Int(data[i + 7]) << 24
            let body = i + 8
            if id == Data("fmt ".utf8), body + 16 <= data.count {
                channels = Int(data[body + 2]) | Int(data[body + 3]) << 8
                rate = Int(data[body + 4]) | Int(data[body + 5]) << 8
                    | Int(data[body + 6]) << 16 | Int(data[body + 7]) << 24
            }
            if id == Data("data".utf8) {
                let end = min(body + size, data.count)
                guard body < end else { return nil }
                return (data.subdata(in: body..<end), rate, max(1, channels))
            }
            if size <= 0 { break }
            i = body + size + (size % 2)   // 块长度是奇数时后面垫一个字节
        }
        return nil
    }

    /// 把任意采样率/声道数的 PCM 就地转成 16 kHz 单声道（自检用）。
    /// 只做最近邻抽点，够听清就够了 —— 真录音那条路是 AVAudioConverter 在转。
    static func normalize(_ pcm: Data, sampleRate: Int, channels: Int) -> Data {
        guard sampleRate != 16000 || channels != 1 else { return pcm }
        let frames = pcm.count / (2 * channels)
        guard frames > 0 else { return pcm }
        var out = Data(capacity: frames * 2 / max(1, sampleRate / 16000))
        let step = Double(sampleRate) / 16000.0
        var f = 0.0
        while Int(f) < frames {
            let off = Int(f) * 2 * channels
            if off + 2 <= pcm.count {
                out.append(pcm[off]); out.append(pcm[off + 1])
            }
            f += step
        }
        return out
    }

    // MARK: - VoiceStudio（必须的那只耳朵）

    /// 人话版的错误：把 URLError 翻成"它没在跑"这种一看就懂的说法。
    private static func friendly(_ err: Error) -> NSError {
        let ns = err as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost, NSURLErrorTimedOut:
                return NSError(domain: "dt", code: 100,
                               userInfo: [NSLocalizedDescriptionKey:
                                            "VoiceStudio 没在跑（\(Config.vsBase)）"])
            default: break
            }
        }
        return ns
    }

    /// 转写。走 VoiceStudio 自己的 /transcribe。
    ///
    /// ⚠️ 别改用 OpenAI 兼容的那个 /v1/audio/transcriptions —— 同一段 5 秒音频，
    /// 实测它要 8 秒，而 /transcribe 只要 0.3 秒（差 30 倍）。这是真踩过的坑。
    static func voiceStudio(_ wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard let url = URL(string: "\(Config.vsBase)/transcribe") else { return }
        let boundary = "----DT\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 120
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "content-type")

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(contentsOf: Array("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        body.append(contentsOf: Array("--\(boundary)\r\nContent-Disposition: form-data; name=\"audio\"; filename=\"a.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(wav)
        body.append(contentsOf: Array("\r\n".utf8))
        field("mode", "fast")
        // auto 就不传，交给它自己判断
        if Config.settings.languageHint != "auto", !Config.settings.languageHint.isEmpty {
            field("language", Config.settings.languageHint)
        }
        body.append(contentsOf: Array("--\(boundary)--\r\n".utf8))
        req.httpBody = body

        session.dataTask(with: req) { data, resp, err in
            if let err = err { completion(.failure(friendly(err))); return }
            if let http = resp as? HTTPURLResponse, http.statusCode >= 400 {
                completion(.failure(NSError(domain: "dt", code: 101, userInfo: [NSLocalizedDescriptionKey:
                    "VoiceStudio 报错 \(http.statusCode)（多半是它刚起来、模型还在加载，等一下再说）"])))
                return
            }
            guard let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
                  let text = obj["text"] as? String else {
                completion(.failure(NSError(domain: "dt", code: 5, userInfo: [NSLocalizedDescriptionKey: "VoiceStudio 返回的东西看不懂"])))
                return
            }
            completion(.success(text))
        }.resume()
    }

    /// 探一下 VoiceStudio 活没活（给 --doctor 和菜单用）。
    static func voiceStudioHealth(timeout: TimeInterval = 3,
                                  completion: @escaping (Bool, String) -> Void) {
        guard let url = URL(string: "\(Config.vsBase)/health") else {
            completion(false, "地址不对：\(Config.vsBase)"); return
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        session.dataTask(with: req) { data, _, err in
            if err != nil { completion(false, "连不上 \(Config.vsBase)"); return }
            guard let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(false, "有响应但看不懂"); return
            }
            let status = obj["status"] as? String ?? "?"
            let device = obj["device"] as? String ?? "?"
            let version = obj["version"] as? String ?? "?"
            completion(status == "ok", "v\(version)，用 \(device)")
        }.resume()
    }

    // MARK: - DSH（可选的中文增强）

    static func dsh(_ wav: Data, completion: @escaping (Result<String, Error>) -> Void) {
        guard Config.dshAllowed else {
            completion(.failure(NSError(domain: "dt", code: 200, userInfo: [NSLocalizedDescriptionKey: "已按设置关掉 DSH"])))
            return
        }
        guard let cookie = Config.dshCookie() else {
            completion(.failure(NSError(domain: "dt", code: 1, userInfo: [NSLocalizedDescriptionKey: "读不到 DSH 凭证（没装 DSH 就是这样，正常）"])))
            return
        }
        let url = URL(string: "http://\(Config.dshAuthority)/api/speech/transcribe")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "content-type")
        req.setValue(Config.dshAuthority, forHTTPHeaderField: "Host")
        req.setValue("http://\(Config.dshAuthority)", forHTTPHeaderField: "Origin")
        req.setValue(cookie, forHTTPHeaderField: "Cookie")

        let payload: [String: Any] = [
            "type": "client-request",
            "rpcId": UUID().uuidString,
            "method": "speech/transcribe",
            // ⚠️ 参数外面必须包一层 request，少这层会被拒：
            // gateway/arguments-invalid: missing "request"
            "payload": ["args": ["request": ["audioBase64": wav.base64EncodedString()]]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload)

        session.dataTask(with: req) { data, _, err in
            if let err = err { completion(.failure(friendly(err))); return }
            guard let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                completion(.failure(NSError(domain: "dt", code: 2, userInfo: [NSLocalizedDescriptionKey: "DSH 回的不是 JSON"])))
                return
            }
            if let result = obj["result"] as? [String: Any] {
                if let ok = result["ok"] as? Bool, ok, let value = result["value"] as? [String: Any],
                   let text = value["text"] as? String {
                    completion(.success(text)); return
                }
                if let e = result["error"] as? [String: Any] {
                    completion(.failure(NSError(domain: "dt", code: 3, userInfo: [NSLocalizedDescriptionKey:
                        "DSH：\(e["code"] ?? "?") \(e["message"] ?? "?")"])))
                    return
                }
            }
            completion(.failure(NSError(domain: "dt", code: 4, userInfo: [NSLocalizedDescriptionKey: "DSH 返回结构不认识"])))
        }.resume()
    }

    /// DSH 在不在（给 --doctor 用）：能算出凭证 + 端口有人应答
    static func dshHealth(timeout: TimeInterval = 3, completion: @escaping (Bool, String) -> Void) {
        guard Config.dshAllowed else { completion(false, "已在设置里关掉"); return }
        guard Config.dshCookie() != nil else { completion(false, "没找到 DSH 凭证（没装 DSH）"); return }
        guard let url = URL(string: "http://\(Config.dshAuthority)/") else { completion(false, "地址不对"); return }
        var req = URLRequest(url: url)
        req.timeoutInterval = timeout
        session.dataTask(with: req) { _, resp, err in
            if err != nil { completion(false, "凭证在，但端口没人应答"); return }
            if let http = resp as? HTTPURLResponse {
                // 没带 Cookie 去敲它，401 是正常的 —— 只要有人应答就说明它在跑
                completion(true, http.statusCode == 401 ? "在跑（端口有应答）" : "在跑（HTTP \(http.statusCode)）")
            } else {
                completion(false, "没应答")
            }
        }.resume()
    }

    // MARK: - 路由

    /// 结果落在"他不会说的文字系统"里？（泰文、阿拉伯文、西里尔文……）
    ///
    /// VoiceStudio 的自动语言检测在短句上会跑偏：明明是中文，它能听成泰文
    /// （2026-10-05 实测，框里出来一串 `อย่างเลา.`）。
    /// 这种情况要送去 DSH 重听 —— DSH 只出中文/英文/日文/韩文/粤语，救得回来。
    /// 德语/英语是拉丁字母、中文是汉字、日韩是假名谚文，都不算"跑偏"，不受影响。
    static func looksOffScript(_ text: String) -> Bool {
        var odd = 0
        var letters = 0
        for s in text.unicodeScalars where CharacterSet.letters.contains(s) {
            letters += 1
            let v = s.value
            let latin = (0x41...0x5A).contains(v) || (0x61...0x7A).contains(v) || (0xC0...0x24F).contains(v)
            let han = (0x4E00...0x9FFF).contains(v)
            let kana = (0x3040...0x30FF).contains(v)
            let hangul = (0xAC00...0xD7AF).contains(v)
            if !(latin || han || kana || hangul) { odd += 1 }
        }
        guard letters > 0 else { return false }
        return Double(odd) / Double(letters) > 0.3
    }

    /// 含汉字的比例够高就认为说的是中文。
    /// 这一步是必需的：SenseVoice 不认识德语时不会说"我不认识"，它硬猜。
    static func looksChinese(_ text: String) -> Bool {
        let han = text.unicodeScalars.filter { (0x4E00...0x9FFF).contains($0.value) }.count
        let letters = text.unicodeScalars.filter { CharacterSet.letters.contains($0) }.count
        guard letters > 0 else { return false }
        return Double(han) / Double(letters) > 0.4
    }

    /// 主流程（2026-10-05 改版，用户要求：「中文直接走 DSH 那个引擎」）。
    ///
    /// 他是中文母语，日常绝大多数话是中文；而 VoiceStudio 的**自动语言检测**
    /// 在短句上会跑偏 —— 实测把中文听成过泰文、也听成过一串拉丁字母。
    /// DSH 的 SenseVoice 是中文专精，这种错它基本不犯。
    ///
    /// 所以顺序倒过来了：**先问 DSH**
    ///   · DSH 给的结果像中文 → 直接用它（这正是它最准的地方）
    ///   · DSH 给的不像中文   → 多半真不是中文（德语/英语…），交给 VoiceStudio
    ///   · DSH 没装 / 没接上  → 全程 VoiceStudio
    ///
    /// 代价：说德语时 DSH 会先空跑一次（约 0.2 秒）才发现"这不是中文"。
    /// 中文则快了一倍 —— 少一次网络往返。
    static func route(_ wav: Data, completion: @escaping (String?, String) -> Void) {
        guard Config.settings.chineseViaDSH else {
            voiceStudioOnly(wav, completion: completion)
            return
        }
        dsh(wav) { dshResult in
            var dshText: String?
            if case .success(let t) = dshResult {
                let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { dshText = trimmed }
                if !trimmed.isEmpty, looksChinese(trimmed) {
                    completion(trimmed, "DSH")
                    return
                }
            }
            // DSH 没结果、或者它听着不像中文 → 请 VoiceStudio 再听
            voiceStudio(wav) { vsResult in
                switch vsResult {
                case .success(let vsText):
                    completion(vsText, dshText == nil ? "VoiceStudio" : "VoiceStudio（DSH 听着不像中文）")
                case .failure(let vsErr):
                    Config.log("VoiceStudio 没接上：\(vsErr.localizedDescription)")
                    if let t = dshText {
                        completion(t, "DSH（VoiceStudio 没接上）")
                    } else {
                        completion(nil, "两个引擎都没接上")
                    }
                }
            }
        }
    }

    /// 不用 DSH 时：VoiceStudio 一条路走到底。
    private static func voiceStudioOnly(_ wav: Data, completion: @escaping (String?, String) -> Void) {
        voiceStudio(wav) { vsResult in
            switch vsResult {
            case .success(let vsText): completion(vsText, "VoiceStudio")
            case .failure(let vsErr):
                Config.log("VoiceStudio 没接上：\(vsErr.localizedDescription)")
                completion(nil, "VoiceStudio 没接上")
            }
        }
    }
}
