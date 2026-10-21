# 阶段二补丁（播放链路，v1.1.0）

阶段一（v1.0.0）只能到登录/片库，点播放会崩。本阶段把 VLC 播放链路修通。

## 根因

`libvlc.so` 在 4.4 上 `dlopen` 失败：

```
dlopen failed: cannot locate symbol "newlocale" referenced by "libvlc.so"
```

设备（海思裁剪版 bionic）缺少 `libvlc.so` 加载时就要解析的 28 个 libc 符号：

```
newlocale uselocale freelocale open64 mmap64 mkstemp64 posix_fadvise64
getmntent_r setmntent endmntent sigaddset sigdelset sigemptyset sigismember
stpcpy lfind random srandom atof accept4 recvmmsg vmsplice
feclearexcept fetestexcept __FD_ISSET_chk __FD_SET_chk
__cmsg_nxthdr __ctype_get_mb_cur_max
```

## 修法

1. `shim/libcompat.c` 实现上述符号（另附 `sig*64` 与 `dl_iterate_phdr` 桩），
   用 Zig 交叉编译成 `libcompat.so`。
2. **只靠 `System.loadLibrary` 预加载无效**：Android 4.4 链接器只沿 NEEDED 链解析符号。
   因此把 `libvlc.so` 的 `.dynstr` 中 `libstdc++.so` 原位改成 `libcompat.so`
   （12 字节等长），使其成为 libvlc 的直接依赖。
   去掉 libstdc++ 无副作用：libvlc 引用的 12 个 libstdc++ 符号全部由 `libc++_shared`
   提供，而后者本来就是 NEEDED。
3. Java 侧 API19 兜底（`patch_player_api19.py`）：

| 位置 | 原调用 | 处理 |
| --- | --- | --- |
| `PlayerActivity` | `AudioManager.register/unregisterAudioDeviceCallback`（API 23） | 指令改 nop |
| `libplayer/h`、`libplayer/a` | `CodecCapabilities.getVideoCapabilities`（API 21） | 结果置空，走原有「无能力信息」分支 |
| `AWindow$SurfaceHelper` | `reparent()` 用 `SurfaceControl$Transaction`（API 29） | 方法首行插 `return-void` |
| `A11yCompat` | `a()` 自递归；`b()` 回退到不存在的 4 参 `obtain` | 改 4 参 `CollectionInfo.obtain` / 5 参 `CollectionItemInfo.obtain` |

`A11yCompat` 两个 bug 平时不触发，但 `uiautomator dump` 查询 View 树会走到
`GridLayoutManager` 的无障碍委托 → `NoSuchMethodError` 崩溃。

## 文件

| 文件 | 作用 |
| --- | --- |
| `build.sh` | 一键：解包 v1.0.0 → baksmali → Java 补丁 → smali → NEEDED 修补 → 重打包 → 签名 |
| `patch_player_api19.py` | Java 侧 API19 兜底（幂等） |
| `patch_libvlc_needed.py` | `libvlc.so` 的 `libstdc++.so` → `libcompat.so`（等长改名） |
| `repack.py` | 替换 dex/libvlc、追加 libcompat.so、去旧签名 |

## 构建

```bash
# 设备 libc 快照（让垫片带 NEEDED libc.so）
mkdir -p work/devlib
adb pull /system/lib/libc.so work/devlib/libc.so

BASE=/path/to/baomihua-1.0.0.apk \
KEYSTORE=$HOME/.android-keys/my.jks \
KEYSTORE_PASS_FILE=$HOME/.android-keys/my.pass \
./build.sh
```

产物：`baomihua-1.1.0-signed.apk`。

## 验证

- `logcat` 里 `libcompat.so` → `libvlc.so` → `libvlcjni.so` 依次加载，无
  `cannot locate symbol`；
- 进播放器后 `VLC-std` 按帧刷 H.264 日志；
- `dumpsys media.audio_flinger` 有 44.1kHz 立体声 active AudioTrack；
- 进度推进、暂停/继续、续播、选集可用。

> 注意：本阶段的 `screenrecord` 截图**不能**证明电视端显示正常（见
> [docs/troubleshooting.md](../../docs/troubleshooting.md)）。画面问题在阶段三修复。
