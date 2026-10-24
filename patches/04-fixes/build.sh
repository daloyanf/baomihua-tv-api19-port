#!/bin/bash
# v1.3.0：播放渲染直通 + 详情页/片库点击播放修复
#
# 用法：
#   BASE=/path/to/v1.2.0.apk \
#   KEYSTORE=$HOME/.android-keys/walldav.jks \
#   KEYSTORE_PASS_FILE=$HOME/.android-keys/walldav.pass \
#   ./build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BASE=${BASE:?请设置 BASE=v1.2.0 成品包路径}
WORK=${WORK:-$ROOT/work/04-fixes}
BT=${BUILD_TOOLS:-$HOME/android-sdk/build-tools/33.0.1}
KS=${KEYSTORE:?请设置 KEYSTORE=签名库路径}
KSPASS=${KEYSTORE_PASS_FILE:?请设置 KEYSTORE_PASS_FILE=签名库口令文件}
KS_ALIAS=${KEYSTORE_ALIAS:-walldav}
OUT=${OUT:-$ROOT/release/baomihua-tv-2.6.22-api19-1.3.0.apk}

mkdir -p "$WORK" "$(dirname "$OUT")"
cd "$WORK"

echo "== 1. 取 classes.dex / classes3.dex 并反汇编"
unzip -o -q "$BASE" classes.dex classes3.dex
rm -rf dec dec3
baksmali d classes.dex -o dec
baksmali d classes3.dex -o dec3

echo "== 2. 打补丁（classes.dex）"
python3 "$HERE/patch_fixes.py" "$WORK/dec"

echo "== 3. 打补丁（classes3.dex：ResCompat vector 回退）"
python3 "$HERE/patch_rescompat.py" "$WORK/dec3"

echo "== 4. 汇编 dex"
smali a --api 19 dec -o classes-new.dex
smali a --api 19 dec3 -o classes3-new.dex

echo "== 5. 重打包（替换两个 dex，其余原样）"
python3 - "$BASE" packed.apk classes-new.dex classes3-new.dex <<'PY'
import sys, zipfile
base, out, dex1, dex3 = sys.argv[1:5]
new = {'classes.dex': open(dex1, 'rb').read(),
       'classes3.dex': open(dex3, 'rb').read()}
drop = {'META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/MANIFEST.MF'}
with zipfile.ZipFile(base) as zin, zipfile.ZipFile(out, 'w') as zout:
    for it in zin.infolist():
        if it.filename in drop:
            continue
        body = new.get(it.filename) or zin.read(it.filename)
        zi = zipfile.ZipInfo(it.filename, date_time=it.date_time)
        zi.compress_type = it.compress_type
        zi.external_attr = it.external_attr
        zi.create_system = it.create_system
        zout.writestr(zi, body)
print('packed:', out)
PY

echo "== 6. 资源补丁（ic_chevron_down: vector -> 25x24 PNG）"
python3 "$HERE/patch_resources.py" packed.apk packed-res.apk

echo "== 7. 对齐 + 签名（沿用 walldav 证书，可覆盖安装 v1.2.0）"
"$BT/zipalign" -f 4 packed-res.apk packed-aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-key-alias "$KS_ALIAS" --ks-pass "file:$KSPASS" \
  --min-sdk-version 19 --v1-signing-enabled true --v2-signing-enabled true \
  --v3-signing-enabled false --out "$OUT" packed-aligned.apk

ls -l "$OUT"
sha256sum "$OUT"
"$BT/apksigner" verify --print-certs "$OUT" | head -4