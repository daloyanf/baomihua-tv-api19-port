# 阶段记录

## 版本时间线

| 版本 | 日期 | 阶段 | 内容 |
| --- | --- | --- | --- |
| v1.0.0 | 2026-10-21 | 阶段一：API19 引导 | 能安装、启动、扫码登录、加载片库/海报墙 |
| v1.1.0 | 2026-10-21 | 阶段二：播放链路 | libvlc 加载、H.264 解码、音频、暂停/续播/选集 |
| v1.2.0 | 2026-10-22 | 阶段三：画面显示 | 画布改 SurfaceView，修复电视端黑屏/只在 UI 处露画面 |
| v1.3.0 | 2026-10-23 | 阶段四：播放修复 | 固定 renderer=direct（修花屏/卡顿）、详情页优先 File 直连、OtherCover 直接播 |

> 早期内部称呼里的 v1/v2/v4 已废弃：v1 → v1.0.0，v2 → v1.1.0，v4 → v1.2.0。
> 当时的 v3 是一次未生效的中间构建（只改默认画布值、被配置覆盖），没有单独发布。

## 详细过程

- **2026-10-20 晚 → 10-21 凌晨（阶段一，v1.0.0）**：解包官方包，处理 Dalvik 校验器/
  API 缺失/服务端签名，做到能启动、过鉴权、登录、片库与海报墙正常。会话因宿主 shell
  故障中断。
- **2026-10-21 白天（阶段一收尾）**：继续修补，装机后确认 `libmmkv` 等原生库的缺符号
  问题用 `libcompatshim.so` 解决；应用启动到媒体库。
- **2026-10-21 晚（阶段二，v1.1.0）**：点播放崩溃 → 定位到 `libvlc.so` 缺 28 个 libc
  符号 → 自编 `libcompat.so` + NEEDED 原位替换 → 播放打通；补 `SurfaceControl`/
  `AudioDeviceCallback`/`getVideoCapabilities`/`A11yCompat`；真机验证解码、出声、暂停、
  续播、选集。
- **2026-10-22（阶段三，v1.2.0）**：真机反馈播放时电视上大面积黑、只有进度条/音量浮层处
  露出画面，而 `screenrecord` 抓帧完整 → 确认 `screenrecord` 走虚拟显示 GPU 合成，
  不代表电视 HWC/OSD 输出；播放器用 `TextureView` 把视频画进应用窗口，视频区域不随帧
  上屏。画布改 `SurfaceView`（独立 HWC 图层）后恢复；补丁见 `patches/03-display/`。
- **2026-10-23（阶段四，v1.3.0）**：真机反馈「画面花 + 卡顿」「片库点视频无法观看，
  只能从最近观看进入」。代码定位到三处：
  ① 服务端 `play_params` 的 `renderer` 可能为 `soft_gles2`，客户端据此加
  `--vout=gles2 --glconv=none`，强制软解 + 无色彩转换；改为固定 `direct`，
  并忽略服务端 `decoder_score_list`，保留内置 OMX 硬解优先级。
  ② 详情页播放按钮在 `MediaFile` 非空时走 `PlayerActivity.a.c(...)`，与最近观看的
  `a.e(File)` 不同；改为有 `File` 一律走 `a.e(File)`。
  ③ 片库 `OtherCover` 选择器原本按行类型决定「直接播/进详情」，改为只要
  `getFile() != null` 就直接播。
  真机进一步确认「点视频没反应」其实是**详情页在 API19 上直接崩**：
  `BottomSheetBehavior` 的 `MotionCompat` 调用漏了 float 常量（`VerifyError`）、
  SDK<30 的 insets 动画回调 `new-instance o0.r0$c$a`（`NoClassDefFoundError`）、
  `j5/b` 把 String 当 Path、以及 `ic_chevron_down` / `crew_empty_dark` 等
  vector drawable 在 4.4 上无法加载。v1.3.0 补回常量、跳过 API21 分支、
  把 chevron 换成 PNG、给 `ResCompat` 加 `VectorDrawableCompat` 回退。
  补丁见 `patches/04-fixes/`；API19 模拟器上关键类已通过 Dalvik 校验。
  **H1 真机复验（2026-10-24）**：片库点海报 → 详情页正常打开；4K H.264
  可播放，`screenrecord` 抓帧画面正常、无花屏；但 VLC 仍走 FFmpeg 软解
  3840×2160（CPU 约 78%），4K 卡顿。H1 有 `OMX.hisi.video.decoder.avc`
  硬解，但 VLC 3.0.21 在 API19 上未接管 MediaCodec（强制
  `--mediacodec` / `--codec=mediacodec,avcodec` 均无效）。音频解码开销小，
  所以“声音流畅、视频卡”。4K 建议切 1080p 版本；要 4K 硬解需换播放器或盒子。

## 阶段一（v1.0.0）验证数据（供参考）

- 全类校验：16,784 个类中 16,732 通过；剩余 52 个是引用缺失 API 的软失败
  （Sentry/VLC/Conscrypt 内部类，只有相应代码路径执行才会触发）。
- 校验工具：自制的 `AllProbe` 走 `dalvikvm -classpath n1.jar:n2.jar:n3.jar:n4.jar AllProbe`
  （每个 jar 里放一个 dex）。注意大 dex 一次跑会 OOM，需分 dex 跑，且跨 dex 引用会误报。

## 阶段一流水线（已实现过的部分）

1. `minSdk 21→19`；`leanback`/`television` 的 `required=false`。
2. 注入 legacy MultiDex 1.0.3：`attachBaseContext` 里 `super` 之后立即 `install`。
3. Application 崩溃历史方法（API30 `ApplicationExitInfo`）桩化；`onTerminate` 桩化。
4. 密度钩子搬到 `compat/DpiHookCompat.apply()`，主 dex 反射延后调用。
5. BouncyCastle append 小工具内联。
6. R8 超类构造器模式全局修复（三类形态，约 5000+ 处）。
7. `android.os.BaseBundle` → `android.os.Bundle`（144 处）。
8. 移除两个 Sentry Provider。
9. dex 均衡：`com/netease/filmlytv/model` 挪到 classes3（主 dex < 64K）。
10. 资源名 `$` 前缀改名（aapt 限制）。
11. 5 个原生库 `__read_chk` → `read`（dynstr 等长改名）。
12. `libcompatshim.so`（getpagesize/rand/strtof/truncate64/…）并通过动态标签注入 NEEDED。
13. 服务端 `getSecretKey`/`getNativeAPI` 改 Java 实现，密钥硬编码为官方证书派生值。

> 其中 1/3/4/5/6/7/8/9/10/12 的后半段的自动化脚本没有保留下来（见 build.md 的说明），
> 文档里保留了做法与关键参数，足够重写。

## 阶段二（v1.1.0）验证数据

- 设备：当贝 H1（Hi3798MV310 / Android 4.4.2 / armeabi-v7a）。
- `libvlc.so` 37.8MB，`libvlcjni.so` 75KB；两者均加载成功。
- 解码：H.264 1080p，约 25fps，日志按帧输出。
- 音频：`dumpsys media.audio_flinger` 显示 44.1kHz 立体声 active track。
- 交互：暂停/继续、双击返回、续播、选集（1-15/16-30 分页）均验证。
- 画面：当时用 `screenrecord` 截图判断"视频层已上屏"——**这个判断方法是错的**：
  `screenrecord` 走虚拟显示 GPU 合成，和电视 HWC/OSD 输出不是一条路。阶段三就是因此在
  真机上暴露了黑屏问题（见 `docs/troubleshooting.md`）。
