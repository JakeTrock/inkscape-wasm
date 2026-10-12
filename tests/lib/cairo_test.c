#include <cairo.h>
#include <assert.h>
#include <stdio.h>

int main() {
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 64, 64);
    assert(cairo_surface_status(s) == CAIRO_STATUS_SUCCESS);
    cairo_t* cr = cairo_create(s);
    cairo_set_source_rgb(cr, 1, 0, 0);
    cairo_paint(cr);
    cairo_set_source_rgb(cr, 0, 0, 1);
    cairo_set_line_width(cr, 4);
    cairo_move_to(cr, 8, 8); cairo_line_to(cr, 56, 56); cairo_stroke(cr);
    cairo_destroy(cr);
    unsigned char* d = cairo_image_surface_get_data(s);
    assert(d[2] == 255 && d[1] == 0 && d[0] == 0); // corner pixel is red (BGRA)
    assert(cairo_surface_write_to_png(s, "/tmp/cairo_test.png") == CAIRO_STATUS_SUCCESS);
    FILE* f = fopen("/tmp/cairo_test.png", "rb");
    unsigned char magic[4];
    assert(fread(magic, 1, 4, f) == 4);
    assert(magic[1] == 'P' && magic[2] == 'N' && magic[3] == 'G');
    fclose(f);
    cairo_surface_destroy(s);
    printf("cairo ok (red pixel + PNG write verified)\n");
    return 0;
}
