# 发布说明

当前最新：**v1.2.0**（2026-10-22）

| 版本 | 日期 | 阶段 | 状态 |
| --- | --- | --- | --- |
| [v1.2.0](#v120--画面显示修复2026-10-22) | 2026-10-22 | 画面显示 | 最新 |
| [v1.1.0](#v110--播放链路打通2026-10-21) | 2026-10-21 | 播放链路 | 历史 |
| [v1.0.0](#v100--api19-引导2026-10-21) | 2026-10-21 | API19 引导 | 历史（不可正常播放） |

---

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
adb install baomihua-tv-2.6.22-api19-1.2.0.apk
```

首次启动需要手机扫码登录；登录态、片库缓存在重装同签名包时会保留。

## 声明

仅供学习与研究使用，请支持正版。网易爆米花及其资源的版权归原权利人所有；
本包由使用者自行构建与分发，作者不对使用后果负责。
