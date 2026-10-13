#ifndef BRIDGE_BYTEPIPE_H
#define BRIDGE_BYTEPIPE_H

#include <gio/gio.h>

typedef struct _BridgePipe BridgePipe;

BridgePipe *bridge_pipe_new (void);
GIOStream *bridge_pipe_end_a (BridgePipe *pipe);
GIOStream *bridge_pipe_end_b (BridgePipe *pipe);

/* Fires after every write made through end A's output stream. Use to pump
 * the in-module daemon synchronously. */
void bridge_pipe_set_write_hook_a (BridgePipe *pipe,
                                   void (*hook) (void *user_data),
                                   void *user_data);

/* Move all pending end-A-readable bytes into one buffer; caller g_free()s. */
guint8 *bridge_pipe_drain_a (BridgePipe *pipe, gsize *len);

#endif
