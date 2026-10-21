/* libcompat.so
 *
 * 补设备（海思裁剪版 bionic / Android 4.4.2）缺失、而 libvlc.so 等库在加载时
 * 就要解析的 libc 符号。共 28 个 + sig*64 + dl_iterate_phdr 桩。
 *
 * 交叉编译（见同目录 build.sh）：
 *   zig cc -target arm-linux-musleabi -mcpu=cortex_a7 -O2 -shared -fPIC -nostdlib \
 *          -fno-stack-protector -Wl,-soname,libcompat.so -Wl,-z,now \
 *          -L<devlib> -Wl,--no-as-needed -l:libc.so -o libcompat.so libcompat.c
 *
 * 注意：必须带上 NEEDED libc.so，否则 4.4 链接器解析不到 strtod/fopen 等；
 *       strtod/open/fopen/fgets/fclose/__errno 交给设备 libc，其余自带实现。
 */

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef unsigned long usize;
typedef long ssize;
typedef long off_t;

extern double strtod(const char *, char **);
extern int open(const char *, int, int);
extern void *mmap(void *, usize, int, int, int, off_t);
extern void *fopen(const char *, const char *);
extern char *fgets(char *, int, void *);
extern int fclose(void *);
extern int *__errno(void);

#define EINVAL 22
#define EEXIST 17
#define ENOMEM 12

static void set_errno(int e) { *__errno() = e; }

/* ---------- raw syscalls (ARM EABI: r7 = number) ---------- */

static long sys0(long n) {
  register long r0 __asm__("r0");
  register long r7 __asm__("r7") = n;
  __asm__ volatile("svc 0" : "=r"(r0) : "r"(r7) : "memory");
  return r0;
}

static long sys3(long n, long a, long b, long c) {
  register long r0 __asm__("r0") = a;
  register long r1 __asm__("r1") = b;
  register long r2 __asm__("r2") = c;
  register long r7 __asm__("r7") = n;
  __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r7) : "memory");
  return r0;
}

static long sys6(long n, long a, long b, long c, long d, long e, long f) {
  register long r0 __asm__("r0") = a;
  register long r1 __asm__("r1") = b;
  register long r2 __asm__("r2") = c;
  register long r3 __asm__("r3") = d;
  register long r4 __asm__("r4") = e;
  register long r5 __asm__("r5") = f;
  register long r7 __asm__("r7") = n;
  __asm__ volatile("svc 0"
                   : "+r"(r0)
                   : "r"(r1), "r"(r2), "r"(r3), "r"(r4), "r"(r5), "r"(r7)
                   : "memory");
  return r0;
}

static long sys_ret(long v) {
  if (v < 0 && v > -4096) {
    set_errno((int)-v);
    return -1;
  }
  return v;
}

#define NR_open 5
#define NR_close 6
#define NR_getpid 20
#define NR_mmap2 192
#define NR_clock_gettime 263
#define NR_arm_fadvise64_64 270
#define NR_vmsplice 343
#define NR_recvmmsg 365
#define NR_accept4 366

/* ---------- tiny freestanding string/memory helpers ---------- */

static void *shim_memcpy(void *d, const void *s, usize n) {
  u8 *dd = d;
  const u8 *ss = s;
  while (n--) *dd++ = *ss++;
  return d;
}

static void *shim_memset(void *d, int c, usize n) {
  u8 *dd = d;
  while (n--) *dd++ = (u8)c;
  return d;
}

static void *shim_memmove(void *d, const void *s, usize n) {
  u8 *dd = d;
  const u8 *ss = s;
  if (dd < ss) {
    while (n--) *dd++ = *ss++;
  } else {
    dd += n;
    ss += n;
    while (n--) *--dd = *--ss;
  }
  return d;
}

static usize shim_strlen(const char *s) {
  const char *p = s;
  while (*p) p++;
  return (usize)(p - s);
}

static int shim_strncmp(const char *a, const char *b, usize n) {
  while (n--) {
    unsigned char x = (unsigned char)*a++, y = (unsigned char)*b++;
    if (x != y) return x - y;
    if (!x) return 0;
  }
  return 0;
}

static int shim_strcmp(const char *a, const char *b) {
  while (*a && *a == *b) a++, b++;
  return (unsigned char)*a - (unsigned char)*b;
}

/* ---------- locale shims ---------- */

static int locale_dummy;

void *newlocale(int mask, const char *loc, void *base) {
  (void)mask;
  (void)loc;
  (void)base;
  return &locale_dummy;
}

void *uselocale(void *loc) {
  static void *cur = &locale_dummy;
  void *prev = cur;
  if (loc) cur = loc;
  return prev;
}

void freelocale(void *loc) { (void)loc; }

int __ctype_get_mb_cur_max(void) { return 1; }

/* ---------- fenv ---------- */

int feclearexcept(int e) {
  (void)e;
  return 0;
}

int fetestexcept(int e) {
  (void)e;
  return 0;
}

/* ---------- misc libc ---------- */

double atof(const char *s) { return strtod(s, (char **)0); }

char *stpcpy(char *dst, const char *src) {
  while ((*dst = *src++)) dst++;
  return dst;
}

void *lfind(const void *key, const void *base, usize *nmemb, usize size,
            int (*compar)(const void *, const void *)) {
  const u8 *p = base;
  usize n = *nmemb;
  while (n--) {
    if (compar(key, p) == 0) return (void *)p;
    p += size;
  }
  return (void *)0;
}

/* glibc random() TYPE_3 (matches what callers expect from libc) */
static u32 rnd_state[344];
static u32 *rnd_f;
static u32 *rnd_r;

void srandom(unsigned seed) {
  int i;
  rnd_state[0] = seed ? seed : 1;
  for (i = 1; i < 31; i++) {
    long long v = (long long)rnd_state[i - 1] * 16807LL;
    rnd_state[i] = (u32)(v % 2147483647LL);
  }
  for (i = 31; i < 34; i++) rnd_state[i] = rnd_state[i - 31];
  for (i = 34; i < 344; i++) rnd_state[i] = rnd_state[i - 31] + rnd_state[i - 3];
  rnd_f = &rnd_state[313];
  rnd_r = &rnd_state[341];
}

long random(void) {
  u32 v;
  if (!rnd_f) srandom(1);
  *rnd_f += *rnd_r;
  v = (*rnd_f >> 1) & 0x7fffffffU;
  if (++rnd_f >= &rnd_state[344]) rnd_f = &rnd_state[0];
  if (++rnd_r >= &rnd_state[344]) rnd_r = &rnd_state[0];
  return (long)v;
}

int open64(const char *path, int flags, int mode) {
  return open(path, flags, mode);
}

void *mmap64(void *addr, usize len, int prot, int flags, int fd, long long off) {
  long page = off >> 12;
  long r = sys6(NR_mmap2, (long)addr, (long)len, prot, flags, fd, page);
  return (void *)sys_ret(r);
}

int mkstemp64(char *tmpl) {
  usize n = shim_strlen(tmpl);
  static const char pat[] = "XXXXXX";
  static u32 seed;
  int tries;
  if (n < 6 || shim_strcmp(tmpl + n - 6, pat) != 0) {
    set_errno(EINVAL);
    return -1;
  }
  if (!seed) {
    struct {
      long sec;
      long nsec;
    } ts = {0, 0};
    sys3(NR_clock_gettime, 1 /* CLOCK_MONOTONIC */, (long)&ts, 0);
    seed = (u32)ts.sec * 2654435761U ^ (u32)ts.nsec ^ (u32)sys0(NR_getpid);
  }
  for (tries = 0; tries < 128; tries++) {
    int i;
    u32 v;
    seed ^= seed << 13;
    seed ^= seed >> 17;
    seed ^= seed << 5;
    v = seed;
    for (i = 0; i < 6; i++) {
      tmpl[n - 6 + i] = "abcdefghijklmnopqrstuvwxyz0123456789"[v % 36];
      v /= 36;
    }
    {
      long fd = sys3(NR_open, (long)tmpl,
                     0x42 /* O_RDWR|O_CREAT */ | 0x80 /* O_EXCL */, 0600);
      if (fd >= 0) return (int)fd;
      if (*__errno() != EEXIST) return -1;
    }
  }
  set_errno(EEXIST);
  return -1;
}

int posix_fadvise64(int fd, long long off, long long len, int advice) {
  long r = sys6(NR_arm_fadvise64_64, fd, advice, (long)off, (long)(off >> 32),
                (long)len, (long)(len >> 32));
  if (r < 0 && r > -4096) return (int)-r;
  return 0;
}

/* ---------- fd_set / cmsg fortify helpers ---------- */

int __FD_ISSET_chk(int d, const unsigned long *s, unsigned long n) {
  if (d < 0 || (unsigned long)d >= n * 8) return 0;
  return (int)((s[d / 32] >> (d % 32)) & 1UL);
}

int __FD_SET_chk(int d, unsigned long *s, unsigned long n) {
  if (d < 0 || (unsigned long)d >= n * 8) return -1;
  s[d / 32] |= 1UL << (d % 32);
  return 0;
}

struct my_cmsghdr {
  unsigned cmsg_len;
  int cmsg_level;
  int cmsg_type;
};

struct my_msghdr {
  void *msg_name;
  unsigned msg_namelen;
  void *msg_iov;
  unsigned msg_iovlen;
  void *msg_control;
  unsigned msg_controllen;
  int msg_flags;
};

void *__cmsg_nxthdr(void *msg, void *cmsg) {
  struct my_msghdr *m = (struct my_msghdr *)msg;
  u8 *start = (u8 *)m->msg_control;
  u8 *end = start + m->msg_controllen;

  if (!cmsg) {
    if (start + sizeof(struct my_cmsghdr) > end) return (void *)0;
    if (start + ((struct my_cmsghdr *)start)->cmsg_len > end) return (void *)0;
    return start;
  }
  if (((struct my_cmsghdr *)cmsg)->cmsg_len < sizeof(struct my_cmsghdr))
    return (void *)0;
  {
    u8 *next = (u8 *)cmsg + (((struct my_cmsghdr *)cmsg)->cmsg_len + 3) / 4 * 4;
    if (next + sizeof(struct my_cmsghdr) > end) return (void *)0;
    if (next + ((struct my_cmsghdr *)next)->cmsg_len > end) return (void *)0;
    return next;
  }
}

/* ---------- sigset (bionic sigset_t = 32-bit unsigned long) ---------- */

int sigemptyset(unsigned long *set) {
  if (!set) return -1;
  *set = 0;
  return 0;
}

int sigfillset(unsigned long *set) {
  if (!set) return -1;
  *set = 0xffffffffUL;
  return 0;
}

int sigaddset(unsigned long *set, int sig) {
  if (!set || sig < 1 || sig > 32) return -1;
  *set |= 1UL << (sig - 1);
  return 0;
}

int sigdelset(unsigned long *set, int sig) {
  if (!set || sig < 1 || sig > 32) return -1;
  *set &= ~(1UL << (sig - 1));
  return 0;
}

int sigismember(const unsigned long *set, int sig) {
  if (!set || sig < 1 || sig > 32) return -1;
  return (int)((*set >> (sig - 1)) & 1UL);
}

/* ---------- sigset64 (bionic sigset64_t = 64-bit) ---------- */

int sigemptyset64(u64 *set) {
  if (!set) return -1;
  *set = 0;
  return 0;
}

int sigfillset64(u64 *set) {
  if (!set) return -1;
  *set = ~0ULL;
  return 0;
}

int sigaddset64(u64 *set, int sig) {
  if (!set || sig < 1 || sig > 64) return -1;
  *set |= 1ULL << (sig - 1);
  return 0;
}

int sigdelset64(u64 *set, int sig) {
  if (!set || sig < 1 || sig > 64) return -1;
  *set &= ~(1ULL << (sig - 1));
  return 0;
}

int sigismember64(const u64 *set, int sig) {
  if (!set || sig < 1 || sig > 64) return -1;
  return (int)((*set >> (sig - 1)) & 1ULL);
}

/* ---------- socket syscall wrappers ---------- */

int accept4(int fd, void *addr, unsigned *addrlen, int flags) {
  long r = sys6(NR_accept4, fd, (long)addr, (long)addrlen, flags, 0, 0);
  return (int)sys_ret(r);
}

struct my_mmsghdr {
  void *msg_hdr;
  unsigned msg_len;
};

int recvmmsg(int fd, void *mmsg, unsigned vlen, unsigned flags, void *timeout) {
  long r = sys6(NR_recvmmsg, fd, (long)mmsg, vlen, flags, (long)timeout, 0);
  return (int)sys_ret(r);
}

long vmsplice(int fd, const void *iov, unsigned long nr_segs, unsigned flags) {
  long r = sys6(NR_vmsplice, fd, (long)iov, nr_segs, flags, 0, 0);
  return sys_ret(r);
}

/* ---------- mntent ---------- */

struct my_mntent {
  char *mnt_fsname;
  char *mnt_dir;
  char *mnt_type;
  char *mnt_opts;
  int mnt_freq;
  int mnt_passno;
};

struct mnt_file {
  void *fp;
  int fd;
  int used;
};

void *setmntent(const char *filename, const char *type) {
  static struct mnt_file files[4];
  int i;
  for (i = 0; i < 4; i++) {
    if (!files[i].used) {
      void *fp = fopen(filename, type);
      if (!fp) return (void *)0;
      files[i].fp = fp;
      files[i].fd = 0;
      files[i].used = 1;
      return &files[i];
    }
  }
  return (void *)0;
}

static int is_space(char c) {
  return c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

/* glibc unescapes \ooo in mount entries */
static void unescape(char *s) {
  char *r = s;
  while (*s) {
    if (s[0] == '\\' && s[1] >= '0' && s[1] <= '3' && s[2] >= '0' &&
        s[2] <= '7' && s[3] >= '0' && s[3] <= '7') {
      *r++ = (char)(((s[1] - '0') << 6) | ((s[2] - '0') << 3) | (s[3] - '0'));
      s += 4;
    } else {
      *r++ = *s++;
    }
  }
  *r = 0;
}

static char *next_field(char **pp) {
  char *p = *pp;
  char *start;
  while (*p && is_space(*p)) p++;
  if (!*p) {
    *pp = p;
    return (char *)0;
  }
  start = p;
  while (*p && !is_space(*p)) p++;
  if (*p) *p++ = 0;
  *pp = p;
  return start;
}

void *getmntent_r(void *filep, struct my_mntent *mnt, char *buf, int buflen) {
  struct mnt_file *f = (struct mnt_file *)filep;
  char *fields[6];
  int n = 0;

  if (!f || !f->used || !mnt || !buf || buflen <= 0) return (void *)0;

  for (;;) {
    if (!fgets(buf, buflen, f->fp)) return (void *)0;
    if (buf[0] == '#' || buf[0] == 0) continue;
    {
      char *p = buf;
      n = 0;
      while (n < 6) {
        char *fld = next_field(&p);
        if (!fld) break;
        fields[n++] = fld;
      }
    }
    if (n >= 4) break;
  }

  mnt->mnt_fsname = fields[0];
  mnt->mnt_dir = fields[1];
  mnt->mnt_type = fields[2];
  mnt->mnt_opts = fields[3];
  mnt->mnt_freq = n > 4 ? (int)strtod(fields[4], (char **)0) : 0;
  mnt->mnt_passno = n > 5 ? (int)strtod(fields[5], (char **)0) : 0;
  unescape(mnt->mnt_fsname);
  unescape(mnt->mnt_dir);
  unescape(mnt->mnt_type);
  unescape(mnt->mnt_opts);
  return mnt;
}

int endmntent(void *filep) {
  struct mnt_file *f = (struct mnt_file *)filep;
  if (f && f->used) {
    fclose(f->fp);
    f->used = 0;
    f->fp = 0;
  }
  return 1;
}

/* ---------- dl_iterate_phdr ----------
 * bionic 4.4 has no dl_iterate_phdr (added API 21). shadowhook/libxdl call it
 * only when the hook pipeline is exercised; report an empty module list so the
 * symbol resolves instead of failing the whole dlopen.
 */
struct dl_phdr_info_fake {
  unsigned dlpi_addr;
  const char *dlpi_name;
  const void *dlpi_phdr;
  unsigned short dlpi_phnum;
  unsigned long long dlpi_adds;
  unsigned long long dlpi_subs;
  unsigned long dlpi_tls_modid;
  void *dlpi_tls_data;
};

int dl_iterate_phdr(int (*callback)(struct dl_phdr_info_fake *, unsigned long,
                                    void *),
                    void *data) {
  (void)callback;
  (void)data;
  return 0;
}
