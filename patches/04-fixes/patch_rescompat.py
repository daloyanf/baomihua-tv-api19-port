#!/usr/bin/env python3
"""classes3.dex: 让 ResCompat 在 API19 上能加载 vector XML。

框架 Resources.getDrawable 在 4.4 上不认识 <vector>，会抛
Resources$NotFoundException（invalid drawable tag vector）。这里先走框架，
捕获 NotFoundException 后回退到应用自带的 VectorDrawableCompat
（混淆名 d2.j，方法 a(int, Resources.Theme, Resources)）。
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else 'dec3'
p = os.path.join(root, 'com/netease/filmlytv/compat/ResCompat.smali')
s = open(p, encoding='utf-8').read()


def sub(old, new, tag):
    global s
    if old not in s:
        if new in s:
            print('  = already applied:', tag)
            return
        sys.exit('  ! anchor not found: ' + tag)
    s = s.replace(old, new, 1)
    print('  + patched:', tag)


sub('''    :cond_b
    invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    invoke-virtual {v0, p1}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v0

    return-object v0''',
'''    :cond_b
    :try_start_0
    invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    invoke-virtual {v0, p1}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v0

    return-object v0
    :try_end_0
    .catch Landroid/content/res/Resources$NotFoundException; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;

    move-result-object v0

    const/4 v1, 0x0

    invoke-static {p1, v1, v0}, Ld2/j;->a(ILandroid/content/res/Resources$Theme;Landroid/content/res/Resources;)Ld2/j;

    move-result-object v0

    return-object v0''',
    'ResCompat.getDrawable vector fallback')

sub('''    :cond_b
    invoke-virtual {p0, p1}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v0

    return-object v0''',
'''    :cond_b
    :try_start_0
    invoke-virtual {p0, p1}, Landroid/content/res/Resources;->getDrawable(I)Landroid/graphics/drawable/Drawable;

    move-result-object v0

    return-object v0
    :try_end_0
    .catch Landroid/content/res/Resources$NotFoundException; {:try_start_0 .. :try_end_0} :catch_0

    :catch_0
    invoke-static {p1, p2, p0}, Ld2/j;->a(ILandroid/content/res/Resources$Theme;Landroid/content/res/Resources;)Ld2/j;

    move-result-object v0

    return-object v0''',
    'ResCompat.getDrawableThemed vector fallback')

open(p, 'w', encoding='utf-8').write(s)
print('done')
