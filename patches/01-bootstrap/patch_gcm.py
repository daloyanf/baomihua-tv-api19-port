import os,re
p=os.environ.get('GCM_SMALI','work/tv-mod/smali/x7/b0.smali')
lines=open(p,encoding='utf-8').read().split('\n')
out=[]
i=0
n=0
while i < len(lines):
    l=lines[i]
    m=re.match(r'^(\s*)new-instance (v\d+), Ljavax/crypto/spec/GCMParameterSpec;\s*$', l)
    if not m:
        out.append(l); i+=1; continue
    ind, reg = m.group(1), m.group(2)
    # scan ahead for const/16 (tag length) and invoke-direct
    j=i+1
    tagreg=None; tagidx=None
    inv=None; invidx=None
    while j < len(lines) and j < i+14:
        mm=re.match(r'^\s*const/16 (v\d+), 0x80\s*$', lines[j])
        if mm and tagreg is None:
            tagreg=mm.group(1); tagidx=j
        mi=re.match(r'^\s*invoke-direct \{(v\d+), (v\d+), (v\d+)\}, Ljavax/crypto/spec/GCMParameterSpec;-><init>\(I\[B\)V\s*$', lines[j])
        if mi:
            inv=mi; invidx=j
            break
        j+=1
    if not inv:
        out.append(l); i+=1; continue
    ivreg=inv.group(3)
    out.append('%snew-instance %s, Ljavax/crypto/spec/IvParameterSpec;' % (ind, reg))
    # copy middle lines except the const/16 tag line
    for k in range(i+1, invidx):
        if tagreg is not None and k == tagidx:
            continue
        out.append(lines[k])
    out.append('%sinvoke-direct {%s, %s}, Ljavax/crypto/spec/IvParameterSpec;-><init>([B)V' % (ind, reg, ivreg))
    n+=1
    i=invidx+1
open(p,'w',encoding='utf-8').write('\n'.join(out))
print('replacements:', n)
