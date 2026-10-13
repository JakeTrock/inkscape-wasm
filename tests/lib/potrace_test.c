/* potrace smoke: library links and reports its version. Inkscape only needs
 * configure-time satisfaction + a linkable lib; tracing is not gated here. */
#include <potracelib.h>
#include <stdio.h>

int main(void) {
    const char *v = potrace_version();
    if (!v) { printf("FAIL: potrace_version NULL\n"); return 1; }
    printf("potrace ok (%s)\n", v);
    return 0;
}
