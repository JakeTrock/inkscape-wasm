# Leg B — Broadway Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate Broadway's process/socket boundary so GDK-broadway, the broadwayd relay logic, and broadway.js all run in one browser tab connected by in-memory pipes — gates T2 (GTK hello world, Playwright-verified) and T3 (gtkmm app with signal + cairo paint).

**Architecture:** The broadwayd relay sources (`broadwayd.c`, `broadway-server.c`, `broadway-output.c`, `broadway-buffer.c`) compile into the app module alongside our `bridge/` code. A `BridgePipe` is a pair of `GIOStream` endpoints over in-memory byte queues; pipe A links GDK to the in-module daemon (pumped synchronously on every GDK write — single thread, so the "daemon" answers round-trips immediately), pipe B links the daemon to a `BridgeSocket` JS class that speaks real WebSocket framing so the daemon's stock frame parser and `broadway.js` both work unpatched on that seam. The page drives `g_main_context_iteration(NULL, FALSE)` per rAF tick (spec's fallback main-loop design — chosen first, per spec "whichever passes T2 first").

**Tech Stack:** Emscripten 6.0.6 (existing emsdk), glib 2.88 GIOStream API, GTK 3.24.43 broadway sources from `build/src/gtk3`, Node, Playwright 1.64 (chromium already cached in `~/.cache/ms-playwright`).

## Grounding facts (verified against the GTK 3.24.43 tree — do not re-derive)

- App side (`gdkbroadway-server.c`): `_gdk_broadway_server_connect` attaches a
  `g_pollable_input_stream_create_source` on the connection's input stream
  (lines ~175-180) — **works unchanged on any GPollableInputStream**. Requests
  go out via `g_output_stream_write_all`; `gdk_broadway_server_wait_for_reply`
  uses `find_response_by_serial` + `read_some_input_blocking`
  (`g_input_stream_read`, returns available data).
- Daemon, app half (`broadwayd.c`): `client_handle_request` (static) handles all
  request types; `send_reply` writes to `client->connection`'s output stream;
  `broadway_events_got_input` writes BROADWAY_REPLY_EVENT replies to matching
  clients. `incoming_client` (lines ~376-412) is the model for creating an app
  client — it also queues the initial SCREEN_SIZE_CHANGED event. The fill loop
  in `client_fill_cb` (lines ~328-373) peeks length-prefixed requests from a
  `GBufferedInputStream`. `main()` sets the file-static `server` global.
  **Stock fill loop spins forever on a partial trailing request** (no `else
  break;`) — our glue adds the break.
- Daemon, browser half (`broadway-server.c`): `start_input`'s post-handshake
  part (lines ~1055-1078) builds `BroadwayInput` (buffer + pollable source +
  `input_data_cb`) and `BroadwayOutput` over the connection, then `start(input)`
  installs it, flushes, and resyncs windows. `broadway_server_new` sets up the
  GSocketService (skip on wasm). `broadway_server_window_update` and friends
  guard `if (server->output != NULL)` — app-before-browser is safe, and
  `start()` resyncs window contents on browser connect.
- Browser client (`broadway.js`): `connect()` does
  `ws = new WebSocket(loc, "broadway"); ws.binaryType = "arraybuffer";` —
  `handleMessage(event.data)` receives **unframed ArrayBuffers** (the browser
  strips WS framing). `sendInput` sends big-endian int32 ArrayBuffers.
- `BroadwayOutput` writes WS-framed binary (`0x82`, unmasked, 16/64-bit
  lengths). Daemon `parse_input` unframes client frames incl. masking.
  → Keep framing on both sides; do the frame/unframe in JS. Zero protocol
  patches on the browser seam.
- shm: app `_gdk_broadway_server_create_surface` → `create_random_shm`
  (36-byte name, NUL-terminated) → daemon `broadway_server_open_surface` →
  `map_named_shm` + `cairo_image_surface_create_for_data` with
  `shm_data_unmap` (munmaps!) and caches by name (`window->cached_surface`).
  → Registry keyed by name; daemon side must NOT free.
- `broadwayd.c`/`broadway-server.c` are **not** in libgdk-3.a (separate meson
  `executable('broadwayd')`) — no symbol clash when compiled into our module.
  They need generated headers: `-Ibuild/gtk3` (config.h),
  `-Ibuild/gtk3/gdk/broadway` (clienthtml.h, broadwayjs.h — already built),
  `-Ibuild/src/gtk3/gdk`, `-Ibuild/src/gtk3/gdk/broadway`.
- glib pollable sources have **no fd** — their `prepare`/`check` call
  `is_readable`. With per-rAF non-blocking iteration no poll-blocking ever
  happens, so no wakeup mechanism is needed.
- `GdkEventSource.event_poll_fd` is a dead field (never added via
  `g_source_add_poll`) — event delivery is queue-driven, no fd work needed.
- Emscripten quirks already solved in leg A (see findings): link-only
  `-sEMULATE_FUNCTION_POINTER_CASTS=1`, `-sALLOW_TABLE_GROWTH=1`,
  `-sSTACK_SIZE=8388608`, export `_main` explicitly, append
  `$SYSROOT/lib/libpthread.a` by path.

## Deviations from spec 02 (record in findings when done)

1. **Pipe A is self-pumping**: bytes written by GDK are dispatched into the
   daemon synchronously via a write hook (the daemon runs as a library in the
   same thread). Same message-level seam points as the spec, smaller diff,
   round-trip replies are always already available so `wait_for_reply` never
   actually blocks.
2. **Main loop = spec's fallback design** (non-blocking
   `g_main_context_iteration` per rAF) tried first.
3. **WS framing kept** on the daemon↔JS seam and handled by `BridgeSocket` in
   JS — avoids protocol patches in `broadway-output.c`/`parse_input`.
4. **shm = name→pointer registry + leak-by-design** (buffers never freed; the
   daemon cache may outlive the app surface). Bounded by window resizes.

## Global Constraints (inherited from leg A)

- Repo root `/data/jake/reversing/inkscape`; all paths relative to it.
- Emscripten only via `source packages/common.sh`.
- No new C dependencies; Playwright is the only new (dev-only, npm) dependency,
  installed under `tests/node_modules` with `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1`
  (chromium-1234 already in `~/.cache/ms-playwright`).
- Patches live in `patches/gtk3/`, applied by `packages/gtk3.sh` with
  reverse-dry-run guards; never in-place edits of `build/src` (edit a pristine
  extract under /tmp/opencode, then `diff`). gtk3.sh already wipes `$SRC/gtk3`
  before extract.
- Long builds (>2 min: the gtk3 rebuild in Task 2) run via
  `oc-bg <log> -- <cmd>`; foreground for the rest.
- Stamps: `build/stamps/<pkg>.ok` only after smoke test passes.
  `build/stamps/check-N.ok` for gates. Commit after every task (`git add -A`).

## File Structure

```
bridge/bytepipe.h/.c     — BridgePipe: in-memory byte pipe as two GIOStreams (new, ours)
bridge/bridge.h/.c       — daemon wiring, shm registry, JS exports (new, ours)
bridge/bridge.js         — BridgeSocket (WS-compatible) + frame pump (new, ours)
patches/gtk3/broadway-bridge-emscripten.patch        — replaces -fake-server- patch (app seam)
patches/gtk3/broadwayd-bridge-emscripten.patch       — app-client glue + main guard (new)
patches/gtk3/broadway-server-bridge-emscripten.patch — browser-client glue + no-socket ctor + shm (new)
packages/gtk3.sh         — renamed patch ref, sysroot header copy, extended wasmtest line
tests/lib/bytepipe_test.c     — Node test for Task 1
tests/lib/bridge_frame_test.mjs — Node test for Task 3 frame codec
tests/lib/wasm_harness.sh     — shared module+harness-page builder for t2/t3
tests/t2/run.sh, hello.c, t2.spec.ts — T2 gate
tests/t3/run.sh, hello.mm, t3.spec.ts — T3 gate
tests/playwright.config.ts, tests/package.json
Makefile                 — check-2, check-3
```

---

### Task 1: BridgePipe — in-memory byte pipe as GIOStream endpoints

**Files:**
- Create: `bridge/bytepipe.h`, `bridge/bytepipe.c`
- Test: `tests/lib/bytepipe_test.c`

**Interfaces:**
- Produces (used by Tasks 2, 4):

```c
BridgePipe *bridge_pipe_new (void);
GIOStream *bridge_pipe_end_a (BridgePipe *);   /* app / JS end   */
GIOStream *bridge_pipe_end_b (BridgePipe *);   /* daemon end     */
void bridge_pipe_set_write_hook_a (BridgePipe *, void (*hook)(void *), void *user_data);
guint8 *bridge_pipe_drain_a (BridgePipe *, gsize *len);  /* g_free() result */
```

- Semantics: end A's output → end B's input and vice versa. Streams implement
  `GPollableInputStream` (input side) so glib's
  `g_pollable_input_stream_create_source` / `read_nonblocking` work. The write
  hook fires after every write **from end A**. `bridge_pipe_drain_a` moves all
  pending end-A-readable bytes out in one allocation. The pipe must outlive its
  streams (bridge.c holds it for module lifetime).

- [ ] **Step 1: Write the failing test**

`tests/lib/bytepipe_test.c`:

```c
/* BridgePipe unit test: bidi byte flow, pollable semantics, write hook, drain. */
#include <gio/gio.h>
#include <string.h>
#include <stdio.h>
#include "bytepipe.h"

static int hook_count = 0;
static void on_write_a (void *user) { hook_count++; *(int*)user += 1; }

static int source_fired = 0;
static gboolean on_readable (gpointer stream, gpointer user_data) {
    GInputStream *in = G_INPUT_STREAM (stream);
    char buf[64];
    GError *error = NULL;
    gssize n = g_pollable_input_stream_read_nonblocking (
        G_POLLABLE_INPUT_STREAM (in), buf, sizeof (buf), NULL, &error);
    g_assert_no_error (error);
    g_assert_cmpint (n, ==, 5);
    g_assert (memcmp (buf, "ping!", 5) == 0);
    source_fired = 1;
    return G_SOURCE_CONTINUE;
}

int main (void) {
    BridgePipe *pipe = bridge_pipe_new ();
    GIOStream *a = bridge_pipe_end_a (pipe), *b = bridge_pipe_end_b (pipe);
    GOutputStream *ao = g_io_stream_get_output_stream (a);
    GInputStream *bi = g_io_stream_get_input_stream (b);
    GError *error = NULL;
    char buf[64];
    gssize n;

    /* 1. empty input stream is not readable; read_nonblocking -> WOULD_BLOCK */
    g_assert (!g_pollable_input_stream_is_readable (G_POLLABLE_INPUT_STREAM (bi)));
    n = g_pollable_input_stream_read_nonblocking (G_POLLABLE_INPUT_STREAM (bi),
                                                  buf, sizeof (buf), NULL, &error);
    g_assert_cmpint (n, ==, -1);
    g_assert_error (error, G_IO_ERROR, G_IO_ERROR_WOULD_BLOCK);
    g_clear_error (&error);

    /* 2. write from A -> readable at B, content round-trips */
    int hook_seen = 0;
    bridge_pipe_set_write_hook_a (pipe, on_write_a, &hook_seen);
    g_assert (g_output_stream_write_all (ao, "ping!", 5, NULL, NULL, &error));
    g_assert_no_error (error);
    g_assert (g_pollable_input_stream_is_readable (G_POLLABLE_INPUT_STREAM (bi)));
    g_assert_cmpint (hook_count, ==, 1);
    g_assert_cmpint (hook_seen, ==, 1);

    /* 3. buffered stream over the pipe (this is how broadwayd.c reads it) */
    GBufferedInputStream *bbuf = G_BUFFERED_INPUT_STREAM (g_buffered_input_stream_new (bi));
    gssize fill = g_buffered_input_stream_fill (bbuf, 4096, NULL, &error);
    g_assert_no_error (error);
    g_assert_cmpint (fill, ==, 5);
    gsize count = 0;
    guint8 *peek = g_buffered_input_stream_peek_buffer (bbuf, &count);
    g_assert_cmpint (count, ==, 5);
    g_assert (memcmp (peek, "ping!", 5) == 0);
    gssize skipped = g_input_stream_skip (G_INPUT_STREAM (bbuf), 5, NULL, &error);
    g_assert_cmpint (skipped, ==, 5);

    /* 4. drain API (used for daemon -> JS) */
    g_output_stream_write_all (ao, "12345678", 8, NULL, NULL, &error);
    gsize len = 0;
    guint8 *drained = bridge_pipe_drain_a (pipe, &len);
    g_assert_cmpint (len, ==, 8);
    g_assert (memcmp (drained, "12345678", 8) == 0);
    g_free (drained);

    /* 5. pollable source fires on write from the other end (GDK/daemon pattern) */
    GSource *src = g_pollable_input_stream_create_source (
        G_POLLABLE_INPUT_STREAM (bi), NULL);
    g_source_set_callback (src, (GSourceFunc) on_readable, NULL, NULL);
    g_source_attach (src, NULL);
    g_output_stream_write_all (ao, "ping!", 5, NULL, NULL, &error);
    while (!source_fired)
        g_main_context_iteration (NULL, FALSE);
    g_assert (source_fired);

    /* 6. blocking read returns available data (wait_for_reply pattern) */
    g_output_stream_write_all (ao, "abc", 3, NULL, NULL, &error);
    n = g_input_stream_read (bi, buf, sizeof (buf), NULL, &error);
    g_assert_no_error (error);
    g_assert_cmpint (n, ==, 3);

    g_print ("bytepipe ok (bidi, pollable, hook=%d, drain, source)\n", hook_count);
    return 0;
}
```

- [ ] **Step 2: Run it to verify it fails**

```bash
source packages/common.sh
wasmtest bytepipe tests/lib/bytepipe_test.c bridge/bytepipe.c \
  -Ibridge $(pkg-config --cflags --libs gio-2.0)
```
Expected: FAIL — `bridge/bytepipe.h: No such file or directory`.

- [ ] **Step 3: Implement bytepipe**

`bridge/bytepipe.h`:

```c
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
```

`bridge/bytepipe.c`:

```c
/* In-memory bidirectional byte pipe presented as two GIOStream endpoints.
 * Single-threaded module: no locks. End A's writes land at end B's input
 * and vice versa. The pipe must outlive its streams (plain struct). */
#include "bytepipe.h"

typedef struct {
  GQueue chunks;   /* of GBytes */
  gsize avail;
} BridgeDir;

struct _BridgePipe {
  BridgeDir a_to_b;
  BridgeDir b_to_a;
  void (*hook_a) (void *);
  void *hook_a_data;
};

static void
dir_push (BridgeDir *dir, const void *data, gsize len)
{
  g_queue_push_tail (&dir->chunks, g_bytes_new (data, len));
  dir->avail += len;
}

/* pops up to len bytes; returns bytes copied */
static gsize
dir_pop (BridgeDir *dir, void *out, gsize len)
{
  gsize done = 0;
  while (done < len && !g_queue_is_empty (&dir->chunks))
    {
      GBytes *chunk = g_queue_peek_head (&dir->chunks);
      gsize clen = g_bytes_get_size (chunk);
      gsize take = MIN (clen, len - done);
      memcpy ((guint8 *) out + done, g_bytes_get_data (chunk, NULL), take);
      if (take == clen)
        g_bytes_unref (g_queue_pop_head (&dir->chunks));
      else
        g_queue_push_head (&dir->chunks,
                           g_bytes_new_with_free_func (
                             (guint8 *) g_bytes_get_data (chunk, NULL) + take,
                             clen - take,
                             (GDestroyNotify) g_bytes_unref, chunk));
      dir->avail -= take;
      done += take;
    }
  return done;
}

/* ---- input stream (pollable) ---- */

typedef struct {
  GInputStream parent;
  BridgePipe *pipe;
  BridgeDir *dir;        /* the direction this end reads */
} BridgeInputStream;

typedef struct {
  GInputStreamClass parent_class;
} BridgeInputStreamClass;

static GType bridge_input_stream_get_type (void);

static gssize
bridge_input_stream_read (GInputStream *stream, void *buffer, gsize count,
                          GCancellable *cancellable, GError **error)
{
  BridgeInputStream *self = (BridgeInputStream *) stream;
  gssize n = dir_pop (self->dir, buffer, count);
  if (n == 0)
    {
      /* Our contract: callers only block-read when the reply was already
       * produced synchronously. Empty means protocol desync — surface it. */
      g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_BROKEN_PIPE,
                           "bridge pipe: blocking read with no data");
      return -1;
    }
  return n;
}

static gssize
bridge_input_stream_read_nonblocking (GPollableInputStream *stream, void *buffer,
                                      gsize count, GCancellable *cancellable,
                                      GError **error)
{
  BridgeInputStream *self = (BridgeInputStream *) stream;
  if (self->dir->avail == 0)
    {
      g_set_error_literal (error, G_IO_ERROR, G_IO_ERROR_WOULD_BLOCK,
                           "bridge pipe: would block");
      return -1;
    }
  return dir_pop (self->dir, buffer, count);
}

static gboolean
bridge_input_stream_is_readable (GPollableInputStream *stream)
{
  return ((BridgeInputStream *) stream)->dir->avail > 0;
}

static GSource *
bridge_input_stream_create_source (GPollableInputStream *stream,
                                   GCancellable *cancellable)
{
  return g_pollable_source_new (G_OBJECT (stream));
}

static void
bridge_input_stream_pollable_init (GPollableInputStreamInterface *iface)
{
  iface->can_poll = (gboolean (*)(GPollableInputStream *)) (void (*) (void)) NULL;
  iface->is_readable = bridge_input_stream_is_readable;
  iface->read_nonblocking = bridge_input_stream_read_nonblocking;
  iface->create_source = bridge_input_stream_create_source;
}

static void
bridge_input_stream_init (gpointer g_ifaces, gpointer iface_data)
{
}

G_DEFINE_TYPE_WITH_CODE (BridgeInputStream, bridge_input_stream, G_TYPE_INPUT_STREAM,
                         G_IMPLEMENT_INTERFACE (G_TYPE_POLLABLE_INPUT_STREAM,
                                                bridge_input_stream_pollable_init))

static void
bridge_input_stream_class_init (BridgeInputStreamClass *klass)
{
  GInputStreamClass *ioc = G_INPUT_STREAM_CLASS (klass);
  ioc->read_fn = bridge_input_stream_read;
  ioc->close_fn = (gboolean (*)(GInputStream *, GCancellable *, GError **))
                  (void (*) (void)) NULL; /* default close is fine */
}

/* ---- output stream ---- */

typedef struct {
  GOutputStream parent;
  BridgePipe *pipe;
  BridgeDir *dir;        /* the direction this end writes into */
  gboolean from_a;       /* fire the A write hook after writes */
} BridgeOutputStream;

typedef struct {
  GOutputStreamClass parent_class;
} BridgeOutputStreamClass;

static GType bridge_output_stream_get_type (void);

static gssize
bridge_output_stream_write (GOutputStream *stream, const void *buffer, gsize count,
                            GCancellable *cancellable, GError **error)
{
  BridgeOutputStream *self = (BridgeOutputStream *) stream;
  dir_push (self->dir, buffer, count);
  if (self->from_a && self->pipe->hook_a)
    self->pipe->hook_a (self->pipe->hook_a_data);
  return count;
}

static void
bridge_output_stream_class_init (BridgeOutputStreamClass *klass)
{
  GOutputStreamClass *ooc = G_OUTPUT_STREAM_CLASS (klass);
  ooc->write_fn = bridge_output_stream_write;
}

static void
bridge_output_stream_init (BridgeOutputStream *self) {}

G_DEFINE_TYPE (BridgeOutputStream, bridge_output_stream, G_TYPE_OUTPUT_STREAM)

/* ---- pipe ---- */

BridgePipe *
bridge_pipe_new (void)
{
  return g_new0 (BridgePipe, 1);
}

static GIOStream *
make_end (BridgePipe *pipe, BridgeDir *read_dir, BridgeDir *write_dir,
          gboolean from_a)
{
  BridgeInputStream *in = g_object_new (bridge_input_stream_get_type (), NULL);
  BridgeOutputStream *out = g_object_new (bridge_output_stream_get_type (), NULL);
  in->pipe = pipe;  in->dir = read_dir;
  out->pipe = pipe; out->dir = write_dir; out->from_a = from_a;
  return g_simple_io_stream_new (G_INPUT_STREAM (in), G_OUTPUT_STREAM (out));
}

GIOStream *
bridge_pipe_end_a (BridgePipe *pipe)
{
  return make_end (pipe, &pipe->b_to_a, &pipe->a_to_b, TRUE);
}

GIOStream *
bridge_pipe_end_b (BridgePipe *pipe)
{
  return make_end (pipe, &pipe->a_to_b, &pipe->b_to_a, FALSE);
}

void
bridge_pipe_set_write_hook_a (BridgePipe *pipe, void (*hook) (void *), void *user_data)
{
  pipe->hook_a = hook;
  pipe->hook_a_data = user_data;
}

guint8 *
bridge_pipe_drain_a (BridgePipe *pipe, gsize *len)
{
  gsize n = pipe->b_to_a.avail;
  guint8 *buf = g_malloc (n ? n : 1);
  dir_pop (&pipe->b_to_a, buf, n);
  *len = n;
  return buf;
}
```

**Notes for the implementer (wasm strict signatures):**
- `can_poll` must return TRUE. The cast-expression above is wrong to copy
  blindly — implement it properly:
  `static gboolean bridge_input_can_poll (GPollableInputStream *s) { return TRUE; }`
  and assign `iface->can_poll = bridge_input_can_poll;`. (Shown this way to
  keep the listing compact — write the real function.)
- Same for `close_fn`: simply omit the assignment (base class handles close).
- `G_DEFINE_TYPE_WITH_CODE` for GInputStream subclasses with an interface:
  follow the standard glib pattern; `bridge_input_stream_init` should be a
  normal instance init (can be empty), not an iface init — fix the listing
  accordingly. The register_typedef dance (`static GType ..._get_type`) is
  generated by the macro.
- If `g_pollable_source_new` is not exported (it is, in `<gio/gio.h>`), fall
  back to leaving `create_source` NULL and let
  `g_pollable_input_stream_create_source` build the default source — both are
  correct; test step 5 verifies whichever is active.

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: `PASS: bytepipe` and the log line
`bytepipe ok (bidi, pollable, hook=1, drain, source)` — the printf output MUST
be in the log (vacuous-PASS rule from findings).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "leg B: BridgePipe — in-memory byte pipe as pollable GIOStream endpoints + node test"
```

---

### Task 2: Daemon in a module — glue patches + bridge.c + gtk3 rebuild

This task makes the **existing** Node gtk3 smoke test run through the real
broadwayd relay logic over pipe A (no browser yet) — a full in-process
app↔daemon round-trip before any JS exists.

**Files:**
- Create: `bridge/bridge.h`, `bridge/bridge.c`
- Create: `patches/gtk3/broadwayd-bridge-emscripten.patch`,
          `patches/gtk3/broadway-server-bridge-emscripten.patch`
- Replace: `patches/gtk3/broadway-fake-server-emscripten.patch` →
           `patches/gtk3/broadway-bridge-emscripten.patch` (delete old)
- Modify: `packages/gtk3.sh`
- Test: existing `tests/lib/gtk3_test.c` (unchanged — it must still pass)

**Interfaces:**
- Consumes: Task 1's `bridge/bytepipe.h` API.
- Produces (declared in `bridge/bridge.h`, implemented in `bridge/bridge.c`):

```c
GIOStream *bridge_daemon_init (void);
void  bridge_shm_register (const char *name, gsize size, void *ptr);
void *bridge_shm_lookup   (const char *name, gsize size);
void bridge_js_connect (void);
void bridge_js_write (const char *ptr, int len);
int  bridge_js_poll (void);
const char *bridge_js_poll_ptr (void);
int  bridge_frame (void);
```

- Produces (added to `build/src/gtk3/gdk/broadway/broadway-server.h` by patch,
  used by bridge.c):

```c
#ifdef __EMSCRIPTEN__
void     broadway_daemon_set_server      (BroadwayServer *server);
gpointer broadway_daemon_app_client_new  (GIOStream *connection);
void     broadway_client_process_buffered (gpointer client);
void     broadway_server_bridge_client_new (BroadwayServer *server, GIOStream *connection);
#endif
```

- [ ] **Step 1: Set up the pristine tree for patch generation**

```bash
source packages/common.sh
rm -rf /tmp/opencode/gtk3-pristine && mkdir -p /tmp/opencode/gtk3-pristine
tar -xf "$DL/gtk+-3.24.43.tar.xz" -C /tmp/opencode/gtk3-pristine
cd /tmp/opencode/gtk3-pristine/gtk+-3.24.43
for p in no-to-pixdata no-tool-install-emscripten no-print-backend-module \
         iface-init-signatures filechooser-delegate-calls; do
  patch -p1 < "$ROOT/patches/gtk3/$p.patch"
done
cp -r gdk/broadway /tmp/opencode/base-broadway
```

All three new patches are generated by diffing `/tmp/opencode/base-broadway`
against the edited tree (per-file), with `--label a/...` / `--label b/...`
headers so `-p1` applies from the gtk+ root.

- [ ] **Step 2: Edit `gdkbroadway-server.c` (app seam — replaces the fake-server patch)**

In the pristine tree's `gdk/broadway/gdkbroadway-server.c`:

a. Add after the existing includes:

```c
#ifdef __EMSCRIPTEN__
#include <bridge.h>
#endif
```

b. Delete the two struct fields `last_request_type` and `next_fake_window_id`
   (fake-patch only; new patch is based on pristine, so simply do not add
   them).

c. In `_gdk_broadway_server_connect`, at the top of the function body (before
   the `if (display == NULL)` block), add:

```c
#ifdef __EMSCRIPTEN__
  /* wasm: the daemon lives in this module. bridge_daemon_init() builds it and
   * hands us pipe A (app end); the stock pollable-source attach below works
   * on our stream unchanged. */
  server = g_object_new (GDK_TYPE_BROADWAY_SERVER, NULL);
  server->connection = bridge_daemon_init ();

  in = g_io_stream_get_input_stream (G_IO_STREAM (server->connection));
  pollable = G_POLLABLE_INPUT_STREAM (in);

  source = g_pollable_input_stream_create_source (pollable, NULL);
  g_source_attach (source, NULL);
  g_source_set_callback (source, (GSourceFunc)input_available_cb, server, NULL);

  return server;
#endif
```

(No synthesized replies, no fake configure-notifies, no fake window ids — the
real daemon produces all of them. Verify by reading the *pristine* function
that variable names `in`, `pollable`, `source` match its declarations; if the
pristine function declares them later/inline, hoist minimal declarations.)

d. In `map_named_shm` (the ~line 603 static), replace the `#ifdef G_OS_UNIX`
   branch with an emscripten branch **first**:

```c
#if defined(__EMSCRIPTEN__)
  /* wasm: no shm — heap buffer registered by name so the in-module daemon
   * can map the same memory. */
  *is_shm = FALSE;
  {
    gpointer ptr = g_malloc0 (size);
    bridge_shm_register (name, size, ptr);
    return ptr;
  }
#elif defined(G_OS_UNIX)
```

e. In `shm_data_destroy` (~line 756), before the `#ifdef G_OS_UNIX`:

```c
#ifdef __EMSCRIPTEN__
  /* wasm: buffer stays alive — the daemon may still cache it by name.
   * shortcut: bounded leak (one buffer per window resize), revisit in Leg C+. */
  g_free (data);
  return;
#endif
```

f. `wait_for_reply`, `gdk_broadway_server_send_message_with_size`,
   `_gdk_broadway_server_create_window`, `_gdk_broadway_server_window_move_resize`:
   no emscripten code at all (stock paths).

Generate the patch:

```bash
cd /tmp/opencode/gtk3-pristine/gtk+-3.24.43
diff -u --label a/gdk/broadway/gdkbroadway-server.c \
        --label b/gdk/broadway/gdkbroadway-server.c \
        /tmp/opencode/base-broadway/gdkbroadway-server.c \
        gdk/broadway/gdkbroadway-server.c \
        > "$ROOT/patches/gtk3/broadway-bridge-emscripten.patch"
git -C "$ROOT" rm "$ROOT/patches/gtk3/broadway-fake-server-emscripten.patch"
```

- [ ] **Step 3: Edit `broadwayd.c` (app-client glue)**

a. Wrap `main` in `#ifndef __EMSCRIPTEN__ ... #endif` (the whole function).

b. Append at end of file:

```c
#ifdef __EMSCRIPTEN__

/* ---- wasm bridge glue: in-module app "client" without a socket ---- */

void
broadway_daemon_set_server (BroadwayServer *s)
{
  server = s;
}

BroadwayClient *
broadway_daemon_app_client_new (GIOStream *connection)
{
  BroadwayClient *client;
  GInputStream *input;
  BroadwayInputMsg ev = { {0} };

  client = g_new0 (BroadwayClient, 1);
  client->id = client_id_count++;
  client->connection = g_object_ref (connection);

  input = g_io_stream_get_input_stream (G_IO_STREAM (client->connection));
  client->in = (GBufferedInputStream *)g_buffered_input_stream_new (input);

  clients = g_list_prepend (clients, client);

  /* initial resize notify (mirrors incoming_client) */
  ev.base.type = BROADWAY_EVENT_SCREEN_SIZE_CHANGED;
  ev.base.serial = broadway_server_get_next_serial (server) - 1;
  ev.base.time = broadway_server_get_last_seen_time (server);
  broadway_server_get_screen_size (server,
                                   &ev.screen_resize_notify.width,
                                   &ev.screen_resize_notify.height);
  broadway_events_got_input (&ev, client->id);

  return client;
}

void
broadway_client_process_buffered (BroadwayClient *client)
{
  guint32 size;
  gsize count, remaining;
  guint8 *buffer;
  gssize res;

  res = g_buffered_input_stream_fill (client->in, 4 * 1024, NULL, NULL);
  if (res <= 0)
    return;

  buffer = (guint8 *)g_buffered_input_stream_peek_buffer (client->in, &count);

  remaining = count;
  while (remaining >= sizeof (guint32))
    {
      memcpy (&size, buffer, sizeof (guint32));

      if (size <= remaining)
        {
          client_handle_request (client, (BroadwayRequest *)buffer);
          remaining -= size;
          buffer += size;
        }
      else
        break; /* stock client_fill_cb spins here on a partial tail */
    }

  g_input_stream_skip (G_INPUT_STREAM (client->in), count - remaining, NULL, NULL);
}

#endif /* __EMSCRIPTEN__ */
```

(`server`, `clients`, `client_id_count`, `client_handle_request` are the
file's existing statics — the glue must be in this file to reach them.)

- [ ] **Step 4: Edit `broadway-server.c` + `broadway-server.h` (browser-client glue, no-socket ctor, shm)**

`broadway-server.c`:

a. Add after the includes:

```c
#ifdef __EMSCRIPTEN__
#include <bridge.h>
#endif
```

b. At the top of `broadway_server_new` (check the exact signature in
   `broadway-server.h` first and pass through whatever it declares):

```c
#ifdef __EMSCRIPTEN__
  /* wasm: no HTTP/socket service — the bridge connects the app and the
   * browser client in-memory. */
  return g_object_new (BROADWAY_TYPE_SERVER, NULL);
#endif
```

c. In `map_named_shm` (~line 832), same pattern as the app side:

```c
#ifdef __EMSCRIPTEN__
  return bridge_shm_lookup (name, size);
#else
  ... stock body ...
#endif
```

d. In `shm_data_unmap` (~line 1800), at the top:

```c
#ifdef __EMSCRIPTEN__
  /* wasm: buffer is owned by the app-side registry — never unmap. */
  g_free (data);
  return;
#endif
```

e. Append at end of file:

```c
#ifdef __EMSCRIPTEN__

void
broadway_server_bridge_client_new (BroadwayServer *server,
                                   GIOStream *connection)
{
  BroadwayInput *input;
  GInputStream *in;

  /* mirrors start_input()'s post-handshake path, minus HTTP/WebSocket */
  input = g_new0 (BroadwayInput, 1);
  input->server = server;
  input->connection = g_object_ref (connection);
  input->buffer = g_byte_array_new ();

  input->output =
    broadway_output_new (g_io_stream_get_output_stream (connection), 0);

  in = g_io_stream_get_input_stream (input->connection);
  input->source = g_pollable_input_stream_create_source (G_POLLABLE_INPUT_STREAM (in), NULL);
  g_source_set_callback (input->source, (GSourceFunc)input_data_cb, input, NULL);
  g_source_attach (input->source, NULL);

  start (input);

  parse_input (input);
}

#endif /* __EMSCRIPTEN__ */
```

`broadway-server.h`: add the `#ifdef __EMSCRIPTEN__` declarations listed in
this task's Interfaces block (with `#include <gio/gio.h>` guarded or assumed
present — check what the header already includes).

Generate the two patches like Step 2 (labels `a/gdk/broadway/broadwayd.c` etc.),
named `broadwayd-bridge-emscripten.patch` and
`broadway-server-bridge-emscripten.patch`.

- [ ] **Step 5: Write `bridge/bridge.h` and `bridge/bridge.c`**

`bridge/bridge.h`: exactly the Interfaces block above, with include guards and
`#include <gio/gio.h>`.

`bridge/bridge.c`:

```c
/* Bridge: wires the in-module broadwayd relay to (a) GDK via pipe A,
 * (b) broadway.js via pipe B, (c) the page's rAF tick. */
#include "bridge.h"
#include "bytepipe.h"
#include <glib.h>
#include "broadway-server.h"

static BridgePipe *pipe_a;           /* app <-> daemon */
static BridgePipe *pipe_b;           /* daemon <-> JS  */
static gpointer    app_client;       /* BroadwayClient (opaque) */
static BroadwayServer *bserver;
static char  *js_buf = NULL;
static gsize  js_len = 0;

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
```

- [ ] **Step 6: Update `packages/gtk3.sh`**

a. Replace the fake-server patch lines with the three new patches (same
   reverse-dry-run guard pattern):

```bash
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/broadway-bridge-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/broadway-bridge-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/broadwayd-bridge-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/broadwayd-bridge-emscripten.patch"
patch -d "$SRC/gtk3" -p1 -R --dry-run -f < "$PATCHES/gtk3/broadway-server-bridge-emscripten.patch" >/dev/null 2>&1 \
  || patch -d "$SRC/gtk3" -p1 < "$PATCHES/gtk3/broadway-server-bridge-emscripten.patch"
```

b. Before `meson setup`, install the bridge headers into the sysroot (gdk and
   daemon sources `#include <bridge.h>`):

```bash
mkdir -p "$SYSROOT/include" && cp "$ROOT"/bridge/*.h "$SYSROOT/include/"
```

c. Replace the final wasmtest line so the smoke test links the bridge + daemon
   sources (the gtk3 test now exercises the real in-process daemon over pipe
   A, no browser):

```bash
DAEMON_SRC="$SRC/gtk3/gdk/broadway"
wasmtest gtk3 gtk3_test.c bridge/bytepipe.c bridge/bridge.c \
  "$DAEMON_SRC/broadwayd.c" "$DAEMON_SRC/broadway-server.c" \
  "$DAEMON_SRC/broadway-buffer.c" "$DAEMON_SRC/broadway-output.c" \
  -I"$BUILD/gtk3" -I"$BUILD/gtk3/gdk/broadway" -I"$SRC/gtk3/gdk" -I"$SRC/gtk3/gdk/broadway" \
  $(pkg-config --static --cflags --libs gtk+-3.0) -lpthread
```

- [ ] **Step 7: Rebuild gtk3 (background — full gdk/gtk rebuild, the patch touches a compiled header consumer)**

```bash
rm build/stamps/gtk3.ok
oc-bg build/logs/gtk3-bridge -- make pkg-gtk3
# later: tail build/logs/gtk3-bridge.log — expect "PASS: gtk3"
```

Expected: `PASS: gtk3` with the gtk3_test.c printf line
`gtk-broadway ok (display GdkBroadwayDisplay, drew 1 frames)` (or more frames)
present in the log. This now proves: connect → daemon init → pipe A round
trips (NEW_WINDOW, SYNC) → draw → UPDATE → shm registry → daemon window cache
— all in Node, no browser.

If it fails: check the log for `bridge pipe: blocking read` (protocol desync —
compare request/reply serials), `Failed to map shm` (registry mismatch), or
wasm signature traps (`null function or function signature mismatch` — fix at
the specific call site per findings).

- [ ] **Step 8: Commit**

```bash
git add -A && git commit -m "leg B: in-module broadwayd daemon over pipe A — real relay in the gtk3 node smoke test (fake-server patch replaced)"
```

---

### Task 3: bridge.js — BridgeSocket + frame pump

**Files:**
- Create: `bridge/bridge.js`
- Test: `tests/lib/bridge_frame_test.mjs`

**Interfaces:**
- Consumes: module exports `_bridge_js_connect`, `_bridge_js_write`,
  `_bridge_js_poll`, `_bridge_js_poll_ptr` (Task 2), `window.__bridge_mod`
  (set by the harness page, Task 4).
- Produces: global `BridgeSocket` class (WebSocket subset:
  `send`, `onopen`, `onclose`, `onmessage`, `binaryType`) used by patched
  broadway.js; global `pumpDaemon()` called by the harness rAF loop. Frame
  codec also exported as `module.exports` when running under Node (test only).

- [ ] **Step 1: Write the failing test**

`tests/lib/bridge_frame_test.mjs` (loads the codec out of bridge.js):

```js
// Frame codec round-trip: buildClientFrame -> parseServerFrames.
import { readFileSync } from 'node:fs';
const src = readFileSync(new URL('../../bridge/bridge.js', import.meta.url), 'utf8');
const mod = await import('data:text/javascript,' +
  encodeURIComponent(src.replace(/^\s*module\.exports.*$/m, '')
    + '\nexport { buildClientFrame, parseServerFrames, concatBytes };'));

function fr(str) { return new TextEncoder().encode(str); }

// one small frame
let f = mod.buildClientFrame(fr('hello'));
let out = mod.parseServerFrames(new Uint8Array(0), f);
console.assert(out.frames.length === 1 && new TextDecoder().decode(out.frames[0]) === 'hello',
  'small frame roundtrip');
console.assert(out.rest.length === 0, 'no rest');

// two frames in one buffer, split across parse calls
f = mod.concatBytes(mod.buildClientFrame(fr('ab')), mod.buildClientFrame(fr('cd')));
let p1 = mod.parseServerFrames(new Uint8Array(0), f.subarray(0, 5)); // partial
console.assert(p1.frames.length === 0, 'partial not delivered');
let p2 = mod.parseServerFrames(p1.rest, f.subarray(5));
console.assert(p2.frames.length === 2 &&
  new TextDecoder().decode(p2.frames[0]) === 'ab' &&
  new TextDecoder().decode(p2.frames[1]) === 'cd', 'two frames, split delivery');

// 16-bit extended length (200 bytes)
f = mod.buildClientFrame(new Uint8Array(200));
out = mod.parseServerFrames(new Uint8Array(0), f);
console.assert(out.frames.length === 1 && out.frames[0].length === 200, 'ext16 length');

// 64-bit extended length (70000 bytes)
f = mod.buildClientFrame(new Uint8Array(70000));
out = mod.parseServerFrames(new Uint8Array(0), f);
console.assert(out.frames.length === 1 && out.frames[0].length === 70000, 'ext64 length');

console.log('bridge frame codec ok');
```

Run: `node tests/lib/bridge_frame_test.mjs`
Expected: TypeError / syntax error (bridge.js missing).

- [ ] **Step 2: Implement bridge.js**

```js
/* BridgeSocket: WebSocket-compatible facade over the in-module Broadway
 * daemon. Real WebSocket framing in both directions so the daemon's stock
 * parse_input and BroadwayOutput framing work unpatched. */
'use strict';

function concatBytes(a, b) {
    var out = new Uint8Array(a.length + b.length);
    out.set(a, 0); out.set(b, a.length);
    return out;
}

/* client -> server frame: binary, masked (browsers always mask) */
function buildClientFrame(payload) {
    var len = payload.length;
    var headLen = 2 + 4 + (len >= 126 ? 2 : 0) + (len >= 65536 ? 6 : 0);
    var frame = new Uint8Array(headLen + len);
    var o = 0;
    frame[o++] = 0x82; /* FIN | binary */
    if (len < 126) frame[o++] = 0x80 | len;
    else if (len < 65536) { frame[o++] = 0x80 | 126; frame[o++] = len >> 8; frame[o++] = len & 0xff; }
    else { frame[o++] = 0x80 | 127; for (var i = 7; i >= 0; i--) frame[o++] = (len / Math.pow(256, i)) & 0xff; }
    for (var m = 0; m < 4; m++) frame[o++] = (Math.random() * 256) | 0;
    var mask = frame.subarray(o - 4, o);
    for (var i = 0; i < len; i++) frame[o + i] = payload[i] ^ mask[i % 4];
    return frame;
}

/* server -> client: parse all complete frames out of (prevRest + chunk).
 * Returns { frames: [Uint8Array...], rest: Uint8Array }. */
function parseServerFrames(prevRest, chunk) {
    var rx = concatBytes(prevRest, chunk);
    var frames = [];
    while (rx.length >= 2) {
        var opcode = rx[0] & 0x0f;
        var len = rx[1] & 0x7f;
        var off = 2;
        if (len === 126) {
            if (rx.length < 4) break;
            len = (rx[2] << 8) | rx[3]; off = 4;
        } else if (len === 127) {
            if (rx.length < 10) break;
            len = 0;
            for (var i = 0; i < 8; i++) len = len * 256 + rx[2 + i];
            off = 10;
        }
        if (rx.length < off + len) break;
        var payload = rx.slice(off, off + len);
        rx = rx.slice(off + len);
        if (opcode === 2) frames.push(payload);
        /* opcode 8 (close), 9 (ping): daemon never sends; drop */
    }
    return { frames: frames, rest: rx };
}

function BridgeSocket() {
    var self = this;
    this.binaryType = 'arraybuffer';
    this.onopen = null; this.onclose = null; this.onmessage = null;
    this._rx = new Uint8Array(0);
    var mod = window.__bridge_mod;
    mod._bridge_js_connect();
    setTimeout(function () {
        if (self.onopen) self.onopen();
        pumpDaemon(); /* hello/resync may already be queued */
    }, 0);
    BridgeSocket.socket = this;
}
BridgeSocket.socket = null;

BridgeSocket.prototype.send = function (data) {
    var mod = window.__bridge_mod;
    var frame = buildClientFrame(new Uint8Array(data));
    var buf = mod._malloc(frame.length);
    mod.HEAPU8.set(frame, buf);
    mod._bridge_js_write(buf, frame.length);
    mod._free(buf);
};

/* Drain daemon -> JS bytes and deliver complete frames to onmessage. */
function pumpDaemon() {
    var mod = window.__bridge_mod;
    if (!mod || !BridgeSocket.socket) return;
    var len = mod._bridge_js_poll();
    if (len <= 0) return;
    var ptr = mod._bridge_js_poll_ptr();
    var chunk = mod.HEAPU8.slice(ptr, ptr + len); /* copies out of wasm heap */
    var sock = BridgeSocket.socket;
    if (!sock.onmessage) { sock._rx = new Uint8Array(0); return; }
    var res = parseServerFrames(sock._rx, chunk);
    sock._rx = res.rest;
    for (var i = 0; i < res.frames.length; i++)
        sock.onmessage({ data: res.frames[i].buffer }); /* ArrayBuffer, like a real WS */
}

if (typeof module !== 'undefined' && typeof module.exports !== 'undefined')
    module.exports = { buildClientFrame: buildClientFrame,
                       parseServerFrames: parseServerFrames,
                       concatBytes: concatBytes };
```

(The Node test strips the CommonJS export line and imports the pure functions
via a data: URL — adjust the strip regex if the file layout changes.)

- [ ] **Step 3: Run the test**

`node tests/lib/bridge_frame_test.mjs`
Expected: `bridge frame codec ok`, exit 0. If the data:-URL import hack fights
you, switch the test to `createRequire` + `require('../../bridge/bridge.js')`
(bridge.js has no browser-only references at module top level — `window` is
only touched inside functions).

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "leg B: BridgeSocket — WebSocket-compatible facade with real WS framing + node codec test"
```

---

### Task 4: T2 gate — GTK hello world in a browser tab (make check-2)

**Files:**
- Create: `tests/lib/wasm_harness.sh`, `tests/t2/run.sh`, `tests/t2/hello.c`,
          `tests/t2/index.html`, `tests/t2/t2.spec.ts`,
          `tests/playwright.config.ts`, `tests/package.json`
- Modify: `Makefile`

**Interfaces:**
- Consumes: everything from Tasks 1-3.
- Produces: `make check-2` → stamp `build/stamps/check-2.ok`; artifact
  `build/t2/t2-shot.png`; shared harness builder used by Task 5:

```bash
# tests/lib/wasm_harness.sh — source it, then:
# build_harness <name> <src-file> [extra compile args...]
#   compiles <src> + bridge + daemon sources into build/<name>/<name>.js
#   (MODULARIZE, EXIT_RUNTIME=0, browser preload of tests/fixtures)
#   and writes build/<name>/index.html from tests/<name>/index.html with
#   <name>.js + bridge.js + broadway.js (WebSocket line sed-swapped) copied in.
```

- [ ] **Step 1: Write the shared harness builder**

`tests/lib/wasm_harness.sh`:

```bash
#!/usr/bin/env bash
# tests/lib/wasm_harness.sh — build a broadway-bridge test module + harness
# page into build/<name>/. Source from tests/<name>/run.sh after common.sh.
set -euo pipefail

build_harness() { # build_harness <name> <src> [extra args...]
  local name="$1" src="$2"; shift 2
  local out="$BUILD/$name"
  local daemon="$SRC/gtk3/gdk/broadway"
  mkdir -p "$out"

  local comp=emcc; case "$src" in *.cpp|*.cc|*.mm) comp=em++;; esac

  "$comp" "$ROOT/$src" "$ROOT/bridge/bytepipe.c" "$ROOT/bridge/bridge.c" \
    "$daemon/broadwayd.c" "$daemon/broadway-server.c" \
    "$daemon/broadway-buffer.c" "$daemon/broadway-output.c" \
    -o "$out/$name.js" \
    -O1 -g1 -ffunction-sections -fdata-sections -fexceptions -frtti \
    -I"$BUILD/gtk3" -I"$BUILD/gtk3/gdk/broadway" \
    -I"$SRC/gtk3/gdk" -I"$SRC/gtk3/gdk/broadway" \
    -sALLOW_MEMORY_GROWTH -sEXIT_RUNTIME=0 -sMODULARIZE=1 -sEXPORT_NAME=Module \
    -sSTACK_SIZE=8388608 -sALLOW_TABLE_GROWTH=1 \
    -sEMULATE_FUNCTION_POINTER_CASTS=1 \
    -sEXPORTED_FUNCTIONS=_main,_malloc,_free,_bridge_frame,_bridge_js_connect,_bridge_js_write,_bridge_js_poll,_bridge_js_poll_ptr \
    --preload-file "$ROOT/tests/fixtures@/fixtures" \
    -I"$SYSROOT/include" -L"$SYSROOT/lib" "$@" "$SYSROOT/lib/libpthread.a"

  cp "$ROOT/bridge/bridge.js" "$out/"
  # broadway.js: swap the WebSocket for our in-memory BridgeSocket
  sed -e 's/ws = new WebSocket(loc, "broadway");/ws = new BridgeSocket();/' \
      "$daemon/broadway.js" > "$out/broadway.js"
  grep -q "new BridgeSocket()" "$out/broadway.js" # sed must have matched
}
```

- [ ] **Step 2: Write the T2 app**

`tests/t2/hello.c` — deterministic geometry so Playwright clicks land:

```c
/* T2: GTK hello world on broadway-over-bridge. Prints "button clicked" on
 * stdout (-> browser console) when the button is activated. main() returns;
 * the page's rAF tick drives g_main_context_iteration via bridge_frame(). */
#include <gtk/gtk.h>
#include <gdk/gdkbroadway.h>
#include <stdio.h>

static void on_clicked (GtkButton *b, gpointer user) {
    g_print ("button clicked\n");
}

int main (int argc, char **argv) {
    GtkWidget *win, *fixed, *label, *button;

    setenv ("GDK_BACKEND", "broadway", 1);
    setenv ("FONTCONFIG_FILE", "/fixtures/fonts.conf", 1);

    gtk_init (NULL, NULL);

    win = gtk_window_new (GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size (GTK_WINDOW (win), 300, 200);
    gtk_window_move (GTK_WINDOW (win), 0, 0);

    fixed = gtk_fixed_new ();
    gtk_container_add (GTK_CONTAINER (win), fixed);

    label = gtk_label_new ("hello wasm");
    gtk_fixed_put (GTK_FIXED (fixed), label, 10, 10);

    button = gtk_button_new_with_label ("click me");
    gtk_fixed_put (GTK_FIXED (fixed), button, 20, 120);
    gtk_widget_set_size_request (button, 100, 40);
    g_signal_connect (button, "clicked", G_CALLBACK (on_clicked), NULL);

    gtk_widget_show_all (win);
    return 0; /* runtime stays alive (EXIT_RUNTIME=0); page drives the loop */
}
```

`tests/t2/index.html`:

```html
<!DOCTYPE html>
<html>
<head>
<meta charset="utf8">
<title>t2</title>
<style type="text/css">body { overflow: hidden; }</style>
<script type="text/javascript" src="t2.js"></script>
<script type="text/javascript" src="bridge.js"></script>
<script type="text/javascript" src="broadway.js"></script>
</head>
<body>
<script type="text/javascript">
Module().then(function (m) {
    window.__bridge_mod = m;
    connect();                       /* broadway.js -> new BridgeSocket() */
    var tick = function () {
        m._bridge_frame();           /* one nonblocking main-loop pass */
        pumpDaemon();                /* daemon -> broadway.js frames */
        requestAnimationFrame(tick);
    };
    requestAnimationFrame(tick);
});
</script>
</body>
</html>
```

- [ ] **Step 3: Write the Playwright spec + config**

`tests/package.json`:

```json
{
  "name": "inkscape-wasm-tests",
  "private": true,
  "devDependencies": {
    "@playwright/test": "1.64.0",
    "playwright": "1.64.0"
  }
}
```

`tests/playwright.config.ts`:

```ts
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: '.',
  timeout: 60000,
  use: { viewport: { width: 1280, height: 800 }, baseURL: 'http://127.0.0.1:8823' },
  webServer: {
    command: 'python3 -m http.server 8823 --directory ../build',
    url: 'http://127.0.0.1:8823',
    reuseExistingServer: true,
  },
});
```

`tests/t2/t2.spec.ts`:

```ts
import { test, expect } from '@playwright/test';

test('T2: gtk hello world paints and click registers', async ({ page }) => {
  const clicks: string[] = [];
  page.on('console', (m) => { if (m.text().includes('button clicked')) clicks.push(m.text()); });

  await page.goto('/t2/index.html');
  await page.waitForSelector('canvas', { timeout: 20000 });
  await page.waitForTimeout(1500); // let a few frames paint

  // label text = dark pixels across all window canvases (broadway: one canvas
  // per surface, stacked; text is rasterized by pango into the window surface)
  const dark = await page.evaluate(() => {
    let n = 0;
    for (const c of document.querySelectorAll('canvas')) {
      const ctx = (c as HTMLCanvasElement).getContext('2d')!;
      if (!ctx || (c as HTMLCanvasElement).width === 0) continue;
      const d = ctx.getImageData(0, 0, (c as HTMLCanvasElement).width, (c as HTMLCanvasElement).height).data;
      for (let i = 0; i < d.length; i += 4)
        if (d[i] < 128 && d[i + 1] < 128 && d[i + 2] < 128) n++;
    }
    return n;
  });
  expect(dark).toBeGreaterThan(50);

  // button at (20,120) size (100,40) in the window at (0,0)
  await page.mouse.click(70, 140);
  await expect.poll(() => clicks.length, { timeout: 10000 }).toBeGreaterThan(0);

  await page.screenshot({ path: '../build/t2/t2-shot.png' });
});
```

- [ ] **Step 4: Write `tests/t2/run.sh` + Makefile target**

`tests/t2/run.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/wasm_harness.sh

[ -f "$TEST/../stamps/check-2.ok" ] && { echo "check-2 cached"; exit 0; }

build_harness t2 tests/t2/hello.c $(pkg-config --static --cflags --libs gtk+-3.0)

# playwright deps (browsers already cached; never download here)
if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t2/t2.spec.ts --reporter=line )

mkdir -p "$BUILD/stamps"
touch "$BUILD/stamps/check-2.ok"
echo "PASS: check-2"
```

Makefile: add `check-2` to `.PHONY` and:

```makefile
check-2: ; bash tests/t2/run.sh
```

- [ ] **Step 5: Run it**

```bash
make check-2
```
Expected: `PASS: check-2`, playwright 1 passed, `build/t2/t2-shot.png` shows
the window with "hello wasm" and the button.

Debug guidance when it fails (in likelihood order):
- **Blank page / no canvas**: open `build/t2/index.html` in a normal browser
  with devtools; check console for module load errors first, then GDK errors.
- **Canvas but no text**: fontconfig — confirm `/fixtures/fonts.conf` and
  DejaVuSans.ttf preload, and that `FONTCONFIG_FILE` env is set before
  `gtk_init` (hello.c does this).
- **No frames pumped**: add `console.log` in the tick; verify
  `window.__bridge_mod` is the resolved module (not the factory).
- **Click misses**: read the daemon window position from the screenshot; the
  button is at window-(20,120)+(100,40) and the window at (0,0); adjust if
  GTK's default position differs (then fix `gtk_window_move` — do not tune
  the test coordinates to a nondeterministic position).
- **Signature trap / crash**: per findings, fix at the specific call site.

If BOTH the non-blocking-iteration design and an Asyncify variant (wrap
`bridge_frame`'s iteration loop with `-sASYNCIFY` and a bounded inner loop)
fail, that is the T2 kill criterion → stop, document in findings, re-route to
the salvage path (spec 04).

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "leg B: T2 gate green — GTK hello world paints in browser over the broadway bridge (make check-2)"
```

---

### Task 5: T3 gate — gtkmm app with signal + cairo paint (make check-3)

**Files:**
- Create: `tests/t3/run.sh`, `tests/t3/hello.mm`, `tests/t3/index.html`, `tests/t3/t3.spec.ts`
- Modify: `Makefile`

**Interfaces:**
- Consumes: `tests/lib/wasm_harness.sh` (Task 4), gtkmm 3.24.9 from sysroot.
- Produces: `make check-3` → stamp `build/stamps/check-3.ok`; artifact
  `build/t3/t3-shot.png`.

- [ ] **Step 1: Write the app**

`tests/t3/hello.mm`:

```cpp
/* T3: gtkmm on broadway-over-bridge: signal handler fires (console log),
 * custom cairo draw paints a red rectangle at a fixed position. */
#include <gtkmm.h>
#include <gdkmm.h>
#include <cairomm/cairomm.h>
#include <cstdio>

class HelloWindow : public Gtk::Window {
public:
    HelloWindow() {
        set_default_size(300, 200);
        move(0, 0);
        put(label_, 10, 10);
        put(area_, 0, 0);
        area_.set_size_request(300, 200);
        area_.signal_draw().connect(sigc::mem_fun(*this, &HelloWindow::on_area_draw));
        button_.set_label("click me");
        put(button_, 20, 120);
        button_.set_size_request(100, 40);
        button_.signal_clicked().connect([] () { g_print("signal fired\n"); });
        show_all_children();
    }
private:
    bool on_area_draw(const Cairo::RefPtr<Cairo::Context>& cr) {
        cr->set_source_rgb(0.85, 0.1, 0.1);
        cr->rectangle(160, 20, 100, 50);
        cr->fill();
        return false; // let label/button (packed later) still render
    }
    Gtk::Label label_{"hello gtkmm"};
    Gtk::Fixed area_;
    Gtk::Button button_;
};

int main(int argc, char** argv) {
    setenv("GDK_BACKEND", "broadway", 1);
    setenv("FONTCONFIG_FILE", "/fixtures/fonts.conf", 1);
    auto app = Gtk::Application::create(argc, argv);
    HelloWindow w;
    w.show_all();
    return 0; // page drives the loop; runtime stays alive
}
```

Note: `Gtk::Fixed area_` used as a zero-size drawing layer under the label —
if Fixed-over-Fixed stacking misbehaves, drop `area_` and instead draw on the
window's own `signal_draw` (same red rectangle), keeping label + button as
direct children. The gate only needs: signal console line + red pixels.

`tests/t3/index.html`: identical to `tests/t2/index.html` with `t2.js` →
`t3.js` and title `t3`.

- [ ] **Step 2: Write the spec**

`tests/t3/t3.spec.ts`:

```ts
import { test, expect } from '@playwright/test';

test('T3: gtkmm signal fires and cairo paints', async ({ page }) => {
  const fired: string[] = [];
  page.on('console', (m) => { if (m.text().includes('signal fired')) fired.push(m.text()); });

  await page.goto('/t3/index.html');
  await page.waitForSelector('canvas', { timeout: 20000 });
  await page.waitForTimeout(1500);

  // cairo red rectangle at (160,20)+(100,50) in the window at (0,0)
  const red = await page.evaluate(() => {
    let n = 0;
    for (const c of document.querySelectorAll('canvas')) {
      const el = c as HTMLCanvasElement;
      const ctx = el.getContext('2d')!;
      if (!ctx || el.width < 200 || el.height < 80) continue;
      const d = ctx.getImageData(160, 20, 100, 50).data;
      for (let i = 0; i < d.length; i += 4)
        if (d[i] > 180 && d[i + 1] < 100 && d[i + 2] < 100) n++;
    }
    return n;
  });
  expect(red).toBeGreaterThan(1000);

  await page.mouse.click(70, 140);
  await expect.poll(() => fired.length, { timeout: 10000 }).toBeGreaterThan(0);

  await page.screenshot({ path: '../build/t3/t3-shot.png' });
});
```

- [ ] **Step 3: Write `tests/t3/run.sh` + Makefile, run**

`tests/t3/run.sh` (same shape as t2):

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source packages/common.sh
source tests/lib/wasm_harness.sh

[ -f "$BUILD/stamps/check-3.ok" ] && { echo "check-3 cached"; exit 0; }

build_harness t3 tests/t3/hello.mm $(pkg-config --static --cflags --libs gtkmm-3.0)

if [ ! -d tests/node_modules/playwright ]; then
  ( cd tests && PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1 npm install --no-fund --no-audit )
fi

( cd tests && npx playwright test t3/t3.spec.ts --reporter=line )

mkdir -p "$BUILD/stamps"
touch "$BUILD/stamps/check-3.ok"
echo "PASS: check-3"
```

Makefile: `check-3: ; bash tests/t3/run.sh` (+ .PHONY).

Run: `make check-3`
Expected: `PASS: check-3`; screenshot shows label, red rectangle, button.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "leg B: T3 gate green — gtkmm app with signal handler + cairo draw in browser (make check-3)"
```

---

### Task 6: Findings + roadmap update

**Files:**
- Modify: `docs/findings.md`, `docs/superpowers/plans/2026-10-12-inkscape-wasm-roadmap.md`

- [ ] **Step 1: Append a "Leg B / T2-T3" section to `docs/findings.md`**

Record (with evidence paths `build/logs/*`, `build/t2/t2-shot.png`):
- gate results (T2, T3: date, PASS, artifacts)
- the four deviations from spec 02 listed in this plan's header, plus:
  the `else break;` fix to broadwayd's fill loop (stock infinite-loop on
  partial tail), and the self-pumping pipe A design
- anything that fought back and how it was fixed (new quirks for the log)

- [ ] **Step 2: Update the roadmap table**

Mark row 2 (Leg B) done with gate results; confirm row 3 (Leg C) is now
unblocked.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "leg B: findings + roadmap — broadway bridge complete, T2/T3 green"
```

---

## Self-Review (done at write time)

- **Spec coverage:** byte pipe (Task 1), app-side seam (Task 2 patch a-e),
  daemon side (Task 2 patches + glue), JS side (Task 3), main loop fallback
  design (Task 4 `bridge_frame` per rAF), T2 (Task 4), T3 (Task 5), findings
  log (Task 6). Spec's "Asyncify first" is superseded by trying the fallback
  first (spec allows either order; kill criterion needs both tried — noted in
  Task 4's debug box).
- **Type consistency:** `bridge_pipe_*` names identical in Task 1/2;
  `broadway_*_bridge_*` glue names match between patches, broadway-server.h,
  and bridge.c; JS exports match bridge.h (`_bridge_js_*`, `_bridge_frame`)
  and the EXPORTED_FUNCTIONS list in the harness builder.
- **Known risks carried into execution:** bytepipe GType boilerplate listing
  is compacted (implementer notes inline cover the expansions); broadway_server_new
  argument order must be checked against broadway-server.h; the gtk3.sh
  wasmtest line assumes daemon sources compile clean with the extra -I flags
  (they compile today for broadwayd.js per leg A).
