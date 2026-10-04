#!/bin/bash
# 用系统自带的朗读功能造三段示例音频，用来做自检（--selftest）。
#   ./tools/make-samples.sh
#
# 用不着联网，也不含任何人的声音 —— 就是系统朗读合成出来的。
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="${ROOT}/samples"
mkdir -p "${OUT}"
SAY=/usr/bin/say
AFCONVERT=/usr/bin/afconvert

# 语音包不是每台机器都全：有就做，没有就跳过，别让脚本半路死掉。
has_voice() { "${SAY}" -v '?' 2>/dev/null | awk '{print $1}' | grep -qx "$1"; }

made=0
make_one() {           # 参数：语言码 语音名 文本
  local code="$1" voice="$2" text="$3"
  if ! has_voice "${voice}"; then
    echo "   ➖ 跳过 ${code}：这台机器没装「${voice}」这个朗读声音"
    return 0
  fi
  "${SAY}" -v "${voice}" -o "${OUT}/${code}.aiff" "${text}"
  "${AFCONVERT}" -f WAVE -d LEI16@16000 -c 1 "${OUT}/${code}.aiff" "${OUT}/${code}.wav" >/dev/null
  rm -f "${OUT}/${code}.aiff"
  echo "   ✅ samples/${code}.wav"
  made=$((made + 1))
}

echo "==> 生成示例音频（16 kHz 单声道 WAV）"
make_one zh Tingting "今天天气不错，我们下午三点开会，别忘了带上笔记本。"
make_one en Samantha "The quick brown fox jumps over the lazy dog."
make_one de Anna     "Guten Tag, das ist ein Test der Spracherkennung."

if [ "${made}" = "0" ]; then
  echo "!! 一个都没生成 —— 这台机器上可能缺朗读声音。" >&2
  echo "   看有哪些：say -v '?'" >&2
  exit 1
fi

echo ""
echo "现在可以验识别那一段（不用开麦克风、不用按热键）："
echo "   \"./build/Dictation Turbo.app/Contents/MacOS/DictationTurbo\" --selftest samples/*.wav"
