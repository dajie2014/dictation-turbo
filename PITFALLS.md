# 踩过的坑

这个项目里**真正花时间的地方全在这里**。
每一条都是实际撞过的，格式统一：**症状 → 为什么 → 怎么绕**。

照着改代码的人，建议先扫一遍这个文件 —— 能省掉重走一遍的时间。

---

## A. 声音与识别

### 1. 音频必须是"最朴素"的 WAV

**症状**：把 `afconvert` 或 `ffmpeg` 转出来的 wav 发给 DSH 的识别接口，被拒：

> Audio must be a canonical 16 kHz mono PCM16 WAV recording

**为什么**：这两个工具都会往文件里塞附加块 —— `afconvert` 塞 `FLLR`，
`ffmpeg` 塞 `LIST/INFO`。DSH 只认"RIFF + fmt + data"三个块的最干净结构。

**怎么绕**：**自己写那 44 字节头**，别用系统转换工具。
见 `Sources/DT/Engines.swift` 的 `wav(fromPCM:)`。
反过来，**读**别人的 WAV 时也别假定"44 字节之后就是数据" ——
老老实实按块遍历（同文件里的 `pcm(fromWav:)`）。

### 2. DSH 的参数必须包一层 `request`

**症状**：`gateway/arguments-invalid: missing "request"`

**为什么**：它的 HTTP 接口外面还套着一层 RPC 信封，
业务参数要放在 `payload.args.request` 里。

**怎么绕**：

```json
{"type":"client-request","rpcId":"任意","method":"speech/transcribe",
 "payload":{"args":{"request":{"audioBase64":"…"}}}}
```

### 3. VoiceStudio 有个"慢 30 倍"的端点

**症状**：同一段 5 秒音频，识别要等 8 秒。

**为什么**：VoiceStudio 同时提供两套接口 —— 自家的 `/transcribe`，和 OpenAI 兼容的
`/v1/audio/transcriptions`。实测后者 **8.1 秒**，前者 **0.26 秒**。
（写本文时是 2026-10，VoiceStudio 0.5.6。将来可能变，所以：**换端点前先测一遍**。）

**怎么绕**：用 `/transcribe`（multipart：`audio` 文件 + `mode=fast`）。
`language` 是可选的；**不传**就等于让它自己判断，这正是多语言混说的用法。

### 4. 不能"先喂给 SenseVoice，听不懂再转走"

**症状**：德语灌进 DSH 的 SenseVoice，它不报错，而是硬猜成中文或英文 —— 出来一串乱码。

**为什么**：SenseVoice **不会说"我不认识"**。那个"听不懂"的判断它自己给不出来。

**怎么绕**：**把顺序倒过来** —— 先问 VoiceStudio（什么语言都敢出一个结果），
如果结果里汉字占比超过 40%，再请 DSH 重听一遍，以 DSH 的为准。

同一句中文的实测差别：

| 引擎 | 结果 |
|---|---|
| VoiceStudio | 今天**天氣**不錯,我們下午3點開會,別忘了**上記本**。 ← 繁体 + 掉字 |
| DSH SenseVoice | 今天天气不错，我们下午3点开会，别忘了带上笔记本。 ← 全对 |

这就是 `Engines.route()` 里那段逻辑存在的全部理由。

### 5. 静音送进识别，它也会"猜"出一串东西

**症状**：明明没说话，却落进来一段莫名其妙的文字（实测猜成过日语乱码「チぼ？」）。

**为什么**：识别引擎不区分"没声音"和"听不懂的声音"，一律给出概率最高的结果。

**怎么绕**：录音时一路盯着峰值，全程没超过 `minPeak`（默认 0.03）就当没说，
直接丢掉，连请求都不发。见 `Recorder.swift` 的 `peak` 和 `main.swift` 的 `finish()`。

**连带教训**：**极短采样和静止截图都不足以判断"麦克风没声音"**。
要持续监听好几秒、同时让人说话，才算数。

### 6. 提示音会被自己录进去

**症状**：偶尔在识别结果最前面多出莫名其妙的字。

**为什么**：开始录音的"叮"如果和录音同时发生，就被录进去了。

**怎么绕**：**先响完再开录** —— 响完之后 `Thread.sleep(0.18)` 再 `recorder.start()`。

---

## B. 权限与签名（花时间最多的一块）

### 7. ad-hoc 签名 = 每次重新编译都丢授权

**症状**：改一行代码、重新编译、装上，双击 Control 没反应。
去系统设置一看 —— 辅助功能里 Dictation Turbo 的勾**没了**。

**为什么**：`codesign --sign -`（ad-hoc）没有身份，系统拿**内容指纹**当身份。
内容一变（哪怕只改一个字符），系统就认为这是**另一个程序**，之前给的授权作废。
实测：6:46 有权限 → 6:48 覆盖安装 → 6:48 没权限了。

**怎么绕**：造一张**固定身份的本地证书**，用它签 —— 身份不随编译变化，授权一次就够。
见 `tools/make-signing-identity.sh`（openssl 自签 → p12 → `security import`）。
`build.sh` 会自动优先用它。

**两个附带事实**：

- 证书在 `security find-identity` 里显示 `CSSMERR_TP_NOT_TRUSTED` ——
  **这是正常的**，代码签名不需要它被系统信任，辅助功能授权也认这个身份。
- 换了签名身份名、或者换了 Bundle ID，等于换了程序，**授权要重给一次**。
  所以别改 `com.jieda.dictation-turbo` 和 `Dictation Turbo Local Signing`。

### 8. 签名时会弹「codesign 想要访问你的钥匙串」

**症状**：脚本跑到签名那一步**停住不动**，等一会儿又好像没反应。

**为什么**：签名要拿证书里的私钥，系统在等一个**图形授权窗口**。
如果那个窗口被别的窗口压在下面，你只会觉得"命令卡死了"。

**怎么绕**：

- 让人输一次登录密码、点 **始终允许** —— 点过一次，以后永远不再问。
- **脚本卡住时先截个屏**看有没有弹窗，别急着重跑。
- 想彻底避免弹窗：把私钥的访问控制设成允许所有程序
  （`security import … -A`；`make-signing-identity.sh` 已经这么做了，
  但不同 macOS 版本行为不完全一样，所以还是留了这条说明）。

### 9. iCloud / 文件提供程序管的目录，签不了名

**症状**：

> resource fork, Finder information, or similar detritus not allowed

**为什么**：iCloud 云盘、Dropbox、坚果云这类目录由"文件提供程序"接管，
会给文件打上 `com.apple.FinderInfo`、`com.apple.fileprovider.fpfs#P` 之类的附加属性。
`codesign` 见到这些一律拒绝 —— 而且这些属性**删不干净**：
`xattr -cr` 返回成功，`xattr -l` 一看东西还在。

**怎么绕**：**换到干净目录签**。`build.sh` 里的 `sign_at()` 就是干这个的：

```sh
ditto --noextattr --norsrc "$APP" "$TMPDIR/app.app"     # 不带附加属性地复制
codesign --force --deep --sign "$IDENT" "$TMPDIR/app.app"
ditto --noextattr --norsrc "$TMPDIR/app.app" "$APP"     # 抄回来
```

签完再复制**不会**破坏签名 —— 签名长在 `_CodeSignature/` 和 Mach-O 里，
跟附加属性没关系。

### 10. 第一次跑就该主动问麦克风权限

**症状**：用户按了双击 Control，只有一声"叮"，然后什么都没有。

**为什么**：麦克风权限是"第一次真的录音时"才弹窗。
用户按热键的那一瞬间弹窗，很容易被理解成"它坏了"。

**怎么绕**：程序一启动就 `AVCaptureDevice.requestAccess(for: .audio)` 问一次
（`main.swift` 的 `askMicrophoneOnce()`），先把这一步走掉。

### 11. 权限没给时，别做常驻轮询

**做法**：只"缺权限"这一个状态下，每 2 秒看一眼，**拿到就停**，最多看 5 分钟。
（`main.swift` 的 `watchPermission()`。）
这是刻意的：这个项目整体上"没有定时、没有后台轮询"，
唯一的例外必须自带终止条件。

---

## C. 系统行为

### 12. macOS 自带的听写，快捷键也是"双击 Control"

**症状**：双击 Control，系统听写面板和本工具**一起**动。

**怎么绕**：让用户把系统听写关掉（**系统设置 → 键盘 → 听写 → 关**）。
这条**没法用命令可靠地检测** —— 别假装检查过了，就写成一句给用户的建议。

### 13. 事件监听会被系统悄悄暂停

**症状**：用着用着，双击 Control 没反应了；重开程序又好。

**为什么**：系统级事件回调**太慢**时，macOS 会把监听停掉，并且给你两个事件
`tapDisabledByTimeout` / `tapDisabledByUserInput`。

**怎么绕**：收到这两个事件就**把它重新启用**：

```swift
if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
    CGEvent.tapEnable(tap: tap, enable: true)
    return
}
```

### 14. 落字为什么走"剪贴板 + ⌘V"，以及为什么会粘错

**为什么不用逐字模拟按键**：会被中文输入法截走，变成一串拼音。

**怎么绕**：借剪贴板 —— 但要处理两件事：

1. **还原不能太快**。有些程序粘贴慢，抢在它读完剪贴板之前还原，
   粘进去的就是**上一份**内容。实测 **0.6 秒**是稳的。
2. **还原之前先看 `changeCount`**：如果这期间用户自己复制了别的东西，
   **就不要还原**，否则把他的剪贴板覆盖了。

（`Typer.swift`。）
**连带限制**：密码框这类不接受 ⌘V 的地方没辙 —— 这是设计限制，别承诺能做到。

### 15. 两个实例 = 一句话录两遍、贴两遍

**怎么绕**：启动时 `flock` 一个锁文件，抢不到就直接退出（`main.swift` 的 `claimSingleInstance()`）。
锁文件放 `~/.dictation-turbo/dictation.lock`。

### 16. 换完文件，跑的往往还是旧进程

**症状**：明明装的是新版，行为一点没变。

**为什么**：开机自启那一份是 launchd 拉起来的，`/usr/bin/open` 一个已经在跑的 app
不会再起第二个 —— 你换的是磁盘上的文件，内存里跑的还是旧的。

**怎么绕**：`install.sh` 里换完文件后**明确重启一次**：

```sh
launchctl kickstart -k "gui/$(id -u)/com.jieda.dictation-turbo"
```

没装自启时，至少要先 `osascript -e 'quit app "…"'` 把旧的请走。

### 17. `~/Documents` 是系统保护目录

**症状**：launchd 或定时任务去读 `~/Documents` 里的脚本/配置，报 `Operation not permitted`。

**怎么绕**：**要给后台任务用的东西，一律放 `~/` 下面的普通目录**。
这个项目的日志、配置、锁文件就都在 `~/.dictation-turbo/`，不碰「文稿」。
（源码放哪儿都行，只有"要被后台任务读"的文件受这条限制。）

---

## D. 工程与脚本

### 18. 编译目标别写死架构

**症状**：在 Apple 芯片上编好，Intel 机器上根本跑不起来（或者反过来）。

**怎么绕**：`-target "$(uname -m)-apple-macosx13.0"`。
`build.sh` 就是这么写的；macOS 最低版本压到 13.0，能覆盖更多人。

### 19. 管道会吃掉退出码

**症状**：构建明明失败了，画面上看着像成功。

**怎么绕**：**别拿 `./build.sh | tail` 当成功判据**。
要看真退出码就用 `${PIPESTATUS[0]}`，或者干脆别套管道。

### 20. bash 3.2 里，变量名后面紧跟中文会出事

**症状**：`set -u` 下报 unbound variable，脚本中途死掉，而且看不出为什么。

**为什么**：macOS 自带的是 bash 3.2，变量名后面紧跟中文/全角字符时，
它会把那个字符的**首字节**吃进变量名。

**怎么绕**：**凡 shell 里写中文，变量一律写成 `${A}`**（带花括号），
不要写 `$A中文`。

### 21. 日志不设上限，能长到几百兆

**怎么绕**：每次写之前看一眼大小，超过 1 MB 就砍掉前面一半
（`Config.log()`）。这是个常驻程序，跑一年不长草才怪。

### 22. 编译的模块缓存放哪儿

默认在 `/var/folders/...`，某些受限环境里写不进去、刷一屏红字。
**怎么绕**：`swiftc -module-cache-path build/ModuleCache`，放进自己的构建目录。

### 23. 国内网络下 `github.com` 会静默卡住

**症状**：`git clone` / `git push` 一直不动，**不报错**，看起来像在下载。
（`api.github.com` 往往是通的，只有 `github.com` 不通。）

**怎么绕**：换 `gh api` 走接口上传/下载；或者用镜像前缀
（发布这个仓库时实测 `https://gh-proxy.com/` 可用，官方校验和仍能从
`api.github.com` 的 asset 端点取到）。
**判断法**：`curl -m 10 -sI https://github.com` 超时、而
`curl -m 10 -sI https://api.github.com` 返回 200 —— 那就是这条。
