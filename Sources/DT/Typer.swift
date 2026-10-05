// 把文字送进当前光标处。
// 走「剪贴板 + ⌘V」而不是逐字模拟按键，原因：模拟按键会被中文输入法截走，
// 变成一串拼音；粘贴不受输入法影响。代价是剪贴板被短暂借用，用完立刻还原。
import Cocoa

enum Typer {
    private struct Piece { let type: NSPasteboard.PasteboardType; let data: Data }

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }
        let pb = NSPasteboard.general

        // 先把原来剪贴板里的东西整份存下来（图片、文件也存）
        let saved: [[Piece]] = (pb.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { Piece(type: t, data: $0) } }
        }

        pb.clearContents()
        pb.setString(text, forType: .string)
        let mine = pb.changeCount

        paste()

        // 等粘贴真的落地再还原。这个等待不能太短：有些程序粘贴慢，
        // 抢在它读完剪贴板之前还原，粘进去的就会是上一份内容。
        // 顺便也防着用户这期间自己复制了东西——那样就不还原，免得覆盖他。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pb.changeCount == mine else { return }
            guard !saved.isEmpty else { return }
            pb.clearContents()
            let items = saved.map { pieces -> NSPasteboardItem in
                let it = NSPasteboardItem()
                for p in pieces { it.setData(p.data, forType: p.type) }
                return it
            }
            pb.writeObjects(items)
        }
    }

    private static func paste() {
        guard let src = CGEventSource(stateID: .combinedSessionState) else { return }
        let vKey: CGKeyCode = 9   // V
        if let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true) {
            down.flags = .maskCommand
            down.post(tap: .cgAnnotatedSessionEventTap)
        }
        usleep(15_000)
        if let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false) {
            up.flags = .maskCommand
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    /// 轻提示音：开始 / 结束 / 出错各一种，不用看屏幕也知道状态
    ///
    /// 用的是随包带进来的三个短音（`Resources/*.wav`），**不是系统提示音**。
    /// 原因：系统那几声彼此响度差得太多 —— 结尾那个 Pop 比开头的 Tink
    /// 轻了约 9 分贝，还拖到 1.6 秒，在吵一点的地方第一个听不见的就是它。
    /// 自己合成的音，音高、音量、时长都自己说了算，也不受 macOS 改版影响。
    ///
    /// 音高：开始 C6(1046.5) / 结束 C5(523.25) —— 同一个音名、低一个八度；
    /// 出错 F#5(740) —— 对 C 调来说是三全音，一听就知道"不对劲"。
    private static var soundCache: [Kind: NSSound] = [:]

    static func beep(_ kind: Kind) {
        if let cached = soundCache[kind] { cached.play(); return }
        guard let url = Bundle.main.url(forResource: kind.fileName, withExtension: "wav"),
              let s = NSSound(contentsOf: url, byReference: true) else {
            // 兜底：万一资源没打进去，退回系统音 —— 宁可音色老，也不能变成"没声音"
            let fallback: String
            switch kind {
            case .start: fallback = "Tink"
            case .stop:  fallback = "Pop"
            case .fail:  fallback = "Basso"
            }
            if let s = NSSound(named: NSSound.Name(fallback)) { s.volume = 0.6; s.play() }
            return
        }
        s.volume = 1.0
        soundCache[kind] = s
        s.play()
    }

    enum Kind {
        case start, stop, fail
        var fileName: String {
            switch self {
            case .start: return "start"
            case .stop:  return "stop"
            case .fail:  return "fail"
            }
        }
    }
}
