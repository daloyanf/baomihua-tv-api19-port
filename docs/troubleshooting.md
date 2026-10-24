# 排障与实战坑

## 日志

- **buffer 很小且回滚极快**：VLC 解码时按 25fps 刷 `E/VLC-std`，几分钟就能把缓冲冲掉。
  查历史用 `adb logcat -d -t 300`（只取尾部），不要 `logcat -d` 全量。
  4.4 的 logcat 不支持 `-G` 调大缓冲。
- `E/VLC-std` 的 `E` 不是错误：那是 `JNI_OnLoad` 里 `std_logger_Open("VLC-std")` 的默认级别。
  判断播放是否在跑，数 `VLC-std` 行数或看 `nal_unit_type` 即可。
- 应用自己的日志（`g7/l`）在 release 包里不进 logcat，排障只能靠系统日志和 VLC。
- 海思的 `HIOMX_CORE`、`HiPlayer [PADPT_SendVidFrame]` 报错是平台噪声，不影响判断。

## 截图

- 该机 `screencap` 不可用：`HI_MPI_DISP_Init[86]:open DISP err`，属于 ROM 抓屏路径损坏。
- 用 `tools/shot.sh`：`screenrecord` 走 MediaCodec 虚拟屏，**能抓到视频层**；
  `adb pull` 后用 `ffmpeg -frames:v 1` 取帧。
- ⚠️ **`screenrecord` 不能用来证明电视上显示正常**：它抓的是 SurfaceFlinger 虚拟显示的
  GPU 合成，和电视实际的 HWC/OSD 输出不是同一条路。阶段二（v1.1.0）就是抓帧全绿、真机却大面积黑
  （见下节）。
- `/dev/graphics/fb0` 虽然 shell 可读（在 `graphics` 组），但内容是 AFBC 压缩帧缓冲，
  按线性 RGBA 解是噪声，不要浪费时间。

## 播放时电视上大面积黑 / 只有进度条·音量浮层处露出画面（v1.2.0）

**现象**：播放中电视上几乎全黑，控制条/音量图标一出现，它们所在区域就短暂露出画面；
`screenrecord` 抓帧却始终完整。

**定位**：

- SurfaceFlinger 里播放器只有一个应用窗口图层，视频由 `TextureView` 画进应用窗口缓冲。
- 应用侧在持续出帧：窗口缓冲轮转、ffmpeg 25fps、音频正常。
- 真实 HWC/OSD 上视频区域不随视频帧刷新，只有 UI 失效区域被重绘/上屏。

**修法**：画布改 `SurfaceView`（独立图层、HWC 直接合成）。有两处要同时改，只改默认值会被
`PlayParams.getView()` 覆盖回 `textureView`：

| 位置 | 修改 |
| --- | --- |
| `IPlayer$Param` 默认构造 | `textureView` → `surfaceView` |
| `IPlayer$b.a(Param)` | `getView()` 结果改为固定 `surfaceView` |

脚本见 `patches/03-display/`。验证：`uiautomator dump` 里出现 `surface_video`；
`dumpsys SurfaceFlinger` 出现独立 `SurfaceView` 图层（1920x1080、RGBX_8888、HWC overlay）。

## 画面花 + 卡顿（v1.3.0）

**现象**：播放时画面有明显色块/噪点，帧率不稳，4K/HEVC 尤其明显。
声音正常，进度也在走。

**定位**：应用会把服务端 `play_params` 的 `renderer` 直接传给 VLC。若服务端对
API19 设备下发 `soft_gles2`，`PlayerActivity` 会追加：

```
--vout=gles2 --glconv=none
```

`--vout=gles2` 会绕开 MediaCodec 直出，VLC 退回软解；`--glconv=none` 又不做
YUV→RGB 色彩转换，海思平台上的结果就是花屏 + 卡顿。

**修法**（v1.3.0）：在 `IPlayer$b.a()` 里把 `renderer` 固定成 `direct`，同时：

- `no_drop_late_frames=false`，避免软解时堆帧；
- 忽略服务端 `decoder_score_list`，保留应用内置的 OMX 硬解评分表。

**怎么确认**：VLC 日志在应用私有目录
`/data/data/com.netease.filmlytv/files/feedbacks/app/vlc-*.txt`（需要 root 或
可调试包才能直接读）。搜 `playWithArg` 行：v1.3.0 之后不应再出现
`--vout=gles2` / `--glconv=none`；`codec` 相关行应出现 `mediacodec` 或设备
OMX 解码器名，而不是 `avcodec`。

## 片库点视频不能播 / 只能从最近观看进入（v1.3.0）

**现象**：片库海报点下去没反应，或进了详情页但播放按钮不起播；“最近观看”里的
同一条目可以正常播。

**两条链路不同**：

| 入口 | 调用 |
| --- | --- |
| 最近观看 | `PlayerActivity.a.e(File)` |
| 详情页播放按钮 | `MediaFile` 非空时 `PlayerActivity.a.c(Source, MediaFile, File)` |
| 片库 OtherCover | 选择器决定 `o6.k`（直接播）或 `o6.f`（进详情） |

v1.3.0 的修改：

- 详情页有 `File` 时一律走 `a.e(File)`，与最近观看完全一致；
- `OtherCover` 只要 `getFile() != null` 就直接播，不再进详情页；
- `File` 为空、`MediaFile` 非空时才保留原来的 `a.c(...)` 路径。

**更主要的原因（真机 2026-10-23）**：详情页本身在 API19 上就崩，所以点击看似
“没反应”。`VideoDetailActivity.onCreate` 依次踩到：

- `BottomSheetBehavior` 的 `VerifyError`（`MotionCompat` 调用漏了 float 常量）；
- SDK<30 insets 动画分支 `new-instance o0.r0$c$a` → `NoClassDefFoundError`；
- `View.setOnApplyWindowInsetsListener`（API21）→ `NoSuchMethodError`；
- `j5/b` 把 String 直接传给 `MotionCompat.b(Path)`；
- `ic_chevron_down` / `crew_empty_dark` 等 vector drawable 在 4.4 上无法加载
  （`invalid drawable tag vector`）。

v1.3.0 的修法见 `patches/04-fixes/README.md`（补常量、跳过 API21 分支、
chevron 换 PNG、`ResCompat` 加 `VectorDrawableCompat` 回退）。判断方法：
`adb logcat` 里搜 `AndroidRuntime` / `VerifyError` / `InflateException` /
`invalid drawable tag vector`。

如果升级后仍不能播，优先查详情页是否卡在“加载失败”/骨架屏：那说明详情数据
本身没取到（网络/接口），与播放链路无关。

## 4K 软解卡顿（H1，2026-10-24）

**现象**：4K 片源声音流畅、视频卡顿；`screenrecord` 抓帧画面正常，没有花屏。

**定位**：H1 有硬件解码器（`OMX.hisi.video.decoder.avc` / `hevc`），但 VLC
3.0.21 在 API19 上仍走 **FFmpeg 软解**（日志 `[h264 @ ...] Reinit context to
3840x2160, pix_fmt: yuv420p`），CPU 约 78%。强制 `--mediacodec` /
`--mediacodec-dr` / `--mediacodec-prefered=jni` / `--codec=mediacodec,avcodec`
都没有让 VLC 接管 MediaCodec；`libvlc.so` 自带 MediaCodec 模块，但该海思/
API19 组合下未生效。音频解码开销小，所以声音一直流畅。

**建议**：

- 4K 片源在播放器“清晰度”里切 1080p（软解 1080p 可流畅）；
- 需要 4K 硬解只能换播放器（ExoPlayer 直接走 MediaCodec）或换新盒子；
- 不要再用 `--vout=gles2 --glconv=none`：它会让画面花（v1.3.0 已移除）。

## UI 自动化

- `uiautomator dump` 偶尔会挂住，命令一定加 `timeout`。
- 播放器控制条约 3 秒无操作就自动隐藏；`input tap` 很容易落在视频画面上。
  遥控键更可靠：`input keyevent 19/20/21/22/23`（上/下/左/右/确定）。
- 退出播放器是**双击返回**（`input keyevent 4` 连续两次，间隔 <1s）。
- 无障碍查询会让应用走 `onInitializeAccessibilityNodeInfo`；阶段二（v1.1.0）修了 `A11yCompat`
  的两个 bug，否则 dump 会把应用打崩。

## adb

- 4.4 的 adbd **不支持 `adb exec-out`**；二进制只能 `adb pull`。
- 这台盒子的 Wi-Fi adb 只有约 0.2 MB/s，拉 26MB 帧缓冲要 2 分钟，属正常。
- 设备 toolbox 很精简：没有 `head`/`tail`，`ps | grep` 可用。
- `pkill -f` / `pgrep -f` 会匹配到你自己那条命令（命令行里含同样的字符串），
  用 `pkill -f "[l]ogcat -v time"` 这种写法。
- 重装同签名 APK 会保留数据（登录态、片库缓存）；换签名必须卸载，数据会丢。

## 构建/宿主

- **不要在宿主上留后台 `adb logcat > /tmp/x.log`**：VLC 日志量很大，`/tmp` 是 tmpfs，
  写满后所有写操作报 `EDQUOT`（errno 122），连 shell 都会异常。
- `strip`/`objdump` 处理不了 ARM ELF（本机 binutils 只有 x86 target）：
  垫片带调试信息也能用；真要 strip 用 LLVM 工具链。
- `apksigner` 需要 JDK；`-v3-signing-enabled false` + `min-sdk-version 19` 是为了兼容 4.4。

## 判断播放是否真的成功

1. `logcat` 里 `VLC-std` 持续输出 H.264 帧；
2. `dumpsys media.audio_flinger` 有该 pid 的 active AudioTrack（44.1kHz 立体声）；
3. UI 里进度数字按秒递增；
4. `dumpsys SurfaceFlinger` 里有独立的视频图层（v1.2.0 起是 `SurfaceView`，HWC overlay），
   且缓冲队列随播放轮转；
5. 最终以**电视实际画面**为准。`screenrecord` 只用于看应用缓冲内容，不能证明 HWC/OSD
   显示正常（见上文 v1.2.0 一节）。
