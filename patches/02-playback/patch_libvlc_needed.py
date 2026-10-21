#!/usr/bin/env python3
"""把 libvlc.so 的 NEEDED 字符串 libstdc++.so 原地改成 libcompat.so。

为什么可以这样改：
  - 两者都是 12 字符 + NUL，.dynstr 内等长替换，动态段无需重排。
  - libvlc 引用的 12 个 libstdc++ 符号（operator new/delete、__cxa_guard_*、
    __cxa_pure_virtual、_ZSt7nothrow）在 libc++_shared 里全部存在，而
    libc++_shared 本来就是 libvlc 的 NEEDED，所以去掉 libstdc++ 无副作用。

用法：patch_libvlc_needed.py <libvlc.so> <out.so>
"""
import sys

src, dst = sys.argv[1], sys.argv[2]
old = b'libstdc++.so\x00'
new = b'libcompat.so\x00'
assert len(old) == len(new)

d = bytearray(open(src, 'rb').read())
n = d.count(old)
if n == 0 and d.count(new) == 1:
    print('already patched')
    open(dst, 'wb').write(d)
    sys.exit(0)
assert n == 1, 'unexpected libstdc++.so occurrences: %d' % n
i = d.find(old)
assert i > 0
d[i:i + len(new)] = new
open(dst, 'wb').write(d)
print('patched libvlc NEEDED at offset', i)
