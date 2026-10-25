# 构建步骤

## 依赖

| 工具 | 版本/说明 |
| --- | --- |
| apktool | 2.7.0（v1 解码/回编） |
| smali / baksmali | 2.5.x（阶段二/三只重编 dex） |
| Android build-tools | 33.0.1（zipalign、apksigner） |
| JDK | 21（apksigner 需要） |
| Zig | 0.13.0（交叉编译垫片） |
| Python | 3.8+ |
| adb | 任意较新版本 |

## 拿官方包

官方版本接口是 `https://api.filmly.netease.com/w/v1/version`。
直接拼下载 URL 会 403，需要在 ADL 页面拿到带 `key1/key2` 的签名 URL 再下载
（TV 版 `2.6.22`，versionCode 1390，minSdk 21，含 armeabi-v7a）。

## 阶段一（v1.0.0）：API19 引导（从官方包到可启动）

阶段一的目标是让应用在 4.4 上能装、能启动、能过服务端鉴权。步骤见
[docs/api19.md](api19.md) 的「阶段一」表，这里给操作顺序：

```bash
# 0) 解码官方包
apktool d -f -o work/tv BaoMiHua-TV-2.6.22.apk

# 1) 手改 minSdk / uses-feature（或写脚本改 apktool.yml + AndroidManifest.xml）
# 2) 注入 legacy multidex（androidx.multidex 1.0.3），attachBaseContext 里 install
# 3) 跑 R8 构造器修复（本仓库提供其中一类）：
python3 patches/01-bootstrap/fix_direct_super.py          # 直接父类非 Object 却直调 Object
#    另外两类（new X + 父类 <init> 重定向、合并类残留）需要自己实现或手工处理
# 4) 换 GCM -> IvParameterSpec
python3 patches/01-bootstrap/patch_gcm.py
# 5) TLS 协议交集等 API19 兜底
python3 patches/01-bootstrap/patch_api19_compat.py
# 6) BaseBundle -> Bundle、Sentry Provider 移除、ApplicationExitInfo/onTerminate 桩
# 7) getSecretKey/getNativeAPI 改 Java 实现（密钥固定 9B7B94D0…，见 protocol.md）
# 8) 资源名去 $/_ 前缀；model 包挪到 classes3；native 垫片与 __read_chk 改名
# 9) 回编 + 对齐 + 签名
bash patches/01-bootstrap/rebuild.sh
```

> ⚠️ **阶段一的自动化流水线不完整。** 早期 `patch_all.py` / `fix_superctor.py` /
> `fix_merged_super.py` 已丢失，仓库只保留了上面能拿到的三个补丁脚本和回编脚本。
> 其余步骤（multidex 注入、R8 另两类修复、dex 均衡、资源改名、native 垫片注入）
> 需要按 docs/api19.md 与 docs/native.md 的描述自行实现。
> 如果你只是想复现 v1.1.0，可以直接使用自己已经做好的 v1.0.0 基础包。

阶段一产物应满足：`adb install` 成功、能启动、能到扫码/登录页、片库能加载。

## 阶段二（v1.1.0）：播放链路

```bash
# 依赖设备 libc 快照（让垫片带 NEEDED libc.so）
mkdir -p work/devlib
adb pull /system/lib/libc.so work/devlib/libc.so

BASE=/path/to/baomihua-1.0.0.apk \
KEYSTORE=$HOME/.android-keys/my.jks \
KEYSTORE_PASS_FILE=$HOME/.android-keys/my.pass \
./patches/02-playback/build.sh
```

脚本做的事：

1. 从 BASE 解出 `classes.dex/classes2.dex/classes3.dex` 和 `libvlc.so`；
2. `baksmali` 解 `classes.dex`、`classes3.dex`；
3. `patch_player_api19.py` 打 Java 补丁（幂等）；
4. `smali a --api 19` 重编；
5. `patch_libvlc_needed.py` 把 `libstdc++.so` 改成 `libcompat.so`；
6. 没有垫片产物就调用 `shim/build.sh`；
7. 重打包（替换 dex + libvlc、加入 libcompat.so）、zipalign、apksigner。

## 阶段三（v1.2.0）：画面显示（画布改 SurfaceView）

```bash
BASE=/path/to/baomihua-1.1.0.apk \
KEYSTORE=$HOME/.android-keys/my.jks \
KEYSTORE_PASS_FILE=$HOME/.android-keys/my.pass \
./patches/03-display/build.sh
```

脚本只替换 `classes.dex`（改两处画布类型），其余文件与原生库原样保留，
然后 zipalign + apksigner。原因与验证见 [troubleshooting.md](troubleshooting.md)
的 v1.2.0 一节。

## 阶段四（v1.3.0）：播放渲染 / 点击播放修复

```bash
BASE=/path/to/baomihua-1.2.0.apk \
KEYSTORE=$HOME/.android-keys/walldav.jks \
KEYSTORE_PASS_FILE=$HOME/.android-keys/walldav.pass \
./patches/04-fixes/build.sh
```

脚本替换 `classes.dex` / `classes3.dex`，另做一处 drawable 资源替换：

1. `IPlayer$b.a()` 固定 `renderer=direct`、`no_drop_late_frames=false`，并忽略服务端
   `decoder_score_list`（保留内置 OMX 硬解评分表）；
2. `h7.e0` 在详情页有 `File` 时优先走 `PlayerActivity.a.e(File)`；
3. `adapter/cover/a$a` 对带 `File` 的 `OtherCover` 固定使用直连播放 presenter；
4. `BottomSheetBehavior` / `SideSheetBehavior` / `j5/b` / `o0/r0$c` 的 API19
   校验与运行修复（`MotionCompat` 常量、API21 insets 分支、Path 转换）；
5. `ResCompat` 在 vector XML 加载失败时回退 `VectorDrawableCompat`；
6. 把 `ic_chevron_down` 从 vector XML 换成 25x24 PNG（改 `resources.arsc` 路径）。

签名证书与 v1.2.0 相同，可直接 `adb install -r` 覆盖，登录态与缓存保留。
原因与验证建议见 [patches/04-fixes/README.md](../patches/04-fixes/README.md)。

## 阶段五（v1.4.0）：换官方 VLC 引擎接海思硬解

前置：下载官方 VLC for Android 3.6.2 armv7 包并解出三个原生库
（videolan 官方镜像：`vlc-android/3.6.2/VLC-Android-3.6.2-armeabi-v7a.apk`）：

```bash
unzip -o VLC-Android-3.6.2-armeabi-v7a.apk 'lib/armeabi-v7a/*' -d vlc362
```

构建：

```bash
OUT=baomihua-tv-2.6.22-api19-1.4.0.apk \
KS_PASS_FILE=$HOME/.android-keys/walldav.pass \
SWAPLIB=vlc362/lib/armeabi-v7a \
./patches/05-engine-swap/build.sh
```

脚本内容（逐条理由写在 `build.sh` 头部注释里）：

1. 替换 `libvlc.so` / `libvlcjni.so` / `libc++_shared.so` 为官方 3.6.2 构建；
2. `HWDecoderUtil.getDecoderFromDevice()` 强制 `ALL`、`Media.getMediaCodecModule()`
   固定 `mediacodec_jni`（fork 的 SDK 判级在 4.4 上错选 ndk 变体）；
3. `Media.createStatsFromNative` 增加官方签名桥接（官方 JNI 回调签名与 fork 构造器
   不同，缺了会 `NoSuchMethodError`）；4 个 Java→native 与 3 个日志 native 改桩；
4. `AWindow.setBuffersGeometry` 补 `holder.setFormat/setFixedSize` 实现
   （fork 的空桩导致显示几何无人设置）；
5. `PlayerActivity` 注入 `--vout=android-opaque`（官方自动选 gles2 在本机 HWC 黑屏）；
6. `o0.o.g(II)` 增 `NoSuchMethodError` catch（Dalvik 触摸崩溃）。

签名证书与 v1.3.0 相同，可直接覆盖安装。真机验证口径与 4K 限制见
[troubleshooting.md](troubleshooting.md) 的 v1.4.0 一节。

## 签名

```bash
keytool -genkey -v -keystore my.jks -alias app -keyalg RSA -keysize 2048 \
  -validity 10000 -storepass '你的口令'
echo -n '你的口令' > my.pass
```

注意：

- **签名证书与 AES 密钥无关**。应用内的密钥是硬编码的官方证书派生值，
  你自己的证书只影响安装/校验，不影响服务端鉴权。
- 与官方签名不同，**首次安装必须先卸载官方版**（同包名不同签名，`-r` 会失败）。
  卸载会清数据，登录态需要重新扫码。

## 安装与自检

```bash
adb install -r baomihua-1.2.0-signed.apk
adb shell am start -n com.netease.filmlytv/.activity.LaunchActivity
adb logcat -c; adb logcat -v time | grep -E "Trying to load lib|dlopen|cannot locate|FATAL"
```

期望：`libcompat.so` → `libvlc.so` → `libvlcjni.so` 依次加载，没有
`cannot locate symbol`；进播放器后 `VLC-std` 开始按帧刷日志。

截图（`screencap` 坏掉的机器）：

```bash
./tools/shot.sh /tmp/shot.png <盒子IP>:5555
```
