// Dictation Turbo —— 在任何地方双击 Control，说话，文字落进光标。
// 常驻菜单栏、没有窗口。它要"躺在系统里"，不是那种要切过去的程序。
import Cocoa
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let recorder = Recorder()
    private let hotkey = HotkeyMonitor()
    private var busy = false
    private var timeoutTimer: Timer?
    private var listening = false
    /// DSH 在前台时让路给页面版插件（不然同一句话会被塞进输入框两次）
    private var yieldToDSHPage = Config.settings.yieldToDSHPage

    func applicationDidFinishLaunching(_ notification: Notification) {
        Config.ensureDir()
        askMicrophoneOnce()
        buildMenu()
        refreshIcon()
        if HotkeyMonitor.hasPermission {
            startListening()
        } else {
            Config.log("缺少辅助功能权限，等用户授权")
            HotkeyMonitor.askPermission()
            watchPermission()
        }
    }

    /// 第一次跑就主动问一次麦克风权限 —— 免得用户按了热键才发现没授权，
    /// 那边只有一声"叮"然后什么都没有。
    private func askMicrophoneOnce() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { ok in
                Config.log(ok ? "麦克风权限已给" : "麦克风权限被拒")
            }
        case .denied:
            Config.log("麦克风权限被拒 —— 系统设置里勾上才能用")
        default:
            break
        }
    }

    /// 权限没拿到时每 2 秒看一眼，拿到就立刻开工，最多看 5 分钟。
    /// 只在"缺权限"这个状态下跑，拿到就停 —— 不是常驻轮询。
    private func watchPermission() {
        var tries = 0
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] t in
            tries += 1
            guard let self = self else { t.invalidate(); return }
            if HotkeyMonitor.hasPermission {
                t.invalidate()
                Config.log("权限到了，自动开始监听")
                self.startListening()
            } else if tries > 150 {
                t.invalidate()
                Config.log("等了 5 分钟还没权限，先不看了（菜单里可手动重试）")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    // MARK: - 菜单栏

    private func buildMenu() {
        let menu = NSMenu()
        let tip = NSMenuItem(title: "双击 Control 开始／结束说话", action: nil, keyEquivalent: "")
        tip.isEnabled = false
        menu.addItem(tip)
        menu.addItem(.separator())

        let perm = NSMenuItem(title: "① 授予辅助功能权限…", action: #selector(openPermission), keyEquivalent: "")
        perm.target = self
        menu.addItem(perm)

        let again = NSMenuItem(title: "② 权限已给，重新开始监听", action: #selector(relisten), keyEquivalent: "")
        again.target = self
        menu.addItem(again)

        menu.addItem(.separator())
        let engines = NSMenuItem(title: "检查引擎状态", action: #selector(checkEngines), keyEquivalent: "")
        engines.target = self
        menu.addItem(engines)

        // 单独验"落字"这一段：不动麦克风，3 秒后往光标处贴一句。
        // 识别对了但字没出来时，用它能把毛病锁在后半段。
        let typetest = NSMenuItem(title: "试一下落字（3 秒后）", action: #selector(testTyping), keyEquivalent: "")
        typetest.target = self
        menu.addItem(typetest)

        let log = NSMenuItem(title: "看记录", action: #selector(openLog), keyEquivalent: "")
        log.target = self
        menu.addItem(log)

        menu.addItem(.separator())
        // 同一个手势已经被 DSH 页面里那版占着了。让全系统版在 DSH 前台时让路，
        // 否则两边会同时开录，同一句话被塞进输入框两次。
        let yield = NSMenuItem(title: "DSH 窗口里让路给页面版", action: #selector(toggleYield), keyEquivalent: "")
        yield.target = self
        yield.state = yieldToDSHPage ? .on : .off
        menu.addItem(yield)

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 Dictation Turbo", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func setIcon(_ symbol: String, tint: NSColor?, tip: String) {
        DispatchQueue.main.async {
            if let button = self.statusItem.button {
                let img = NSImage(systemSymbolName: symbol, accessibilityDescription: tip)
                img?.isTemplate = (tint == nil)
                button.image = img
                button.contentTintColor = tint
                button.toolTip = tip
            }
        }
    }

    private func refreshIcon() {
        if !listening {
            setIcon("exclamationmark.triangle", tint: .systemOrange, tip: "还没拿到辅助功能权限")
        } else if recorder.isRecording {
            setIcon("mic.fill", tint: .systemRed, tip: "正在听…（再双击 Control 结束）")
        } else if busy {
            setIcon("ellipsis.circle", tint: .systemBlue, tip: "正在转写…")
        } else {
            setIcon("mic", tint: nil, tip: "待命：双击 Control 开始")
        }
    }

    // MARK: - 菜单动作

    @objc private func openPermission() {
        HotkeyMonitor.askPermission()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relisten() {
        startListening()
    }

    @objc private func toggleYield(_ sender: NSMenuItem) {
        yieldToDSHPage.toggle()
        sender.state = yieldToDSHPage ? .on : .off
        UserDefaults.standard.set(yieldToDSHPage, forKey: "yieldToDSHPage")
        Config.settings.yieldToDSHPage = yieldToDSHPage
        Config.log("DSH 页面让路：\(yieldToDSHPage ? "开" : "关")")
    }

    /// 出问题时先点这个：一眼看清是哪一只耳朵没接上。
    @objc private func checkEngines() {
        Engines.voiceStudioHealth { vsOK, vsDetail in
            Engines.dshHealth { dshOK, dshDetail in
                DispatchQueue.main.async {
                    let a = NSAlert()
                    a.messageText = vsOK ? "引擎正常" : "没连上 VoiceStudio"
                    a.informativeText = """
                    VoiceStudio（必须的）：\(vsOK ? "✅ 在跑，\(vsDetail)" : "❌ \(vsDetail)")
                    DSH 中文增强（可选）：\(dshOK ? "✅ \(dshDetail)" : "➖ \(dshDetail)")

                    \(vsOK ? "双击 Control 就能用了。"
                           : "请先把 VoiceStudio 打开 —— 把话变成字是它干的活。")
                    """
                    a.addButton(withTitle: "好")
                    NSApp.activate(ignoringOtherApps: true)
                    a.runModal()
                }
            }
        }
    }

    @objc private func testTyping() {
        Config.log("落字自测：3 秒后往光标处贴一句")
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            Typer.insert("这是落字测试，一二三四五。")
            Config.log("落字自测已发出")
        }
    }

    @objc private func openLog() {
        NSWorkspace.shared.open(URL(fileURLWithPath: Config.logPath))
    }

    private func startListening() {
        guard HotkeyMonitor.hasPermission else {
            listening = false; refreshIcon(); return
        }
        if !listening {
            hotkey.onDoubleTap = { [weak self] in self?.toggle() }
            listening = hotkey.start()
            Config.log(listening ? "监听已就绪" : "监听启动失败")
        }
        refreshIcon()
    }

    // MARK: - 主流程

    private func toggle() {
        // 已经在录了就一定让它能停，哪怕这时候人切到了 DSH
        if yieldToDSHPage, !recorder.isRecording,
           NSWorkspace.shared.frontmostApplication?.bundleIdentifier == Config.dshBundleID {
            Config.log("DSH 在前台，让路给页面版")
            return
        }
        if recorder.isRecording { finish() } else { begin() }
    }

    private func begin() {
        guard !busy, !recorder.isRecording else { return }
        do {
            // 先响再开录：这一声要是被自己录进去，偶尔会被识别成莫名其妙的字
            Typer.beep(.start)
            Thread.sleep(forTimeInterval: 0.18)
            try recorder.start()
            refreshIcon()
            timeoutTimer = Timer.scheduledTimer(withTimeInterval: Config.settings.maxRecordSeconds,
                                                repeats: false) { [weak self] _ in
                Config.log("录满 \(Int(Config.settings.maxRecordSeconds)) 秒，自动收工")
                self?.finish()
            }
        } catch {
            Config.log("麦克风打不开：\(error.localizedDescription)")
            Typer.beep(.fail)
            refreshIcon()
        }
    }

    private func finish() {
        timeoutTimer?.invalidate(); timeoutTimer = nil
        let length = recorder.seconds
        let peak = recorder.peak
        let pcm = recorder.stop()
        refreshIcon()

        guard length >= Config.settings.minRecordSeconds, !pcm.isEmpty else {
            Config.log("录得太短（\(String(format: "%.2f", length)) 秒），当误触丢掉")
            return
        }
        // 全程几乎没声音就不必送识别了（静音也会被硬猜出东西来）
        guard peak > Config.settings.minPeak else {
            Config.log("没听到声音（峰值 \(String(format: "%.3f", peak))），跳过识别")
            Typer.beep(.fail)
            return
        }

        busy = true
        refreshIcon()
        Config.log("收工：\(String(format: "%.2f", length)) 秒，峰值 \(String(format: "%.2f", peak))")

        let wav = Engines.wav(fromPCM: pcm)
        Engines.route(wav) { [weak self] text, who in
            DispatchQueue.main.async {
                self?.busy = false
                if let text = text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    Config.log("[\(who)] \(clean)")
                    Typer.insert(clean)
                    Config.log("已送进光标：\(clean.count) 个字")
                    Typer.beep(.stop)
                } else {
                    Config.log("没接上引擎，什么都没落（菜单里点「检查引擎状态」看看）")
                    Typer.beep(.fail)
                }
                self?.refreshIcon()
            }
        }
    }
}

// MARK: - 命令行模式（不起界面、不碰麦克风）

private func printHelp() {
    print("""
    Dictation Turbo \(Config.version) —— 在任何地方双击 Control，说话，文字落进光标

    用法：
      DictationTurbo                 正常跑（菜单栏常驻）
      DictationTurbo --doctor        体检：权限、签名、两只耳朵、麦克风、自启
      DictationTurbo --selftest a.wav [b.wav …]   不开麦克风，只验识别那一段
      DictationTurbo --version
    """)
}

let argv = CommandLine.arguments
if argv.count >= 2 {
    switch argv[1] {
    case "--selftest":
        SelfTest.run(paths: Array(argv.dropFirst(2)))
    case "--doctor":
        Doctor.run()
    case "--version":
        print(Config.version); exit(0)
    case "--help", "-h":
        printHelp(); exit(0)
    default:
        break
    }
}

// 只允许一个实例。开两个的话，同一个手势会被两边同时响应，
// 一句话录两遍、往光标里贴两遍。
private func claimSingleInstance() {
    Config.ensureDir()
    let fd = open(Config.lockPath, O_CREAT | O_RDWR, 0o644)
    if fd < 0 || flock(fd, LOCK_EX | LOCK_NB) != 0 {
        FileHandle.standardError.write(Data("已经有一个在跑了，这个就不开了\n".utf8))
        exit(0)
    }
}
claimSingleInstance()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
