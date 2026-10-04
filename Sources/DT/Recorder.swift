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
        converter = AVAudioConverter(from: inFormat, to: Recorder.target)

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

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard let converter = converter else { return }
        let ratio = Recorder.target.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Recorder.target, frameCapacity: capacity) else { return }

        var fed = false
        var err: NSError?
        converter.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
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
