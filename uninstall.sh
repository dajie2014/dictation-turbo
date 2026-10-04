#!/bin/bash
# 卸载：把跑着的、开机自启的、装在「应用程序」里的都撤掉。
#   ./uninstall.sh            撤掉程序，留着 ~/.dictation-turbo（记录和配置）
#   ./uninstall.sh --purge    连记录一起删
set -euo pipefail

APP_NAME="Dictation Turbo"
EXEC_NAME="DictationTurbo"
LABEL="com.jieda.dictation-turbo"
APP="${HOME}/Applications/${APP_NAME}.app"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
UID_NUM="$(id -u)"

echo "==> 停掉开机自启"
launchctl bootout "gui/${UID_NUM}/${LABEL}" 2>/dev/null || true
rm -f "${PLIST}"

echo "==> 退出正在跑的"
osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
pkill -f "${APP}/Contents/MacOS/${EXEC_NAME}" >/dev/null 2>&1 || true
sleep 1

echo "==> 删掉程序"
rm -rf "${APP}"

if [ "${1:-keep}" = "--purge" ]; then
  echo "==> 删掉记录和配置"
  rm -rf "${HOME}/.dictation-turbo"
else
  echo "（记录和配置留在 ~/.dictation-turbo，要一起删就加 --purge）"
fi

echo "==> 剩下一步要手动：去「系统设置 → 隐私与安全性 → 辅助功能」"
echo "    把已经不存在的 Dictation Turbo 那条减号删掉（留着也不影响，只是碍眼）。"
echo "完成。"
