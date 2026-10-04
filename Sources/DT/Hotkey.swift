// 全局热键：在任何应用里双击 Control。
// 用的是系统级事件监听，所以需要「辅助功能」权限 —— 给一次就够。
import Cocoa

/// 「干净的双击」判定。
///
/// 为什么单独拎出来：这段是最容易被误触的地方，也是唯一能**不碰键盘就测出来**的逻辑
/// （见 `--hotkey-test`）。判定规则两条：
///   1. 两次 Control 按下，间隔不超过 window；
///   2. 这两次之间**不能按过别的键** —— 否则就是在连按快捷键，不是在双击。
///
/// 第 2 条是踩出来的：只按间隔判断的话，连按两次 Ctrl+Z（撤销）之类的操作
/// 会被当成"开始听写"，然后一直录到用户再双击一次为止 —— 实测误录过 61 秒。
struct DoubleTapDetector {
    /// 两次 Control 之间最多隔多久（秒）
    var window: TimeInterval = 0.35
    /// 第一次按下、还在等第二次的那个时刻
    private var pending: Date?

    /// 收到一次 Control 按下；返回 true 表示这构成了双击。
    mutating func controlDown(at now: Date) -> Bool {
        if let last = pending, now.timeIntervalSince(last) <= window {
            pending = nil
            return true
        }
        pending = now
        return false
    }

    /// 收到别的键按下 —— 把还在等的那次取消掉。
    mutating func otherKeyDown() {
        pending = nil
    }
}

final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var detector = DoubleTapDetector()

    var onDoubleTap: (() -> Void)?
    /// 正在录音时返回 true —— 这时候**放松**"干净双击"那条要求。
    /// 免得一边说话一边还在打字的人，反而停不下来。
    var isRelaxed: (() -> Bool)?

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// 弹系统的授权引导（会打开「系统设置 → 隐私与安全性 → 辅助功能」）
    static func askPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard HotkeyMonitor.hasPermission else { return false }
        // 除了修饰键的变化，还要听普通按键 —— 只为了判断"两次 Control 中间有没有按别的键"
        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                if let refcon = refcon {
                    let me = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                    me.handle(type: type, event: event)
                }
                // 原样放行 —— 我们只是旁听，绝不改别人的按键
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }

        self.tap = tap
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.source = src
        CFRunLoopAddSource(CFRunLoopGetCurrent(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        Config.log("热键监听已启动")
        return true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        // 系统偶尔会因为回调太慢把监听关掉，这里给它开回来。
        // 少了这一段，表现就是"用着用着双击就没反应了"。
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Config.log("监听被系统暂停过，已重新启用")
            return
        }

        // 普通按键：只用来把待定的那次 Control 作废。
        // ⚠️ 这里在按键路径上，**不要做任何写文件之类的慢活** ——
        // 回调一慢，系统就会把整个监听停掉。
        if type == .keyDown {
            if !(isRelaxed?() ?? false) { detector.otherKeyDown() }
            return
        }

        guard type == .flagsChanged else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 59 || code == 62 else { return }            // 左 / 右 Control
        guard event.flags.contains(.maskControl) else { return }  // 只认"按下"

        detector.window = Config.settings.doubleTapSeconds
        if detector.controlDown(at: Date()) {
            DispatchQueue.main.async { self.onDoubleTap?() }
        }
    }
}

// MARK: - 不碰键盘也能验的双击判定

/// `DictationTurbo --hotkey-test`
/// 全是纯逻辑，不申请权限、不发任何按键 —— 所以随时可以跑，不会动到你在编辑的东西。
enum HotkeySelfTest {
    static func run() -> Int32 {
        var fails = 0
        let t0 = Date()

        func check(_ name: String, _ got: Bool, _ want: Bool) {
            let ok = (got == want)
            print("  \(ok ? "✓" : "✗") \(name)")
            if !ok { fails += 1 }
        }

        print("")
        print("双击判定自检（纯逻辑，不碰键盘）")
        print("==============================================")

        // ① 正常双击
        var d = DoubleTapDetector()
        _ = d.controlDown(at: t0)
        check("干净双击（隔 0.18 秒）→ 应该开始/结束听写",
              d.controlDown(at: t0.addingTimeInterval(0.18)), true)

        // ② 中间夹了别的键：连按 Ctrl+Z 这类操作不该被当成双击
        d = DoubleTapDetector()
        _ = d.controlDown(at: t0)
        d.otherKeyDown()
        check("中间按过别的键（连按快捷键那种）→ 不应该触发",
              d.controlDown(at: t0.addingTimeInterval(0.18)), false)

        // ③ 隔太久：算两次单击
        d = DoubleTapDetector()
        _ = d.controlDown(at: t0)
        check("隔 0.8 秒（超过窗口）→ 不应该触发",
              d.controlDown(at: t0.addingTimeInterval(0.8)), false)
        check("上面那次算新的一次按下，再隔 0.18 秒 → 应该触发",
              d.controlDown(at: t0.addingTimeInterval(0.98)), true)

        // ④ 连按三下只触发一次
        d = DoubleTapDetector()
        let f1 = d.controlDown(at: t0)
        let f2 = d.controlDown(at: t0.addingTimeInterval(0.12))
        let f3 = d.controlDown(at: t0.addingTimeInterval(0.24))
        check("连按三下 → 只触发一次",
              [f1, f2, f3].filter { $0 }.count == 1, true)

        // ⑤ 作废之后重新计：中间夹键取消，再双击一次仍然好使
        d = DoubleTapDetector()
        _ = d.controlDown(at: t0)
        d.otherKeyDown()
        _ = d.controlDown(at: t0.addingTimeInterval(0.30))
        check("被作废之后，重新双击一次照样能用",
              d.controlDown(at: t0.addingTimeInterval(0.45)), true)

        print("")
        print(fails == 0 ? "全过 ✓" : "有 \(fails) 项没过 ✗")
        return fails == 0 ? 0 : 1
    }
}
