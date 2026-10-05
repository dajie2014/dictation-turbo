# Dictation Turbo · a system add-on for Mac

**English** · [Read this in English →](README.en.md)

**在任何能打字的地方，双击 Control，说一句话，字落在光标那儿。**
不用切窗口、不用切输入法、不用点麦克风图标。它常驻在菜单栏，没有窗口。

- 中文、英文、德文、日文、法文…… **646 种语言**直接说，
  一句话里混着说几种也行
- 说话的时候**不用选语言** —— 它自己判断
- 装上之后**开机就在**，不用记得先开它

> ⚠️ **它必须配 VoiceStudio 用。** [VoiceStudio](https://github.com/debpalash/VoiceStudio)
> 是**免费的开源软件**（AGPL-3.0）—— **不用花钱，也不用订阅**，下载装上就行。
> 它自带 646 种语言的听写引擎，装好后在本机 `127.0.0.1:3900`
> 上跑一个服务。Dictation Turbo 做的事，是给这个服务配一个**随时能按的开关**，
> 并且把结果**送进你正在打字的地方**。
>
> **没有 VoiceStudio，它一句都转不出来。** 先装 VoiceStudio，再装它。
> **两个都不要钱**：这个 MIT，那个 AGPL。

---

## 0. 不想碰终端？直接下载

1. **下载**：<https://github.com/dajie2014/dictation-turbo/releases/latest>
   （文件叫 `DictationTurbo-1.0.3-macOS.zip`）

   > **下载卡在 0% 不动？** 国内网络常见 —— 那个下载服务器时通时不通。
   > **换这条备用直链**（走的是另一个 CDN，实测快二十多倍）：
   > <https://cdn.jsdelivr.net/gh/dajie2014/dictation-turbo@main/dist/DictationTurbo-1.0.3-macOS.zip>

2. 解压，把 **Dictation Turbo** 拖进「应用程序」
3. **第一次打开，系统会拦你一下** —— 因为没买苹果的开发者证书（一年 99 美元那个）。
   **不是它有问题。** 放行一次：
   - 右键点它 →「打开」→ 弹窗里再点「打开」；
   - 要是找不到「打开」这个选项（macOS 15 之后取消了这一步），去
     **系统设置 → 隐私与安全性**，往下翻会看到一条拦下它的提示，
     点旁边的 **「仍要打开」**；
   - 命令行一行也行：
     `xattr -dr com.apple.quarantine "/Applications/Dictation Turbo.app"`
4. **打开它之前，先做第 1 节**（装 VoiceStudio）—— 没有它，它转不出一个字。

> 这个包适合 **Apple 芯片的 Mac（M1 及以后）**，我在真机上编译、签名、验过。
> Intel 的机器走第 2 节自己编译（`./build.sh` 会跟着你的机器架构走）。

---

## 1. 先装 VoiceStudio（必须）

> **这一节不要钱。** VoiceStudio 是免费的开源软件：下载、安装、使用都不收费，
> 也没有订阅、没有试用期、没有"高级版"。**这里没有任何要买的东西** ——
> 两个程序都是免费的，这个 MIT，那个 AGPL-3.0。
> （唯一要花的可能是时间和几个 G 的硬盘：首次启动它会下一套识别模型。）

1. 下载并安装：<https://voicestudio.sh/> 或
   <https://github.com/debpalash/VoiceStudio/releases/latest>
2. 打开它一次，让它在后台把本机服务跑起来（端口 `3900`）。
   首次启动它要下载识别模型，可能要等一会儿、占几个 G。
3. 验一下（看到 `{"status":"ok"...}` 就成了）：

   ```sh
   curl -s http://127.0.0.1:3900/health
   ```

**语言能力来自 VoiceStudio**：它支持 646 种语言，Dictation Turbo 一个不少地转给你用。
想限制成某一种语言，见下面第 6 节（默认是"自动判断"，这也是最省事的用法）。

## 2. 装 Dictation Turbo

```sh
git clone https://github.com/dajie2014/dictation-turbo.git
cd dictation-turbo
./install.sh
```

装完会有一次体检报告。**接着只剩两件事要你动手**：

1. **给它「辅助功能」权限** —— 双击 Control 才有人听得见。
   程序会自己弹窗带你去：**系统设置 → 隐私与安全性 → 辅助功能**，
   把 **Dictation Turbo** 勾上。
2. **如果你开着 macOS 自带的听写，建议关掉它** ——
   它的快捷键也是"按两次 Control"，两个一起动会很乱。
   **系统设置 → 键盘 → 听写 → 关**。

想让它开机自己起来：

```sh
./install.sh --autostart
```

## 3. 用

| 想干什么 | 怎么做 |
|---|---|
| 开始说话 | **双击 Control**（左右那个都行），听到"叮" |
| 说完了 | **再双击 Control**，听到"啪" |
| 看它活没活 | 菜单栏那个小麦克风图标 |
| 换个手势？ | 见下面第 6 节 `doubleTapSeconds` |

文字会**落在你现在打字的地方** —— 编辑器、聊天框、浏览器、终端，都一样。
落字走"剪贴板 + ⌘V"，所以**密码框之类不接受粘贴的地方没辙**（它用完会把你原来的剪贴板还原）。

菜单栏点开有：授予权限、重新监听、检查引擎状态、试一下落字、看记录、退出。

## 4. 出问题了先跑这个

```sh
"/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --doctor
```

（装在 `~/Applications` 的话就把路径换掉。装 `--autostart` 时体检里也会告诉你在哪。）

它会一行一行告诉你：权限给没给、签名对不对、**两只耳朵通不通**、麦克风能不能用、
开机自启装上没、最近几条记录长什么样。

**不按热键、不动麦克风，只验识别那一段**（最有用的一招）：

```sh
./tools/make-samples.sh        # 造三段示例音（中/英/德，系统朗读合成，不含人声）
"/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --selftest samples/*.wav
```

**双击判定单独也能验**（纯逻辑，不碰键盘、不会动到你在编辑的东西）：

```sh
"/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --hotkey-test
```

## 5. 卸载

```sh
./uninstall.sh            # 撤程序，留着记录
./uninstall.sh --purge    # 连记录一起删
```

（最后一小步要手动：去辅助功能列表里把已经不存在的那条删掉。）

## 6. 想改点什么（可选）

写一个 `~/.dictation-turbo/config.json`，缺什么就用默认值：

```json
{
  "language": "auto",
  "doubleTapSeconds": 0.35,
  "chineseViaDSH": true,
  "minPeak": 0.03,
  "maxRecordSeconds": 120,
  "yieldToDSHPage": true
}
```

| 键 | 默认 | 什么意思 |
|---|---|---|
| `language` | `"auto"` | 传给识别引擎的语言提示。`auto` = 自己判断（推荐）。想固定就写 `"zh"` `"de"` `"en"` 这种。 |
| `doubleTapSeconds` | `0.35` | 两次 Control 间隔多短才算"双击"。手慢的话调到 `0.5`。 |
| `chineseViaDSH` | `true` | 中文要不要再用 DSH 复核一遍（更准）。没装 DSH 会自动跳过。 |
| `minPeak` | `0.03` | 全程比这还轻就当没说人话，不送识别（防止静音被硬猜出一串乱码）。 |
| `maxRecordSeconds` | `120` | 最长录这么久就自动停，免得忘了关。 |
| `yieldToDSHPage` | `true` | 在 DSH 窗口里让路给它的页面版插件。没装那个插件就无所谓。 |

改完**不用重启**，下一次听写就生效。

**开发用**：改完代码，`./build.sh` 重新编译即可。
第一次装完建议先跑一次 `./tools/make-signing-identity.sh` 造个固定身份的本地证书 ——
否则每次重新编译，系统都把它当成"另一个程序"，之前给的辅助功能授权会作废。
细节见 [PITFALLS.md](PITFALLS.md)。

## 7. 它是怎么做的（一句话）

双击 Control → 录音（16 kHz 单声道）→ 打包成最朴素的 WAV →
问 VoiceStudio → 如果结果像中文、机器上又有 DSH，就请 DSH 的 SenseVoice 重听一遍 →
把文字粘进当前光标。全程本地，不出这台机器。

花了哪些功夫、踩了哪些坑，都写在 **[PITFALLS.md](PITFALLS.md)** 里 ——
那份文档才是这个项目最值钱的部分。

## 8. 已知限制

- **VoiceStudio 必须开着**（识别是它做的，它是免费的，见第 1 节）。
- **DSH 是可选的**。没有它，中文照样能出，只是偶尔会冒出繁体字或掉个字。
- 密码输入框、以及任何不接受 ⌘V 的地方，粘不进去。
- 说错了想中途取消 —— **不支持，也不打算做**：说完再手动改就是了。
- 边说边出字（流式）—— 同上，不做。

## 9. 给 AI agent 用

想直接让你的 agent 把这一套装好、验好，把
**[AGENT-INSTALL.md](AGENT-INSTALL.md)** 整份丢给它就行 ——
里面是分好步的指令，每一步都写了**怎么确认这一步真的成了**。

## 许可

MIT。见 [LICENSE](LICENSE)。
本项目**不包含** VoiceStudio 的代码，只是在你的机器上调用它的本机服务 ——
VoiceStudio 自己是**免费的开源软件**（AGPL-3.0，不收费），用它请遵守它的许可。

---

# English (short version)

**Double-tap Control anywhere on your Mac, speak, and the text lands at your cursor.**
It lives in the menu bar, has no window, and never asks you to switch input methods.

- **646 languages** through [VoiceStudio](https://github.com/debpalash/VoiceStudio) —
  mix Chinese, English and German in one sentence if you like
- You don't pick the language; it figures it out
- Starts with your Mac (optional), so it's always there

### Requirements

**VoiceStudio is required — and it is free.** It is open source (AGPL-3.0): no purchase,
no subscription, no paid tier. It runs a local speech
service on `127.0.0.1:3900`. Install it from <https://voicestudio.sh/>, launch it once,
then check with `curl -s http://127.0.0.1:3900/health`.
Without it Dictation Turbo cannot transcribe anything.
**Both programs are free** — this one MIT, VoiceStudio AGPL.

Optionally, if you happen to run **DeepSeek Harness (DSH)**, Chinese gets a second pass
through its SenseVoice engine — slightly more accurate, simplified characters.

### Install

```sh
git clone https://github.com/dajie2014/dictation-turbo.git
cd dictation-turbo
./install.sh          # add --autostart to start it at login
```

Then two things by hand:

1. **Grant Accessibility permission**: System Settings → Privacy & Security →
   Accessibility → tick **Dictation Turbo** (the app will prompt you).
2. **Turn off macOS's own dictation** if it's on — it uses the same
   double-tap-Control shortcut and the two fight each other.

### Use

Double-tap **Control** to start, speak, double-tap again to stop.
Text is pasted into whatever app you're typing in. A note plays at start and stop.

### Troubleshooting

```sh
"/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --doctor
```

Prints a plain-language health report: permissions, code signature, whether both
engines answer, microphone access, autostart, and the last few log lines.

To test transcription without touching the microphone:

```sh
./tools/make-samples.sh
"/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --selftest samples/*.wav
```

### Uninstall

```sh
./uninstall.sh            # keep your logs and config
./uninstall.sh --purge    # remove everything
```

### For AI agents

Hand your agent **[AGENT-INSTALL.md](AGENT-INSTALL.md)** — it's a step-by-step
install-and-verify instruction set with a check for every step.

MIT licensed. Bundles no VoiceStudio code — it only calls the local service.
