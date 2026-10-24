#!/usr/bin/env python3
"""把 detail 页的矢量图 ic_chevron_down 换成同尺寸 PNG。

API19 的 View 构造器加载 android:background 时走框架 Resources，不认识 <vector>。
这里改 resources.arsc 里的文件路径 xml->png（等长），并把 ZIP 里的该条目换成
25x24 的白色下箭头 PNG。布局和其他资源不动。
"""
import io
import sys
import zipfile
from PIL import Image, ImageDraw

src, out = sys.argv[1:3]

# 4x 绘制后缩到 25x24（与 vector 的 intrinsic 尺寸一致）
S = 4
img = Image.new('RGBA', (25 * S, 24 * S), (0, 0, 0, 0))
d = ImageDraw.Draw(img)
pts = [(int(6.5 * S), 9 * S), (int(12.5 * S), 15 * S), (int(18.5 * S), 9 * S)]
w = 2 * S
d.line(pts, fill=(255, 255, 255, 255), width=w, joint='curve')
for p in pts:
    r = w // 2
    d.ellipse([p[0] - r, p[1] - r, p[0] + r, p[1] + r], fill=(255, 255, 255, 255))
buf = io.BytesIO()
img.resize((25, 24), Image.LANCZOS).save(buf, 'PNG')
png = buf.getvalue()

with zipfile.ZipFile(src) as z:
    arsc = bytearray(z.read('resources.arsc'))
needle = b'res/drawable/ic_chevron_down.xml'
pos = arsc.find(needle)
if pos < 0:
    sys.exit('chevron path not found in resources.arsc')
if arsc.find(needle, pos + 1) >= 0:
    sys.exit('chevron path duplicated, aborting')
arsc[pos + len(needle) - 3:pos + len(needle)] = b'png'

drop = {'META-INF/CERT.RSA', 'META-INF/CERT.SF', 'META-INF/MANIFEST.MF'}
with zipfile.ZipFile(src) as zin, zipfile.ZipFile(out, 'w') as zout:
    for it in zin.infolist():
        if it.filename in drop:
            continue
        name, data, ctype = it.filename, None, it.compress_type
        if name == 'res/drawable/ic_chevron_down.xml':
            name, data, ctype = 'res/drawable/ic_chevron_down.png', png, zipfile.ZIP_DEFLATED
        elif name == 'resources.arsc':
            data = bytes(arsc)
        else:
            data = zin.read(name)
        zi = zipfile.ZipInfo(name, date_time=it.date_time)
        zi.compress_type = ctype
        zi.external_attr = it.external_attr
        zi.create_system = it.create_system
        zout.writestr(zi, data)
print('resource patch:', out, 'png', len(png), 'bytes')
