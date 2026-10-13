/* In-memory bidirectional byte pipe presented as two GIOStream endpoints.
 * Single-threaded module: no locks. End A's writes land at end B's input and
 * vice versa. The pipe must outlive its streams (plain struct). */
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
      gconstpointer pdata = g_bytes_get_data (chunk, NULL);
      gsize clen = g_bytes_get_size (chunk);
      gsize take = MIN (clen, len - done);
      memcpy ((guint8 *) out + done, pdata, take);
      if (take == clen)
        g_bytes_unref (g_queue_pop_head (&dir->chunks));
      else
        {
          /* keep the unconsumed tail of this chunk alive in a new GBytes
           * holding a reference to the original */
          g_bytes_unref (g_queue_pop_head (&dir->chunks));
          g_queue_push_head (&dir->chunks,
                             g_bytes_new ((const guint8 *) pdata + take,
                                          clen - take));
        }
      dir->avail -= take;
      done += take;
    }
  return done;
}

/* ---- poll source: fires when the pipe's read side has data ---- */

typedef struct {
  GSource source;
  GInputStream *stream;   /* unref'd in finalize */
} BridgePollSource;

static gboolean
bridge_poll_source_is_ready (GSource *source)
{
  BridgePollSource *ps = (BridgePollSource *) source;
  return g_pollable_input_stream_is_readable (G_POLLABLE_INPUT_STREAM (ps->stream));
}

static gboolean
bridge_poll_source_prepare (GSource *source, gint *timeout)
{
  *timeout = -1;
  return bridge_poll_source_is_ready (source);
}

static gboolean
bridge_poll_source_check (GSource *source)
{
  return bridge_poll_source_is_ready (source);
}

static gboolean
bridge_poll_source_dispatch (GSource *source, GSourceFunc callback,
                             gpointer user_data)
{
  BridgePollSource *ps = (BridgePollSource *) source;
  GPollableSourceFunc func = (GPollableSourceFunc) callback;

  if (func == NULL)
    return G_SOURCE_REMOVE;
  return (*func) (G_OBJECT (ps->stream), user_data);
}

static void
bridge_poll_source_finalize (GSource *source)
{
  BridgePollSource *ps = (BridgePollSource *) source;
  g_object_unref (ps->stream);
}

static GSourceFuncs bridge_poll_source_funcs = {
  bridge_poll_source_prepare,
  bridge_poll_source_check,
  bridge_poll_source_dispatch,
  bridge_poll_source_finalize,
  NULL,
  NULL,
};

static GSource *
bridge_poll_source_new (GInputStream *stream)
{
  GSource *source;
  BridgePollSource *ps;

  source = g_source_new (&bridge_poll_source_funcs, sizeof (BridgePollSource));
  g_source_set_static_name (source, "BridgePipePoll");
  ps = (BridgePollSource *) source;
  ps->stream = g_object_ref (stream);
  return source;
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

static gboolean
bridge_input_stream_can_poll (GPollableInputStream *stream)
{
  return TRUE;
}

static gboolean
bridge_input_stream_is_readable (GPollableInputStream *stream)
{
  return ((BridgeInputStream *) stream)->dir->avail > 0;
}

static gssize
bridge_input_stream_read_nonblocking (GPollableInputStream *stream, void *buffer,
                                      gsize count, GError **error)
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

static GSource *
bridge_input_stream_create_source (GPollableInputStream *stream,
                                   GCancellable *cancellable)
{
  /* g_pollable_source_new() alone never fires (NULL prepare/check) — it
   * exists to wrap an fd child source. We have no fd: build a source that
   * polls is_readable directly, dispatching the 2-arg
   * GPollableSourceFunc(stream, user_data) the stock callers expect. */
  return bridge_poll_source_new (G_INPUT_STREAM (stream));
}

static void
bridge_input_stream_pollable_init (GPollableInputStreamInterface *iface)
{
  iface->can_poll = bridge_input_stream_can_poll;
  iface->is_readable = bridge_input_stream_is_readable;
  iface->read_nonblocking = bridge_input_stream_read_nonblocking;
  iface->create_source = bridge_input_stream_create_source;
}

static void
bridge_input_stream_init (BridgeInputStream *self)
{
}

static void
bridge_input_stream_class_init (BridgeInputStreamClass *klass)
{
  GInputStreamClass *ioc = G_INPUT_STREAM_CLASS (klass);
  ioc->read_fn = bridge_input_stream_read;
}

G_DEFINE_TYPE_WITH_CODE (BridgeInputStream, bridge_input_stream, G_TYPE_INPUT_STREAM,
                         G_IMPLEMENT_INTERFACE (G_TYPE_POLLABLE_INPUT_STREAM,
                                                bridge_input_stream_pollable_init))

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
bridge_output_stream_init (BridgeOutputStream *self)
{
}

static void
bridge_output_stream_class_init (BridgeOutputStreamClass *klass)
{
  GOutputStreamClass *ooc = G_OUTPUT_STREAM_CLASS (klass);
  ooc->write_fn = bridge_output_stream_write;
}

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
  BridgeInputStream *in;
  BridgeOutputStream *out;

  in = g_object_new (bridge_input_stream_get_type (), NULL);
  in->pipe = pipe;
  in->dir = read_dir;

  out = g_object_new (bridge_output_stream_get_type (), NULL);
  out->pipe = pipe;
  out->dir = write_dir;
  out->from_a = from_a;

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
