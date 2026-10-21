# 阶段一补丁（API19 引导，v1.0.0）

这里的脚本是 阶段一保留下来的**部分**补丁，假设你已经用 apktool 把官方包解到
`work/tv-mod`（可用环境变量 `TV_MOD` 覆盖）。

| 文件 | 作用 | 备注 |
| --- | --- | --- |
| `fix_direct_super.py` | R8 构造器三类修复中的一类：直接父类不是 Object，却直调 `Object.<init>` | 会扫描 `smali*/` 全部类，给父类补空构造器并重定向 |
| `patch_gcm.py` | `GCMParameterSpec` → `IvParameterSpec` | 默认路径 `work/tv-mod/smali/x7/b0.smali`，用 `GCM_SMALI` 覆盖；混淆类名随版本变化 |
| `patch_api19_compat.py` | Sentry 初始化关闭、TLS 用 `getSupportedProtocols`、GCM、`getSecretKey/getNativeAPI` 改 Java 并硬编码官方证书密钥 | 密钥常量在文件顶部的 `KEY` |
| `rebuild.sh` | `apktool b` + zipalign + apksigner（v1+v2，minSdk 19） | 需要 `KEYSTORE` / `KEYSTORE_PASS_FILE` |

## 未包含的步骤

早期的一次性编排脚本（`patch_all.py`、`fix_superctor.py`、`fix_merged_super.py`）已丢失。
以下步骤需要按 [docs/api19.md](../../docs/api19.md) 自行实现：

- R8 构造器的另外两类修复（`new X` + 父类 `<init>` 重定向；合并类残留）；
- legacy MultiDex 注入；
- `BaseBundle` → `Bundle` 批量重映射；
- `ApplicationExitInfo` / `onTerminate` 桩化；
- 密度钩子搬迁；
- dex 均衡（model 包挪到 classes3）；
- 资源名去 `$`/`_` 前缀；
- 原生库 `__read_chk` 改名与 `libcompatshim.so` 注入（见 [docs/native.md](../../docs/native.md)）。

> 实践上，阶段二（v1.1.0）只需要一个「已经能启动并过鉴权」的 v1.0.0 基础包；如果你手上已有这样的包，
> 可以跳过本目录，直接看 `../02-playback/`。
