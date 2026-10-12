#include <gdk-pixbuf/gdk-pixbuf.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main() {
    assert(gdk_pixbuf_get_formats() != NULL);
    // decode the tiny 1x1 PNG fixture
    GError* err = NULL;
    GdkPixbuf* pb = gdk_pixbuf_new_from_file("/fixtures/tiny.png", &err);
    assert(pb != NULL);
    assert(gdk_pixbuf_get_width(pb) == 1 && gdk_pixbuf_get_height(pb) == 1);
    // create + fill an RGBA pixbuf, then re-encode to PNG in memory
    GdkPixbuf* out = gdk_pixbuf_new(GDK_COLORSPACE_RGB, TRUE, 8, 3, 3);
    assert(out);
    memset(gdk_pixbuf_get_pixels(out), 0xCC, gdk_pixbuf_get_rowstride(out) * 3);
    gchar* buf = NULL; gsize len = 0;
    assert(gdk_pixbuf_save_to_buffer(out, &buf, &len, "png", &err, NULL));
    assert(len > 8 && (unsigned char)buf[1] == 'P' && (unsigned char)buf[2] == 'N');
    g_free(buf);
    printf("gdk-pixbuf ok (decode 1x1 png, encode %zu bytes)\n", (size_t)len);
    return 0;
}
