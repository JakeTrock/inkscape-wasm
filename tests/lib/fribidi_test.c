#include <fribidi.h>
#include <assert.h>
#include <stdio.h>

int main() {
    const FriBidiChar logical[] = {0x05D0, 0x05D1, 0x0041}; // alef, bet, 'A' — RTL run in LTR paragraph
    FriBidiChar visual[3]; FriBidiStrIndex len = 3;
    FriBidiParType base = FRIBIDI_PAR_LTR;
    FriBidiLevel levels[3];
    FriBidiLevel max = fribidi_log2vis(logical, len, &base, visual, NULL, NULL, levels);
    assert(max > 0);
    assert(visual[2] == 0x0041); // LTR char keeps trailing slot
    printf("fribidi ok: max level %d\n", max);
    return 0;
}
