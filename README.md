# 让老电视盒子也能看网易爆米花

网易爆米花 TV 官方版要求 **Android 5.0 以上**。很多老电视盒子——包括当贝 H1——
还停在 **Android 4.4**，官方包装不上，或者装上后一点播放就闪退。

这个项目把官方 TV 版（2.6.22）适配到了 Android 4.4，并且把**播放**这条链路真正修通：
装好之后用法和官方版一样，扫码登录、选片、播放、续播、选集都能用。

- **下载**：[Releases → v1.2.0](https://github.com/daloyanf/baomihua-tv-api19-port/releases/tag/v1.2.0)
- 测试机：当贝 H1（Hi3798MV310，Android 4.4.2，armeabi-v7a，1080p）
- 基于：网易爆米花 TV `2.6.22`

## 版本

| 版本 | 日期 | 阶段 | 内容 |
| --- | --- | --- | --- |
| **v1.2.0** | 2026-10-22 | 画面显示 | 画布改 SurfaceView，修复电视端黑屏/只在 UI 处露画面（**最新**） |
| v1.1.0 | 2026-10-21 | 播放链路 | libvlc 加载、H.264 解码、音频、暂停/续播/选集 |
| v1.0.0 | 2026-10-21 | API19 引导 | 能安装、启动、扫码登录、加载片库/海报墙（不能正常播放） |

## 适合哪些设备

- 系统：**Android 4.4（API 19）及以上**（低于 4.4 不支持）
- CPU：**armeabi-v7a**（32 位 ARM；这个包不含 arm64）
- 已在当贝 H1 上逐项实测；其他 4.4 盒子理论上可用，但没有逐台验证
- 内存建议 1GB 以上

> 新盒子（Android 5+）请直接用官方版，不需要这个包。

## 安装

1. 从 [Releases](https://github.com/daloyanf/baomihua-tv-api19-port/releases/tag/v1.2.0) 下载
   `baomihua-tv-2.6.22-api19-1.2.0.apk`
2. **如果装过官方版，先卸载**（两者签名不同，直接覆盖会提示"应用未安装"）
3. 用 U 盘、当贝市场或 adb 安装
4. 打开应用，用手机扫码登录

用 adb 的话：

```bash
adb uninstall com.netease.filmlytv     # 装过官方版才需要
adb install baomihua-tv-2.6.22-api19-1.2.0.apk
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
| 字幕菜单 | ⚠️ 界面在，未逐项确认 |
| 音轨菜单 | ⚠️ 界面在，未逐项确认 |
| 4K / HEVC | ➖ 未专项测试，取决于盒子解码器 |

## 常见问题

**安装失败 / 提示"应用未安装"？**
先卸载官方版。这个包是重新签名的，系统不允许覆盖安装不同签名的同名应用。

**打开就闪退？**
先确认盒子是 Android 4.4 及以上、CPU 是 32 位 ARM；再确认是否残留官方版。

**有画面没声音？**
先检查盒子音量和音频输出设置。这个包在测试机上已验证能正常出声。

**播放时电视大面积黑，只有进度条/音量图标处露画面？**
请升级到 v1.2.0。这个问题是 v1.1.0 的 `TextureView` 画布在该海思显示链路上
不随视频帧上屏导致的，v1.2.0 已改用 `SurfaceView` 独立图层。

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

## 自己构建

三个阶段按顺序：

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
shim/         libcompat.c：补齐缺失的 28 个系统函数
tools/        符号差集工具、截图脚本
release/      发布说明与 SHA256SUMS（APK 走 GitHub Releases）
```

## 已知问题

- 字幕、音轨菜单还没逐项人工确认（VLC 的轨道枚举本身已经跑通）。
- 当贝 H1 的系统截图功能（`screencap`）本身是坏的，与这个包无关；
  需要截图时用 `tools/shot.sh` 里的录屏取帧方案。
- 只在当贝 H1 上验证过，其他 4.4 盒子可能需要额外适配。

## 免责声明

本项目仅供学习与研究，请支持正版。网易爆米花及其资源的版权归原权利人所有；
本仓库不包含官方安装包。自行构建和安装产生的一切后果由使用者自行承担。

## License

脚本与文档以 MIT 协议提供（见 `LICENSE`）。
