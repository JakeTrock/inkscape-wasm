#include <pango/pango.h>
#include <pango/pangocairo.h>
#include <cairo.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
    setenv("FONTCONFIG_PATH", "/fixtures/fc", 1);
    PangoFontMap* fm = pango_cairo_font_map_new();
    assert(fm);
    PangoContext* ctx = pango_font_map_create_context(fm);
    PangoLayout* layout = pango_layout_new(ctx); // 2-arg form dropped in newer pango
    PangoFontDescription* desc = pango_font_description_from_string("DejaVu Sans 16");
    pango_layout_set_font_description(layout, desc);
    pango_font_description_free(desc);
    pango_layout_set_text(layout, "Hi", -1);
    PangoRectangle ink, logical;
    pango_layout_get_extents(layout, &ink, &logical);
    assert(logical.width > 0 && logical.height > 0);
    // render and check the bitmap has ink
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 64, 32);
    cairo_t* cr = cairo_create(s);
    cairo_set_source_rgb(cr, 1, 1, 1);
    cairo_paint(cr);
    cairo_set_source_rgb(cr, 0, 0, 0);
    cairo_translate(cr, 4, 4);
    pango_cairo_show_layout(cr, layout);
    cairo_destroy(cr);
    unsigned char* d = cairo_image_surface_get_data(s);
    int dark = 0;
    for (int i = 0; i < 64 * 32 * 4; i += 4)
        if (d[i] < 128 && d[i+1] < 128) dark++; // dark text pixels on white
    assert(dark > 20);
    printf("pango ok: layout %dx%d, %d text pixels\n",
           logical.width / PANGO_SCALE, logical.height / PANGO_SCALE, dark);
    return 0;
}
