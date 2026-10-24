# v1.3.0 修复（播放渲染 / 点击播放）

基于 v1.2.0，替换 `classes.dex`、`classes3.dex`，并把
`res/drawable/ic_chevron_down.xml` 换成同尺寸 PNG；原生库不动。

## 1. 花屏 + 卡顿：固定 renderer=direct

服务端 `/a/v1/play_params` 会按设备下发 `renderer`。API19 设备可能拿到
`soft_gles2`，客户端据此追加：

```
--vout=gles2 --glconv=none
```

这会绕开 MediaCodec 直出（硬件解码），退到软解 + GLES2，且 `glconv=none`
不做色彩转换；在当贝 H1 上表现为**画面花、严重卡顿**（尤其 4K/HEVC）。

修改 `com.filmlytv.libplayer.IPlayer$b.a()`：

- 服务端 `renderer` 仍会被读取，但随后固定成 `"direct"`；
- `no_drop_late_frames` 固定为 `false`；
- 服务端 `decoder_score_list` 不再覆盖应用内置的评分表，保留
  `OMX.*` 硬件解码器优先级（内置表把 `OMX.PV`/`OMX.google` 等软解压到 0）；
- 过滤服务端 `extra_options` 里的 `--vout=` / `--glconv=` / `--no-mediacodec` /
  `--codec=`，防止它绕过上面的 renderer 覆盖。

`direct` 是应用默认值，也是 Android TV 上正常的 VLC 输出选择：有硬解就直出
SurfaceView，硬解不可用时 VLC 自己回退，仍走默认 GL 输出。

## 2. 详情页点播放没反应：优先走 File 直连

`h7.e0`（详情页播放按钮/选集点击）原本在 `MediaFile` 可用时走
`PlayerActivity.a.c(source, mediaFile, file)`；这条路径在部分源上解析失败。
“最近观看”走的是 `PlayerActivity.a.e(file)`，一直正常。

修改后：

- `file != null` → 一律走 `a.e(file)`（与最近观看完全同一条路径）；
- `file == null` 且 `mediaFile != null` → 仍走 `a.c(...)`；
- 两者都为空 → 保留原提示。

## 3. 片库 OtherCover 点不进去：带文件就直接播

`com.netease.filmlytv.adapter.cover.a$a.c(Object)`（Presenter 选择器）原本按
行类型在 `o6.k`（直接播放）与 `o6.f`（进详情页）之间选。现在：

- `OtherCover` 且 `getFile() != null` → 统一用 `o6.k` 直接播放；
- `OtherCover` 无 `File` → 仍进详情页；
- `MovieCover`/`SeriesCover` → 保持详情页。

这条针对的是“片库里的视频点了没反应、只有最近观看能播”：这类条目本身已经带
`File`，不需要再走详情页/网络解析。

## 4. 详情页在 API19 上直接崩（“点视频没反应”的真因）

点片库海报会进 `VideoDetailActivity`；该页此前在 API19 上直接崩，表现就是
“点了没反应”、App 退回桌面。逐层定位到四个问题：

| 位置 | 问题 | 修法 |
| --- | --- | --- |
| `BottomSheetBehavior` | 阶段一把 `new PathInterpolator(FFFF)` 换成 `MotionCompat.a(FFFF)` 时漏了 `const v4,0.1f` / `const/4 v5,0`，Dalvik 把对象/资源 ID 当 float，`VerifyError` 拒绝整个类 | 补回 float 常量 |
| `BottomSheetBehavior.h` | SDK<30 分支 `new-instance o0.r0$c$a`（API21 类）→ `NoClassDefFoundError`；`setOnApplyWindowInsetsListener`（API21）→ `NoSuchMethodError`；`H()` 引用 API21 `AccessibilityAction` | SDK<30 跳过 insets 动画分支；`H()` 整体桩掉 |
| `j5/b` | `MotionCompat.b(Path)` 直接收到 String（漏了 `PathParser.createPathFromPathData`） | 补回 `g0/j;->d(String)Path` |
| `SideSheetBehavior` / `o0/r0$c` | 同样漏了 `MotionCompat.a` 的 float 常量 | 补回常量 |

## 5. 详情页 vector drawable（API19 不支持 `<vector>`）

- `item_video_detail_header` 的 `arrow_down` 用
  `android:background="@drawable/ic_chevron_down"` 加载 vector，框架直接抛
  `invalid drawable tag vector`。把该 drawable 换成 25x24 PNG：只改
  `resources.arsc` 里的文件路径 `xml`→`png`，布局和其他资源不动。
- Glide 占位图 `crew_empty_dark` 走 `ResCompat.getDrawableThemed`；在 classes3 里
  给 `ResCompat` 加 try/catch：框架加载失败时回退到应用自带的
  `VectorDrawableCompat`（混淆名 `d2.j.a(int, Theme, Resources)`）。

## 6. 校验验证

在 API19 x86 模拟器上用 `dalvikvm` 显式 `Class.forName` 加载以下类，全部通过：
`BottomSheetBehavior`、`SideSheetBehavior`、`j5.b`、`o0.r0$c`、`ResCompat`、
`h7.e0`、`adapter.cover.a$a`、`PlayerActivity`、`h`（VlcPlayerImpl）。
H1 真机复验（2026-10-24）：详情页正常打开；4K H.264 抓帧无花屏；但 VLC 仍
FFmpeg 软解 4K（CPU ~78%），4K 卡顿；H1 有 `OMX.hisi` 硬解，VLC 3.0.21 在
API19 上未接管 MediaCodec。4K 建议切 1080p。

## 构建

```bash
BASE=/path/to/baomihua-tv-2.6.22-api19-1.2.0.apk \
KEYSTORE=$HOME/.android-keys/walldav.jks \
KEYSTORE_PASS_FILE=$HOME/.android-keys/walldav.pass \
./build.sh
```

签名证书与 v1.2.0 相同（`CN=walldav`），可直接覆盖安装，登录态和缓存保留。

## 验证建议

1. 播放任意 4K/HEVC 片源，观察是否仍花屏/卡顿；
2. 查看 VLC 日志（应用私有目录 `files/feedbacks/app/vlc-*.txt`）里是否还有
   `--vout=gles2` / `--glconv=none`，以及用的是 `mediacodec` 还是 `avcodec`；
3. 片库点视频应直接进播放器；详情页点播放应直接起播。
