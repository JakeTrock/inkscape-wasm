#include <ft2build.h>
#include <freetype/freetype.h>
#include <assert.h>
#include <stdio.h>

int main() {
    FT_Library lib;
    assert(FT_Init_FreeType(&lib) == 0);
    FT_Face face;
    assert(FT_New_Face(lib, "/fixtures/DejaVuSans.ttf", 0, &face) == 0);
    assert(face->num_glyphs > 1000);
    assert(FT_Set_Char_Size(face, 0, 16 * 64, 72, 72) == 0);
    assert(FT_Load_Char(face, 'A', FT_LOAD_RENDER) == 0);
    printf("freetype ok: %ld glyphs, 'A' bitmap %dx%d\n",
           face->num_glyphs, face->glyph->bitmap.width, face->glyph->bitmap.rows);
    return 0;
}
