#ifndef BRIDGE_BRIDGE_H
#define BRIDGE_BRIDGE_H

#include <gio/gio.h>

/* One-time init of the in-module daemon (broadwayd logic without sockets).
 * Returns the app-side GIOStream (pipe A end A) for GdkBroadwayServer. */
GIOStream *bridge_daemon_init (void);

/* shm registry: app registers its heap "shm" surfaces by name; the
 * daemon-side map_named_shm looks them up. Registry never frees. */
void  bridge_shm_register (const char *name, gsize size, void *ptr);
void *bridge_shm_lookup   (const char *name, gsize size);

/* JS-facing exports (called from bridge.js via Module exports) */
void bridge_js_connect (void);                     /* browser client attach  */
void bridge_js_write   (const char *ptr, int len); /* browser -> daemon bytes */
int  bridge_js_poll    (void);                     /* pending daemon->JS bytes */
const char *bridge_js_poll_ptr (void);             /* pointer to them */
int  bridge_frame      (void);                     /* one nonblocking main-loop pass */

#endif
