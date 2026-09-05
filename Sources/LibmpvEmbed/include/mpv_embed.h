#pragma once

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Load libmpv from `dylib_path`. Safe to call more than once.
int mpv_embed_load(const char *dylib_path);
int mpv_embed_is_loaded(void);

typedef struct MpvEmbed MpvEmbed;

typedef struct MpvEmbedHooks {
    void *ctx;
    void (*on_wakeup)(void *ctx);
    void (*on_file_loaded)(void *ctx);
    void (*on_end_file_eof)(void *ctx);
    void (*on_time_pos)(void *ctx, double value);
    void (*on_duration)(void *ctx, double value);
    void (*on_pause)(void *ctx, int paused);
} MpvEmbedHooks;

MpvEmbed *mpv_embed_create(void);
int mpv_embed_initialize(MpvEmbed *embed);
void mpv_embed_destroy(MpvEmbed *embed);

int mpv_embed_set_option(MpvEmbed *embed, const char *name, const char *value);
int mpv_embed_command2(MpvEmbed *embed, const char *arg0, const char *arg1);
int mpv_embed_command3(MpvEmbed *embed, const char *arg0, const char *arg1, const char *arg2);
int mpv_embed_command4(MpvEmbed *embed, const char *arg0, const char *arg1, const char *arg2, const char *arg3);

int mpv_embed_set_flag(MpvEmbed *embed, const char *name, int value);
int mpv_embed_set_double(MpvEmbed *embed, const char *name, double value);
int mpv_embed_set_string(MpvEmbed *embed, const char *name, const char *value);
int mpv_embed_get_double(MpvEmbed *embed, const char *name, double *out);
int mpv_embed_get_flag(MpvEmbed *embed, const char *name, int *out);
char *mpv_embed_get_string(MpvEmbed *embed, const char *name);
char *mpv_embed_get_node_json(MpvEmbed *embed, const char *name);
void mpv_embed_free(void *ptr);
void mpv_embed_free_buffer(void *ptr);

int mpv_embed_observe(MpvEmbed *embed, uint64_t userdata, const char *name, int format_double_not_flag);
void mpv_embed_set_hooks(MpvEmbed *embed, MpvEmbedHooks hooks);
void mpv_embed_drain_events(MpvEmbed *embed);

/// Current GL context must be current on this thread.
int mpv_embed_create_gl(MpvEmbed *embed);
void mpv_embed_set_gl_update(MpvEmbed *embed, void (*cb)(void *), void *ctx);
int mpv_embed_render_gl(MpvEmbed *embed, int fbo, int width, int height);
void mpv_embed_report_swap(MpvEmbed *embed);
void mpv_embed_destroy_gl(MpvEmbed *embed);

#ifdef __cplusplus
}
#endif
