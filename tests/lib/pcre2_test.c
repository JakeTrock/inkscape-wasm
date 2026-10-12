#define PCRE2_CODE_UNIT_WIDTH 8
#include <pcre2.h>
#include <assert.h>
#include <stdio.h>

int main() {
    int errcode; PCRE2_SIZE erroffset;
    pcre2_code* re = pcre2_compile((PCRE2_SPTR)"h(l+)o", PCRE2_ZERO_TERMINATED,
                                   0, &errcode, &erroffset, NULL);
    assert(re);
    pcre2_match_data* md = pcre2_match_data_create_from_pattern(re, NULL);
    int rc = pcre2_match(re, (PCRE2_SPTR)"hello", 5, 0, 0, md, NULL);
    assert(rc == 2);
    PCRE2_SIZE* ovec = pcre2_get_ovector_pointer(md);
    assert(ovec[2] == 2 && ovec[3] == 4); // "ll"
    printf("pcre2 ok (matched groups=%d)\n", rc - 1);
    pcre2_match_data_free(md);
    pcre2_code_free(re);
    return 0;
}
