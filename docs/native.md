# 原生库：libvlc 起不来与 libcompat 垫片

## 症状

点播放，`PlayerActivity.onCreate` 直接崩：

```
java.lang.UnsatisfiedLinkError: Native method not found:
    org.videolan.libvlc.util.VLCUtil.log:(ILjava/lang/String;Ljava/lang/String;)I
    at org.videolan.libvlc.LibVLC.loadLibraries
```

同时 logcat 里有真正的原因：

```
D/dalvikvm: Trying to load lib .../libvlc.so
E/dalvikvm: dlopen(".../libvlc.so") failed:
    dlopen failed: cannot locate symbol "newlocale" referenced by "libvlc.so"...
W/dalvikvm: No implementation found for native ...VLCUtil;.log
```

`libvlc.so` 加载失败 → 依赖它的 `libvlcjni.so` 也不会注册 JNI → `VLCUtil.log` 未实现。

## 根因

设备的 libc 是海思裁剪版 bionic，`libvlc.so` 的未定义符号里有 **28 个**它没有：

```
__FD_ISSET_chk  __FD_SET_chk  __cmsg_nxthdr  __ctype_get_mb_cur_max
accept4         atof          endmntent      feclearexcept
fetestexcept    freelocale    getmntent_r    lfind
mkstemp64       mmap64        newlocale      open64
posix_fadvise64 random        recvmmsg       setmntent
sigaddset       sigdelset     sigemptyset    sigismember
srandom         stpcpy        uselocale      vmsplice
```

另外 `libshadowhook` / `libxdl` 还缺 `sig*64` 系列和 `dl_iterate_phdr`。

### 怎么算出来的（可复现）

```bash
# 1. 取 libvlc 的未定义符号
readelf -sW --dyn-syms libvlc.so | awk '$7=="UND"{print $8}' | sed 's/@.*//' | sort -u > undef.txt
# 2. 取设备所有系统库的导出符号（至少 libc/libm/libdl/liblog/libstdc++/libz/libEGL/libGLESv2）
# 3. 差集就是缺的
```

不要只看 `libc.so`：`c++_shared`、`libm`、`libEGL` 等也会提供一部分。

## 解法一：libcompat.so

`shim/libcompat.c` 用 Zig 交叉编译成 armeabi-v7a 的 `libcompat.so`：

```bash
ZIG=/path/to/zig DEVLIBS=/path/to/devlib ./shim/build.sh
```

要点：

- `-target arm-linux-musleabi -mcpu=cortex_a7 -shared -fPIC -nostdlib`
- **必须链接设备 libc.so**（`-L$DEVLIBS -l:libc.so`），否则产物没有 `NEEDED libc.so`，
  运行时连 `strtod/fopen` 都找不到（Android 4.4 链接器只在 NEEDED 链里找符号）。
- 实现里避免依赖 libc：内存/字符串函数自带静态实现，只保留 `strtod/open/fopen/fgets/fclose/__errno`
  这几个交给 bionic。
- 细节与取舍：
  - `sigset_t` 按 bionic 32 位（`unsigned long`）实现；`sig*64` 按 64 位实现。
  - `mmap64` 用 `mmap2`（字节偏移 >> 12），**大于 4GB 的偏移会截断**；本机片子都在 2GB 内。
  - `getmntent_r/setmntent/endmntent` 按 glibc 结构体布局实现，文件指针用 bionic 的 `FILE*`。
  - `dl_iterate_phdr` 是**返回 0 的桩**：只保证 shadowhook/libxdl 能加载，不提供真实模块遍历。
  - `feclearexcept/fetestexcept` 返回 0（不做 FP 异常跟踪）。
- 编译产物约 30KB（无调试信息）。

## 解法二：把 compat 变成 libvlc 的直接依赖

**关键坑：只 `System.loadLibrary("compat")` 预加载是没用的。**
Android 4.4 的链接器在给 `libvlc.so` 重定位时，只查它自己的 NEEDED 链，不查全局作用域。
实测预加载后仍然报 `cannot locate symbol "newlocale"`。

做法（`patches/02-playback/patch_libvlc_needed.py`）：

- 在 `libvlc.so` 的 `.dynstr` 里，把 `libstdc++.so` 原地改成 `libcompat.so`（都是
  12 字节 + NUL，等长替换，动态段不用重排）。
- 为什么可以删 libstdc++：`libvlc.so` 引用的 12 个 libstdc++ 符号
  （`operator new/delete`、`__cxa_guard_*`、`__cxa_pure_virtual`、`_ZSt7nothrow`）
  全部由 `libc++_shared` 提供，而后者本来就是它的 NEEDED。
- 改完 `readelf -d libvlc.so` 应该看到 `NEEDED libcompat.so`。

## 验证

- 运行时：logcat 里 `Trying to load lib .../libcompat.so` 之后紧接
  `libvlc.so`、`libvlcjni.so`，没有 `cannot locate symbol`；随后 `E/VLC-std` 开始刷
  H.264 帧日志（`E` 是 VLC 的 std logger 的默认级别，不是错误）。
- 静态：`libvlcjni.so` 的 `JNI_OnLoad`（Ghidra 里能看到）会
  `FindClass("org/videolan/libvlc/util/VLCUtil")` 并
  `RegisterNatives` 一个方法：名字 `log`、签名
  `(ILjava/lang/String;Ljava/lang/String;)I`、函数指针 `vlcLog`。
  同一函数里还 `std_logger_Open("VLC-std")`——这就是 logcat 里 `VLC-std` 标签的来源。

## v1 阶段的另一套垫片

v1 还处理过另一批缺失符号（`__read_chk`、`rand/srand`、`strtof/strtold`、
`wcstoll/wcstoull`、`truncate64`、`getpagesize`、`android_set_abort_message` 等），
做法是：

- 5 个库（`libmarsxlog/libmmkv/libsentry/libvlc/libvlcjni`）的 `.dynstr` 里
  `__read_chk` → `read` 原地改名；
- 自编 `libcompatshim.so` 导出其余符号；
- 改 GNU versioning 动态标签，把 `libcompatshim.so` 注入到 10 个库的 NEEDED。

这部分产物叫 `libcompatshim.so`，与阶段二（v1.1.0）的 `libcompat.so` 是两套，互不替代。
如果你从官方包自己走一遍 v1，需要自己重建这套（见 docs/history.md）。
