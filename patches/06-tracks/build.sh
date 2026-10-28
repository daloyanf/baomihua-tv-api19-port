#!/bin/bash
# =============================================================================
# 06-tracks: 网易爆米花 v1.4.0 -> v1.5.0（清晰度/字幕/音轨菜单可用性修复）
# =============================================================================
#
# 背景（真机证据见 docs/troubleshooting.md 的「v1.5.0」一节）：
#   1) v1.4.0 换官方 VLC 3.6.2 引擎后，轨道枚举本身正常：
#      真机日志能看到 getAudioTracks: Disable / Chinese - [Chinese] x2，
#      getAudioTracks ret: 2。
#      但官方 libvlcjni 的 createTrackDescriptionFromNative 传的是裸名称字符串，
#      而 fork 的 TrackDescription 构造器把 jstring 当 JSON 解析；
#      JSONException 被 catch 掉后 name/uri/lang/desc/format 全为 null，
#      菜单里的轨道名因此丢失（音轨 N / 字幕 N）。
#   2) 播放器选项面板（DPAD 下键打开）的类别行展开高度被 p0$a.e() 钳制：
#      普通类别上限 100dp、电视剧类别上限 150dp。
#      1080p/240dpi 下展开内容约 182px，而钳制值是 150px，
#      于是「清晰度」展开后的选项按钮向下压住「字幕 / 音轨」标题，
#      Leanback 焦点搜索按几何中心就近选择，DOWN 从「字幕」又跳回「原画」，
#      字幕/音轨两行实际无法聚焦 —— 菜单看起来“用不了”。
#      修法是把上限放宽：普通 100dp -> 150dp，电视剧 150dp -> 200dp。
#   3) 选项网格自身还带 80dp topMargin（PlayerActivity.M() 返回值），
#      而面板容器只有 270dp 高，网格底部因此超出屏幕约 80dp：
#      1080p 下「音轨」行落在屏幕外，焦点搜索 DOWN 从「字幕」回跳「原画」。
#      修法：M() 返回 0，让网格与容器顶部对齐。
#   4) 折叠只把选项网格 alpha 置 0，占位按钮（「暂无/加载中…」）和网格本身
#      仍可被焦点命中；类别标题没有 tag，聚焦标题时不会展开对应类别。
#      修法：所有类别常展开（bind 时强制 WRAP_CONTENT + VISIBLE）、
#      标题打 p0$b tag、占位按钮与选项网格不可聚焦。
#
# 用法:
#   BASE=/path/v1.4.0.apk OUT=/path/v1.5.0.apk KS_PASS=<口令> ./build.sh
#
# 前置：baksmali/smali 在 PATH；Android build-tools（zipalign/apksigner）
#       在 $BT；密钥库 $KS（与 v1.0.0~v1.4.0 同一把，可直接覆盖安装）。
# =============================================================================
set -euo pipefail

BASE=${BASE:-/mnt/Others/baomihua-tv-api19-port/release/baomihua-tv-2.6.22-api19-1.4.0.apk}
KS=${KEYSTORE:-$HOME/.android-keys/walldav.jks}
KS_ALIAS=${KS_ALIAS:-walldav}
BT=${BUILD_TOOLS:-$HOME/android-sdk/build-tools/33.0.1}
OUT=${OUT:?OUT=输出apk}
: "${KS_PASS:?KS_PASS=签名口令}"

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

unzip -q "$BASE" -d "$W/apk"

# ---------------------------------------------------------------------------
# A. classes3.dex：TrackDescription 纯文本回退
#    官方 JNI 传 "Chinese - [Chinese]" 这类裸字符串；JSON 解析失败时用它回填。
#    写 name/desc；uri/language/format 置空串（h.j() 据此走内封字幕分支）。
# ---------------------------------------------------------------------------
baksmali d "$W/apk/classes3.dex" -o "$W/apk/smali3_out"
python3 - "$W/apk/smali3_out/org/videolan/libvlc/MediaPlayer\$TrackDescription.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()

# 需要多给几个本地寄存器做分支
old_regs = ".method private constructor <init>(ILjava/lang/String;)V\n    .registers 3\n"
new_regs = ".method private constructor <init>(ILjava/lang/String;)V\n    .registers 8\n"
assert src.count(old_regs) == 1, "TrackDescription header: %d" % src.count(old_regs)
src = src.replace(old_regs, new_regs, 1)

old_catch = """    :catchall_39
    move-exception p1

    .line 11
    invoke-virtual {p1}, Ljava/lang/Throwable;->printStackTrace()V

    return-void
.end method"""
new_catch = """    :catchall_39
    move-exception p1

    .line 11
    invoke-virtual {p1}, Ljava/lang/Throwable;->printStackTrace()V

    # 官方引擎传裸名称（非 JSON）：用它回填 name/desc，其余留空
    iget-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->jstring:Ljava/lang/String;
    if-eqz p1, :plain_done
    iput-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->name:Ljava/lang/String;
    iput-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->desc:Ljava/lang/String;
    const-string p1, ""
    iput-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->uri:Ljava/lang/String;
    iput-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->language:Ljava/lang/String;
    iput-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->format:Ljava/lang/String;
    :plain_done
    return-void
.end method"""
assert src.count(old_catch) == 1, "TrackDescription catch: %d" % src.count(old_catch)
src = src.replace(old_catch, new_catch, 1)
open(path, "w").write(src)
print("patched: TrackDescription plain-string fallback")
PYEOF

smali a --api 19 "$W/apk/smali3_out" -o "$W/apk/classes3.dex"
# 落地校验：smali 失败不报错会静默留旧 dex（见 docs/troubleshooting.md）
baksmali d "$W/apk/classes3.dex" -o "$W/apk/verify3"
grep -q 'iput-object p1, p0, Lorg/videolan/libvlc/MediaPlayer$TrackDescription;->name:Ljava/lang/String;' \
  "$W/apk/verify3/org/videolan/libvlc/MediaPlayer\$TrackDescription.smali" \
  || { echo "FATAL: TrackDescription 补丁未进 dex"; exit 1; }
rm -rf "$W/apk/verify3" "$W/apk/smali3_out"

# ---------------------------------------------------------------------------
# B. classes.dex：放宽选项面板类别行高度钳制
#    p0$a.e() 里两处 coerceIn 上限：
#      普通类别 100dp -> 150dp；电视剧类别 150dp -> 200dp
#    展开后的选项按钮不再压住后续类别标题，字幕/音轨行可以正常聚焦。
# ---------------------------------------------------------------------------
baksmali d "$W/apk/classes.dex" -o "$W/apk/smali_out"
python3 - "$W/apk/smali_out/r6/p0\$a.smali" <<'PYEOF'
import sys
path = sys.argv[1]
src = open(path).read()

old_tv = "const/high16 v1, 0x43160000    # 150.0f"
new_tv = "const/high16 v1, 0x43480000    # 200.0f"
assert src.count(old_tv) == 1, "tv clamp: %d" % src.count(old_tv)
src = src.replace(old_tv, new_tv, 1)

old_normal = "const/high16 v1, 0x42c80000    # 100.0f"
new_normal = "const/high16 v1, 0x43160000    # 150.0f"
assert src.count(old_normal) == 1, "normal clamp: %d" % src.count(old_normal)
src = src.replace(old_normal, new_normal, 1)

open(path, "w").write(src)
print("patched: option row height clamp 100dp->150dp, 150dp->200dp")
PYEOF

# ---------------------------------------------------------------------------
# C. classes.dex：选项面板网格不再向下溢出屏幕
#    PlayerActivity.M(List) 返回值被用作 option_grid 的 topMargin（80dp）。
#    面板容器本身只有 270dp 高，网格再下移 80dp 后底部超出屏幕：
#    1080p 下「音轨」行落在屏幕外，焦点搜索无法到达（DOWN 会回跳「原画」）。
#    改为 0：网格与容器顶部对齐，270dp 视口内可容纳展开行 + 后续类别行。
# ---------------------------------------------------------------------------
python3 - "$W/apk/smali_out/com/netease/filmlytv/activity/player/PlayerActivity.smali" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path).read()
pat = re.compile(r"\.method public final M\(Ljava/util/List;\)I.*?\.end method", re.S)
assert len(pat.findall(src)) == 1, "M(List) not unique"
new = (
    ".method public final M(Ljava/util/List;)I\n"
    "    .registers 3\n"
    "    const/4 v0, 0x0\n"
    "    return v0\n"
    ".end method")
src = pat.sub(new, src, count=1)
open(path, "w").write(src)
print("patched: option_grid topMargin -> 0")
PYEOF

# ---------------------------------------------------------------------------
# D. classes.dex：跳转音轨/字幕时只保留目标类别展开
#    p0.l()/m()（音轨/字幕键 222/175 触发）原本只展开目标类别，
#    而面板创建时「清晰度」行仍处于展开态，两行互相压住，
#    焦点会在 AUDIO <-> RESOLUTION 之间来回跳（真机日志实证）。
#    改为：先折叠除目标外的所有类别，再展开目标；焦点由随后的 p0.k() 落到
#    当前选中的轨道按钮上。
# ---------------------------------------------------------------------------
python3 - "$W/apk/smali_out/r6/p0.smali" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path).read()

def body(enum_field, tag):
    return f""".method public final {tag}()V
    .registers 12

    iget-object v0, p0, Lr6/p0;->b:Landroidx/leanback/widget/y;

    instance-of v1, v0, Lr6/p0$a;

    if-eqz v1, :cast

    return-void

    :cast
    check-cast v0, Lr6/p0$a;

    if-eqz v0, :ret

    iget-object v1, v0, Lr6/p0$a;->b:Ljava/util/List;

    sget-object v2, Lr6/p0$b;->{enum_field}:Lr6/p0$b;

    invoke-interface {{v1, v2}}, Ljava/util/List;->indexOf(Ljava/lang/Object;)I

    move-result v3

    if-gez v3, :ret

    const/4 v4, 0x0

    invoke-interface {{v1}}, Ljava/util/List;->size()I

    move-result v5

    :loop
    if-ge v4, v5, :expand

    if-ne v4, v3, :next

    invoke-virtual {{v0, v4}}, Lr6/p0$a;->f(I)Lr6/q0;

    move-result-object v6

    iget-object v6, v6, Lr6/q0;->b:Landroid/view/ViewGroup;

    const/4 v7, 0x0

    const/16 v8, 0x8

    invoke-static {{v0, v7, v6, v8}}, Lr6/p0$a;->j(Lr6/p0$a;ZLandroid/view/ViewGroup;I)V

    :next
    add-int/lit8 v4, v4, 0x1

    goto :loop

    :expand
    invoke-virtual {{v0, v3}}, Lr6/p0$a;->f(I)Lr6/q0;

    move-result-object v6

    iget-object v6, v6, Lr6/q0;->b:Landroid/view/ViewGroup;

    const/4 v7, 0x1

    const/16 v8, 0x8

    invoke-static {{v0, v7, v6, v8}}, Lr6/p0$a;->j(Lr6/p0$a;ZLandroid/view/ViewGroup;I)V

    :ret
    return-void
.end method"""

for tag, enum_field in (("l", "e"), ("m", "c")):
    pat = re.compile(r"\.method public final " + tag + r"\(\)V.*?\.end method", re.S)
    assert len(pat.findall(src)) == 1, "p0." + tag + "() not unique"
    src = pat.sub(body(enum_field, tag), src, count=1)

open(path, "w").write(src)
print("patched: p0.l()/m() collapse other categories")
PYEOF

# ---------------------------------------------------------------------------
# E. classes.dex：类别行展开/收起改为「即时 + WRAP_CONTENT + GONE」
#    原实现用「父行当前高度 + 选项网格当前高度」做动画目标，而折叠行的
#    HorizontalGridView 受 50dp 父高限制只测到 ~44dp；展开后实际内容更高，
#    行高少算 ~20px，后续类别标题仍被选项按钮压住（真机实测）。
#    且折叠只设 alpha=0，子按钮仍可被焦点命中，DOWN 会跳回上方选项。
#    改为：展开 = VISIBLE + LayoutParams.height=WRAP_CONTENT + requestLayout；
#          收起 = GONE + height=50dp。放弃 200ms 动画（API19 上布局更可靠）。
# ---------------------------------------------------------------------------
python3 - "$W/apk/smali_out/r6/p0\$a.smali" <<'PYEOF'
import re, sys
path = sys.argv[1]
src = open(path).read()
pat = re.compile(r"\.method public final i\(ZLandroid/view/ViewGroup;ZZ\)V.*?\.end method", re.S)
assert len(pat.findall(src)) == 1, "p0$a.i() not unique"
new = """.method public final i(ZLandroid/view/ViewGroup;ZZ)V
    .registers 9

    if-nez p2, :ret

    const/4 p1, 0x1

    invoke-virtual {p2}, Landroid/view/View;->getParent()Landroid/view/ViewParent;

    move-result-object v0

    check-cast v0, Landroid/widget/LinearLayout;

    if-eqz p1, :expand

    const/4 v1, 0x0

    invoke-virtual {p2, v1}, Landroid/view/View;->setAlpha(F)V

    const/16 v1, 0x8

    invoke-virtual {p2, v1}, Landroid/view/View;->setVisibility(I)V

    invoke-virtual {v0}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;

    move-result-object v1

    invoke-virtual {v0}, Landroid/view/View;->getContext()Landroid/content/Context;

    move-result-object v2

    const/high16 v3, 0x42480000    # 50.0f

    invoke-static {v2, v3}, Lx7/j;->b(Landroid/content/Context;F)I

    move-result v2

    iput v2, v1, Landroid/view/ViewGroup$LayoutParams;->height:I

    invoke-virtual {v0, v1}, Landroid/view/View;->setLayoutParams(Landroid/view/ViewGroup$LayoutParams;)V

    return-void

    :expand
    const/high16 v1, 0x3f800000    # 1.0f

    invoke-virtual {p2, v1}, Landroid/view/View;->setAlpha(F)V

    const/4 v1, 0x0

    invoke-virtual {p2, v1}, Landroid/view/View;->setVisibility(I)V

    invoke-virtual {v0}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;

    move-result-object v1

    const/4 v2, -0x2

    iput v2, v1, Landroid/view/ViewGroup$LayoutParams;->height:I

    invoke-virtual {v0, v1}, Landroid/view/View;->setLayoutParams(Landroid/view/ViewGroup$LayoutParams;)V

    invoke-virtual {v0}, Landroid/view/View;->requestLayout()V

    :ret
    return-void
.end method"""
src = pat.sub(new, src, count=1)
open(path, "w").write(src)
print("patched: category expand/collapse (WRAP_CONTENT + GONE)")
PYEOF

# ---------------------------------------------------------------------------
# G. classes.dex：类别标题打 tag + 占位按钮不可聚焦
#    面板焦点监听只认带 p0$b tag 的 View；标题没有 tag，聚焦标题时不会展开
#    该类别。这里在类别行 bind 时把 item（p0$b）写到标题的 tag 上，
#    聚焦标题即可触发原有的展开逻辑。
#    另外把「加载中…/未检测到字幕」占位按钮设为不可聚焦，避免焦点被它抢走。
# ---------------------------------------------------------------------------
python3 - "$W/apk/smali_out/r6/q0.smali" "$W/apk/smali_out/r6/k0\$a.smali" <<'PYEOF'
import re, sys
q0, k0 = sys.argv[1], sys.argv[2]

src = open(q0).read()
pat = re.compile(r"\.method public final c\(Landroidx/leanback/widget/x\$a;Ljava/lang/Object;\)V.*?\.end method", re.S)
assert len(pat.findall(src)) == 1, "q0.c not unique"
new_c = """.method public final c(Landroidx/leanback/widget/x$a;Ljava/lang/Object;)V
    .registers 6

    const-string v0, "viewHolder"

    invoke-static {p1, v0}, Lkb/i;->e(Ljava/lang/Object;Ljava/lang/String;)V

    iget-object v0, p1, Landroidx/leanback/widget/x$a;->a:Landroid/view/View;

    const v1, 0x7f0902ac

    invoke-virtual {v0, v1}, Landroid/view/View;->findViewById(I)Landroid/view/View;

    move-result-object v0

    if-eqz v0, :ret

    invoke-virtual {v0, p2}, Landroid/view/View;->setTag(Ljava/lang/Object;)V

    iget-object v0, p1, Landroidx/leanback/widget/x$a;->a:Landroid/view/View;

    invoke-virtual {v0}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;

    move-result-object v1

    const/4 v2, -0x2

    iput v2, v1, Landroid/view/ViewGroup$LayoutParams;->height:I

    invoke-virtual {v0, v1}, Landroid/view/View;->setLayoutParams(Landroid/view/ViewGroup$LayoutParams;)V

    const v1, 0x7f0902ab

    invoke-virtual {v0, v1}, Landroid/view/View;->findViewById(I)Landroid/view/View;

    move-result-object v0

    if-eqz v0, :ret

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/view/View;->setVisibility(I)V

    const/high16 v1, 0x3f800000    # 1.0f

    invoke-virtual {v0, v1}, Landroid/view/View;->setAlpha(F)V

    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/view/View;->setFocusable(Z)V

    :ret
    return-void
.end method"""
src = pat.sub(new_c, src, count=1)
open(q0, "w").write(src)

src = open(k0).read()
anchor = """    invoke-virtual {v0, v1}, Landroid/view/View;->setTag(Ljava/lang/Object;)V
"""
assert src.count(anchor) == 1, "k0 tag anchor"
src = src.replace(anchor, anchor + """
    const/4 v1, 0x0

    invoke-virtual {v0, v1}, Landroid/view/View;->setFocusable(Z)V

    invoke-virtual {v0, v1}, Landroid/view/View;->setClickable(Z)V
""", 1)
open(k0, "w").write(src)
print("patched: category title tag + placeholder non-focusable")
PYEOF

smali a --api 19 "$W/apk/smali_out" -o "$W/apk/classes.dex"
baksmali d "$W/apk/classes.dex" -o "$W/apk/verify"
grep -q "const/high16 v1, 0x43480000" "$W/apk/verify/r6/p0\$a.smali" \
  || { echo "FATAL: 类别行高度补丁未进 dex"; exit 1; }
python3 - "$W/apk/verify/r6/q0.smali" "$W/apk/verify/r6/k0\$a.smali" <<'PYEOF'
import sys
q0, k0 = sys.argv[1], sys.argv[2]
src = open(q0).read()
assert "setTag(Ljava/lang/Object;)V" in src and "0x7f0902ac" in src, "q0 title tag missing"
src = open(k0).read()
assert "setFocusable(Z)V" in src, "placeholder focus patch missing"
print("verified: title tag + placeholder non-focusable")
PYEOF
rm -rf "$W/apk/verify" "$W/apk/smali_out"

# ---------------------------------------------------------------------------
# 打包 + 签名（与 v1.0.0~v1.4.0 同证书，可直接覆盖安装）
# ---------------------------------------------------------------------------
cd "$W/apk"
rm -rf META-INF
zip -qr9 "$W/out.apk" .
cd - >/dev/null
"$BT/zipalign" -f 4 "$W/out.apk" "$W/aligned.apk"
"$BT/apksigner" sign --ks "$KS" --ks-key-alias "$KS_ALIAS" \
    --ks-pass env:KS_PASS --key-pass env:KS_PASS \
    --out "$OUT" "$W/aligned.apk"
"$BT/apksigner" verify --print-certs "$OUT" | head -2
ls -la "$OUT"
