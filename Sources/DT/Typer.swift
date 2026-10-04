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
    static func beep(_ kind: Kind) {
        let name: String
        switch kind {
        case .start: name = "Tink"
        case .stop:  name = "Pop"
        case .fail:  name = "Basso"
        }
        if let s = NSSound(named: NSSound.Name(name)) { s.volume = 0.35; s.play() }
    }

    enum Kind { case start, stop, fail }
}
