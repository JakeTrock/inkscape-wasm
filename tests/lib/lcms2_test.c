/* lcms2 smoke: build the sRGB profile and read back its description. */
#include <lcms2.h>
#include <stdio.h>

int main(void) {
    cmsHPROFILE p = cmsCreate_sRGBProfile();
    if (!p) { printf("FAIL: no sRGB profile\n"); return 1; }
    cmsFloat64Number ver = cmsGetProfileVersion(p);
    char desc[128] = {0};
    cmsGetProfileInfoASCII(p, cmsInfoDescription, "en", "US", desc, sizeof desc);
    cmsCloseProfile(p);
    printf("lcms2 ok (sRGB v%.1f, desc \"%s\")\n",
           ver, desc[0] ? desc : "(none)");
    return 0;
}
