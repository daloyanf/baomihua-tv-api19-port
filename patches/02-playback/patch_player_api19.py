#!/usr/bin/env python3
"""阶段二播放链路 API19 兼容补丁（幂等）。

输入：baksmali 解出的两个目录
  <root>/dec            <- classes.dex
  <root>/classes3_dec   <- classes3.dex

每处修改都对应一次 API 19 上真实发生的崩溃/NoSuchMethod：
  1. PlayerActivity: AudioManager.register/unregisterAudioDeviceCallback (API23) -> nop
  2. libplayer/h: CodecCapabilities.getVideoCapabilities (API21) -> 结果置空，走 "无能力信息" 分支
  3. libplayer/a: 同上
  4. A11yCompat: 修正 a() 自递归 & b() 在 API19 只有 5 参 obtain
  5. AWindow$SurfaceHelper.reparent: SurfaceControl$Transaction (API29) 整体桩掉
  6. LibVLC.loadLibraries: 在加载 libvlc 前先加载 libcompat（便于失败时定位）
"""
import os
import sys

root = sys.argv[1] if len(sys.argv) > 1 else 'dexwork'


def load(rel):
    p = os.path.join(root, rel)
    if not os.path.exists(p):
        print('SKIP (missing):', p)
        return None
    return open(p, encoding='utf-8').read()


def save(rel, s):
    open(os.path.join(root, rel), 'w', encoding='utf-8').write(s)


def sub_once(s, old, new, tag):
    if old not in s:
        print('  - already applied/absent:', tag)
        return s
    print('  + patched:', tag)
    return s.replace(old, new, 1)


# ---------------------------------------------------------------- 1. PlayerActivity
rel = 'dec/com/netease/filmlytv/activity/player/PlayerActivity.smali'
s = load(rel)
if s is not None:
    s = sub_once(
        s,
        '    invoke-virtual {v0, v1, v4}, Landroid/media/AudioManager;->registerAudioDeviceCallback(Landroid/media/AudioDeviceCallback;Landroid/os/Handler;)V',
        '    nop\n    nop\n    nop',
        'PlayerActivity registerAudioDeviceCallback')
    s = sub_once(
        s,
        '    invoke-virtual {v2, v6}, Landroid/media/AudioManager;->unregisterAudioDeviceCallback(Landroid/media/AudioDeviceCallback;)V',
        '    nop\n    nop',
        'PlayerActivity unregisterAudioDeviceCallback')
    save(rel, s)


# ------------------------------------------- 2/3. getVideoCapabilities (API21)
def patch_video_capabilities(rel, invoke, reg, tag):
    s = load(rel)
    if s is None:
        return
    i = s.find(invoke)
    if i < 0:
        print('  - already applied/absent:', tag)
        return
    j = s.find('    move-result-object ' + reg + '\n', i)
    if j < 0 or j - i > 400:
        print('  ! move-result for %s not found, skip' % tag)
        return
    s2 = (s[:i]
          + '    const/4 %s, 0x0\n    nop\n    nop' % reg
          + s[i + len(invoke):j]
          + '    nop'
          + s[j + len('    move-result-object ' + reg):])
    save(rel, s2)
    print('  + patched:', tag)


patch_video_capabilities(
    'dec/com/filmlytv/libplayer/h.smali',
    '    invoke-virtual {v11}, Landroid/media/MediaCodecInfo$CodecCapabilities;->getVideoCapabilities()Landroid/media/MediaCodecInfo$VideoCapabilities;',
    'v11', 'libplayer/h getVideoCapabilities')
patch_video_capabilities(
    'dec/com/filmlytv/libplayer/a.smali',
    '    invoke-virtual {v9}, Landroid/media/MediaCodecInfo$CodecCapabilities;->getVideoCapabilities()Landroid/media/MediaCodecInfo$VideoCapabilities;',
    'v1', 'libplayer/a getVideoCapabilities')


# ---------------------------------------------------------------- 4. A11yCompat
rel = 'dec/com/netease/filmlytv/compat/A11yCompat.smali'
s = load(rel)
if s is not None:
    s = sub_once(
        s,
        '    invoke-static {p0, p1, p2, p3}, Lcom/netease/filmlytv/compat/A11yCompat;->a(IIZI)Landroid/view/accessibility/AccessibilityNodeInfo$CollectionInfo;',
        '    invoke-static {p0, p1, p2, p3}, Landroid/view/accessibility/AccessibilityNodeInfo$CollectionInfo;->obtain(IIZI)Landroid/view/accessibility/AccessibilityNodeInfo$CollectionInfo;',
        'A11yCompat.a self-recursion')
    s = sub_once(
        s,
        '    invoke-static {p0, p1, p2, p3}, Landroid/view/accessibility/AccessibilityNodeInfo$CollectionItemInfo;->obtain(IIII)Landroid/view/accessibility/AccessibilityNodeInfo$CollectionItemInfo;',
        '    invoke-static {p0, p1, p2, p3, p4}, Landroid/view/accessibility/AccessibilityNodeInfo$CollectionItemInfo;->obtain(IIIIZ)Landroid/view/accessibility/AccessibilityNodeInfo$CollectionItemInfo;',
        'A11yCompat.b API19 overload')
    save(rel, s)


# ------------------------------------- 5. AWindow$SurfaceHelper.reparent (API29)
rel = 'classes3_dec/org/videolan/libvlc/AWindow$SurfaceHelper.smali'
s = load(rel)
if s is not None:
    old = '''.method private reparent(Landroid/view/SurfaceView;)V
    .registers 5

    .line 1'''
    new = '''.method private reparent(Landroid/view/SurfaceView;)V
    .registers 5

    return-void

    .line 1'''
    s = sub_once(s, old, new, 'AWindow$SurfaceHelper.reparent stub')
    save(rel, s)


# ------------------------------------------------ 6. LibVLC compat preload
rel = 'classes3_dec/org/videolan/libvlc/LibVLC.smali'
s = load(rel)
if s is not None:
    old = '''    const-string v4, "vlc"

    .line 23
    .line 24
    invoke-static {v4}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V'''
    new = '''    const-string v4, "compat"

    invoke-static {v4}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V

    const-string v4, "vlc"

    .line 23
    .line 24
    invoke-static {v4}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V'''
    s = sub_once(s, old, new, 'LibVLC preload libcompat')
    save(rel, s)

print('done')
