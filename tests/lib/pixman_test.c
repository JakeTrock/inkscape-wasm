#include <pixman.h>
#include <assert.h>
#include <stdio.h>

int main() {
    pixman_image_t* img = pixman_image_create_bits(PIXMAN_a8r8g8b8, 8, 8, NULL, 0);
    assert(img);
    pixman_color_t color = { 0xffff, 0, 0, 0xffff }; // opaque red
    pixman_rectangle16_t rect = { 0, 0, 8, 8 };
    assert(pixman_image_fill_rectangles(PIXMAN_OP_SRC, img, &color, 1, &rect));
    uint32_t* bits = (uint32_t*)pixman_image_get_data(img);
    assert(bits[0] == 0xffff0000u); // a8r8g8b8 red
    pixman_image_unref(img);
    printf("pixman ok\n");
    return 0;
}
