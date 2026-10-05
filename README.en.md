# Dictation Turbo · a system add-on for Mac

**[中文说明 →](README.md)**

**Double-tap Control anywhere on a Mac, speak, and the text lands at your cursor.**
No window, no input-method switching: it lives in the menu bar.

- Chinese, German, English, Japanese, French … **646 languages**, and you can mix
  them inside one sentence
- **You never pick a language** — it works it out itself
- Once installed it **starts with your Mac**

> ⚠️ **It needs [VoiceStudio](https://github.com/debpalash/VoiceStudio) to transcribe anything.**
> VoiceStudio is **free, open-source software** (AGPL-3.0) — **nothing to buy, no
> subscription**. It runs a local speech engine on
> `127.0.0.1:3900`. Dictation Turbo is the always-available switch in front of that
> engine, plus the part that types the result into whatever you were typing in.
> **Without VoiceStudio it cannot turn a single word into text.**
> **Both programs are free** — this one MIT, VoiceStudio AGPL.

---

## 1. Install VoiceStudio first (required)

> **This section costs nothing.** VoiceStudio is free and open source: no purchase,
> no subscription, no trial period, no "pro" edition. **There is nothing to buy here** —
> both programs are free (this one MIT, VoiceStudio AGPL-3.0). The only thing you spend
> is time and a few GB of disk: the first launch downloads a recognition model.

1. Download and install it: <https://voicestudio.sh/> or
   <https://github.com/debpalash/VoiceStudio/releases/latest>
2. Open it once, so its local service starts on port `3900`.
   The first launch downloads the recognition model — that can take a while and a few GB.
3. Check it (you want `{"status":"ok"...}`):

   ```sh
   curl -s http://127.0.0.1:3900/health
   ```

## 2. Install Dictation Turbo

### Option A — download (no terminal needed)

1. **[Download the latest release](https://github.com/dajie2014/dictation-turbo/releases/latest)**
   (`DictationTurbo-1.0.3-macOS.zip`)

   > **Stuck at 0%?** Common on Chinese networks — that download host is flaky.
   > **Use this mirror instead** (it was ~25× faster in testing):
   > <https://cdn.jsdelivr.net/gh/dajie2014/dictation-turbo@main/dist/DictationTurbo-1.0.3-macOS.zip>

2. Unzip it and drag **Dictation Turbo** into Applications.
3. **macOS will block it on first launch** — the app is self-signed, with no paid Apple
   developer certificate. **It is not broken.** Allow it once:
   - Right-click the app → **Open**, then click **Open** again in the dialog;
   - if there is no **Open** entry (macOS 15 and later removed it), go to
     **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**
     next to the message about Dictation Turbo;
   - or from a terminal:
     `xattr -dr com.apple.quarantine "/Applications/Dictation Turbo.app"`
4. Requires macOS 13 or later and an **Apple silicon** Mac (M1 and later).
   On Intel Macs, build it yourself — see Option B.

### Option B — build from source

```sh
git clone https://github.com/dajie2014/dictation-turbo.git
cd dictation-turbo
./build.sh          # produces build/Dictation Turbo.app
./install.sh        # copies it into Applications
```

`./build.sh` follows the architecture of the machine it runs on, so this works on Intel too.
It only needs the Xcode Command Line Tools (`xcode-select --install`).

## 3. Two things you have to do by hand

1. **Grant Accessibility permission** — otherwise a double-tap of Control reaches nobody.
   The app opens the right settings pane for you:
   **System Settings → Privacy & Security → Accessibility**, tick **Dictation Turbo**.
2. **If macOS Dictation is on, turn it off** — it uses the same "press Control twice"
   gesture and the two will fight.
   **System Settings → Keyboard → Dictation → off**.

Want it to start automatically:

```sh
./install.sh --autostart
```

## 4. Use

| What | How |
|---|---|
| Start talking | **Double-tap Control** (either one), you hear a "ding" |
| Finish | **Double-tap Control** again, you hear a "clack" |
| Is it alive? | The small microphone icon in the menu bar |
| Different gesture? | `doubleTapSeconds` — see section 6 of the [Chinese README](README.md) |

The text lands wherever you were typing — editor, chat, browser, terminal.
It types by putting the text on the clipboard and pressing ⌘V, so password fields
that refuse pastes will not work (your previous clipboard is restored afterwards).

## 5. Something is wrong

```sh
"/Applications/Dictation Turbo.app/Contents/MacOS/DictationTurbo" --doctor
```

It reports, line by line: permissions, code signature, whether the engines are reachable,
whether the microphone works, whether autostart is installed, and the last few transcriptions.

## 6. Known limitations

- **macOS only.** It is a Mac app, built on the Mac's own accessibility APIs.
- **VoiceStudio is required** for transcription (see above).
- **Intel Macs** have to build from source; the released binary is Apple silicon only.
- Transcription happens **after** you stop speaking (roughly half a second), not live.
- The full design notes, pitfalls and rationale are written in Chinese:
  [README.md](README.md), [PITFALLS.md](PITFALLS.md), [AGENT-INSTALL.md](AGENT-INSTALL.md).

## 7. Uninstall

```sh
./uninstall.sh            # removes the app, keeps the history
./uninstall.sh --purge    # removes the history too
```

One last manual step: delete the now-stale entry from the Accessibility list.

## Licence

MIT · by [Jie Da](https://github.com/dajie2014)
