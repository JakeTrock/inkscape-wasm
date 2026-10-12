#include <hb.h>
#include <hb-ft.h>
#include <assert.h>
#include <stdio.h>

int main() {
    hb_blob_t* blob = hb_blob_create_from_file("/fixtures/DejaVuSans.ttf");
    assert(blob && hb_blob_get_length(blob) > 0);
    hb_face_t* face = hb_face_create(blob, 0);
    hb_font_t* font = hb_font_create(face);
    hb_buffer_t* buf = hb_buffer_create();
    hb_buffer_add_utf8(buf, "xy", -1, 0, -1); // "fi" would ligate in DejaVu
    hb_buffer_guess_segment_properties(buf);
    hb_shape(font, buf, NULL, 0);
    unsigned len = hb_buffer_get_length(buf);
    hb_glyph_info_t* info = hb_buffer_get_glyph_infos(buf, NULL);
    assert(len == 2);
    assert(info[0].codepoint > 0 && info[1].codepoint > 0); // real glyph ids, not .notdef
    printf("harfbuzz ok: glyphs %u %u\n", info[0].codepoint, info[1].codepoint);
    return 0;
}
