#!/bin/bash
# Dictation Turbo —— 一条命令装好。
#
#   ./install.sh                 编译 → 装进「应用程序」→ 打开 → 体检
#   ./install.sh --autostart     顺带设成开机自启
#   ./install.sh --no-sign       跳过"造本地签名证书"（不推荐，见下）
#   ./install.sh --no-doctor     装完不体检
#
# 装完只剩一件事要你动手：在「系统设置 → 隐私与安全性 → 辅助功能」里
# 给 Dictation Turbo 打个勾（程序会自己弹窗带你去）。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Dictation Turbo"
EXEC_NAME="DictationTurbo"
LABEL="com.jieda.dictation-turbo"
DEST_DIR="${HOME}/Applications"
APP_SRC="${ROOT}/build/${APP_NAME}.app"
APP_DST="${DEST_DIR}/${APP_NAME}.app"
VS_BASE="${DT_VS_BASE:-http://127.0.0.1:3900}"

WANT_AUTOSTART=0
WANT_SIGN=1
WANT_DOCTOR=1
for arg in "$@"; do
  case "${arg}" in
    --autostart) WANT_AUTOSTART=1 ;;
    --no-sign)   WANT_SIGN=0 ;;
    --no-doctor) WANT_DOCTOR=0 ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "不认识的参数：${arg}" >&2; exit 2 ;;
  esac
done

say()  { printf '%s\n' "$*"; }
warn() { printf '⚠️  %s\n' "$*" >&2; }
die()  { printf '❌ %s\n' "$*" >&2; exit 1; }

say ""
say "Dictation Turbo —— 安装"
say "================================"

# ---------------------------------------------------------------- 1/6 环境
say "① 看环境"
[ "$(uname -s)" = "Darwin" ] || die "这是 macOS 专用的（现在这个不是 macOS）。"
SW_VERS="$(sw_vers -productVersion 2>/dev/null || echo '?')"
say "   macOS ${SW_VERS}，$(uname -m)"
command -v swiftc >/dev/null 2>&1 || die "找不到 swiftc。先跑：xcode-select --install"

# ------------------------------------------------------- 2/6 VoiceStudio
say "② 看 VoiceStudio（把话变成字全靠它，必须有）"
if curl -fsS -m 4 "${VS_BASE}/health" >/dev/null 2>&1; then
  say "   ✅ 在跑：${VS_BASE}"
else
  warn "现在连不上 ${VS_BASE}"
  say "   → 它是这个工具必需的那只耳朵。没装的话："
  say "     下载：https://voicestudio.sh/  （开源，AGPL-3.0，支持 646 种语言）"
  say "     装好后打开它一次，让它在后台把本机服务 3900 跑起来。"
  say "     首次启动它要下载识别模型，可能要等一会儿、占几个 G。"
  say "   → 没装也能继续装完，但双击 Control 会转不出字。"
fi

# ------------------------------------------------------------ 3/6 签名
say "③ 准备签名身份"
if [ "${WANT_SIGN}" = "1" ]; then
  bash "${ROOT}/tools/make-signing-identity.sh" || warn "签名身份没造出来，退回 ad-hoc（不影响能用，但改一次代码就要重新授权一次）"
else
  say "   （按 --no-sign 跳过）"
fi

# ------------------------------------------------------------ 4/6 编译
say "④ 编译"
bash "${ROOT}/build.sh" | sed 's/^/   /'
[ -d "${APP_SRC}" ] || die "没编出 ${APP_SRC}"

# ------------------------------------------------------------ 5/6 安装
say "⑤ 装进「应用程序」"
# 先把正在跑的旧版请走 —— 否则换完文件，跑着的还是旧代码
osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
pkill -f "${APP_DST}/Contents/MacOS/${EXEC_NAME}" >/dev/null 2>&1 || true
sleep 1
mkdir -p "${DEST_DIR}"
rm -rf "${APP_DST}"
cp -R "${APP_SRC}" "${APP_DST}"
# 从网上下的包里会带"隔离"标记，清掉它省得系统拦一道
xattr -cr "${APP_DST}" 2>/dev/null || true
say "   ✅ ${APP_DST}"

# 已经设过开机自启的，换完文件要让它重起一次，不然跑的还是旧代码
if [ -f "${HOME}/Library/LaunchAgents/${LABEL}.plist" ]; then
  launchctl kickstart -k "gui/$(id -u)/${LABEL}" >/dev/null 2>&1 || true
  say "   （开机自启那份已经重启，用的是新版）"
fi

say "   打开它（菜单栏会出现一个小麦克风）"
open "${APP_DST}" || warn "没能自动打开，自己去「应用程序」里双击它"

if [ "${WANT_AUTOSTART}" = "1" ]; then
  bash "${ROOT}/install-autostart.sh" | sed 's/^/   /'
fi

# ------------------------------------------------------------ 6/6 体检
if [ "${WANT_DOCTOR}" = "1" ]; then
  say "⑥ 体检"
  sleep 2
  "${APP_DST}/Contents/MacOS/${EXEC_NAME}" --doctor | sed 's/^/   /' || true
fi

say ""
say "================================"
say "接下来只剩两步（都是点几下）："
say ""
say "1) 给它「辅助功能」权限 —— 双击 Control 才有人听得到。"
say "   系统设置 → 隐私与安全性 → 辅助功能 → 把 Dictation Turbo 勾上。"
say "   （菜单栏那个小图标 →「① 授予辅助功能权限…」也能直接跳过去）"
say ""
say "2) 如果你开着 macOS 自带的听写，建议关掉它 —— 它的快捷键也是「按两次 Control」，"
say "   两个一起动会很乱。系统设置 → 键盘 → 听写 → 关。"
say ""
say "然后：在任何能打字的地方，双击 Control，说话，再双击 Control。"
say "字会落在光标那儿。要说德语、法语、日语……直接说，不用切输入法。"
say ""
say "出问题先跑这个，它会把毛病定位到具体哪一段："
say "   \"${APP_DST}/Contents/MacOS/${EXEC_NAME}\" --doctor"
say ""
