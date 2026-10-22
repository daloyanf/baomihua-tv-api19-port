#!/bin/bash
# 阶段三构建（v1.2.0）：v1.1.0 成品 -> 播放画布改走 SurfaceView
#
# 背景：海思（当贝 H1）显示链路上，TextureView 把视频画进应用窗口后，视频区域
#       不随帧上屏；电视上大面积黑，只有进度条/音量浮层所在区域短暂露出画面。
#       SurfaceView 走独立 HWC 图层，可正常显示（详见 docs/troubleshooting.md）。
#
# 依赖（PATH 里要有）：baksmali、smali、python3、zipalign、apksigner
# 用法：
#   BASE=/path/to/baomihua-1.1.0.apk \
#   KEYSTORE=/path/to/my.jks KEYSTORE_PASS_FILE=/path/to/my.pass \
#   ./build.sh
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
BASE=${BASE:?请设置 BASE=v1.1.0 成品包路径}
WORK=${WORK:-$ROOT/work/03-display}
BT=${BUILD_TOOLS:-$HOME/android-sdk/build-tools/33.0.1}
KS=${KEYSTORE:?请设置 KEYSTORE=签名库路径}
KSPASS=${KEYSTORE_PASS_FILE:?请设置 KEYSTORE_PASS_FILE=签名库口令文件}

mkdir -p "$WORK"
cd "$WORK"

echo "== 1. 取 classes.dex 并反汇编"
unzip -o -q "$BASE" classes.dex
rm -rf dec
baksmali d classes.dex -o dec

echo "== 2. 改两处画布类型"
python3 - "$WORK/dec" <<'PY'
import os
import sys

root = sys.argv[1]

# ① IPlayer$Param 默认构造：SDK<29 原本固定 textureView
p = os.path.join(root, 'com/filmlytv/libplayer/IPlayer$Param.smali')
s = open(p, encoding='utf-8').read()
n = s.count('const-string v0, "textureView"')
if n != 1:
    sys.exit(f'Param: expected 1 textureView literal, got {n}')
s = s.replace('const-string v0, "textureView"', 'const-string v0, "surfaceView"')
open(p, 'w', encoding='utf-8').write(s)

# ② IPlayer$b.a(Param)：PlayParams.getView() 会覆盖 p/q，强制 surfaceView
p = os.path.join(root, 'com/filmlytv/libplayer/IPlayer$b.smali')
lines = open(p, encoding='utf-8').read().splitlines(keepends=True)
out = []
seen_get_view = False
patched = False
for line in lines:
    out.append(line)
    if 'PlayParams;->getView()Ljava/lang/String;' in line:
        seen_get_view = True
        continue
    if seen_get_view and 'move-result-object v3' in line:
        out.append('\n    const-string v3, "surfaceView"\n')
        seen_get_view = False
        patched = True
if not patched:
    sys.exit('IPlayer$b: getView() move-result site not found')
open(p, 'w', encoding='utf-8').write(''.join(out))
print('patched both sites')
PY

echo "== 3. 汇编 dex"
smali a --api 19 dec -o classes-new.dex

echo "== 4. 用新 classes.dex 重打包（其余文件、原生库原样保留）"
python3 - "$BASE" packed.apk classes-new.dex <<'PY'
import sys
import zipfile

base, out, newdex = sys.argv[1:4]
drop = {'META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/MANIFEST.MF'}
with zipfile.ZipFile(base) as zin, zipfile.ZipFile(out, 'w') as zout:
    for it in zin.infolist():
        if it.filename in drop:
            continue
        data = open(newdex, 'rb').read() if it.filename == 'classes.dex' else zin.read(it.filename)
        zi = zipfile.ZipInfo(it.filename, date_time=it.date_time)
        zi.compress_type = it.compress_type
        zi.external_attr = it.external_attr
        zi.create_system = it.create_system
        zout.writestr(zi, data)
print('packed:', out)
PY

echo "== 5. 对齐 + 签名"
"$BT/zipalign" -f 4 packed.apk packed-aligned.apk
"$BT/apksigner" sign --ks "$KS" --ks-pass "file:$KSPASS" \
  --min-sdk-version 19 --v1-signing-enabled true --v2-signing-enabled true \
  --v3-signing-enabled false --out baomihua-1.2.0-signed.apk packed-aligned.apk

ls -l baomihua-1.2.0-signed.apk
sha256sum baomihua-1.2.0-signed.apk
