# 让 AI agent 帮你装好

这份文件是**给 AI agent 看的**（Claude Code、Cursor、DSH、Codex……都行）。
它是一套能照着执行、而且**每一步都知道自己成没成**的指令。

人也可以照着自己做 —— 只是第 2 步那两件手动的事还是得人来点。

---

## 直接复制给你的 agent 的提示词

> 在这台 Mac 上帮我装好 **Dictation Turbo**（<https://github.com/dajie2014/dictation-turbo>）：
> 一个常驻菜单栏的听写工具 —— 在任何程序里双击 Control 说一句话，文字落进光标。
>
> **硬前提：这台机器必须已经装好并运行 VoiceStudio**（<https://voicestudio.sh/>，开源 AGPL-3.0，
> 本机服务在 `127.0.0.1:3900`）。它的 646 种语言识别就是本工具的**全部**语言能力来源 ——
> 装好之后 646 种语言一个都不能少，不要自作主张限制成某一种语言（默认 `language: auto`）。
> 如果 VoiceStudio 没装或没在跑：**先停下来告诉我**，别自己下一个几 G 的模型。
>
> 接下来照 `AGENT-INSTALL.md` 的分步做。规矩：
>
> 1. **每一步都要真的执行、真的看输出**。不要用"没报错"当"成功了"，
>    更不要拿被管道吃掉的退出码当成功。
> 2. 需要我在图形界面上点的（辅助功能授权、关掉系统听写），你**打开对应的设置面板**，
>    然后用一句话告诉我**点哪个开关**，然后等我回话。
> 3. 涉及验证时，把命令的**原始输出**贴给我，别只写"已验证"。
> 4. 最后按第 7 步的格式给我一份报告。

---

## 第 0 步 · 先看清楚这台机器

```sh
sw_vers -productVersion      # macOS 版本，13 以上就行
uname -m                     # arm64 或 x86_64，编译脚本会跟着走
command -v swiftc || xcode-select --install
curl --version | head -1
```

**验收**：`swiftc` 有输出（版本号即可）。没有就先装 Xcode Command Line Tools
（`xcode-select --install`，那是个图形安装过程，要人点）。

> 别跳过这一步。没有编译器的机器上，后面每一步都会以看不懂的方式失败。

## 第 1 步 · 确认 VoiceStudio 在跑（必须）

```sh
curl -s -m 5 http://127.0.0.1:3900/health
curl -s -m 5 http://127.0.0.1:3900/.well-known/voicestudio-speech | head -c 300
```

**验收**：第一条返回类似 `{"status":"ok","device":"mps","version":"0.5.6"}`。

- 返回 ok → 记下 `device` 和 `version`，继续。
- 连不上 → **停下来告诉用户**：需要先装 VoiceStudio
  （<https://voicestudio.sh/>），装完打开一次让服务起来（首次会下模型，几个 G）。
  **不要**替用户下载模型。
- 想确认它真能转写（可选，但很值）：

  ```sh
  curl -s -m 60 -F "audio=@某个.wav" -F "mode=fast" http://127.0.0.1:3900/transcribe
  ```

  返回里有 `"text"` 就是好的。

## 第 2 步 · 把仓库拿下来

```sh
git clone https://github.com/dajie2014/dictation-turbo.git
cd dictation-turbo
```

**验收**：目录里能看到 `install.sh`、`build.sh`、`Sources/DT/`。

> 如果 `github.com` 在这台机器上不通（国内常见现象：它会一直静默卡住、不报错），
> 换 `gh` 或镜像再试；**别把"卡住"当成"在下载"**。
> 判断法和绕法见 [PITFALLS.md](PITFALLS.md) 第 14 条。

## 第 3 步 · 装

```sh
./install.sh
```

脚本自己会做：造本地签名证书 → 编译 → 装进 `~/Applications` → 打开 → 体检。

**验收**（三样都要看到）：

1. 编译那一段末尾有 `✓ 签名有效`；
2. `~/Applications/Dictation Turbo.app` 存在；
3. 最后的体检报告里 ④ 那行是 `✅ 在跑`。

**可能卡住的地方**（都会在屏幕上弹窗，需要人点）：

- **「codesign 想要访问你的钥匙串中的密钥」** → 让人输一次登录密码，点 **始终允许**。
  点过一次以后永远不再问。这一步不是错误，**别把它当成失败重来**。
- 如果一直没弹窗、命令却停住不动，**截一张屏幕图**给用户看，
  大概率那个弹窗被别的窗口压在下面了。

如果脚本报 `resource fork, Finder information, or similar detritus not allowed`：
脚本自己会换到临时目录签，正常。若连临时目录也失败，见 PITFALLS 第 7 条。

## 第 4 步 · 让人给「辅助功能」权限（必须人工）

程序已经弹过引导了。如果没弹或者被关掉了：

```sh
open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
```

**告诉用户**：在列表里找到 **Dictation Turbo**，把开关打开。
（macOS 版本不同，位置可能写作「系统设置 → 隐私与安全性 → 辅助功能」。）

**验收**（权限给没给，程序自己知道）：

```sh
"$HOME/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --doctor | grep 辅助功能
```

要看到 `✅ 已给`。还是 `❌` 的话，让人再确认一次开关，
或者让他从菜单栏那个小图标点「② 权限已给，重新开始监听」。

## 第 5 步 · 关掉 macOS 自带的听写（建议）

**告诉用户**：系统自带的听写快捷键也是"按两次 Control"，两个一起动会很乱 ——
「系统设置 → 键盘 → 听写 → 关」。

这一步**没法用命令可靠地判断**（系统不暴露这个开关的状态）。
**不要假装检查过了**，就把它当成一句给用户的建议。

## 第 6 步 · 验（这是最要紧的一步）

### 6.1 验识别那一段 —— 不用麦克风、不用人按任何键

```sh
./tools/make-samples.sh
"$HOME/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --selftest samples/*.wav
```

**验收**：每段音频都要打印 `引擎：` 和 `文字：`，且退出码是 0。参考结果：

```
音频：samples/de.wav  16000 Hz / 1 声道 → 3320 毫秒
  用时：0.23 秒
  引擎：VoiceStudio
  文字：Guten Tag, das ist ein Test der Spracherkennung.
...
  引擎：DSH（中文增强）          ← 装了 DSH 才会有这行
  文字：今天天气不错，我们下午3点开会，别忘了带上笔记本。
```

德语能出 → **VoiceStudio 那只耳朵是通的**（这是 646 种语言的代表）。
中文那行如果显示 `引擎：VoiceStudio` 而不是 `DSH（中文增强）`，也**不算失败** ——
说明这台机器上没有 DSH，或者 `chineseViaDSH` 关着，中文照样能用。

> ⚠️ `make-samples.sh` 用的是**系统朗读**合成的音频，需要机器上有对应的朗读声音。
> 某个语言被跳过（`➖ 跳过 de：这台机器没装「Anna」`）是正常的，
> **只要还有一段能过就行**。有三段的语音包不是每台机器都有。

### 6.2 验「字能不能落进光标」

菜单栏点开 → **「试一下落字（3 秒后）」**，然后**马上点进任意一个能打字的框**
（备忘录、浏览器地址栏都行）。3 秒后那里应该出现一句「这是落字测试，一二三四五。」

或者直接查记录：

```sh
tail -5 ~/.dictation-turbo/dictation.log
```

**验收**：日志里出现 `落字自测已发出`。

### 6.3 验端到端（这一步只能人来）

**告诉用户**：请在任意一个能打字的地方 —— 比如备忘录 ——
**双击 Control**，说一句"今天天气不错"，再**双击 Control**。看字有没有出来。

然后**你自己去看日志**：

```sh
tail -8 ~/.dictation-turbo/dictation.log
```

**验收**：这一轮里应该依次出现

```
收工：3.10 秒，峰值 0.42
[VoiceStudio] 今天天气不错。          ← 引擎名和文字
已送进光标：7 个字
```

- 有 `[……] 文字` 但没有 `已送进光标` → 是**落字**那一段的问题，回 6.2。
- 有 `没听到声音（峰值 …）` → 麦克风没收到，让人确认默认输入设备、并且说话时靠近一点。
- 有 `已送进光标` 但用户说没看到字 → 多半是他当时没有把光标放在能打字的地方。

## 第 7 步 · 报告（照这个格式）

```
Dictation Turbo 安装报告
- macOS / 架构：
- VoiceStudio：在跑 / 版本 / device
- 编译与签名：✓ / ad-hoc
- 辅助功能权限：已给 / 没给
- 自检（--selftest）：通过几段、引擎分别是
- 落字自测：通过 / 没通过
- 端到端实测（用户操作）：通过 / 没通过 / 未做
- 还没解决的事：
```

**没通过的项就写没通过。** 这一份报告的价值全在它是否如实 ——
用户拿它决定"能不能放心用"。

---

## 给 agent 的注意事项

1. **别改 `BUNDLE_ID`**（`com.jieda.dictation-turbo`）和签名身份的名字。
   一改，系统就把它当另一个程序，之前给的权限全作废。
2. **别用 `codesign --sign -`（ad-hoc）** 去"解决"签名问题 ——
   那会让用户每次重新编译都要重新授权。正确做法是跑
   `./tools/make-signing-identity.sh` 造固定证书。
3. **这个工具只跟两个本机端口说话**：`127.0.0.1:3900`（VoiceStudio）和可选的
   `127.0.0.1:19387`（DSH）。不需要联网、不需要 API key。
   **不要**给它配任何云端识别服务 —— 那就不是这个项目了。
4. **本地 `~/.dictation-turbo/`** 里是日志和配置，没有秘密。
   `build/signing/` 里如果出现过私钥文件，**不要提交到任何仓库**。
5. 想验证"真的在监听"，日志里找 `监听已就绪` —— 这行是拿到权限、监听挂上之后才写的。
