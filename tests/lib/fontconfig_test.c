#include <fontconfig/fontconfig.h>
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main() {
    setenv("FONTCONFIG_PATH", "/fixtures/fc", 1); // fixtures dir holds our fonts.conf
    assert(FcInit());
    FcPattern* pat = FcPatternBuild(NULL, FC_FAMILY, FcTypeString, (FcChar8*)"DejaVu Sans", NULL);
    FcConfigSubstitute(NULL, pat, FcMatchPattern);
    FcDefaultSubstitute(pat);
    FcResult res;
    FcPattern* m = FcFontMatch(NULL, pat, &res);
    assert(m != NULL);
    FcChar8* file = NULL;
    assert(FcPatternGetString(m, FC_FILE, 0, &file) == FcResultMatch);
    printf("fontconfig ok: matched %s\n", file);
    return 0;
}
