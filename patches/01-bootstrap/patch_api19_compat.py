#!/usr/bin/env python3
# API19 兼容修复：Sentry 关闭、TLS 协议、AES-GCM 参数、签名密钥/签名算法
import re, glob, os

DST=os.environ.get('TV_MOD','work/tv-mod')
KEY='9B7B94D0B96797545A5510FE9A23B250'

def find(rel):
    for d in ('smali','smali_classes2','smali_classes3'):
        p=os.path.join(DST,d,rel)
        if os.path.exists(p): return p
    return None

# 1) 关闭 Sentry 初始化（API19 上 SDK 初始化会导致 dalvik 校验器崩溃）
p=find('com/netease/filmlytv/core/b.smali')
s=open(p,encoding='utf-8').read()
if 'Sentry init disabled' not in s:
    m=re.search(r'\n\s*new-instance v\d+, Lio/sentry/android/replay/capture/f0;\n(?:.*\n)*?\s*invoke-static \{[^}]*\}, Lio/sentry/android/core/r1;->c\(Landroid/content/Context;Lio/sentry/g4\$a;Lio/sentry/android/core/w;\)V', s)
    s=s[:m.start()]+'\n    # Sentry init disabled for API19 port'+s[m.end():]
    open(p,'w',encoding='utf-8').write(s)

# 2) TLS：OkHttp 4 用 enabledProtocols 做交集，4.4 默认只有 SSLv3/TLSv1 -> 改用 supportedProtocols
for rel,anchor in [('ic/d.smali','iget-object v3, v1, Lec/i;->d:[Ljava/lang/String;'),
                   ('ec/i.smali','iget-object v2, p0, Lec/i;->d:[Ljava/lang/String;')]:
    p=find(rel); lines=open(p,encoding='utf-8').read().split('\n')
    ai=next(i for i,l in enumerate(lines) if anchor in l)
    for j in range(ai,ai+30):
        if 'getEnabledProtocols' in lines[j]:
            lines[j]=lines[j].replace('getEnabledProtocols','getSupportedProtocols')
            break
    open(p,'w',encoding='utf-8').write('\n'.join(lines))

# 3) AES-GCM：4.4 BC 不认 GCMParameterSpec（API19 有类但 provider 不支持）→ IvParameterSpec
p=find('x7/b0.smali')
lines=open(p,encoding='utf-8').read().split('\n')
out=[];i=0
while i<len(lines):
    m=re.match(r'^(\s*)new-instance (v\d+), Ljavax/crypto/spec/GCMParameterSpec;$', lines[i])
    if not m: out.append(lines[i]); i+=1; continue
    ind,reg=m.group(1),m.group(2); j=i+1; tagidx=None; inv=None
    while j<len(lines) and j<i+16:
        if re.match(r'^\s*const/16 v\d+, 0x80\s*$', lines[j]) and tagidx is None: tagidx=j
        mi=re.match(r'^\s*invoke-direct \{(v\d+), (v\d+), (v\d+)\}, Ljavax/crypto/spec/GCMParameterSpec;-><init>\(I\[B\)V\s*$', lines[j])
        if mi: inv=mi; break
        j+=1
    if not inv: out.append(lines[i]); i+=1; continue
    out.append('%snew-instance %s, Ljavax/crypto/spec/IvParameterSpec;'%(ind,reg))
    for k in range(i+1,j):
        if tagidx is not None and k==tagidx: continue
        out.append(lines[k])
    out.append('%sinvoke-direct {%s, %s}, Ljavax/crypto/spec/IvParameterSpec;-><init>([B)V'%(ind,reg,inv.group(3)))
    i=j+1
open(p,'w',encoding='utf-8').write('\n'.join(out))

# 4) 原生密钥/签名替换为 Java 实现（密钥=MD5(官方证书小写hex)，Sign=SHA256 拼接串）
p=find('com/netease/filmlytv/utils/NativeUtils.smali')
s=open(p,encoding='utf-8').read()
if 'public final getSecretKey()Ljava/lang/String;' not in s.replace('native getSecretKey',''):
    s=s.replace('.method public final native getSecretKey()Ljava/lang/String;\n.end method',
'''.method public final getSecretKey()Ljava/lang/String;
    .locals 1

    const-string v0, "%s"

    return-object v0
.end method'''%KEY,1)
if 'public final getNativeAPI(' in s and 'native getNativeAPI' in s:
    print('WARN: getNativeAPI still native')
open(p,'w',encoding='utf-8').write(s)
print('api19 compat patches applied')
