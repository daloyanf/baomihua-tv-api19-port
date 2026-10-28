# 让老电视盒子也能看网易爆米花

网易爆米花 TV 官方版要求 **Android 5.0 以上**。很多老电视盒子——包括当贝 H1——
还停在 **Android 4.4**，官方包装不上，或者装上后一点播放就闪退。

这个项目把官方 TV 版（2.6.22）适配到了 Android 4.4，并且把**播放**这条链路真正修通：
装好之后用法和官方版一样，扫码登录、选片、播放、续播、选集、切换音轨都能用。

- **下载**：[Releases → v1.5.0](https://github.com/daloyanf/baomihua-tv-api19-port/releases/tag/v1.5.0)
- 测试机：当贝 H1（Hi3798MV310，Android 4.4.2，armeabi-v7a，1080p）
- 基于：网易爆米花 TV `2.6.22`

## 版本

| 版本 | 日期 | 阶段 | 内容 |
| --- | --- | --- | --- |
| **v1.5.0** | 2026-10-27 | 轨道菜单 | 清晰度/字幕/音轨菜单可用：显示真实轨道名、面板可上下导航、选中即切换（**最新**） |
| v1.4.0 | 2026-10-26 | 硬件解码 | 换官方 VLC 3.6.2 引擎，接海思硬解（OMX.hisi），1080 级内容 CPU 10% 左右；4K 显示受限（见下）；顺带修触摸崩溃 |
| v1.3.0 | 2026-10-23 | 播放修复 | 固定 renderer=direct（修花屏/卡顿）、详情页优先 File 直连、OtherCover 直接播 |
| v1.2.0 | 2026-10-22 | 画面显示 | 画布改 SurfaceView，修复电视端黑屏/只在 UI 处露画面 |
| v1.1.0 | 2026-10-21 | 播放链路 | libvlc 加载、H.264 解码、音频、暂停/续播/选集 |
| v1.0.0 | 2026-10-21 | API19 引导 | 能安装、启动、扫码登录、加载片库/海报墙（不能正常播放） |

## 适合哪些设备

- 系统：**Android 4.4（API 19）及以上**（低于 4.4 不支持）
- CPU：**armeabi-v7a**（32 位 ARM；这个包不含 arm64）
- 已在当贝 H1 上逐项实测；其他 4.4 盒子理论上可用，但没有逐台验证
- 内存建议 1GB 以上

> 新盒子（Android 5+）请直接用官方版，不需要这个包。

## 安装

1. 从 [Releases](https://github.com/daloyanf/baomihua-tv-api19-port/releases/tag/v1.5.0) 下载
   `baomihua-tv-2.6.22-api19-1.5.0.apk`
2. **如果装过官方版，先卸载**（两者签名不同，直接覆盖会提示"应用未安装"）
3. 用 U 盘、当贝市场或 adb 安装
4. 打开应用，用手机扫码登录

用 adb 的话：

```bash
adb uninstall com.netease.filmlytv     # 装过官方版才需要
adb install baomihua-tv-2.6.22-api19-1.5.0.apk
```

## 现在能做什么

| 功能 | 状态 |
| --- | --- |
| 扫码登录 | ✅ |
| 片库、海报墙、最近观看 | ✅ |
| 播放（H.264 1080p） | ✅ 实测约 25fps |
| 声音（44.1kHz 立体声） | ✅ |
| 暂停/继续、双击返回退出 | ✅ |
| 续播（记住上次位置） | ✅ |
| 选集（1-15 / 16-30 分页） | ✅ |
| 画面显示（电视端） | ✅ v1.2.0 起走 SurfaceView 独立图层 |
| 花屏 | ✅ v1.3.0 移除 `glconv=none`；H1 抓帧正常 |
| 硬件解码（1080 级） | ✅ v1.4.0 起走海思 OMX.hisi 硬解，典型内容 CPU 约 10%（软件解码同内容约 60%） |
| 4K 显示 | ⚠️ 4K 内容能硬解但官方 vout 在 4.4 上出不了画面（大片黑屏）。「清晰度」只有源提供多版本时才有非「原画」选项（WebDAV/夸克直挂只有原画） |
| 片库点视频直接播放 | ✅ H1 验证详情页正常打开 |
| 字幕菜单 | ✅ v1.5.0 起可上下导航；有字幕轨时与音轨同一枚举/切换链路（测试片源无字幕轨，未做实际切换） |
| 音轨菜单 | ✅ v1.5.0 起可上下导航并切换；显示真实轨道名（如 Chinese - [Chinese]） |
| HEVC / 其他编码 | ✅ 海思硬解组件覆盖 avc/hevc/mpeg2/mpeg4/vc1/wmv/avs/dolby-vision，VLC mediacodec 自动选取 |

## 常见问题

**安装失败 / 提示"应用未安装"？**
先卸载官方版。这个包是重新签名的，系统不允许覆盖安装不同签名的同名应用。

**打开就闪退？**
先确认盒子是 Android 4.4 及以上、CPU 是 32 位 ARM；再确认是否残留官方版。

**有画面没声音？**
先检查盒子音量和音频输出设置。这个包在测试机上已验证能正常出声。

**播放时电视大面积黑，只有进度条/音量图标处露画面？**
请升级到 v1.2.0 或更高。这个问题是 v1.1.0 的 `TextureView` 画布在该海思显示链路上
不随视频帧上屏导致的，v1.2.0 已改用 `SurfaceView` 独立图层。

**播放卡顿（v1.4.0 起）？**
v1.4.0 换用官方 VLC 3.6.2 引擎并接通海思硬解：典型内容（1440×600/764 等）解码全部走硬件，
CPU 从软解的 60%+ 降到约 10%。已知限制：**4K（3840×2160）能硬解但显示黑屏**——
海思 H.264 硬解组件官方上限 1920×1088，4.4 的旧 vout 也扛不住 4K 缓冲区。
临时办法：源的「清晰度」列表里有非「原画」档时切过去（115/123/Emby 转码等）；WebDAV/夸克直挂只有原画，无法在客户端降档。

**画面是花的、还卡顿？**
请升级到 v1.3.0。服务端可能给 API19 设备下发 `renderer=soft_gles2`，客户端据此
强制软解并关掉色彩转换（`--vout=gles2 --glconv=none`），在 H1 上就会花屏 + 卡顿。
v1.3.0 不再采用服务端 renderer，固定走 `renderer=direct`，优先 MediaCodec 硬解。

**片库里的视频点了没反应，只有“最近观看”能播？**
请升级到 v1.3.0。真机定位到三条原因：①点海报进入的详情页在 API19 上直接崩
（`BottomSheetBehavior` 的 `VerifyError`、API21 insets 回调、vector drawable
不支持）；②详情页播放按钮优先走 `File` 直连（与最近观看同一条路径）；
③OtherCover 带 `File` 时直接起播，不再绕详情页。

**字幕/音轨菜单怎么用？**
播放中按「下键」打开选项面板；各类别现在是常展开的，继续按「下键」经过「字幕」到「音轨」，
再用「左右键」选轨道、「确定键」切换。音轨/字幕轨由片源决定：文件里没有字幕轨时
字幕行显示「暂无」；WebDAV 直挂的片源通常只有一个音轨、没有字幕。

**能装在手机或新盒子上吗？**
能装，但没必要——那些设备直接用官方版更好。

**会不会偷偷上传数据？**
原版里的 Sentry 崩溃上报已在适配时去掉。应用本身仍会联网（登录、片库、播放地址），
这部分和官方版一致。

**为什么安装包有 33MB？**
官方包本身约 32MB，里面带了 VLC 播放引擎和整套界面资源。

## 它是怎么做到的（给好奇的人）

三句话版本：

1. **过服务端校验**：爆米花的请求要签名加密，密钥由 APK 的签名证书推导。重新签名后必须
   换成官方证书对应的密钥，否则服务端拒绝。细节见 [docs/protocol.md](docs/protocol.md)。
2. **让播放器能加载**：盒子系统缺少 VLC 需要的 28 个底层函数。补一个很小的兼容库
   （`libcompat.so`），并让它成为 VLC 的直接依赖。细节见 [docs/native.md](docs/native.md)。
3. **抹平 Android 4.4 的差异**：老系统的运行时更严格，还缺一些新 API。逐条替换/兜底，
   清单见 [docs/api19.md](docs/api19.md)。画面链路另外改用 `SurfaceView`，
   见 [docs/troubleshooting.md](docs/troubleshooting.md)。

再补两句：

4. **换发动机**：包里自带的 VLC 是网易自编译版，mediacodec 在 4.4 上起不来（恒软解）。
   v1.4.0 起换成官方 VLC 3.6.2 的三个原生库，接上海思硬解；代价是官方 JNI 与
   原 Java 层有 9 处接口差异，逐条补齐（见 `patches/05-engine-swap/`）。
5. **修轨道菜单**：官方引擎的轨道名是纯文本，原 Java 层按 JSON 解析所以名称丢失；
   选项面板的行高/边距在老 Leanback 上算错，字幕、音轨行点不到。v1.5.0 逐条修掉
   （见 `patches/06-tracks/`）。

## 自己构建

六个阶段按顺序：

```bash
# 依赖：apktool、smali/baksmali、Android build-tools、JDK、Zig 0.13、python3

# 阶段一：v1.0.0 基础包（API19 引导）
#   见 docs/build.md 的「阶段一」

# 阶段二：v1.0.0 -> v1.1.0（播放链路）
adb pull /system/lib/libc.so work/devlib/libc.so
BASE=/path/to/baomihua-1.0.0.apk KEYSTORE=my.jks KEYSTORE_PASS_FILE=my.pass \
  ./patches/02-playback/build.sh

# 阶段三：v1.1.0 -> v1.2.0（画面显示）
BASE=/path/to/baomihua-1.1.0.apk KEYSTORE=my.jks KEYSTORE_PASS_FILE=my.pass \
  ./patches/03-display/build.sh

# 阶段四：v1.2.0 -> v1.3.0（播放渲染 / 点击播放修复）
BASE=/path/to/baomihua-1.2.0.apk KEYSTORE=my.jks KEYSTORE_PASS_FILE=my.pass \
  ./patches/04-fixes/build.sh

# 阶段五：v1.3.0 -> v1.4.0（换官方 VLC 引擎接海思硬解）
#   需要官方 VLC 3.6.2 armv7 APK 解出的三个库（见 docs/build.md 阶段五）
OUT=out.apk KS_PASS_FILE=my.pass SWAPLIB=/path/to/vlc362/lib/armeabi-v7a \
  ./patches/05-engine-swap/build.sh

# 阶段六：v1.4.0 -> v1.5.0（清晰度/字幕/音轨菜单修复）
BASE=/path/to/baomihua-1.4.0.apk OUT=out.apk KS_PASS=my.pass \
  ./patches/06-tracks/build.sh
```

完整步骤见 [docs/build.md](docs/build.md)；遇到问题先看
[docs/troubleshooting.md](docs/troubleshooting.md)。

## 目录

```
docs/         方法与排障文档
patches/
  01-bootstrap/  阶段一：API19 引导（v1.0.0）
  02-playback/   阶段二：播放链路（v1.1.0）
  03-display/    阶段三：画面显示（v1.2.0）
  04-fixes/      阶段四：播放渲染 / 点击播放修复（v1.3.0）
  05-engine-swap/ 阶段五：换官方 VLC 引擎接海思硬解（v1.4.0）
  06-tracks/     阶段六：清晰度/字幕/音轨菜单修复（v1.5.0）
shim/         libcompat.c：补齐缺失的 28 个系统函数
tools/        符号差集工具、截图脚本
release/      发布说明与 SHA256SUMS（APK 走 GitHub Releases）
```

## 已知问题

- v1.5.0 已在 H1 实测：音轨两项可聚焦、选中第二轨出现勾选并关闭面板；字幕行可到达，
  无字幕轨时显示「暂无」。清晰度列表只有源端提供多版本时才有非原画选项。
- 当贝 H1 的系统截图功能（`screencap`）本身是坏的，与这个包无关；
  需要截图时用 `tools/shot.sh` 里的录屏取帧方案。
- 只在当贝 H1 上验证过，其他 4.4 盒子可能需要额外适配。
- 4K 内容显示黑屏（见 FAQ），与 v1.4.0 相同。

## 免责声明

本项目仅供学习与研究，请支持正版。网易爆米花及其资源的版权归原权利人所有；
本仓库不包含官方安装包。自行构建和安装产生的一切后果由使用者自行承担。

## License

脚本与文档以 MIT 协议提供（见 `LICENSE`）。
