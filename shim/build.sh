#!/bin/bash
# 交叉编译 libcompat.so（armeabi-v7a，补设备 libc 缺失的 28 个符号）
#
# 依赖：
#   - Zig 0.13（$ZIG 指向 zig 可执行文件；https://ziglang.org/download/0.13.0/）
#   - 设备 libc 快照：adb pull /system/lib/libc.so 到 $DEVLIBS
#     （只为让产物带上 NEEDED libc.so；符号在运行时由设备 libc 提供）
#
# 用法：ZIG=/path/to/zig DEVLIBS=/path/to/devlib ./build.sh
set -e
ZIG=${ZIG:-/tmp/zig-linux-x86_64-0.13.0/zig}
DEVLIBS=${DEVLIBS:-$(cd "$(dirname "$0")/.." && pwd)/work/devlib}
HERE=$(cd "$(dirname "$0")" && pwd)

"$ZIG" cc -target arm-linux-musleabi -mcpu=cortex_a7 -O2 -shared -fPIC -nostdlib \
  -fno-stack-protector \
  -Wl,-soname,libcompat.so -Wl,-z,now \
  -L"$DEVLIBS" -Wl,--no-as-needed -l:libc.so \
  -o "$HERE/libcompat.so" "$HERE/libcompat.c"

readelf -d "$HERE/libcompat.so" | grep -E "NEEDED|SONAME"
echo "built: $HERE/libcompat.so"
