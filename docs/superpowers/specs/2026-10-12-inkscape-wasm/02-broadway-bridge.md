# Leg B — The Broadway Bridge

Goal: eliminate Broadway's process/socket boundary so the GDK Broadway
backend, the `broadwayd` relay logic, and the `broadway.js` browser client
all live in one browser tab, connected by in-memory buffers instead of
Unix sockets and WebSockets. This is the novel part of the port and the
T2 make-or-break spike.

## What stock Broadway does

```
GTK app process                              browser
┌────────────────────────┐                  ┌──────────────┐
│ GDK broadway backend   │  unix socket     │ broadway.js  │
│ (gdkbroadway-server.c, │ ───────────────► │ (canvas, DOM │
│  gdkbroadway-window.c) │                  │  input)      │
└────────────────────────┘        │          └──────▲───────┘
                                  ▼                 │ WebSocket
                          ┌─────────────────────────┴────┐
                          │ broadwayd (separate process) │
                          │ broadwayd.c + broadway-server │
                          │ serves client over HTTP+WS    │
                          └───────────────────────────────┘
```

Three seams to patch:

1. **App side**: GDK's broadway backend opens a `GSocket` to broadwayd
   (`_gdk_broadway_server_connect`) and sends/receives protocol messages.
2. **Daemon side**: `broadwayd` accepts that connection and relays/
   rewrites messages; it also serves `broadway.js` and speaks WebSocket
   to it.
3. **Client side**: `broadway.js` connects with `new WebSocket(...)` and
   renders protocol messages into DOM/canvas.

## Design: the byte pipe

`bridge/` (our code, not upstream):

- **`bridge/bytepipe.c`** — a pair of in-memory SPSC ring buffers acting
  as a bidirectional byte stream:

  ```
  app-GDK  ──send buffer A──►  relay/JS side
  relay/JS ──send buffer B──►  app-GDK
  ```

  Each direction is a plain malloc'd ring with a write index, read index,
  and a "data available" flag. No locks — single-threaded module.

- **App-side seam**: rather than emulating fd/socket semantics, patch
  GDK's broadway server connection at the *message* level
  (`gdk_broadway_socket_send` / the `GSocketConnection` read/write calls in
  `gdkbroadway-server.c`) to write into / read from byte pipe A. Where GDK
  installs a `GSource` waiting on socket readability, install our
  `BridgeSource` (a `GSource` whose `check()` returns the pipe's
  data-available flag; dispatched from JS — see main loop below).

- **Daemon side**: compile `broadwayd.c` + `broadway-server.c` + protocol
  sources from the GTK tree into the module. Patch their socket accept and
  client-read/write calls the same way: the single "client connection" is
  byte pipe A (to the app) and byte pipe B (to the browser client).
  broadwayd's HTTP-serving of `broadway.js` is dropped — the harness page
  loads `broadway.js` directly as a `<script>`.

- **JS side (`bridge/bridge.js`)**: a `BridgeSocket` class with the same
  interface `broadway.js` expects from `WebSocket` (`send()`, `onmessage`,
  `onopen`, `onclose`). `send()` calls into the module (an exported
  `bridge_write()`), writing into byte pipe B. An exported
  `bridge_poll_js()` (called from the page's rAF tick) drains pipe B into
  `onmessage` callbacks. A minimal patch to `broadway.js` swaps
  `new WebSocket(...)` for `new BridgeSocket()` — the protocol bytes are
  untouched.

**Why message-level patching, not fd emulation**: emscripten's socket
layer and `poll()` over virtual fds is fragile for a bidi stream with
glib sources watching it. Patching at the GSocket call sites in two GTK
files is a smaller, more auditable diff. Fallback if the call sites turn
out to be more tangled than expected: implement a custom emscripten POSIX
fd device (both approaches stay inside this leg's scope).

## GLib main loop ↔ browser loop (risk #2)

glib's main loop blocks in `g_poll()` on fds; the browser forbids
blocking. Plan:

- Build glib with a patched `g_poll()` compiled under
  `-sASYNCIFY`-friendly rules: it calls an `emscripten_sleep`-style
  "wait until event" intrinsic that suspends the module until the page
  wakes it (`Asyncify.handleSleep`), then reports readiness of the
  bridge pipes and glib's timer fds.
- The page drives wakeups: one `requestAnimationFrame` tick per frame
  calls `bridge_tick()` (exported), which (a) wakes the suspended loop,
  (b) pumps byte pipe B → `broadway.js`, (c) delivers queued input events
  into pipe B via `bridge_write()`.
- Asyncify allowlist (`-sASYNCIFY_ONLY=...`) keeps the performance cost
  confined to the main-loop iteration path.
- **Fallback** (if Asyncify around g_poll proves unstable): replace
  `g_poll` with a non-blocking implementation — return immediately with
  current readiness; the page's rAF tick calls
  `g_main_context_iteration(NULL, FALSE)` on each frame. Simpler and
  always correct, at the cost of main-loop spin. Choose whichever passes
  T2 first; record the choice here.

## Input and display

- Mouse/keyboard: `broadway.js` already captures DOM events and speaks the
  protocol — untouched.
- Clipboard: broadway has a simple clipboard protocol; text-only is
  expected to work, image clipboard is a v1 non-goal.
- Window sizing: the harness page creates the broadway "browser window"
  div sized to the viewport; Inkscape's single window fills it.

## What T2 looks like

A `tests/t2/` GTK hello-world (`gtk_label_new("hello wasm")` in a
`GtkWindow`, broadway backend) compiled against the sysroot, loaded by a
stripped-down harness page, screenshot-captured by Playwright. Green =
architecture is sound. Red = kill criterion hit; we stop, document the
failure, and re-route to the salvage path (headless engine, leg D).
