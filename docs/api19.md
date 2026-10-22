# API 19 兼容问题清单

## 怎么找

1. **静态**：把 dex 里的 `invoke-*` 引用按类收集，和 `platforms/android-19/android.jar`
   对方法名。注意 `javap` 只看类自己声明的方法，**继承来的方法会误报**（例如
   `Activity.finish`），要人工复核或改走设备验证。
2. **设备验证**：Dalvik 校验器会把解析不到的类/方法打到 logcat：

   ```
   I/dalvikvm: Could not find method android.media.AudioManager.registerAudioDeviceCallback,
               referenced from method ...PlayerActivity.onCreate
   ```

   跑一遍所有会走到的界面，比静态扫描准。
3. 不要只看编译期：很多 API 是"类在、方法不在"，异常是运行时 `NoSuchMethodError`。

## 阶段二（v1.1.0）：播放链路

| 位置 | 问题 | 修法 |
| --- | --- | --- |
| `libvlc.so` | 设备 libc 缺 28 个符号，dlopen 失败 | 自编 `libcompat.so` + 改 NEEDED（见 native.md） |
| `PlayerActivity` | `AudioManager.registerAudioDeviceCallback` / `unregisterAudioDeviceCallback`（API 23） | 两处 invoke 改 `nop`；字段本来只在 SDK≥23 时创建 |
| `com/filmlytv/libplayer/h` | `CodecCapabilities.getVideoCapabilities()`（API 21） | invoke + move-result 换成 `const/4 vXX, 0x0` + nop，走原有"无能力信息"分支 |
| `com/filmlytv/libplayer/a` | 同上 | 同上 |
| `AWindow$SurfaceHelper` | `reparent()` 无条件用 `SurfaceControl$Transaction` / `SurfaceView.getSurfaceControl`（API 29） | 方法首行插 `return-void`，整体桩掉 |
| `A11yCompat.a()` | SDK≥21 分支误调自身（无限递归） | 改成真正的 `CollectionInfo.obtain(IIZI)` |
| `A11yCompat.b()` | SDK<21 回退调用 4 参 `CollectionItemInfo.obtain`，API 19 只有 5 参 | 改 5 参 `obtain(IIIIZ)` |

`A11yCompat` 这两个 bug 平时不触发，但**一旦有 accessibility 服务查询 View 树就会崩**
（我们用 `uiautomator dump` 时被它打崩过）：`View.onInitializeAccessibilityNodeInfo` →
`GridLayoutManager` 的无障碍委托 → `A11yCompat.b` → `NoSuchMethodError`。

## 阶段三（v1.2.0）：画布类型（显示链路）

不是 API 缺失，而是显示路径选择问题：`TextureView` 把视频画进应用窗口后，
在该海思 HWC/OSD 上视频区域不随帧上屏。改用 `SurfaceView`（独立图层）。

| 位置 | 问题 | 修法 |
| --- | --- | --- |
| `IPlayer$Param` 默认构造 | `SDK < 29` 固定 `textureView`（`surfaceControl` 是 API29 分支） | 常量改 `surfaceView` |
| `IPlayer$b.a(Param)` | `PlayParams.getView()` 非空时覆盖 `p`/`q`，会把默认值改回 `textureView` | 把 `getView()` 的结果固定为 `surfaceView` |

细节与验证方法见 [troubleshooting.md](troubleshooting.md) 的 v1.2.0 一节与
`patches/03-display/`。

### 复核过、确认安全的点（不要重复踩）

- `Display.getHdrCapabilities()`（API 24）：外层有 `SDK_INT >= 24` 的早退，4.4 直接返回 0。
- `Activity.isInPictureInPictureMode()` / `isInMultiWindowMode()`（API 24）：有 `SDK_INT >= 24` 守卫。
- `AudioFocusRequest.Builder` / `requestAudioFocus(AudioFocusRequest)`（API 26）：有 `SDK_INT >= 26` 守卫，
  低版本走 legacy `requestAudioFocus(listener, streamType, gain)`。
- `VpuScorer` 里的 `getVideoCapabilities`：显式 `catch NoSuchMethodError / NoClassDefFoundError`。
- VLC `MediaPlayer` 的 `registerAudioPlugV23`：按字段 `mAudioDeviceCallback` 是否为空分派，
  4.4 走 V21 的广播接收器路径。
- `MediaCodecInfo.isSoftwareOnly()`（API 29）：`SDK_INT > 29` 才调用。

## 阶段一（v1.0.0）：让应用能启动（API19 引导）

| # | 问题 | 修法 |
| --- | --- | --- |
| 1 | minSdk 21，安装被拒 | Manifest/`apktool.yml` 改 `minSdkVersion 19`；leanback/television 的 `<uses-feature required>` 改 false |
| 2 | 4.4 无原生 multidex | 注入 legacy `androidx.multidex` 1.0.3，在 `attachBaseContext` 里 `super` 后立即 `MultiDex.install` |
| 3 | R8 生成的非法构造器调用（Dalvik 校验器拒绝，ART 接受） | 三种形态：① `new X` 后 `invoke-direct` 到父类 `<init>` → 改指 X 自身并给 X 补转发构造器（约 5000 处，含 `invoke-direct/range`）；② 合并类残留 → 构造器内改 `Object.<init>`、普通方法内改 `nop`；③ 直接父类非 Object 却直调 `Object.<init>` → 给父类补空构造器并重定向 |
| 4 | `android.os.BaseBundle`（API 21） | 全部引用重映射到 `android.os.Bundle`（API 19 等价） |
| 5 | `ApplicationExitInfo`（API 30）崩溃历史 | 对应用 `Application` 里读它的方法做桩 |
| 6 | `onTerminate` 里用 `NetworkCallback`（API 21） | 桩化 |
| 7 | 密度钩子 `XplayerPlantProvider` 的类校验时序 | 把逻辑整段搬到 `compat/DpiHookCompat.apply()`，主 dex 反射延后调用 |
| 8 | BouncyCastle `GCMParameterSpec` 不被 4.4 provider 支持 | 换 `IvParameterSpec`（tag 仍 128 位，密文格式不变） |
| 9 | OkHttp 4 用 `getEnabledProtocols()` 做 TLS 交集，4.4 默认只有 SSLv3/TLSv1 | 改用 `getSupportedProtocols()`；应用自带 ISRG Root X1/X2 |
| 10 | Sentry SDK 初始化触发 `dvmDescriptorToName` 空指针原生崩溃 | 移除两个 Sentry Provider / 关闭初始化 |
| 11 | 主 dex 方法数 > 64K | 把 `com/netease/filmlytv/model` 包挪到 classes3；资源名不能以 `$`/`_` 开头（aapt 限制）需改名 |
| 12 | 主题层 ActionBar 兼容 | `windowActionBar=false`，否则 4.4 的 `ActionBarOverlayLayout` 抛 ClassCastException |
| 13 | 服务端签名依赖 native 库 | 把 `getSecretKey`/`getNativeAPI` 改为 Java 实现并硬编码官方证书密钥（见 protocol.md） |
| 14 | 4.4 缺 `__read_chk`、`rand/strtof` 等符号 | 自编 `libcompatshim.so` + 改 dynstr + 注入 NEEDED（见 native.md） |

### 一个必须遵守的约束

R8 会把静态常量内联到调用方。像 `getSecretKey` 这种要替换实现的方法，
**补丁必须打在 native 方法声明所在的类里**（让调用方仍然走方法调用），
直接改调用方 `x7/b0` 的 `<clinit>` 会 `VerifyError`。
