#!/bin/bash
# 回编 + 对齐 + 签名（v1 用）
#
# 用法（在包含 work/tv-mod 的目录执行）：
#   TV_MOD=work/tv-mod OUT=work/mod-signed.apk \
#   KEYSTORE=/path/my.jks KEYSTORE_PASS_FILE=/path/my.pass ./rebuild.sh
set -e
TV_MOD=${TV_MOD:-work/tv-mod}
OUT=${OUT:-work/mod-signed.apk}
BT=${BUILD_TOOLS:-$HOME/android-sdk/build-tools/33.0.1}
KS=${KEYSTORE:?请设置 KEYSTORE=签名库路径}
KSPASS=${KEYSTORE_PASS_FILE:?请设置 KEYSTORE_PASS_FILE=签名库口令文件}

BASE=${OUT%.apk}
apktool b --use-aapt2 "$TV_MOD" -o "${BASE}-unsigned.apk"
"$BT/zipalign" -f 4 "${BASE}-unsigned.apk" "${BASE}-aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass "file:$KSPASS" \
  --min-sdk-version 19 --v1-signing-enabled true --v2-signing-enabled true \
  --v3-signing-enabled false --out "$OUT" "${BASE}-aligned.apk"
ls -l "$OUT"
