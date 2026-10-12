#include <zlib.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

int main() {
    const char* msg = "the quick brown fox jumps over the lazy dog";
    unsigned char comp[128], decomp[128];
    uLongf comp_len = sizeof comp, decomp_len = sizeof decomp;
    assert(compress(comp, &comp_len, (const Bytef*)msg, strlen(msg)) == Z_OK);
    assert(uncompress(decomp, &decomp_len, comp, comp_len) == Z_OK);
    assert(decomp_len == strlen(msg));
    assert(memcmp(decomp, msg, decomp_len) == 0);
    printf("zlib ok: %zu -> %lu -> %zu bytes\n", strlen(msg), comp_len, decomp_len);
    return 0;
}
