#!/bin/bash
# 阶段二构建（v1.1.0）：v1.0.0 基础包 -> 播放链路可用的 API19 包
#
# 依赖（PATH 里要有）：baksmali、smali、python3、zipalign、apksigner
# 用法：
#   BASE=/path/to/base.apk \
#   KEYSTORE=/path/to/my.jks KEYSTORE_PASS_FILE=/path/to/my.pass \
#   ./build.sh
#
# 说明：
#   - BASE 必须是已经过 API19 引导的包（minSdk19/MultiDex/R8 构造器修复/签名密钥替换），
#     也就是阶段一（v1.0.0）的产物。
#   - 第一次运行前把设备 libc 放到 $WORK/devlib/libc.so（仅用于让垫片带 NEEDED libc.so）：
#       adb pull /system/lib/libc.so work/devlib/libc.so
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BASE=${BASE:?请设置 BASE=v1.0.0 基础包路径}
WORK=${WORK:-$ROOT/work}
BT=${BUILD_TOOLS:-$HOME/android-sdk/build-tools/33.0.1}
KS=${KEYSTORE:?请设置 KEYSTORE=签名库路径}
KSPASS=${KEYSTORE_PASS_FILE:?请设置 KEYSTORE_PASS_FILE=签名库口令文件}

mkdir -p "$WORK"
cd "$WORK"

echo "== 1. 解包 v1 基础包"
unzip -o -q "$BASE" classes.dex classes2.dex classes3.dex 'lib/armeabi-v7a/libvlc.so'

echo "== 2. baksmali（classes.dex 与 classes3.dex）"
rm -rf dexwork
mkdir -p dexwork
baksmali d classes.dex -o dexwork/dec
baksmali d classes3.dex -o dexwork/classes3_dec

echo "== 3. 应用阶段二补丁（幂等）"
python3 "$HERE/patch_player_api19.py" "$WORK/dexwork"

echo "== 4. 汇编 dex"
smali a --api 19 dexwork/dec -o dexwork/classes-new.dex
smali a --api 19 dexwork/classes3_dec -o dexwork/classes3-new.dex

echo "== 5. 改 libvlc 的 NEEDED"
mkdir -p patched
python3 "$HERE/patch_libvlc_needed.py" lib/armeabi-v7a/libvlc.so patched/libvlc.so

echo "== 6. 垫片"
if [ ! -f "$ROOT/shim/libcompat.so" ]; then
  ( cd "$ROOT/shim" && DEVLIBS="$WORK/devlib" ./build.sh )
fi

echo "== 7. 重打包 + 签名"
python3 "$HERE/repack.py" "$BASE" packed.apk \
  dexwork/classes-new.dex dexwork/classes3-new.dex patched/libvlc.so "$ROOT/shim/libcompat.so"
"$BT/zipalign" -f 4 packed.apk packed-aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass "file:$KSPASS" \
  --min-sdk-version 19 --v1-signing-enabled true --v2-signing-enabled true \
  --v3-signing-enabled false --out baomihua-1.1.0-signed.apk packed-aligned.apk

ls -l baomihua-1.1.0-signed.apk
sha256sum baomihua-1.1.0-signed.apk
