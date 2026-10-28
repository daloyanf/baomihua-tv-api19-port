# 阶段六：清晰度/字幕/音轨菜单（v1.5.0）

输入 v1.4.0，输出 v1.5.0。原因链与真机验证见
[docs/troubleshooting.md](../../docs/troubleshooting.md) 的「v1.5.0」一节。

## 补丁点

| 位置 | 修改 | 目的 |
| --- | --- | --- |
| `org.videolan.libvlc.MediaPlayer$TrackDescription` | JSON 解析失败时用 `jstring` 回填 `name`/`desc`，`uri`/`language`/`format` 置空串 | 官方 JNI 传纯文本，恢复真实轨道名 |
| `r6.p0$a.e()` | 行高上限 100dp→150dp、150dp→200dp | 放宽展开行高度（保险） |
| `PlayerActivity.M()` | 返回值固定 0 | 选项网格不再被 80dp topMargin 推出屏幕 |
| `r6.p0$a.i()` | 展开=VISIBLE+WRAP_CONTENT+requestLayout；收起=GONE+50dp | 行高量表准确，折叠行不再抢焦点 |
| `r6.q0.c()` | bind 时给类别标题打 `p0$b` tag，并强制该行展开 | 所有类别常展开；标题可触发展开逻辑 |
| `r6.k0$a.d()` | 占位按钮 `setFocusable(false)`/`setClickable(false)`；options_list 非聚焦 | 「暂无/加载中…」不抢焦点 |

## 构建

```bash
BASE=release/baomihua-tv-2.6.22-api19-1.4.0.apk \
OUT=release/baomihua-tv-2.6.22-api19-1.5.0.apk \
KS_PASS=$(cat ~/.android-keys/walldav.pass) \
./patches/06-tracks/build.sh
```

脚本自带落地校验（baksmali 回读 dex，确认补丁存在；smali 失败不报错会静默留旧 dex）。

## 验证（H1 真机，2026-10-27）

```bash
# 播放中按 DOWN 打开面板，再按 3 次 DOWN
adb shell uiautomator dump /sdcard/ui.xml
```

焦点顺序：`字幕(title) → 音轨(title) → 音轨选项(option_btn)`。

- 《逃学威龙》MKV：2 条音轨都显示 `Chinese - [Chinese]`；选中第二项出现勾选并关闭面板。
- 该片无字幕轨：字幕行显示「暂无」；有轨场景与音轨同一链路，未取得测试片源做实际切换。
- 清晰度只有「原画」：WebDAV/夸克直挂没有转码档，不是菜单故障。
