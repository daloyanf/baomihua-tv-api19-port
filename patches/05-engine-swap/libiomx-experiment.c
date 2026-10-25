/*
 * libiomx.c — minimal pass-through OMX IL core shim for libvlc's omxil module.
 *
 * libvlc 3.0.21 (USE_IOMX build) dlopens "libiomx.so" and dlsyms six standard
 * OMX IL core symbols. Official VLC-Android 3.x builds stopped shipping that
 * shim, so the omxil module can never load and VLC always falls back to
 * avcodec software decode — even on boxes whose /system/lib carries a working
 * OMX core (e.g. HiSilicon libOMX_Core.so with OMX.hisi.* components).
 *
 * This shim restores the missing piece: it dlopens the device's own OMX core
 * and forwards every call. Graphic-buffer (direct rendering) symbols are
 * intentionally NOT exported; omxil.c treats them as optional and switches
 * back to plain byte-buffer output.
 */
#include <dlfcn.h>
#include <stddef.h>
#include <android/log.h>

typedef int OMX_ERRORTYPE;
typedef unsigned int OMX_U32;
typedef void *OMX_HANDLETYPE;
typedef char *OMX_STRING;
typedef unsigned char OMX_U8;
typedef void *OMX_PTR;

typedef struct OMX_CALLBACKTYPE OMX_CALLBACKTYPE;

static OMX_ERRORTYPE (*core_init)(void);
static OMX_ERRORTYPE (*core_deinit)(void);
static OMX_ERRORTYPE (*core_component_enum)(OMX_STRING, OMX_U32 *, OMX_U32);
static OMX_ERRORTYPE (*core_get_handle)(OMX_HANDLETYPE *, OMX_STRING, OMX_PTR, OMX_CALLBACKTYPE *);
static OMX_ERRORTYPE (*core_free_handle)(OMX_HANDLETYPE);
static OMX_ERRORTYPE (*core_get_roles)(OMX_STRING, OMX_U32 *, OMX_U8 **);

static void *core_dl;
static int core_tried;

#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, "libiomx", __VA_ARGS__)

__attribute__((constructor))
static void libiomx_loaded(void)
{
    LOGI("libiomx.so dlopened into process");
}

/* candidate OMX IL core libraries, most specific first */
static const char *core_candidates[] = {
    "libOMX_Core.so",
    "libstagefrighthw.so",
    "libOmxCore.so",
    NULL,
};

static OMX_ERRORTYPE err_load_core(void)
{
    int i;

    if (core_dl != NULL)
        return 0; /* OMX_ErrorNone */
    if (core_tried)
        return 0x80001003; /* OMX_ErrorUndefined-ish: already failed */
    core_tried = 1;

    for (i = 0; core_candidates[i] != NULL; i++) {
        void *h = dlopen(core_candidates[i], RTLD_NOW | RTLD_GLOBAL);
        if (h == NULL)
            continue;
        core_init = (OMX_ERRORTYPE (*)(void))dlsym(h, "OMX_Init");
        core_deinit = (OMX_ERRORTYPE (*)(void))dlsym(h, "OMX_Deinit");
        core_component_enum = (OMX_ERRORTYPE (*)(OMX_STRING, OMX_U32 *, OMX_U32))dlsym(h, "OMX_ComponentNameEnum");
        core_get_handle = (OMX_ERRORTYPE (*)(OMX_HANDLETYPE *, OMX_STRING, OMX_PTR, OMX_CALLBACKTYPE *))dlsym(h, "OMX_GetHandle");
        core_free_handle = (OMX_ERRORTYPE (*)(OMX_HANDLETYPE))dlsym(h, "OMX_FreeHandle");
        core_get_roles = (OMX_ERRORTYPE (*)(OMX_STRING, OMX_U32 *, OMX_U8 **))dlsym(h, "OMX_GetRolesOfComponent");
        if (core_init && core_deinit && core_component_enum && core_get_handle &&
            core_free_handle && core_get_roles) {
            core_dl = h;
            LOGI("forwarding to %s", core_candidates[i]);
            return 0;
        }
        core_init = core_deinit = core_component_enum = NULL;
        core_get_handle = core_free_handle = core_get_roles = NULL;
        dlclose(h);
    }
    LOGI("no usable OMX core found");
    return 0x80001003;
}

OMX_ERRORTYPE OMX_Init(void)
{
    OMX_ERRORTYPE e = err_load_core();
    if (e != 0)
        return e;
    return core_init();
}

OMX_ERRORTYPE OMX_Deinit(void)
{
    OMX_ERRORTYPE e = err_load_core();
    if (e != 0)
        return e;
    return core_deinit();
}

OMX_ERRORTYPE OMX_ComponentNameEnum(OMX_STRING name, OMX_U32 *len, OMX_U32 index)
{
    OMX_ERRORTYPE e = err_load_core();
    if (e != 0)
        return e;
    return core_component_enum(name, len, index);
}

OMX_ERRORTYPE OMX_GetHandle(OMX_HANDLETYPE *handle, OMX_STRING name,
                            OMX_PTR app_data, OMX_CALLBACKTYPE *callbacks)
{
    OMX_ERRORTYPE e = err_load_core();
    if (e != 0)
        return e;
    return core_get_handle(handle, name, app_data, callbacks);
}

OMX_ERRORTYPE OMX_FreeHandle(OMX_HANDLETYPE handle)
{
    OMX_ERRORTYPE e = err_load_core();
    if (e != 0)
        return e;
    return core_free_handle(handle);
}

OMX_ERRORTYPE OMX_GetRolesOfComponent(OMX_STRING name, OMX_U32 *num_roles, OMX_U8 **roles)
{
    OMX_ERRORTYPE e = err_load_core();
    if (e != 0)
        return e;
    return core_get_roles(name, num_roles, roles);
}
