/* Bridge: wires the in-module broadwayd relay to (a) GDK via pipe A,
 * (b) broadway.js via pipe B, (c) the page's rAF tick. */
#include "bridge.h"
#include "bytepipe.h"
#include <glib.h>
#include "broadway-server.h"

static BridgePipe *pipe_a;           /* app <-> daemon */
static BridgePipe *pipe_b;           /* daemon <-> JS  */
static gpointer    app_client;       /* BroadwayClient (opaque) */
static BroadwayServer *bserver = NULL;
static char  *js_buf = NULL;
static gsize  js_len = 0;

/* C++ apps: static ctors in the gtkmm archives touch glib (creating quarks)
 * before glib's own unprioritized constructor runs, leaving quark_ht NULL.
 * Priority 101 (first user priority) beats every archive ctor. */
extern void glib_init (void);
__attribute__((constructor(101)))
static void bridge_glib_early_init (void)
{
  glib_init ();
}

static void
pipe_a_pump (void *user)
{
  broadway_client_process_buffered (app_client);
}

GIOStream *
bridge_daemon_init (void)
{
  if (pipe_a != NULL)
    return bridge_pipe_end_a (pipe_a);

  bserver = broadway_server_new (NULL, 0, NULL, NULL, NULL);
  g_assert (bserver != NULL);
  broadway_daemon_set_server (bserver);

  pipe_a = bridge_pipe_new ();
  app_client = broadway_daemon_app_client_new (bridge_pipe_end_b (pipe_a));
  bridge_pipe_set_write_hook_a (pipe_a, pipe_a_pump, NULL);
  return bridge_pipe_end_a (pipe_a);
}

/* ---- shm registry (name -> app heap buffer; never freed) ---- */

static GHashTable *shm_registry = NULL;

void
bridge_shm_register (const char *name, gsize size, void *ptr)
{
  if (shm_registry == NULL)
    shm_registry = g_hash_table_new (g_str_hash, g_str_equal);
  g_hash_table_replace (shm_registry, g_strdup (name), ptr);
}

void *
bridge_shm_lookup (const char *name, gsize size)
{
  return shm_registry ? g_hash_table_lookup (shm_registry, name) : NULL;
}

/* ---- JS-facing exports ---- */

void
bridge_js_connect (void)
{
  if (pipe_b != NULL || bserver == NULL)
    return;
  pipe_b = bridge_pipe_new ();
  broadway_server_bridge_client_new (bserver, bridge_pipe_end_b (pipe_b));
}

void
bridge_js_write (const char *ptr, int len)
{
  GOutputStream *out;

  if (pipe_b == NULL || len <= 0)
    return;
  out = g_io_stream_get_output_stream (bridge_pipe_end_a (pipe_b));
  g_output_stream_write_all (out, ptr, (gsize) len, NULL, NULL, NULL);
}

int
bridge_js_poll (void)
{
  if (pipe_b == NULL)
    return 0;
  g_free (js_buf);
  js_buf = (char *) bridge_pipe_drain_a (pipe_b, &js_len);
  return (int) js_len;
}

const char *
bridge_js_poll_ptr (void)
{
  return js_buf ? js_buf : "";
}

int
bridge_frame (void)
{
  return g_main_context_iteration (NULL, FALSE);
}
