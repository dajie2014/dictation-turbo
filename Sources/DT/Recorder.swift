// 收音：麦克风 → 16 kHz 单声道 PCM。
import AVFoundation

final class Recorder {
    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var pcm = Data()
    private var converter: AVAudioConverter?
    private var startedAt: Date?
    private(set) var isRecording = false
    /// 实时电平（0…1），给菜单栏图标用
    private(set) var level: Float = 0
    /// 录到过的最响一下，用来判断"其实没说话"
    private(set) var peak: Float = 0

    static let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!

    var seconds: Double {
        guard let s = startedAt else { return 0 }
        return Date().timeIntervalSince(s)
    }

    func start() throws {
        guard !isRecording else { return }
        pcm.removeAll()
        peak = 0
        level = 0

        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0 else {
            throw NSError(domain: "dt", code: 10, userInfo: [NSLocalizedDescriptionKey: "拿不到麦克风（可能还没授权）"])
        }

        // ★ 转换器建在「单声道」格式上，而不是设备原始的多通道格式上。
        //   为什么（2026-10-07 实测）：多通道声卡（Scarlett 18i8，20 路输入）
        //   直接丢给 AVAudioConverter 做 20→1 下混，输出**恒为全零** ——
        //   表现就是"收音失败"（三全音），日志写「没听到声音（峰值 0.000）」。
        //   同一段音频实测：直接 20→1 得 0.00000；先挑出有声音的那一路再转，得 0.06565。
        //   所以这里先自己缩成单声道，再交给转换器。
        guard let monoFormat = AVAudioFormat(commonFormat: inFormat.commonFormat,
                                             sampleRate: inFormat.sampleRate,
                                             channels: 1,
                                             interleaved: inFormat.isInterleaved) else {
            throw NSError(domain: "dt", code: 11, userInfo: [NSLocalizedDescriptionKey: "建不出单声道格式"])
        }
        converter = AVAudioConverter(from: monoFormat, to: Recorder.target)

        input.installTap(onBus: 0, bufferSize: 4096, format: inFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        engine.prepare()
        try engine.start()
        startedAt = Date()
        isRecording = true
    }

    /// 停止并交出录到的 PCM
    @discardableResult
    func stop() -> Data {
        guard isRecording else { return Data() }
        isRecording = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        startedAt = nil
        lock.lock(); let out = pcm; lock.unlock()
        return out
    }

    /// 把多通道缩成单声道：**取绝对值最大的那一路**，不是求平均。
    /// 求平均会把"只有一路有话简"的信号稀释成 1/20（约 −26 dB）；
    /// 而直接下混在 20 通道设备上干脆输出全零。
    private func downmixToMono(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let nch = Int(buffer.format.channelCount)
        if nch <= 1 { return buffer }
        guard let fmt = AVAudioFormat(commonFormat: buffer.format.commonFormat,
                                      sampleRate: buffer.format.sampleRate,
                                      channels: 1,
                                      interleaved: buffer.format.isInterleaved),
              let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: buffer.frameLength)
        else { return nil }
        out.frameLength = buffer.frameLength
        let n = Int(buffer.frameLength)

        if let src = buffer.floatChannelData, let dst = out.floatChannelData {
            for i in 0..<n { dst[0][i] = 0 }
            for c in 0..<nch {
                let p = src[c]
                for i in 0..<n where abs(p[i]) > abs(dst[0][i]) { dst[0][i] = p[i] }
            }
            return out
        }
        if let src = buffer.int16ChannelData, let dst = out.int16ChannelData {
            for i in 0..<n { dst[0][i] = 0 }
            for c in 0..<nch {
                let p = src[c]
                for i in 0..<n where abs(Int(p[i])) > abs(Int(dst[0][i])) { dst[0][i] = p[i] }
            }
            return out
        }
        if let src = buffer.int32ChannelData, let dst = out.int32ChannelData {
            for i in 0..<n { dst[0][i] = 0 }
            for c in 0..<nch {
                let p = src[c]
                for i in 0..<n where abs(p[i]) > abs(dst[0][i]) { dst[0][i] = p[i] }
            }
            return out
        }
        return nil
    }

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
        guard let mono = downmixToMono(buffer) else { return }

        let ratio = Recorder.target.sampleRate / mono.format.sampleRate
        let capacity = AVAudioFrameCount(Double(mono.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Recorder.target, frameCapacity: capacity) else { return }

        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return mono
        }
        guard err == nil, out.frameLength > 0, let ch = out.int16ChannelData else { return }

        let frames = Int(out.frameLength)
        let bytes = Data(bytes: ch[0], count: frames * 2)
        lock.lock(); pcm.append(bytes); lock.unlock()

        // 电平：取这一块的最大绝对值
        var maxAbs: Int16 = 0
        ch[0].withMemoryRebound(to: Int16.self, capacity: frames) { p in
            for i in 0..<frames { let v = abs(Int(p[i])); if v > Int(maxAbs) { maxAbs = Int16(min(v, 32767)) } }
        }
        let l = Float(maxAbs) / 32767.0
        level = l
        if l > peak { peak = l }
    }
}
