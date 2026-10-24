#!/usr/bin/env python3
"""v1.3.0 播放体验修复（幂等）。

三个修改点：
  1. IPlayer$b.a(Param)：服务端 play_params 的 renderer 会覆盖默认值。API19 上
     服务端可能下发 soft_gles2，客户端据此追加 --vout=gles2 --glconv=none，
     强制软解 + 无色彩转换，表现为花屏 + 卡顿。这里固定 renderer="direct"，
     清掉 no_drop_late_frames，并忽略服务端的 decoder_score_list（保留内置
     OMX 硬解优先级）。
  2. h7.e0：详情页播放优先走 File 直连路径（与“最近观看”完全一致），
     有 File 时不再走 Source+MediaFile 的解析分支。
  3. adapter/cover/a$a：OtherCover 只要带 File 就用直连播放 presenter（o6.k），
     不再进详情页；没有 File 的仍走详情页。
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else 'dec'


def load(rel):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        sys.exit('missing: ' + p)
    return open(p, encoding='utf-8').read()


def save(rel, s):
    open(os.path.join(root, rel), 'w', encoding='utf-8').write(s)


def replace_once(s, old, new, tag):
    if old not in s:
        if new in s:
            print('  = already applied:', tag)
            return s
        sys.exit('  ! anchor not found: ' + tag)
    print('  + patched:', tag)
    return s.replace(old, new, 1)


# ---------------------------------------------------------------- 1. renderer
rel = 'com/filmlytv/libplayer/IPlayer$b.smali'
s = load(rel)
old = '''    iput-object v3, p0, Lcom/filmlytv/libplayer/IPlayer$Param;->n:Ljava/lang/String;

    .line 23
    .line 24
    :cond_17'''
new = '''    iput-object v3, p0, Lcom/filmlytv/libplayer/IPlayer$Param;->n:Ljava/lang/String;

    const-string v3, "direct"

    iput-object v3, p0, Lcom/filmlytv/libplayer/IPlayer$Param;->n:Ljava/lang/String;

    const/4 v3, 0x0

    iput-boolean v3, p0, Lcom/filmlytv/libplayer/IPlayer$Param;->t:Z

    .line 23
    .line 24
    :cond_17'''
s = replace_once(s, old, new, 'force renderer=direct + noDropLateFrames=false')
save(rel, s)

# ------------------------------------------- 1b. keep built-in hardware decoder scoring
rel = 'com/filmlytv/libplayer/IPlayer$b.smali'
s = load(rel)
s = replace_once(
    s,
    '    iput-object v0, p0, Lcom/filmlytv/libplayer/IPlayer$Param;->y:Ljava/lang/String;',
    '    # keep Param\'s built-in decoder score list (favour OMX hardware decoders)\n    nop',
    'ignore server decoder_score_list (keep OMX enabled)')
save(rel, s)

# ------------------------------------------- 1c. strip server options that force software/vout
# 服务端 extra_options 里如果带 --vout= / --glconv= / --no-mediacodec / --codec=，
# 会绕过上面的 renderer 覆盖。这里在加入 LibVLC 参数列表前过滤掉。
rel = 'com/netease/filmlytv/activity/player/PlayerActivity.smali'
s = load(rel)
old = '''    invoke-static {v15, v5}, Lkb/i;->a(Ljava/lang/Object;Ljava/lang/Object;)Z

    .line 1603
    .line 1604
    move-result v5

    .line 1605
    if-nez v5, :cond_649

    .line 1606
    .line 1607
    invoke-virtual {v6, v15}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
'''
new = '''    invoke-static {v15, v5}, Lkb/i;->a(Ljava/lang/Object;Ljava/lang/Object;)Z

    .line 1603
    .line 1604
    move-result v5

    .line 1605
    if-nez v5, :cond_649

    const-string v17, "--vout="

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_glconv

    goto :cond_649

    :filter_glconv
    const-string v17, "--glconv="

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_mc

    goto :cond_649

    :filter_mc
    const-string v17, "--no-mediacodec"

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_codec

    goto :cond_649

    :filter_codec
    const-string v17, "--codec="

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_add

    goto :cond_649

    :filter_add
    .line 1606
    .line 1607
    invoke-virtual {v6, v15}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
'''
# 用更短、实际存在的锚点（smali 里 .line 注释没有空行）
old = '''    if-nez v5, :cond_649

    .line 1606
    .line 1607
    invoke-virtual {v6, v15}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
'''
new = '''    if-nez v5, :cond_649

    const-string v17, "--vout="

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_glconv

    goto :cond_649

    :filter_glconv
    const-string v17, "--glconv="

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_mc

    goto :cond_649

    :filter_mc
    const-string v17, "--no-mediacodec"

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_codec

    goto :cond_649

    :filter_codec
    const-string v17, "--codec="

    invoke-virtual {v15, v17}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z

    move-result v17

    if-eqz v17, :filter_add

    goto :cond_649

    :filter_add
    .line 1606
    .line 1607
    invoke-virtual {v6, v15}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z
'''
s = replace_once(s, old, new, 'strip server vout/glconv/no-mediacodec options')
save(rel, s)

# ---------------------------------------------------------------- 2. detail play: File first
rel = 'h7/e0.smali'
s = load(rel)
old = '''    :cond_34
    const-string v2, "getContext(...)"

    .line 54
    .line 55
    if-eqz v5, :cond_8d'''
new = '''    :cond_34
    const-string v2, "getContext(...)"

    if-nez v4, :cond_8d

    .line 54
    .line 55
    if-eqz v5, :cond_8d'''
s = replace_once(s, old, new, 'detail play prefers File path')
save(rel, s)

# ---------------------------------------------------------------- 3. OtherCover with File -> direct play presenter
rel = 'com/netease/filmlytv/adapter/cover/a$a.smali'
s = load(rel)
old = '''    if-eqz v0, :cond_35

    .line 25
    .line 26
    iget-boolean p1, p0, Lcom/netease/filmlytv/adapter/cover/a$a;->a:Z

    .line 27
    .line 28
    if-eqz p1, :cond_2a'''
new = '''    if-eqz v0, :cond_35

    move-object v0, p1

    check-cast v0, Lcom/netease/filmlytv/model/cover/OtherCover;

    invoke-virtual {v0}, Lcom/netease/filmlytv/model/cover/OtherCover;->getFile()Lcom/netease/filmlytv/model/File;

    move-result-object v0

    if-eqz v0, :cond_2a'''
s = replace_once(s, old, new, 'OtherCover with File -> o6.k direct play')
save(rel, s)

# ------------------------------------------- 4. MotionCompat call sites lost their float constants
# 阶段一把 new PathInterpolator(f1,f2,f3,f4) 换成了 MotionCompat.a(FFFF)，但下面三处
# 连 f1..f4 的 const 加载一起删了；Dalvik 校验器看到对象/资源ID 当 float 用会拒绝整个类。
rel = 'com/google/android/material/bottomsheet/BottomSheetBehavior.smali'
s = load(rel)
old = '''    invoke-static {v4, v4, v5, v2}, Lcom/netease/filmlytv/compat/MotionCompat;->a(FFFF)Landroid/view/animation/Interpolator;'''
new = '''    const v4, 0x3dcccccd

    const/4 v5, 0x0

    invoke-static {v4, v4, v5, v2}, Lcom/netease/filmlytv/compat/MotionCompat;->a(FFFF)Landroid/view/animation/Interpolator;'''
s = replace_once(s, old, new, 'BottomSheetBehavior interpolator float args')
# API21+ 的 insets 动画监听在 4.4 上不存在，调用必然 NoSuchMethodError；直接跳过。
s = replace_once(
    s,
    '    invoke-virtual {p2, v0}, Landroid/view/View;->setOnApplyWindowInsetsListener(Landroid/view/View$OnApplyWindowInsetsListener;)V',
    '    nop',
    'BottomSheetBehavior skip setOnApplyWindowInsetsListener on API19')
# H() 只做无障碍 action 注册，引用了 API21 的 AccessibilityAction；整段桩掉，
# 校验器也不会再去看不可达代码里的缺失类。
s = replace_once(
    s,
    '''.method public final H()V
    .registers 16

    .line 1''',
    '''.method public final H()V
    .registers 16

    return-void

    .line 1''',
    'BottomSheetBehavior stub H() (AccessibilityAction API21)')
# SDK<30 的 insets 动画回调分支会 new-instance 一个 API21 才有的 o0.r0$c$a；
# 4.4 上直接跳过整段（否则 NoClassDefFoundError）。
s = replace_once(
    s,
    '''    :cond_9a
    sget-object v0, Lo0/r0$c;->e:Landroid/view/animation/Interpolator;''',
    '''    :cond_9a
    goto :goto_bc

    sget-object v0, Lo0/r0$c;->e:Landroid/view/animation/Interpolator;''',
    'BottomSheetBehavior skip insets animation callback on API19')
save(rel, s)

# j5/b 把 String 直接传给 MotionCompat.b(Path)；官方是先 PathParser 转 Path。
rel = 'j5/b.smali'
s = load(rel)
old = '    invoke-static {p0}, Lcom/netease/filmlytv/compat/MotionCompat;->b(Landroid/graphics/Path;)Landroid/view/animation/Interpolator;'
new = '''    invoke-static {p0}, Lg0/j;->d(Ljava/lang/String;)Landroid/graphics/Path;

    move-result-object p0

    invoke-static {p0}, Lcom/netease/filmlytv/compat/MotionCompat;->b(Landroid/graphics/Path;)Landroid/view/animation/Interpolator;'''
s = replace_once(s, old, new, 'j5/b: convert path string before MotionCompat.b')
save(rel, s)

rel = 'com/google/android/material/sidesheet/SideSheetBehavior.smali'
s = load(rel)
old = '''    invoke-static {v5, v5, v3, v6}, Lcom/netease/filmlytv/compat/MotionCompat;->a(FFFF)Landroid/view/animation/Interpolator;'''
new = '''    const v5, 0x3dcccccd

    const/high16 v6, 0x3f800000

    invoke-static {v5, v5, v3, v6}, Lcom/netease/filmlytv/compat/MotionCompat;->a(FFFF)Landroid/view/animation/Interpolator;'''
s = replace_once(s, old, new, 'SideSheetBehavior interpolator float args')
save(rel, s)

rel = 'o0/r0$c.smali'
s = load(rel)
old = '''.method static constructor <clinit>()V
    .registers 4

    .line 1
    invoke-static {v3, v1, v3, v2}, Lcom/netease/filmlytv/compat/MotionCompat;->a(FFFF)Landroid/view/animation/Interpolator;'''
new = '''.method static constructor <clinit>()V
    .registers 4

    .line 1
    const v1, 0x3f8ccccd

    const/high16 v2, 0x3f800000

    const/4 v3, 0x0

    invoke-static {v3, v1, v3, v2}, Lcom/netease/filmlytv/compat/MotionCompat;->a(FFFF)Landroid/view/animation/Interpolator;'''
s = replace_once(s, old, new, 'r0$c clinit interpolator float args')
save(rel, s)

print('done')
