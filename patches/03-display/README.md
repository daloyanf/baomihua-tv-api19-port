# 阶段三补丁（画面显示，v1.2.0）

## 问题

当贝 H1 上播放时，电视大面积黑屏，只有进度条/音量浮层出现的位置短暂露出画面；
但 `screenrecord` 抓帧始终完整。

## 原因

`screenrecord` 抓的是 SurfaceFlinger **虚拟显示的 GPU 合成**，不代表电视上
**HWC/OSD 的实际输出**。播放器用 `TextureView` 把视频画进应用窗口缓冲，
在这台海思盒子的真实显示链路上，视频区域不随视频帧上屏，只有 UI 失效区域
被重绘/刷新——于是黑屏上只在 UI 所在位置露画面。

## 修法

播放画布改用 `SurfaceView`：视频成为独立图层，由 HWC 直接合成。

代码里有两处决定画布类型，必须同时改：

| 位置 | 原逻辑 | 修改 |
| --- | --- | --- |
| `com.filmlytv.libplayer.IPlayer$Param` 默认构造 | `SDK < 29` 固定 `textureView` | 常量改成 `surfaceView` |
| `com.filmlytv.libplayer.IPlayer$b.a(Param)` | 用 `PlayParams.getView()` 覆盖 `p`/`q`，会把默认值改回 `textureView` | 在 `getView()` 的 `move-result-object v3` 后插 `const-string v3, "surfaceView"` |

只改第一处会被第二处覆盖（第一次构建就踩了这个坑）。

## 构建

```bash
BASE=/path/to/baomihua-1.1.0.apk \
KEYSTORE=$HOME/.android-keys/my.jks \
KEYSTORE_PASS_FILE=$HOME/.android-keys/my.pass \
./build.sh
```

脚本只替换 `classes.dex`，其余文件与原生库原样保留，然后 zipalign + apksigner。

## 验证

```bash
adb shell uiautomator dump /sdcard/ui.xml   # 应出现 surface_video，不再有 texture_video
adb shell dumpsys SurfaceFlinger | grep -E "SurfaceView|PlayerActivity"
# 应看到独立的 SurfaceView 图层（1920x1080、RGBX_8888、HWC overlay），
# 且缓冲队列随播放持续轮转
```

> `smali` 对同一份 smali 树的字节输出不保证逐字节一致（文件枚举顺序影响 dex 内
> id 排列），重建包的 sha256 可能不同；反汇编对比已确认语义一致。
