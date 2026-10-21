# 服务端鉴权与签名

爆米花 TV 的 API 在 `https://api.filmly.netease.com`。关键逻辑原本在 `libnative.so`
（`getSecretKey` / `getNativeAPI`）。移植时改为纯 Java 实现，一是避开 4.4 上原生库的加载
问题，二是必须把密钥固定成**官方签名证书**派生值（见下）。

## 请求体

```
body = AES-GCM( gzip( JSON ) )
格式 = [ivLen = 16 (4 bytes, 大端)][iv(16 字节)][密文 || tag(16 字节)]
```

要点：

- AES-128（密钥 16 字节），GCM tag 128 位。
- Android 4.4 的 BouncyCastle 不认 `GCMParameterSpec`（类存在但 provider 不支持），
  改用 `IvParameterSpec`，密文格式不变。
- 先 gzip，再加密。

## AES 密钥

```
key = MD5( APK 签名证书 DER 的小写十六进制字符串 ).toUpperCase()   # 32 位 hex 字符串
AES 密钥 = key 的前 16 字节
```

也就是说密钥只取决于**签名证书**，与包名、版本无关。

官方证书（`O=Netease`）对应的密钥：

```
9B7B94D0B96797545A5510FE9A23B250
```

重签名后如果继续用自己证书推导，服务端会拒绝（`10004 参数解密失败`）。
所以补丁里把密钥硬编码成上面这个值。

## 请求头 Sign

```
Sign = lowercase_hex( SHA256(
          params
        + (params 非空 ? "&SecTag=" : "SecTag=") + secTag
        + "&Seed="   + seed
        + "&Key="    + key
        + (body != null ? "&post_content=" + body 的明文 JSON : "")
      ) )
```

- `params`：按 key 排序拼接的请求参数串（形如 `a=1&b=2`）。
- `secTag`：应用内的固定标签。
- `seed`：秒级时间戳。
- `key`：上面 32 位 hex 的密钥字符串（注意是字符串，不是二进制）。
- `post_content`：PUT/POST 时参与签名的是**明文 JSON**，不是加密后的 body。

## 错误码

| code | 含义 | 通常原因 |
| --- | --- | --- |
| `10004` | 参数解密失败 | AES 密钥不对（重签后没换密钥） |
| `10012` | 签名错误 | Sign/Seed/密钥字符串不对 |

## 验证方法

抓 `logcat` 里应用打印的请求/响应最简单；如果自己实现客户端，先用一个已知可用的
GET 接口（如版本接口）对齐 `params` 拼接顺序和 `Seed`，再调带 body 的接口。

> 注意：`Seed` 是秒级时间戳，服务端允许的时钟偏差未知；排查 `10012` 时先校准时间。
