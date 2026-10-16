/* Single-threaded pthread/DNS supplement for emscripten non-mt builds.
 * The updated emsdk's libc stub now provides a complete coherent pthread
 * set (mutexes, cond, once, TLS with destructors, rwlocks); these few are
 * still declared in headers but missing from the non-mt libc.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>
#ifdef __EMSCRIPTEN__
/* glib's g_thread_new would abort the process (emscripten's non-mt
 * pthread_create returns ENOTSUP). Single-threaded wasm: report success
 * without running the thread body — GDBus worker & friends degrade
 * instead of killing boot. */
int pthread_create(pthread_t *t, const pthread_attr_t *a,
                   void *(*f)(void *), void *arg) {
    (void)a; (void)f; (void)arg;
    *t = (pthread_t)0x1; /* fake handle: never joined in practice */
    return 0;
}
#endif

int pthread_getname_np(pthread_t t, char *name, size_t len) {
    (void)t;
    if (len > 0) name[0] = '\0';
    return 0;
}

/* CPU affinity is meaningless on one (non-)thread. */
#include <sched.h>
int pthread_getaffinity_np(pthread_t t, size_t s, cpu_set_t *set) {
    (void)t; (void)s;
    CPU_ZERO_S(sizeof(cpu_set_t), set);
    return 0;
}
int __sched_cpucount(size_t s, const cpu_set_t *set) {
    (void)s; (void)set;
    return 1; /* the one thread we have */
}

/* DNS is not available; report "not found" so gio's resolver errors cleanly. */
#include <resolv.h>
#include <netdb.h>
int res_query(const char *d, int c, int t, unsigned char *a, int len) {
    (void)d; (void)c; (void)t; (void)a; (void)len;
    h_errno = HOST_NOT_FOUND; /* shortcut: no DNS in wasm; resolver fails clean */
    return -1;
}

/* No directory-tree walking in wasm; only needed so host-side tools link. */
#include <ftw.h>
int ftw(const char *dir, int (*fn)(const char *, const struct stat *, int), int nfd) {
    (void)dir; (void)fn; (void)nfd;
    return -1;
}
