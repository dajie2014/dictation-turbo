// 全局热键：在任何应用里双击 Control。
// 用的是系统级事件监听，所以需要「辅助功能」权限——一次就够。
import Cocoa

final class HotkeyMonitor {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var lastDown: Date?

    var onDoubleTap: (() -> Void)?

    static var hasPermission: Bool { AXIsProcessTrusted() }

    /// 弹系统的授权引导（会打开「系统设置 → 隐私与安全性 → 辅助功能」）
    static func askPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard HotkeyMonitor.hasPermission else { return false }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
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
                // 原样放行——我们只是旁听，绝不改别人的按键
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
        // 系统偶尔会因为回调太慢把监听关掉，这里给它开回来
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = tap { CGEvent.tapEnable(tap: tap, enable: true) }
            Config.log("监听被系统暂停过，已重新启用")
            return
        }
        guard type == .flagsChanged else { return }
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        guard code == 59 || code == 62 else { return }        // 左 / 右 Control
        guard event.flags.contains(.maskControl) else { return }  // 只认"按下"

        let now = Date()
        if let last = lastDown, now.timeIntervalSince(last) <= Config.settings.doubleTapSeconds {
            lastDown = nil
            DispatchQueue.main.async { self.onDoubleTap?() }
        } else {
            lastDown = now
        }
    }
}
