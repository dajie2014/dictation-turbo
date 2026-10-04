#!/bin/bash
# 造一个「固定身份」的本地代码签名证书。做一次就够，以后一直用它。
#
# ★ 为什么非做不可
#   不签名、或用 ad-hoc（codesign --sign -）的时候，**每次重新编译**，
#   系统看到的都是"另一个程序"，之前给过的「辅助功能」授权立刻作废。
#   表现是：改一次代码 → 双击 Control 没反应 → 用户得去系统设置里重新勾一次。
#   用一个固定名字的证书签名，身份不随编译变化，**授权一次就够**。
#
# 用法：./tools/make-signing-identity.sh
#   已有同名证书就直接退出，不会重复造。
#   想换名字：DT_SIGN_IDENTITY="我的签名" ./tools/make-signing-identity.sh
#
# ⚠️ 这张证书没有被系统信任（security 里显示 CSSMERR_TP_NOT_TRUSTED）——
#    **这是正常的，不用管**：代码签名不需要它被信任，系统那一套授权也认这个身份。
set -euo pipefail

NAME="${DT_SIGN_IDENTITY:-Dictation Turbo Local Signing}"
KC="${HOME}/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "${NAME}"; then
  echo "✅ 已经有这个签名身份了：${NAME}"
  echo "   （不用重造。要换名字就设 DT_SIGN_IDENTITY 再跑一次。）"
  exit 0
fi

if ! command -v openssl >/dev/null 2>&1; then
  echo "!! 找不到 openssl（macOS 自带的那个在 /usr/bin/openssl）" >&2
  exit 1
fi

WORK="$(mktemp -d "${TMPDIR:-/tmp}/dt-signing.XXXXXX")"
trap 'rm -rf "${WORK}"' EXIT

cat > "${WORK}/cnf.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = ${NAME}
[v3]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

echo "==> 1/3 生成自签证书（10 年有效）"
openssl req -x509 -newkey rsa:2048 \
  -keyout "${WORK}/key.pem" -out "${WORK}/cert.pem" \
  -days 3650 -nodes -config "${WORK}/cnf.cnf" >/dev/null 2>&1

PASS="$(openssl rand -hex 12)"
echo "==> 2/3 打包成 p12"
openssl pkcs12 -export -out "${WORK}/cert.p12" \
  -inkey "${WORK}/key.pem" -in "${WORK}/cert.pem" \
  -passout "pass:${PASS}" >/dev/null 2>&1

echo "==> 3/3 导入登录钥匙串"
# -A：允许任何程序使用这把私钥。少了它，codesign 第一次签名时
# 系统会弹一个"要不要允许"的框，得人工点一下（点「始终允许」也行，但别让人干等）。
if ! security import "${WORK}/cert.p12" -k "${KC}" -P "${PASS}" -A >/dev/null 2>&1; then
  echo "   （-A 不行，退回只授权给 codesign）"
  security import "${WORK}/cert.p12" -k "${KC}" -P "${PASS}" -T /usr/bin/codesign >/dev/null
fi

if security find-identity -p codesigning 2>/dev/null | grep -q "${NAME}"; then
  echo ""
  echo "✅ 造好了：${NAME}"
  echo "   现在重新跑 ./build.sh，以后改代码就不用再授权了。"
  echo ""
  echo "   备注：security 会把它标成 CSSMERR_TP_NOT_TRUSTED —— 正常，不用理会。"
  echo "   万一签名时弹出钥匙串对话框，输一次登录密码、点「始终允许」即可。"
else
  echo "!! 没造出来。手动看一眼：security find-identity -p codesigning" >&2
  exit 1
fi
