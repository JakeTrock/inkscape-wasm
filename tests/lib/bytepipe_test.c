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

    /* 4. drain API (used for daemon -> JS: JS is end A, so write from end B) */
    GOutputStream *bo = g_io_stream_get_output_stream (b);
    g_output_stream_write_all (bo, "12345678", 8, NULL, NULL, &error);
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
