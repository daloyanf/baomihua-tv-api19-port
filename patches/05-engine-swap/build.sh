#!/bin/bash
# =============================================================================
# 05-engine-swap: 网易爆米花 v1.3.0 -> v1.4.0（换官方 VLC 引擎接海思硬解）
# =============================================================================
#
# 背景（证据链见 docs/troubleshooting.md 的「v1.4.0」一节）：
#   - 爆米花自带 libvlc 是网易自编译的 3.0.21。该构建在 API19 上 mediacodec
#     的两种变体（ndk/jni）初始化都失败，播放恒落 libavcodec 软解，
#     1440x600 级内容 CPU 就有 57~76%。
#   - 官方 VLC 3.6.2（同为 LibVLC 3.0.21）在同机可正常使用 mediacodec_jni，
#     实测能拉起海思硬解组件 OMX.hisi.video.decoder.avc（4K 解码 CPU 约 2%）。
#   - 因此本补丁把 APK 内的三个 native 库换成官方包的版本，并在 Java 层
#     补齐两边的 9 处接口差异。
#
# 前置条件：
#   1. 官方 VLC 3.6.2 armv7 APK 解出的三个库放在 $SWAPLIB：
#        VLC-Android-3.6.2-armeabi-v7a.apk (videolan 官方镜像 44.6MB)
#        unzip -o VLC-Android-3.6.2-armeabi-v7a.apk 'lib/armeabi-v7a/*'
#      SWAPLIB 结构：lib/armeabi-v7a/{libvlc.so,libvlcjni.so,libc++_shared.so}
#   2. v1.3.0 基础包在 $BASE；apktool/baksmali/smali 在 PATH；
#      Android build-tools（zipalign/apksigner）在 $BT；密钥库 $KS。
#
# 用法:
#   OUT=/path/out.apk KS_PASS=<口令> [SWAPLIB=dir] ./build.sh
#
# 补丁清单与理由：
#   A. native 库替换  — 硬解能力来源（见上）
#   B. HWDecoderUtil.getDecoderFromDevice -> ALL
#      fork 的 SOC 黑名单在 H1 上命中，返回 MEDIACODEC，导致 Media 拼出的
#      解码器偏好列表不含 omx 路径；强制 ALL 走通用分支（保险丝）。
#   C. Media.getMediaCodecModule -> "mediacodec_jni"
#      fork 的 SDK 判级在 4.4 上错选 mediacodec_ndk（API21+ 才可用），
#      官方库需要用 jni 变体才能在 4.4 上初始化。
#   D. Media.createStatsFromNative：加官方签名桥接
#      官方 libvlcjni 会反射回调 Java 的这个静态方法；fork 把
#      displayedPictures/lostPictures 扩成 long 并新增 5 个统计字段，
#      签名不同会抛 NoSuchMethodError 崩溃。桥接方法把官方 15 参映射到
#      fork 的 20 参构造器（新增字段填 0）。
#   E. 4 个 Java->native 方法改桩（Media.nativeGetMetaExtra、
#      MediaPlayer.nativeGetBytePosition/nativeGetCodecInfo/nativeNextFrame）
#      官方 libvlcjni 不导出这些 fork 私有方法，不改则调用时
#      UnsatisfiedLinkError。均为元数据/调试用途，返回默认值不影响播放。
#   F. 3 个日志 native 改桩（OkClient.nativeLog、VlcNativeLog.nativeLog、
#      VLCUtil.log）同 E，fork 私有日志接口，官方库没有。
#   G. AWindow.setBuffersGeometry：补真实现
#      fork 把它改成了 return false 的空桩，而官方 C 端在 4.4 上会回退调用
#      这个方法设置 Surface 缓冲几何（holder.setFormat + setFixedSize）。
#      不实现则视频缓冲进不了窗口（4K 黑屏的直接原因之一）。
#      注意：nativeOnMouseEvent/nativeOnWindowSize 两个 AWindow 的 native
#      回调 **不能桩**——官方 C 用 RegisterNatives 动态绑定它们，
#      桩掉会报 "AndroidNativeWindow jni init failed"。
#   H. PlayerActivity 参数注入 --vout=android-opaque
#      官方引擎在本机自动选 gles2，其 GL 层被海思 HWC 合成不了（SurfaceFlinger
#      层 UNKNOWN、黑屏）；android-opaque 是 ANativeWindow 直出，可用。
#      模块名是连字符（android-display / android-opaque），下划线无效。
#   I. o0.o 触摸崩溃修复
#      Dalvik 对缺失接口方法抛 NoSuchMethodError，而 androidx 的
#      ViewParentCompat 只 catch 了 AbstractMethodError，任何触摸事件都会崩。
#      给同一 try 区段补一个 NoSuchMethodError 的 catch 即可。
#
# 验证（真机）：
#   adb logcat | grep HIOMX_CORE   # 应出现 OMX.hisi.video.decoder.avc + Init OMX component
#   adb shell top -n 1 | grep filmlytv   # 播放中 CPU 约 10%（软解同内容 57~76%）
#   画面以电视实际输出为准；本机 gles2 不可用，只能走 android-opaque。
# =============================================================================
set -euo pipefail

BASE=${BASE:-/mnt/Others/baomihua-tv-api19-port/release/baomihua-tv-2.6.22-api19-1.3.0.apk}
KS=${KEYSTORE:-$HOME/.android-keys/walldav.jks}
BT=${BUILD_TOOLS:-$HOME/android-sdk/build-tools/33.0.1}
SWAPLIB=${SWAPLIB:-/tmp/hwtest/swap/lib/armeabi-v7a}
OUT=${OUT:?OUT=输出apk}
: "${KS_PASS:?KS_PASS=签名口令}"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

unzip -q "$BASE" -d "$W/apk"

# ---------------------------------------------------------------------------
# A. 换官方 native 库
#   libvlc.so      : 播放引擎本体（官方 3.6.2 构建，mediacodec_jni 可用）
#   libvlcjni.so   : 引擎 Java 桥（与官方 libvlc.so 配套，勿混用 fork 版）
#   libc++_shared.so: STL（官方与 fork 同版本，替换保持一致）
#   注意：fork 的 libcompat.so/libcompatshim.so 留在包里不再被依赖，无害。
# ---------------------------------------------------------------------------
cp "$SWAPLIB/libvlc.so" "$SWAPLIB/libvlcjni.so" "$SWAPLIB/libc++_shared.so" \
   "$W/apk/lib/armeabi-v7a/"

# ---------------------------------------------------------------------------
# I. classes.dex：触摸崩溃修复（o0.o = androidx ViewParentCompat 混淆名）
#   在原有 catch AbstractMethodError 的同一 try 区段追加 NoSuchMethodError，
#   两者都跳到既有的 :catch_2e 处理（记录日志并返回 false）。
# ---------------------------------------------------------------------------
baksmali d "$W/apk/classes.dex" -o "$W/apk/smali_out"
python3 - "$W/apk/smali_out/o0/o.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
old = ".catch Ljava/lang/AbstractMethodError; {:try_start_29 .. :try_end_2d} :catch_2e"
assert src.count(old) == 1, "touch anchor: %d" % src.count(old)
src = src.replace(old, old + "\n    .catch Ljava/lang/NoSuchMethodError; {:try_start_29 .. :try_end_2d} :catch_2e", 1)
open(path, "w").write(src)
print("patched: o0.o +NoSuchMethodError catch (Dalvik 触摸崩溃)")
PYEOF
smali a --api 19 "$W/apk/smali_out" -o "$W/apk/classes.dex"
rm -rf "$W/apk/smali_out"

# ---------------------------------------------------------------------------
# B~H 全部在 classes3.dex（org.videolan.libvlc.*），一次性拆包处理
# ---------------------------------------------------------------------------
baksmali d "$W/apk/classes3.dex" -o "$W/apk/smali3_out"

# ---- B. 解码器设备判定强制 ALL（绕开 fork 的 SOC 黑名单） ----
python3 - "$W/apk/smali3_out/org/videolan/libvlc/util/HWDecoderUtil.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = ".method public static getDecoderFromDevice()Lorg/videolan/libvlc/util/HWDecoderUtil$Decoder;\n    .registers 7\n"
assert src.count(anchor) == 1
# 方法体开头直接 return ALL，跳过黑名单表与 SOC 匹配
src = src.replace(anchor, anchor +
    "    sget-object v0, Lorg/videolan/libvlc/util/HWDecoderUtil$Decoder;->ALL:Lorg/videolan/libvlc/util/HWDecoderUtil$Decoder;\n"
    "    return-object v0\n", 1)
open(path, "w").write(src)
print("patched: getDecoderFromDevice -> ALL")
PYEOF

# ---- C. getMediaCodecModule 固定 mediacodec_jni + E. nativeGetMetaExtra 改桩 ----
python3 - "$W/apk/smali3_out/org/videolan/libvlc/Media.smali" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
# E: fork 私有 native（官方 libvlcjni 无导出）→ 返回 null 的普通方法
pat = re.compile(r"\.method private native nativeGetMetaExtra\(Ljava/lang/String;\)Ljava/lang/String;\n\.end method")
new_m = (
    ".method private nativeGetMetaExtra(Ljava/lang/String;)Ljava/lang/String;\n"
    "    .locals 1\n"
    "    const/4 v0, 0x0\n"
    "    return-object v0\n"
    ".end method\n")
assert pat.search(src), "nativeGetMetaExtra not found"
src = pat.sub(new_m, src, count=1)
# C: fork 的 SDK 判级 bug（4.4 上调到 ndk 变体）→ 硬编码 jni
pat2 = re.compile(r"\.method private static getMediaCodecModule\(\)Ljava/lang/String;.*?\.end method", re.S)
new_g = (
    ".method private static getMediaCodecModule()Ljava/lang/String;\n"
    "    .registers 1\n"
    "    const-string v0, \"mediacodec_jni\"\n"
    "    return-object v0\n"
    ".end method\n")
assert pat2.search(src), "getMediaCodecModule not found"
src = pat2.sub(new_g, src, count=1)
open(path, "w").write(src)
print("patched: Media nativeGetMetaExtra stub + getMediaCodecModule -> mediacodec_jni")
PYEOF

# ---- E. MediaPlayer 三个私有 native 改桩 ----
python3 - "$W/apk/smali3_out/org/videolan/libvlc/MediaPlayer.smali" <<'PYEOF'
import sys, re
path = sys.argv[1]
src = open(path).read()
subs = [
  (re.compile(r"\.method private native nativeGetBytePosition\(\)J\n\.end method"),
   ".method private nativeGetBytePosition()J\n    .locals 2\n    const-wide/16 v0, 0x0\n    return-wide v0\n.end method\n"),
  (re.compile(r"\.method private native nativeGetCodecInfo\(\)Ljava/lang/String;\n\.end method"),
   ".method private nativeGetCodecInfo()Ljava/lang/String;\n    .locals 1\n    const/4 v0, 0x0\n    return-object v0\n.end method\n"),
  (re.compile(r"\.method private native nativeNextFrame\(\)V\n\.end method"),
   ".method private nativeNextFrame()V\n    .locals 0\n    return-void\n.end method\n"),
]
for pat, rep in subs:
    assert pat.search(src), pat.pattern[:50]
    src = pat.sub(rep, src, count=1)
open(path, "w").write(src)
print("patched: MediaPlayer 3 native stubs")
PYEOF

# ---- D. createStatsFromNative 官方签名桥接 ----
# 官方 libvlcjni 的回调签名：(IFIFIIIIIIIIIIF)Lorg/videolan/libvlc/interfaces/IMedia$Stats;
# fork 构造器签名：       (IFIFIIIIJJIIIIJIIIIF)V  —— 多 5 个字段、两个 I 改 J
# 映射：官方 p8(displayedPictures→J)、p9(lostPictures→J)，新增字段(videoDelay/
# videoDropRate/videoInputRate/videoInputRateAdjust/videoDecoderLimitFps)填 0。
# smali 要点：.registers 39 时参数在末端（p0..p14 = v24..v38）；int-to-long 与
# const/4 只能寻址 v0..v15，所以宽化先落到低位再 move-wide/from16 到目标槽。
python3 - "$W/apk/smali3_out/org/videolan/libvlc/Media.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = ".method private static getMediaCodecModule()Ljava/lang/String;"
assert src.count(anchor) == 1
bridge = (
    ".method private static createStatsFromNative(IFIFIIIIIIIIIIF)Lorg/videolan/libvlc/interfaces/IMedia$Stats;\n"
    "    .registers 39\n"
    "    new-instance v0, Lorg/videolan/libvlc/interfaces/IMedia$Stats;\n"
    "    move/from16 v1, v24\n"
    "    move/from16 v2, v25\n"
    "    move/from16 v3, v26\n"
    "    move/from16 v4, v27\n"
    "    move/from16 v5, v28\n"
    "    move/from16 v6, v29\n"
    "    move/from16 v7, v30\n"
    "    move/from16 v8, v31\n"
    "    move/from16 v13, v32\n"
    "    int-to-long v9, v13\n"
    "    const/4 v13, 0x0\n"
    "    const-wide/16 v11, 0x0\n"
    "    move/from16 v14, v33\n"
    "    int-to-long v11, v14\n"
    "    move-wide/from16 v17, v11\n"
    "    const-wide/16 v11, 0x0\n"
    "    const/4 v14, 0x0\n"
    "    const/4 v15, 0x0\n"
    "    move/from16 v16, v15\n"
    "    move/from16 v19, v34\n"
    "    move/from16 v20, v35\n"
    "    move/from16 v21, v36\n"
    "    move/from16 v22, v37\n"
    "    move/from16 v23, v38\n"
    "    invoke-direct/range {v0 .. v23}, Lorg/videolan/libvlc/interfaces/IMedia$Stats;-><init>(IFIFIIIIJJIIIIJIIIIF)V\n"
    "    return-object v0\n"
    ".end method\n"
    "\n")
src = src.replace(anchor, bridge + anchor, 1)
open(path, "w").write(src)
print("patched: createStatsFromNative 桥接（官方签名 -> fork 构造器）")
PYEOF

# ---- F. 三个 fork 私有日志 native 改桩 ----
python3 - "$W" <<'PYEOF2'
import re
def stub(path, name_sig, body):
    src = open(path).read()
    pat = re.compile(r"\.method (public|private) static native " + re.escape(name_sig) + r"\n\.end method")
    m = pat.search(src)
    assert m, "stub target missing in %s: %s" % (path, name_sig)
    vis = m.group(1)
    rep = ".method %s static %s\n%s.end method\n" % (vis, name_sig, body)
    src = pat.sub(rep, src, count=1)
    open(path, "w").write(src)
    print("patched:", path.split('/')[-1], name_sig)

import sys
W = sys.argv[1]
d = W + "/apk/smali3_out/org/videolan/libvlc"
stub(d + "/OkClient.smali", "nativeLog(ILjava/lang/String;)V", "    .locals 0\n    return-void\n")
stub(d + "/VlcNativeLog.smali", "nativeLog(ILjava/lang/String;)V", "    .locals 0\n    return-void\n")
stub(d + "/util/VLCUtil.smali", "log(ILjava/lang/String;Ljava/lang/String;)I", "    .locals 1\n    const/4 v0, 0x0\n    return v0\n")
PYEOF2

# ---- G. AWindow.setBuffersGeometry 补真实现 ----
# fork 版是空桩（return false）。官方 C（display.c AndroidWindow_ConfigureJavaSurface）
# 在 4.4 上会回退调用它设置缓冲几何：按 surface 找到对应的 SurfaceHelper，
# 对 holder 依次 setFormat/setFixedSize，让随后的断/连重建拿到新几何。
# 找不到匹配/任何异常 → 返回 false（保持旧行为，不中断播放）。
# 再次强调：同类的 nativeOnMouseEvent/nativeOnWindowSize 必须保持 native！
python3 - "$W/apk/smali3_out/org/videolan/libvlc/AWindow.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
h = src.find(".method private setBuffersGeometry(Landroid/view/Surface;III)Z")
assert h >= 0, "header not found"
e = src.find(".end method", h)
assert e > h
new = """.method private setBuffersGeometry(Landroid/view/Surface;III)Z
    .locals 4
    if-eqz p1, :fail
    if-nez p2, :fail
    if-nez p3, :fail
    const/4 v0, 0x0

    :loop
    iget-object v3, p0, Lorg/videolan/libvlc/AWindow;->mSurfaceHelpers:[Lorg/videolan/libvlc/AWindow$SurfaceHelper;
    array-length v3, v3
    if-ge v0, v3, :fail
    iget-object v3, p0, Lorg/videolan/libvlc/AWindow;->mSurfaceHelpers:[Lorg/videolan/libvlc/AWindow$SurfaceHelper;
    aget-object v1, v3, v0
    if-nez v1, :next
    iget-object v2, v1, Lorg/videolan/libvlc/AWindow$SurfaceHelper;->mSurface:Landroid/view/Surface;
    if-ne v2, p1, :next
    :try_start
    iget-object v2, v1, Lorg/videolan/libvlc/AWindow$SurfaceHelper;->mSurfaceHolder:Landroid/view/SurfaceHolder;
    if-eqz v2, :ok
    if-eqz p4, :skipformat
    invoke-interface {v2, p4}, Landroid/view/SurfaceHolder;->setFormat(I)V
    :skipformat
    invoke-interface {v2, p2, p3}, Landroid/view/SurfaceHolder;->setFixedSize(II)V
    :try_end
    .catch Ljava/lang/Throwable; {:try_start .. :try_end} :catch_all
    :ok
    const/4 v3, 0x1
    return v3

    :catch_all
    const/4 v3, 0x0
    return v3

    :next
    add-int/lit8 v0, v0, 0x1
    goto :loop

    :fail
    const/4 v3, 0x0
    return v3
.end method"""
src = src[:h] + new + src[e + len(".end method"):]
open(path, "w").write(src)
print("patched: AWindow.setBuffersGeometry 真实现（holder setFormat+setFixedSize）")
PYEOF

# ---- 汇编 classes3 并做落地校验（防止 smali 静默失败留下旧 dex） ----
smali a --api 19 "$W/apk/smali3_out" -o "$W/apk/classes3.dex"
baksmali d "$W/apk/classes3.dex" -o "$W/apk/verify3"
grep -q "createStatsFromNative(IFIFIIIIIIIIIIF)" "$W/apk/verify3/org/videolan/libvlc/Media.smali" \
  || { echo "FATAL: createStatsFromNative 桥接未进 dex"; exit 1; }
grep -q 'const-string v0, "mediacodec_jni"' "$W/apk/verify3/org/videolan/libvlc/Media.smali" \
  || { echo "FATAL: getMediaCodecModule 补丁未进 dex"; exit 1; }
rm -rf "$W/apk/verify3"
# 清掉中间目录，否则会被一起打进球包（曾漏删导致 APK 虚增 8MB/3000+ 文件）
rm -rf "$W/apk/smali3_out"
echo "verified: classes3 patches present"

# ---- H. PlayerActivity 注入 --vout=android-opaque ----
# 官方引擎自动选 gles2 → 本机 HWC 合成不了 GL 层（黑屏）；
# android-opaque 走 ANativeWindow 直出。注入点在 LibVLC 构造前、参数列表(v6)上。
baksmali d "$W/apk/classes.dex" -o "$W/apk/smali_out"
python3 - "$W/apk/smali_out/com/netease/filmlytv/activity/player/PlayerActivity.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()
anchor = "    new-instance v4, Lorg/videolan/libvlc/LibVLC;"
assert src.count(anchor) == 1, "LibVLC anchor: %d" % src.count(anchor)
inject = (
    "    const-string v9, \"--vout=android-opaque\"\n"
    "    invoke-interface {v6, v9}, Ljava/util/List;->add(Ljava/lang/Object;)Z\n"
    "\n"
)
src = src.replace(anchor, inject + anchor, 1)
open(path, "w").write(src)
print("patched: PlayerActivity 注入 --vout=android-opaque")
PYEOF
smali a --api 19 "$W/apk/smali_out" -o "$W/apk/classes.dex"
rm -rf "$W/apk/smali_out"

# ---------------------------------------------------------------------------
# 打包 + 签名（与 v1.0.0~v1.3.0 同证书，可直接覆盖安装）
# ---------------------------------------------------------------------------
cd "$W/apk"
rm -rf META-INF
zip -qr9 "$W/out.apk" .
cd - >/dev/null
"$BT/zipalign" -f 4 "$W/out.apk" "$W/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias walldav \
    --ks-pass env:KS_PASS --key-pass env:KS_PASS \
    --out "$OUT" "$W/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT" | head -2
ls -la "$OUT"
