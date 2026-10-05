#!/bin/bash
# Dictation Turbo —— 编译 + 打成 .app
#
# 只依赖 Xcode Command Line Tools（不需要完整 Xcode，也没有 .xcodeproj）。
# 用法：./build.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Dictation Turbo"
EXEC_NAME="DictationTurbo"
BUNDLE_ID="com.jieda.dictation-turbo"
VERSION="$(cat "${ROOT}/VERSION" 2>/dev/null || echo 0.1.0)"

# 跟机器走：Apple 芯片是 arm64，Intel 是 x86_64。
# （写死架构的话，另一台机器上编出来的东西根本不能跑。）
ARCH="$(uname -m)"
MACOS_MIN="13.0"

BUILD_DIR="${ROOT}/build"
APP_DIR="${BUILD_DIR}/${APP_NAME}.app"
BIN="${BUILD_DIR}/${EXEC_NAME}"

if ! command -v swiftc >/dev/null 2>&1; then
  echo "!! 找不到 swiftc。先装 Xcode Command Line Tools：" >&2
  echo "     xcode-select --install" >&2
  exit 1
fi

echo "==> [1/4] 编译（$(swiftc --version 2>/dev/null | head -1 | sed 's/.*version //;s/ .*//')，目标 ${ARCH}-apple-macosx${MACOS_MIN}）"
mkdir -p "${BUILD_DIR}"
# 模块缓存放进构建目录：默认位置在 /var/folders，受限环境里不一定写得进去。
swiftc -O -swift-version 5 \
  -module-cache-path "${BUILD_DIR}/ModuleCache" \
  -target "${ARCH}-apple-macosx${MACOS_MIN}" \
  -o "${BIN}" \
  "${ROOT}"/Sources/DT/*.swift

if [ ! -f "${BIN}" ]; then
  echo "!! 没编出可执行文件" >&2
  exit 1
fi

echo "==> [2/4] 组装 .app"
rm -rf "${APP_DIR}"
mkdir -p "${APP_DIR}/Contents/MacOS" "${APP_DIR}/Contents/Resources"
cp "${BIN}" "${APP_DIR}/Contents/MacOS/${EXEC_NAME}"

# 提示音随包进去：开始 / 结束 / 出错三个短音。
# 自己合成而不用系统音 —— 系统那几声彼此响度差太多（结尾那个比开头轻约 9 分贝），
# 吵一点的地方就听不出来；合成音的音高、音量、时长都自己定，也不受 macOS 改版影响。
if [ -d "${ROOT}/Resources" ]; then
  cp "${ROOT}"/Resources/*.wav "${APP_DIR}/Contents/Resources/"
fi

cat > "${APP_DIR}/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleExecutable</key>
	<string>${EXEC_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MACOS_MIN}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.productivity</string>
	<!-- 没有窗口、没有 Dock 图标：它躺在菜单栏里 -->
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSMicrophoneUsageDescription</key>
	<string>Dictation Turbo 要用麦克风把你说的变成文字。</string>
	<key>NSAppleEventsUsageDescription</key>
	<string>Dictation Turbo 要把转写好的文字送进你正在打字的窗口。</string>
	<!-- 只跟本机两个服务说话，都走 http://127.0.0.1 -->
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsLocalNetworking</key>
		<true/>
	</dict>
</dict>
</plist>
PLIST

echo "==> [3/4] 清理扩展属性 + 签名"
xattr -cr "${APP_DIR}" 2>/dev/null || true

# 在"干净目录"里签一次名。
#
# 为什么要这么绕：iCloud 云盘、Dropbox、坚果云这类目录由"文件提供程序"管着，
# 会给文件打上 com.apple.FinderInfo、com.apple.fileprovider.fpfs#P 这些附加属性。
# codesign 见到它们一律拒绝（原话：resource fork, Finder information, or similar
# detritus not allowed），而且这些属性**删不干净** —— xattr -cr 返回成功，东西还在。
# 解法：用 ditto --noextattr 把 .app 复制到一个临时目录，在那儿签，签完再抄回来。
# 签完的包再复制也不会坏：签名长在 _CodeSignature/ 里，跟附加属性没关系。
sign_at() {   # $1 = 要签的 .app   $2 = 签名身份（- 表示 ad-hoc）
  local target="$1" ident="$2" out
  if out="$(codesign --force --deep --sign "${ident}" "${target}" 2>&1)"; then
    return 0
  fi
  case "${out}" in
    *detritus*|*"resource fork"*)
      local tmp; tmp="$(mktemp -d "${TMPDIR:-/tmp}/dt-sign.XXXXXX")"
      echo "    （这个目录被文件提供程序管着，附加属性删不掉 —— 换到临时目录签）"
      if ditto --noextattr --norsrc "${target}" "${tmp}/app.app" 2>/dev/null \
         && codesign --force --deep --sign "${ident}" "${tmp}/app.app" >/dev/null 2>&1; then
        rm -rf "${target}"
        ditto --noextattr --norsrc "${tmp}/app.app" "${target}"
        rm -rf "${tmp}"
        echo "    （临时目录签好了，已抄回来）"
        return 0
      fi
      rm -rf "${tmp}"
      ;;
  esac
  printf '%s\n' "${out}" | sed 's/^/    /'
  return 1
}

# 优先用**固定身份**的本地证书签名，而不是 ad-hoc。
# 为什么这点很要紧：ad-hoc 签名每次重编译指纹都会变，系统就把它当成另一个程序，
# 之前给的「辅助功能」授权随即作废 —— 每改一次代码，用户就得重新勾一次。
# 固定证书的身份不随编译变化，授权一次就够。造法见 tools/make-signing-identity.sh
SIGN_ID="${DT_SIGN_IDENTITY:-Dictation Turbo Local Signing}"
if security find-identity -p codesigning 2>/dev/null | grep -q "${SIGN_ID}"; then
  echo "    签名：${SIGN_ID}（本地证书）"
  if ! sign_at "${APP_DIR}" "${SIGN_ID}"; then
    echo "    ! 本地证书签不上，退回 ad-hoc（照样能用）"
    sign_at "${APP_DIR}" - || true
  fi
else
  echo "    签名：ad-hoc（没找到本地证书 —— 每次重编译都要重新授权一次）"
  echo "    想免掉这一步：先跑 ./tools/make-signing-identity.sh"
  sign_at "${APP_DIR}" - || true
fi

if codesign --verify "${APP_DIR}" 2>/dev/null; then
  echo "    ✓ 签名有效"
else
  echo "    ! 签名校验没过（ad-hoc 时常见，本机照常能跑）"
fi

echo "==> [4/4] 完成"
echo "    产物：${APP_DIR}"
echo "    单独跑一下（不进「应用程序」）：open \"${APP_DIR}\""
echo "    装到系统里：./install.sh"
