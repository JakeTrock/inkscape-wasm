#include <png.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main() {
    const char* path = "/tmp/png_test.png";
    png_bytep row = calloc(4, 4 * 4);
    row[0] = 0xAA; row[1] = 0xBB; row[2] = 0xCC; row[3] = 0xFF; // pixel (0,0) as RGBA
    FILE* f = fopen(path, "wb");
    png_structp w = png_create_write_struct(PNG_LIBPNG_VER_STRING, 0, 0, 0);
    png_infop wi = png_create_info_struct(w);
    png_init_io(w, f);
    png_set_IHDR(w, wi, 4, 4, 8, PNG_COLOR_TYPE_RGBA, PNG_INTERLACE_NONE,
                 PNG_COMPRESSION_TYPE_DEFAULT, PNG_FILTER_TYPE_DEFAULT);
    png_write_info(w, wi);
    for (int y = 0; y < 4; y++) png_write_row(w, row);
    png_write_end(w, wi);
    png_destroy_write_struct(&w, &wi);
    fclose(f);
    FILE* r = fopen(path, "rb");
    unsigned char magic[8];
    assert(fread(magic, 1, 8, r) == 8);
    static const unsigned char png_sig[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    assert(memcmp(magic, png_sig, 8) == 0);
    fclose(r);
    printf("libpng ok (magic bytes verified)\n");
    return 0;
}
