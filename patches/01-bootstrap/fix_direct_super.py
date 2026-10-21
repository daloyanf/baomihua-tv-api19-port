import os,re,collections,sys
DST2=os.environ.get('TV_MOD','work/tv-mod')
cls={}
for d in ('smali','smali_classes2','smali_classes3','smali_assets'):
    base=os.path.join(DST2,d)
    for dp,dn,fn in os.walk(base):
        for f in fn:
            if not f.endswith('.smali'): continue
            p=os.path.join(dp,f)
            t=open(p,encoding='utf-8',errors='ignore').read()
            m=re.search(r'^\.class[^\n]*?L([A-Za-z0-9_$/]+);',t,re.M)
            m2=re.search(r'^\.super L([^;]+);',t,re.M)
            if m: cls[m.group(1)]=(p,(m2.group(1) if m2 else 'java/lang/Object'),t)

def ctors_of(C,sig):
    if C not in cls: return None
    s=cls[C][2]
    ms=list(re.finditer(r'^\.method[^\n]*constructor <init>\('+re.escape(sig)+r'\)V',s,re.M))
    if not ms: return []
    out=[]
    for m in ms:
        j=s.find('.end method',m.start())
        out.append(s[m.start():j+len('.end method')])
    return out

def is_pure_obj_forwarder(body,sig):
    """trivial forwarder: exactly one invoke-direct {p0}, <any>.<init>(same sig) + return"""
    calls=[]
    for l in body.split('\n'):
        l=l.strip()
        if not l or l.startswith('.') or l.startswith('#'): continue
        if l=='return-void': continue
        m=re.match(r'invoke-direct(?:/range)? \{p0(?: \.\. p\d+)?\}, L[^;]+;-><init>\(([^)]*)\)V',l)
        if m and m.group(1)==sig:
            calls.append(l); continue
        return False
    return len(calls)==1

_plat_cache={}
def platform_has_ctor(C,sig):
    key=(C,sig)
    if key in _plat_cache: return _plat_cache[key]
    ok=False
    try:
        import subprocess as _sp
        jar=os.path.expanduser('~/android-sdk/platforms/android-19/android.jar')
        out=_sp.run(['javap','-classpath',jar,C.replace('/','.')],capture_output=True,text=True,timeout=20).stdout
        import re as _r2
        simple=C.split('/')[-1].split('$')[-1]
        pat=_r2.compile(r'\b'+_r2.escape(simple)+r'\((.*)\);\s*$')
        for ln in out.splitlines():
            m2=pat.search(ln.strip())
            if m2:
                if sig=='':
                    if m2.group(1).strip()=='': ok=True; break
                else:
                    ok=True; break  # loose match for parameterized ctors
    except Exception:
        ok=(sig=='')
    _plat_cache[key]=ok
    return ok

def ensure_ctor_chain(C,sig,depth=0):
    """make sure C has a dalvik-legal <init>(sig); returns 'ok' or None"""
    if C=='java/lang/Object': return 'ok'
    if C not in cls:
        return 'ok' if platform_has_ctor(C,sig) else None
    bodies=ctors_of(C,sig)
    if bodies is None: return None
    if len(bodies)>0:
        # exists: legal iff it calls its own direct super (any ancestor ok if chain legal) -- assume existing are fine
        return 'ok'
    sup=cls[C][1]
    r=ensure_ctor_chain(sup,sig,depth+1)
    if r is None: return None
    p,_,s=cls[C]
    n=1+param_count(sig)
    if n-1==0:
        inv='invoke-direct {p0}, L'+sup+';-><init>('+sig+')V'
    else:
        inv='invoke-direct/range {p0 .. p%d}, L'%(n-1)+sup+';-><init>('+sig+')V'
    ctor='.method public constructor <init>('+sig+')V\n    .locals 0\n\n    '+inv+'\n\n    return-void\n.end method\n'
    s=s.rstrip()+'\n\n'+ctor
    open(p,'w',encoding='utf-8').write(s)
    cls[C]=(p,cls[C][1],s)
    return 'ok'

def param_count(sig):
    n=0;i=0
    while i<len(sig):
        ch=sig[i]
        if ch in 'JD': n+=2;i+=1
        elif ch=='L': n+=1;i=sig.index(';',i)+1
        elif ch=='[':
            n+=1;i+=1
            while i<len(sig) and sig[i]=='[': i+=1
            if i<len(sig) and sig[i]=='L': i=sig.index(';',i)+1
            else: i+=1
        else: n+=1;i+=1
    return n

def anc_chain(S):
    out=[]
    c=cls[S][1]
    while True:
        out.append(c)
        if c not in cls: break   # platform superclass: include its name, cannot traverse further
        c=cls[c][1]
    if 'java/lang/Object' not in out: out.append('java/lang/Object')
    return out
INV=re.compile(r'(invoke-direct(?:/range)? \{([^}]*)\}, )L([^;]+);-><init>\(([^)]*)\)V')
retarget=0; skipped=[]; touched=0
for S,(p,sup,s) in list(cls.items()):
    if sup=='java/lang/Object': continue
    changed=False
    for m in re.finditer(r'^\.method[^\n]*constructor <init>\(([^)]*)\)V', s, re.M):
        sig=m.group(1)
        j=s.find('.end method',m.start()); body=s[m.start():j]
        for im in INV.finditer(body):
            regs=[x.strip() for x in im.group(2).split(',')]
            if len(regs)==1 and '..' in regs[0]:
                regs=[regs[0].split('..')[0].strip()]
            if not (regs and regs[0]=='p0'): continue
            C=im.group(3); sigc=im.group(4)
            if C==sup: continue          # already direct super
            if C==S: continue            # this()
            if C not in (['java/lang/Object']+list(anc_chain(S))): continue  # unrelated: pass1 handled
            # calling a non-direct ancestor (incl Object) while direct super != Object
            if ctors_of(sup,sigc)==[] or (len(ctors_of(sup,sigc) or [])==1 and is_pure_obj_forwarder(ctors_of(sup,sigc)[0],sigc)) or ctors_of(sup,sigc) is None:
                pass
            r=ensure_ctor_chain(sup,sigc)
            if r=='ok' and (not ctors_of(sup,sigc) or is_pure_obj_forwarder(ctors_of(sup,sigc)[0],sigc) or len(ctors_of(sup,sigc))>=0):
                # safe only if direct super ctor is trivial; if it has real body we still must call it per dalvik -> behavior change; report instead
                bs=ctors_of(sup,sigc)
                if bs and not is_pure_obj_forwarder(bs[0],sigc):
                    skipped.append((S,C,sigc,'super-ctor-has-body')); continue
                nl=im.group(0).replace('L'+C+';-><init>('+sigc+')V','L'+sup+';-><init>('+sigc+')V')
                body=body.replace(im.group(0),nl,1)
                s=s[:m.start()]+body+s[j:]
                changed=True; retarget+=1
            else:
                skipped.append((S,C,sigc,'chain-unresolvable'))
    if changed:
        open(p,'w',encoding='utf-8').write(s); touched+=1
print('retargeted:',retarget,'files:',touched,'skipped:',len(skipped))
for x in skipped[:20]: print('  SKIP',x)

