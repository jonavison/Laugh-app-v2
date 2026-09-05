#include "mpv_embed.h"

#include "mpv/client.h"
#include "mpv/render.h"
#include "mpv/render_gl.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    void *lib;
    mpv_handle *(*create)(void);
    int (*initialize)(mpv_handle *);
    void (*terminate_destroy)(mpv_handle *);
    int (*set_option_string)(mpv_handle *, const char *, const char *);
    int (*command)(mpv_handle *, const char **);
    int (*set_property)(mpv_handle *, const char *, mpv_format, void *);
    int (*set_property_string)(mpv_handle *, const char *, const char *);
    int (*get_property)(mpv_handle *, const char *, mpv_format, void *);
    char *(*get_property_string)(mpv_handle *, const char *);
    int (*observe_property)(mpv_handle *, uint64_t, const char *, mpv_format);
    void (*set_wakeup_callback)(mpv_handle *, void (*)(void *), void *);
    mpv_event *(*wait_event)(mpv_handle *, double);
    void (*free)(void *);
    void (*free_node_contents)(mpv_node *);
    int (*render_context_create)(mpv_render_context **, mpv_handle *, mpv_render_param *);
    void (*render_context_set_update_callback)(mpv_render_context *, mpv_render_update_fn, void *);
    int (*render_context_render)(mpv_render_context *, mpv_render_param *);
    void (*render_context_report_swap)(mpv_render_context *);
    void (*render_context_free)(mpv_render_context *);
} MpvAPI;

struct MpvEmbed {
    mpv_handle *mpv;
    mpv_render_context *render;
    MpvEmbedHooks hooks;
};

static MpvAPI api;
static int api_loaded;

static void *load_sym(void *lib, const char *name) {
    void *sym = dlsym(lib, name);
    if (!sym) {
        fprintf(stderr, "[libmpv] missing symbol %s: %s\n", name, dlerror());
    }
    return sym;
}

int mpv_embed_load(const char *dylib_path) {
    if (api_loaded) {
        return 0;
    }
    if (!dylib_path || !dylib_path[0]) {
        return -1;
    }
    void *lib = dlopen(dylib_path, RTLD_NOW | RTLD_LOCAL);
    if (!lib) {
        fprintf(stderr, "[libmpv] dlopen failed: %s\n", dlerror());
        return -1;
    }
    api.lib = lib;
    api.create = load_sym(lib, "mpv_create");
    api.initialize = load_sym(lib, "mpv_initialize");
    api.terminate_destroy = load_sym(lib, "mpv_terminate_destroy");
    api.set_option_string = load_sym(lib, "mpv_set_option_string");
    api.command = load_sym(lib, "mpv_command");
    api.set_property = load_sym(lib, "mpv_set_property");
    api.set_property_string = load_sym(lib, "mpv_set_property_string");
    api.get_property = load_sym(lib, "mpv_get_property");
    api.get_property_string = load_sym(lib, "mpv_get_property_string");
    api.observe_property = load_sym(lib, "mpv_observe_property");
    api.set_wakeup_callback = load_sym(lib, "mpv_set_wakeup_callback");
    api.wait_event = load_sym(lib, "mpv_wait_event");
    api.free = load_sym(lib, "mpv_free");
    api.free_node_contents = load_sym(lib, "mpv_free_node_contents");
    api.render_context_create = load_sym(lib, "mpv_render_context_create");
    api.render_context_set_update_callback = load_sym(lib, "mpv_render_context_set_update_callback");
    api.render_context_render = load_sym(lib, "mpv_render_context_render");
    api.render_context_report_swap = load_sym(lib, "mpv_render_context_report_swap");
    api.render_context_free = load_sym(lib, "mpv_render_context_free");
    if (!api.create || !api.initialize || !api.terminate_destroy || !api.command
        || !api.set_option_string || !api.set_property || !api.get_property
        || !api.render_context_create || !api.render_context_render || !api.wait_event) {
        dlclose(lib);
        memset(&api, 0, sizeof(api));
        return -1;
    }
    api_loaded = 1;
    return 0;
}

int mpv_embed_is_loaded(void) {
    return api_loaded;
}

static void wakeup_trampoline(void *ctx) {
    MpvEmbed *embed = ctx;
    if (embed && embed->hooks.on_wakeup) {
        embed->hooks.on_wakeup(embed->hooks.ctx);
    }
}

MpvEmbed *mpv_embed_create(void) {
    if (!api_loaded) {
        return NULL;
    }
    MpvEmbed *embed = calloc(1, sizeof(*embed));
    if (!embed) {
        return NULL;
    }
    embed->mpv = api.create();
    if (!embed->mpv) {
        free(embed);
        return NULL;
    }
    return embed;
}

int mpv_embed_initialize(MpvEmbed *embed) {
    if (!embed || !embed->mpv) {
        return -1;
    }
    return api.initialize(embed->mpv);
}

void mpv_embed_destroy(MpvEmbed *embed) {
    if (!embed) {
        return;
    }
    mpv_embed_destroy_gl(embed);
    if (embed->mpv) {
        api.set_wakeup_callback(embed->mpv, NULL, NULL);
        api.terminate_destroy(embed->mpv);
    }
    free(embed);
}

int mpv_embed_set_option(MpvEmbed *embed, const char *name, const char *value) {
    if (!embed || !embed->mpv || !name || !value) {
        return -1;
    }
    return api.set_option_string(embed->mpv, name, value);
}

int mpv_embed_command2(MpvEmbed *embed, const char *arg0, const char *arg1) {
    if (!embed || !embed->mpv || !arg0) {
        return -1;
    }
    const char *args[] = {arg0, arg1, NULL};
    return api.command(embed->mpv, args);
}

int mpv_embed_command3(MpvEmbed *embed, const char *arg0, const char *arg1, const char *arg2) {
    if (!embed || !embed->mpv || !arg0) {
        return -1;
    }
    const char *args[] = {arg0, arg1, arg2, NULL};
    return api.command(embed->mpv, args);
}

int mpv_embed_command4(
    MpvEmbed *embed,
    const char *arg0,
    const char *arg1,
    const char *arg2,
    const char *arg3
) {
    if (!embed || !embed->mpv || !arg0) {
        return -1;
    }
    const char *args[] = {arg0, arg1, arg2, arg3, NULL};
    return api.command(embed->mpv, args);
}

int mpv_embed_set_flag(MpvEmbed *embed, const char *name, int value) {
    if (!embed || !embed->mpv || !name) {
        return -1;
    }
    return api.set_property(embed->mpv, name, MPV_FORMAT_FLAG, &value);
}

int mpv_embed_set_double(MpvEmbed *embed, const char *name, double value) {
    if (!embed || !embed->mpv || !name) {
        return -1;
    }
    return api.set_property(embed->mpv, name, MPV_FORMAT_DOUBLE, &value);
}

int mpv_embed_set_string(MpvEmbed *embed, const char *name, const char *value) {
    if (!embed || !embed->mpv || !name || !value) {
        return -1;
    }
    return api.set_property_string(embed->mpv, name, value);
}

int mpv_embed_get_double(MpvEmbed *embed, const char *name, double *out) {
    if (!embed || !embed->mpv || !name || !out) {
        return -1;
    }
    return api.get_property(embed->mpv, name, MPV_FORMAT_DOUBLE, out);
}

int mpv_embed_get_flag(MpvEmbed *embed, const char *name, int *out) {
    if (!embed || !embed->mpv || !name || !out) {
        return -1;
    }
    return api.get_property(embed->mpv, name, MPV_FORMAT_FLAG, out);
}

char *mpv_embed_get_string(MpvEmbed *embed, const char *name) {
    if (!embed || !embed->mpv || !name) {
        return NULL;
    }
    return api.get_property_string(embed->mpv, name);
}

void mpv_embed_free(void *ptr) {
    if (ptr && api.free) {
        api.free(ptr);
    }
}

void mpv_embed_free_buffer(void *ptr) {
    free(ptr);
}

typedef struct {
    char *data;
    size_t len;
    size_t cap;
} JsonBuf;

static int json_reserve(JsonBuf *buf, size_t extra) {
    if (buf->len + extra + 1 <= buf->cap) {
        return 0;
    }
    size_t cap = buf->cap ? buf->cap : 256;
    while (buf->len + extra + 1 > cap) {
        cap *= 2;
    }
    char *data = realloc(buf->data, cap);
    if (!data) {
        return -1;
    }
    buf->data = data;
    buf->cap = cap;
    return 0;
}

static int json_append(JsonBuf *buf, const char *text, size_t n) {
    if (json_reserve(buf, n) != 0) {
        return -1;
    }
    memcpy(buf->data + buf->len, text, n);
    buf->len += n;
    buf->data[buf->len] = 0;
    return 0;
}

static int json_append_cstr(JsonBuf *buf, const char *text) {
    return json_append(buf, text, strlen(text));
}

static int json_append_quoted(JsonBuf *buf, const char *text) {
    if (json_append_cstr(buf, "\"") != 0) {
        return -1;
    }
    if (!text) {
        return json_append_cstr(buf, "\"");
    }
    for (const unsigned char *p = (const unsigned char *)text; *p; p++) {
        char tmp[8];
        size_t n = 1;
        switch (*p) {
        case '"':
            memcpy(tmp, "\\\"", 2);
            n = 2;
            break;
        case '\\':
            memcpy(tmp, "\\\\", 2);
            n = 2;
            break;
        case '\n':
            memcpy(tmp, "\\n", 2);
            n = 2;
            break;
        case '\r':
            memcpy(tmp, "\\r", 2);
            n = 2;
            break;
        case '\t':
            memcpy(tmp, "\\t", 2);
            n = 2;
            break;
        default:
            if (*p < 0x20) {
                snprintf(tmp, sizeof(tmp), "\\u%04x", *p);
                n = 6;
            } else {
                tmp[0] = (char)*p;
                n = 1;
            }
            break;
        }
        if (json_append(buf, tmp, n) != 0) {
            return -1;
        }
    }
    return json_append_cstr(buf, "\"");
}

static int json_append_node(JsonBuf *buf, const mpv_node *node);

static int json_append_list(JsonBuf *buf, const mpv_node_list *list, int is_map) {
    if (json_append_cstr(buf, is_map ? "{" : "[") != 0) {
        return -1;
    }
    for (int i = 0; i < list->num; i++) {
        if (i > 0 && json_append_cstr(buf, ",") != 0) {
            return -1;
        }
        if (is_map) {
            if (json_append_quoted(buf, list->keys[i]) != 0) {
                return -1;
            }
            if (json_append_cstr(buf, ":") != 0) {
                return -1;
            }
        }
        if (json_append_node(buf, &list->values[i]) != 0) {
            return -1;
        }
    }
    return json_append_cstr(buf, is_map ? "}" : "]");
}

static int json_append_node(JsonBuf *buf, const mpv_node *node) {
    char tmp[64];
    switch (node->format) {
    case MPV_FORMAT_NONE:
        return json_append_cstr(buf, "null");
    case MPV_FORMAT_STRING:
        return json_append_quoted(buf, node->u.string);
    case MPV_FORMAT_FLAG:
        return json_append_cstr(buf, node->u.flag ? "true" : "false");
    case MPV_FORMAT_INT64:
        snprintf(tmp, sizeof(tmp), "%lld", (long long)node->u.int64);
        return json_append_cstr(buf, tmp);
    case MPV_FORMAT_DOUBLE:
        snprintf(tmp, sizeof(tmp), "%.17g", node->u.double_);
        return json_append_cstr(buf, tmp);
    case MPV_FORMAT_NODE_ARRAY:
        return json_append_list(buf, node->u.list, 0);
    case MPV_FORMAT_NODE_MAP:
        return json_append_list(buf, node->u.list, 1);
    default:
        return json_append_cstr(buf, "null");
    }
}

char *mpv_embed_get_node_json(MpvEmbed *embed, const char *name) {
    if (!embed || !embed->mpv || !name) {
        return NULL;
    }
    mpv_node node;
    if (api.get_property(embed->mpv, name, MPV_FORMAT_NODE, &node) < 0) {
        return NULL;
    }
    JsonBuf buf = {0};
    int ok = json_append_node(&buf, &node);
    api.free_node_contents(&node);
    if (ok != 0 || !buf.data) {
        free(buf.data);
        return NULL;
    }
    return buf.data;
}

int mpv_embed_observe(MpvEmbed *embed, uint64_t userdata, const char *name, int format_double_not_flag) {
    if (!embed || !embed->mpv || !name) {
        return -1;
    }
    mpv_format format = format_double_not_flag ? MPV_FORMAT_DOUBLE : MPV_FORMAT_FLAG;
    return api.observe_property(embed->mpv, userdata, name, format);
}

void mpv_embed_set_hooks(MpvEmbed *embed, MpvEmbedHooks hooks) {
    if (!embed) {
        return;
    }
    embed->hooks = hooks;
    if (embed->mpv) {
        api.set_wakeup_callback(embed->mpv, wakeup_trampoline, embed);
    }
}

void mpv_embed_drain_events(MpvEmbed *embed) {
    if (!embed || !embed->mpv) {
        return;
    }
    while (1) {
        mpv_event *event = api.wait_event(embed->mpv, 0);
        if (!event || event->event_id == MPV_EVENT_NONE) {
            break;
        }
        switch (event->event_id) {
        case MPV_EVENT_FILE_LOADED:
            if (embed->hooks.on_file_loaded) {
                embed->hooks.on_file_loaded(embed->hooks.ctx);
            }
            break;
        case MPV_EVENT_END_FILE: {
            mpv_event_end_file *end = event->data;
            if (end && end->reason == MPV_END_FILE_REASON_EOF && embed->hooks.on_end_file_eof) {
                embed->hooks.on_end_file_eof(embed->hooks.ctx);
            }
            break;
        }
        case MPV_EVENT_PROPERTY_CHANGE: {
            mpv_event_property *prop = event->data;
            if (!prop || !prop->name || !prop->data) {
                break;
            }
            if (strcmp(prop->name, "time-pos") == 0 && prop->format == MPV_FORMAT_DOUBLE
                && embed->hooks.on_time_pos) {
                embed->hooks.on_time_pos(embed->hooks.ctx, *(double *)prop->data);
            } else if (strcmp(prop->name, "duration") == 0 && prop->format == MPV_FORMAT_DOUBLE
                       && embed->hooks.on_duration) {
                embed->hooks.on_duration(embed->hooks.ctx, *(double *)prop->data);
            } else if (strcmp(prop->name, "pause") == 0 && prop->format == MPV_FORMAT_FLAG
                       && embed->hooks.on_pause) {
                embed->hooks.on_pause(embed->hooks.ctx, *(int *)prop->data);
            }
            break;
        }
        default:
            break;
        }
    }
}

static void *get_proc_address(void *ctx, const char *name) {
    (void)ctx;
    CFStringRef symbol = CFStringCreateWithCString(kCFAllocatorDefault, name, kCFStringEncodingASCII);
    if (!symbol) {
        return NULL;
    }
    CFBundleRef bundle = CFBundleGetBundleWithIdentifier(CFSTR("com.apple.opengl"));
    void *addr = bundle ? CFBundleGetFunctionPointerForName(bundle, symbol) : NULL;
    CFRelease(symbol);
    return addr;
}

int mpv_embed_create_gl(MpvEmbed *embed) {
    if (!embed || !embed->mpv || embed->render) {
        return embed && embed->render ? 0 : -1;
    }
    mpv_opengl_init_params gl_init = {
        .get_proc_address = get_proc_address,
        .get_proc_address_ctx = NULL,
    };
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_API_TYPE, (void *)MPV_RENDER_API_TYPE_OPENGL},
        {MPV_RENDER_PARAM_OPENGL_INIT_PARAMS, &gl_init},
        {0}
    };
    return api.render_context_create(&embed->render, embed->mpv, params);
}

void mpv_embed_set_gl_update(MpvEmbed *embed, void (*cb)(void *), void *ctx) {
    if (!embed || !embed->render) {
        return;
    }
    api.render_context_set_update_callback(embed->render, cb, ctx);
}

int mpv_embed_render_gl(MpvEmbed *embed, int fbo, int width, int height) {
    if (!embed || !embed->render || width <= 0 || height <= 0) {
        return -1;
    }
    mpv_opengl_fbo gl_fbo = {
        .fbo = fbo,
        .w = width,
        .h = height,
        .internal_format = 0,
    };
    int flip_y = 1;
    int block_for_target = 0;
    mpv_render_param params[] = {
        {MPV_RENDER_PARAM_OPENGL_FBO, &gl_fbo},
        {MPV_RENDER_PARAM_FLIP_Y, &flip_y},
        {MPV_RENDER_PARAM_BLOCK_FOR_TARGET_TIME, &block_for_target},
        {0}
    };
    return api.render_context_render(embed->render, params);
}

void mpv_embed_report_swap(MpvEmbed *embed) {
    if (!embed || !embed->render) {
        return;
    }
    api.render_context_report_swap(embed->render);
}

void mpv_embed_destroy_gl(MpvEmbed *embed) {
    if (!embed || !embed->render) {
        return;
    }
    api.render_context_set_update_callback(embed->render, NULL, NULL);
    api.render_context_free(embed->render);
    embed->render = NULL;
}
