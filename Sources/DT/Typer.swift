// 把文字送进当前光标处。
//
// 主路是「剪贴板 + ⌘V」而不是逐字模拟按键，原因：模拟按键会被中文输入法截走，
// 变成一串拼音；粘贴不受输入法影响。代价是剪贴板被短暂借用，用完立刻还原。
//
// ⚠️ 但有一条路它走不通：**聚焦搜索（⌘空格）这类系统浮窗不理合成的 ⌘V**。
// 2026-10-05 实测：识别结果出来了、日志也写"已送进光标"，可框里一个字都没有。
// 所以粘完之后会核对一次，没进去就改成「走辅助功能接口直接写值」——
// 那条路不经过键盘，系统浮窗认。
import Cocoa
import ApplicationServices

enum Typer {
    private struct Piece { let type: NSPasteboard.PasteboardType; let data: Data }

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }

        // 先记住"键盘现在归哪个应用、它里面那个文本框是谁、里面原本是什么" —— 待会儿核对要用。
        let target = focusedElementOfKeyboardApp()
        let before = target.flatMap(valueOf)

        // 主路：剪贴板 + ⌘V
        insertViaClipboard(text)

        // 核对：普通应用这会儿已经粘进去了，直接收工。
        // 只有"读得到值、但值没变"（= 这个界面不理合成粘贴）才走写值那条路。
        // 读不到值就不动 —— 读不到说明这套接口对它无效，硬写只会落两遍。
        guard let el = target else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            guard let now = valueOf(el) else { return }
            if now.contains(text) { return }          // 粘贴成了
            guard now == before else { return }       // 值变了但不是我们要的，别插手
            if writeValue(el, old: now, add: text) {
                Config.log("粘贴进不去（这个界面不理合成按键），改成直接写值：成功")
            } else {
                Config.log("粘贴进不去，直接写值也没成")
            }
        }
    }

    /// 问系统："键盘现在归哪个应用"，再问那个应用"你自己的焦点元素是谁"。
    ///
    /// ⚠️ 不能直接问系统级的「焦点元素」—— 聚焦搜索开着的时候它会撒谎（照样报 DSH）。
    /// 必须先问到应用，再向那个应用问它自己的焦点元素。
    private static func focusedElementOfKeyboardApp() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedApplicationAttribute as CFString, &appRef) == .success,
              let appEl = appRef else { return nil }
        var focusRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl as! AXUIElement, kAXFocusedUIElementAttribute as CFString, &focusRef) == .success,
              let focusEl = focusRef else { return nil }
        return (focusEl as! AXUIElement)
    }

    /// 读一个元素的文字。读不到（接口不支持）就返回 nil —— 调用方按"别插手"处理。
    private static func valueOf(_ el: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &roleRef)
        let role = (roleRef as? String) ?? ""
        let editable = [kAXTextFieldRole as String, kAXTextAreaRole as String, kAXComboBoxRole as String]
        guard editable.contains(role) else { return nil }
        var valRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXValueAttribute as CFString, &valRef) == .success else { return nil }
        return (valRef as? String)
    }

    /// 直接把这句话写进那个文本框（追加在原有内容后面），写完读回来核对。
    private static func writeValue(_ el: AXUIElement, old: String, add: String) -> Bool {
        guard AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, (old + add) as CFString) == .success else {
            return false
        }
        usleep(80_000)
        guard let now = valueOf(el) else { return false }
        return now != old
    }

    /// 主路：借用剪贴板 + 合成一次 ⌘V，用完把剪贴板还回去。
    private static func insertViaClipboard(_ text: String) {
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
