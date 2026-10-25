# 发布说明

当前最新：**v1.4.0**（2026-10-26）

| 版本 | 日期 | 阶段 | 状态 |
| --- | --- | --- | --- |
| [v1.4.0](#v140--换官方-vlc-引擎接海思硬解2026-10-26) | 2026-10-26 | 硬件解码 | 最新 |
| [v1.3.0](#v130--播放渲染--点击播放修复2026-10-23) | 2026-10-23 | 播放修复 | 历史 |
| [v1.2.0](#v120--画面显示修复2026-10-22) | 2026-10-22 | 画面显示 | 历史 |
| [v1.1.0](#v110--播放链路打通2026-10-21) | 2026-10-21 | 播放链路 | 历史 |
| [v1.0.0](#v100--api19-引导2026-10-21) | 2026-10-21 | API19 引导 | 历史（不可正常播放） |

---

## v1.4.0 — 换官方 VLC 引擎接海思硬解（2026-10-26）

| 项目 | 内容 |
| --- | --- |
| 文件 | `baomihua-tv-2.6.22-api19-1.4.0.apk` |
| 大小 | 33,820,535 字节 |
| sha256 | `5d06094db36a55e971600b8c84db2724bff8367fae38c1c680a2967dfa867bcc` |
| 基于 | v1.3.0（换 `libvlc.so`/`libvlcjni.so`/`libc++_shared.so`，补丁 `classes.dex`/`classes3.dex`） |
| 签名 | 与 v1.3.0 相同（`CN=walldav`），可直接覆盖安装，登录态和缓存保留 |

### 这个版本做了什么

- **换播放引擎接硬解**：爆米花自带的 libvlc 是网易自编译版，其 mediacodec 在 API19 上
  初始化失败（ndk/jni 变体都挂），播放恒走 libavcodec 软解（1440 级内容 CPU 57~76%）。
  本版换成官方 VLC 3.6.2 的同版本内核，实测能拉起 `OMX.hisi.video.decoder.avc`，
  播放中 CPU 约 10%。
- **修触摸崩溃**：Dalvik 对缺失接口方法抛 `NoSuchMethodError`，androidx 只 catch 了
  `AbstractMethodError`，任何触摸/飞鼠点击都会闪退（v1.3.0 起潜伏）。
- **显示路径固定** `--vout=android-opaque`：官方引擎自动选 `gles2`，其 GL 层在本机
  HWC 上合成不了（黑屏）。

### 已知限制

- **4K（3840×2160）显示黑屏**：解码能硬解，但海思 H.264 硬解组件自报上限
  `1920×1088`，且 4.4 的旧 vout 分配 4K 缓冲池超出内存。临时办法：
  播放器「清晰度」切非「原画」档。
- **音轨/字幕菜单**：官方与 fork 的轨道描述协议不同（JSON vs 裸字符串），
  菜单枚举抛 `JSONException`（非致命，不影响播放）。

### 验证要点（H1 真机）

- `logcat | grep HIOMX_CORE` 应见 `OMX.hisi.video.decoder.avc` + `Init OMX component`
- 播放中 `top` 里 `com.netease.filmlytv` CPU 约 10%，画面以电视实际输出为准

---

## v1.3.0 — 播放渲染 / 点击播放修复（2026-10-23）

| 项目 | 内容 |
| --- | --- |
| 文件 | `baomihua-tv-2.6.22-api19-1.3.0.apk` |
| 大小 | 33,774,309 字节 |
| sha256 | `c0023b71a19167875b824044598cf215b847137d810559fe17bb934a8de3c886` |
| 基于 | v1.2.0（替换 `classes.dex` / `classes3.dex`，另换一个 drawable） |
| 签名 | 与 v1.2.0 相同（`CN=walldav`），可直接覆盖安装 |

### 这个版本做了什么

- **花屏 + 卡顿**：服务端 `play_params.renderer` 可能是 `soft_gles2`，客户端据此
  加 `--vout=gles2 --glconv=none`，强制软解且不做色彩转换。v1.3.0 固定
  `renderer=direct`，忽略服务端 `decoder_score_list`，并过滤服务端
  `extra_options` 里的 `--vout=` / `--glconv=` / `--no-mediacodec` / `--codec=`。
- **详情页播放没反应**：有 `File` 时优先走 `PlayerActivity.a.e(File)`，与
  “最近观看”同一条路径；`MediaFile` 分支仅在没有 `File` 时使用。
- **片库点视频没反应**：`OtherCover` 带 `File` 时直接起播，不再绕详情页。
- **详情页在 API19 上直接崩**：修掉 `BottomSheetBehavior` 的 `VerifyError`
  （`MotionCompat` 漏 float 常量）、`o0.r0$c$a` 的 `NoClassDefFoundError`、
  `j5/b` 的 Path/String 类型错误；并把 `ic_chevron_down` 改成 PNG、
  给 `ResCompat` 加 vector 回退（`crew_empty_dark` 等 Glide 占位图）。

### 验证（H1 真机，2026-10-24）

- 片库点海报 → 详情页正常打开（不再 VerifyError/闪退）；
- 4K H.264 片源可播放；`screenrecord` 抓帧画面正常，**无花屏**；
- 该 4K 片源 VLC 仍走 **FFmpeg 软解 3840×2160**（CPU 约 78%），所以 4K 会卡顿。
  H1 的 `OMX.hisi.video.decoder.avc` 存在，但 VLC 3.0.21 在 API19 上没接管
  MediaCodec（强制 `--mediacodec` / `--codec=mediacodec,avcodec` 均无效）。
- 声音流畅、视频卡是预期的：音频解码开销小，4K 软解是瓶颈。4K 建议切 1080p
  版本；要 4K 硬解需要换播放器（ExoPlayer）或新盒子。
- 部分“最近观看”报“网络异常…WebDAV 地址正确”，是片源不可达，与补丁无关。

> API19 x86 模拟器另外验证了 `BottomSheetBehavior` / `SideSheetBehavior` /
> `j5.b` / `o0.r0$c` / `ResCompat` / `h7.e0` / `adapter.cover.a$a` /
> `PlayerActivity` / `h`（VlcPlayerImpl）的 Dalvik 类校验全部通过。

## v1.2.0 — 画面显示修复（2026-10-22）

| 项目 | 内容 |
| --- | --- |
| 文件 | `baomihua-tv-2.6.22-api19-1.2.0.apk` |
| 大小 | 33,774,309 字节 |
| sha256 | `20eba1436c5c71dc7a8d76a1f56431004a1067fa82a779e1ce139ee82bb57d51` |
| 基于 | v1.1.0（只替换 `classes.dex`） |
| 适用 | Android 4.4+ / armeabi-v7a（真机验证：当贝 H1，Android 4.4.2） |
| 签名 | 自签名（与官方不同，安装前需卸载官方版） |

### 这个版本做了什么

- 修复真机「播放时电视大面积黑、只有进度条/音量浮层处露出画面」：
  播放画布从 `TextureView` 改成 `SurfaceView`，视频走独立 HWC 图层。
- 两处画布类型同时改：`IPlayer$Param` 默认值 + `IPlayer$b.a()`
  里 `PlayParams.getView()` 的覆盖点（只改前者会被覆盖回 `textureView`）。
- 其余与 v1.1.0 完全一致（解码、音频、续播、选集都不变）。

### 验证

- `uiautomator dump` 出现 `surface_video`；
- `dumpsys SurfaceFlinger` 出现独立 `SurfaceView` 图层（1920x1080、RGBX_8888、
  HWC overlay），缓冲队列随播放轮转；
- 控制条弹出时 UI 与视频叠层正常。

---

## v1.1.0 — 播放链路打通（2026-10-21）

| 项目 | 内容 |
| --- | --- |
| 文件 | `baomihua-tv-2.6.22-api19-1.1.0.apk` |
| 大小 | 33,774,309 字节 |
| sha256 | `3a1f4973bbc3f2e8e74e35a5e36b36b35870b55fc4a014851f9dbdeb6bd6a662` |
| 基于 | v1.0.0 |
| 适用 | Android 4.4+ / armeabi-v7a（真机验证：当贝 H1，Android 4.4.2） |
| 签名 | 自签名（与官方不同，安装前需卸载官方版） |

### 这个版本做了什么

- 原生库：`libcompat.so` 补齐设备 libc 缺失的 28 个符号；`libvlc.so` 的 NEEDED
  `libstdc++.so` 原位替换为 `libcompat.so`。
- 播放链路 API 兜底：`AudioDeviceCallback`、`getVideoCapabilities`、
  `SurfaceControl.reparent`、无障碍 `A11yCompat`。
- 播放打通：`libvlc`/`libvlcjni` 加载、H.264 解码、44.1kHz 音频、进度推进、
  暂停/继续、续播、选集。

### 已知问题

- 电视端画面可能大面积黑（v1.2.0 修复）。
- 字幕、音轨菜单未逐项验收（VLC 轨道枚举本身已跑通）。

---

## v1.0.0 — API19 引导（2026-10-21）

| 项目 | 内容 |
| --- | --- |
| 文件 | `baomihua-tv-2.6.22-api19-1.0.0.apk` |
| 大小 | 33,778,331 字节 |
| sha256 | `5fd017ec98acdba33ba98f44779c43adce68411f61297c61a755f9ce66e28ee2` |
| 基于 | 网易爆米花 TV 2.6.22（versionCode 1390） |
| 适用 | Android 4.4+ / armeabi-v7a（真机验证：当贝 H1，Android 4.4.2） |
| 签名 | 自签名（与官方不同，安装前需卸载官方版） |

### 这个版本做了什么

- API 19 引导：minSdk、MultiDex、R8 构造器修复、`BaseBundle`、Sentry 移除、GCM 参数等。
- 服务端鉴权改为 Java 实现，密钥固定为官方证书派生值（重签后仍能过鉴权）。
- 原生库缺符号用 `libcompatshim.so` 兜底。

### 状态

- 可安装、启动、扫码登录、加载片库/海报墙。
- **不能正常播放**（点击播放崩溃），仅作为阶段二的基础包与历史存档。

---

## 安装

```bash
# 必须先卸载官方版（签名不同，直接 -r 会失败）
adb uninstall com.netease.filmlytv
adb install baomihua-tv-2.6.22-api19-1.3.0.apk
```

首次启动需要手机扫码登录；登录态、片库缓存在重装同签名包时会保留。

## 声明

仅供学习与研究使用，请支持正版。网易爆米花及其资源的版权归原权利人所有；
本包由使用者自行构建与分发，作者不对使用后果负责。
