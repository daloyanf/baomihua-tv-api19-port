#!/usr/bin/env python3
"""计算一个 ELF 共享库的未定义符号里，哪些在给定的一组系统库里找不到。

用途：把 libvlc.so 这类预编译库搬到精简 Android 系统上时，先算出缺哪些 libc 符号，
再决定垫片要补什么。

用法：
  ./check-elf-symbols.py libvlc.so devlib/ libc++_shared.so
  # devlib/ = 设备 /system/lib/*.so 的快照（至少 libc/libm/libdl/liblog/libstdc++/libz/libEGL/libGLESv2）
  # 别忘了把 APK 自带的 libc++_shared.so 也作为 provider 传进来，否则 C++ 符号会误报

输出：缺失符号列表（按字母序），可直接对照 shim/libcompat.c。
"""
import glob
import os
import subprocess
import sys


def dynsyms(path, mode):
    out = subprocess.run(['readelf', '-sW', '--dyn-syms', path],
                         capture_output=True, text=True)
    if out.returncode != 0:
        return set()
    res = set()
    for line in out.stdout.splitlines():
        p = line.split()
        if len(p) < 8:
            continue
        typ, ndx, name = p[3], p[6], p[7].split('@')[0]
        if not name:
            continue
        if mode == 'undef' and ndx == 'UND':
            res.add(name)
        if mode == 'export' and typ in ('FUNC', 'OBJECT', 'IFUNC', 'COMMON') and ndx != 'UND':
            res.add(name)
    return res


def expand(args):
    files = []
    for a in args:
        if os.path.isdir(a):
            files += sorted(glob.glob(os.path.join(a, '*.so')))
        else:
            files += sorted(glob.glob(a)) or [a]
    return [f for f in files if os.path.isfile(f)]


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    target = sys.argv[1]
    providers = expand(sys.argv[2:])

    undef = dynsyms(target, 'undef')
    have = set()
    for p in providers:
        have |= dynsyms(p, 'export')
    missing = sorted(undef - have)
    print('# target:', target)
    print('# providers:', len(providers))
    print('# undef=%d have=%d missing=%d' % (len(undef), len(have), len(missing)))
    for s in missing:
        print(s)


if __name__ == '__main__':
    main()
