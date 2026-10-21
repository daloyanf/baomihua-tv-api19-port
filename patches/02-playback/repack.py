#!/usr/bin/env python3
"""重打包：替换 dex、libvlc.so，追加 libcompat.so，去掉旧 v1 签名。

用法：repack.py <base.apk> <out.apk> [classes.dex classes3.dex libvlc.so libcompat.so]
未提供的参数使用默认路径（见 DEFAULTS）。
"""
import os
import sys
import zipfile

DEFAULTS = {
    'classes': 'work/dexwork/classes-new.dex',
    'classes3': 'work/dexwork/classes3-new.dex',
    'libvlc': 'work/patched/libvlc.so',
    'libcompat': 'shim/libcompat.so',
}

base = sys.argv[1] if len(sys.argv) > 1 else 'base-signed.apk'
out = sys.argv[2] if len(sys.argv) > 2 else 'packed.apk'
paths = list(sys.argv[3:]) + [DEFAULTS[k] for k in ('classes', 'classes3', 'libvlc', 'libcompat')][len(sys.argv[3:]):]
cls, cls3, vlc, compat = paths[:4]

mapping = {
    'classes.dex': cls,
    'classes3.dex': cls3,
    'lib/armeabi-v7a/libvlc.so': vlc,
}
extra = {
    'lib/armeabi-v7a/libcompat.so': compat,
}
drop = {'META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/MANIFEST.MF'}

for p in list(mapping.values()) + list(extra.values()):
    if not os.path.exists(p):
        sys.exit('missing input: ' + p)

with zipfile.ZipFile(base) as zin, zipfile.ZipFile(out, 'w') as zout:
    for it in zin.infolist():
        n = it.filename
        if n in drop:
            continue
        data = open(mapping[n], 'rb').read() if n in mapping else zin.read(n)
        zi = zipfile.ZipInfo(n, date_time=it.date_time)
        zi.compress_type = it.compress_type
        zi.external_attr = it.external_attr
        zi.create_system = it.create_system
        zout.writestr(zi, data)
    for n, p in extra.items():
        zi = zipfile.ZipInfo(n, date_time=(2026, 10, 21, 0, 0, 0))
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = 0o100644 << 16
        zi.create_system = 3
        zout.writestr(zi, open(p, 'rb').read())

print('packed:', out)
