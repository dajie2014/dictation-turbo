#!/bin/bash
# 让 Dictation Turbo 开机自己起来，不用手动开。
#   ./install-autostart.sh           装上
#   ./install-autostart.sh remove    撤掉
#
# 为什么走 LaunchAgent：这是 macOS 一贯的"登录时替我起个东西"的做法，
# 不占 Dock、不需要点。用 /usr/bin/open 起 —— 系统会把它认成那个 .app 本身，
# 权限归属最清楚（直接跑包里的二进制也行，但那一套授权更容易认错路径）。
set -euo pipefail

LABEL="com.jieda.dictation-turbo"
APP="${HOME}/Applications/Dictation Turbo.app"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"

if [ "${1:-install}" = "remove" ]; then
  launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
  rm -f "${PLIST}"
  echo "已撤销开机自启"
  exit 0
fi

if [ ! -d "${APP}" ]; then
  echo "!! 没找到 ${APP}" >&2
  echo "   先跑 ./install.sh 把它装进去，再回来跑这个。" >&2
  exit 1
fi

mkdir -p "${HOME}/Library/LaunchAgents" "${HOME}/.dictation-turbo"

cat > "${PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>Label</key>
	<string>${LABEL}</string>
	<key>ProgramArguments</key>
	<array>
		<string>/usr/bin/open</string>
		<string>-a</string>
		<string>${APP}</string>
	</array>
	<key>RunAtLoad</key>
	<true/>
	<!-- 它自己退出就退出，不强行拉起来：听写工具崩一次就无限重启会很吵 -->
	<key>KeepAlive</key>
	<false/>
	<!-- 只在有人登录到桌面时跑 -->
	<key>LimitLoadToSessionType</key>
	<string>Aqua</string>
	<key>StandardErrorPath</key>
	<string>${HOME}/.dictation-turbo/launchd.err</string>
</dict>
</plist>
PLIST

# 先卸掉旧的再装，避免 "service already loaded"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/${UID_NUM}" "${PLIST}"
echo "已设好开机自启：${PLIST}"
echo "（现在就想起的话：open \"${APP}\"）"
