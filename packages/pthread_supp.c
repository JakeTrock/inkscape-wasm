/* Single-threaded pthread supplement for emscripten non-mt builds.
 * emscripten's libc already stubs most pthread_* (mutex init/destroy, cond,
 * rwlock, attr, getspecific/setspecific); these are the ones that need
 * actual single-threaded behavior and are absent from the non-mt libc.
 */
#define _GNU_SOURCE
#include <pthread.h>
#include <stdlib.h>
#include <errno.h>
#include <string.h>

static char _main_thread; /* any unique address */

pthread_t pthread_self(void) { return (pthread_t)&_main_thread; }

int pthread_mutex_lock(pthread_mutex_t *m) { (void)m; return 0; }
int pthread_mutex_trylock(pthread_mutex_t *m) { (void)m; return 0; }
int pthread_mutex_unlock(pthread_mutex_t *m) { (void)m; return 0; }

int pthread_once(pthread_once_t *once, void (*init)(void)) {
    if (once == NULL || init == NULL) return EINVAL;
    if (*once != PTHREAD_ONCE_INIT) return 0; /* already done */
    *once = ~PTHREAD_ONCE_INIT;
    init();
    return 0;
}

/* TLS: small fixed pool, single-threaded so no locking needed */
#define MAX_KEYS 128
static void *tls_values[MAX_KEYS];
static void (*tls_dtors[MAX_KEYS])(void *);
static int key_used[MAX_KEYS];

int pthread_key_create(pthread_key_t *key, void (*dtor)(void *)) {
    for (int i = 0; i < MAX_KEYS; i++) {
        if (!key_used[i]) {
            key_used[i] = 1;
            tls_values[i] = NULL;
            tls_dtors[i] = dtor;
            *key = i;
            return 0;
        }
    }
    return EAGAIN;
}

int pthread_key_delete(pthread_key_t key) {
    if (key >= MAX_KEYS || !key_used[key]) return EINVAL;
    key_used[key] = 0;
    return 0;
}

/* Nobody else can signal us; report timeout instead of deadlocking. */
int pthread_cond_timedwait(pthread_cond_t *c, pthread_mutex_t *m,
                           const struct timespec *ts) {
    (void)c; (void)m; (void)ts;
    return ETIMEDOUT;
}

/* Thread creation is impossible in a single-threaded wasm module. */
int pthread_create(pthread_t *t, const pthread_attr_t *a,
                   void *(*fn)(void *), void *arg) {
    (void)t; (void)a; (void)fn; (void)arg;
    return EAGAIN;
}
void pthread_exit(void *v) { (void)v; abort(); }
int pthread_join(pthread_t t, void **rv) { (void)t; (void)rv; return EDEADLK; }
int pthread_detach(pthread_t t) { (void)t; return EINVAL; }

int pthread_getname_np(pthread_t t, char *name, size_t len) {
    (void)t;
    if (len > 0) name[0] = '\0';
    return 0;
}

/* CPU affinity is meaningless on one (non-)thread; headers declare these
 * but non-mt libc doesn't implement them. */
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

/* Run TLS destructors at exit (glib relies on this for GPrivate) */
__attribute__((destructor)) static void tls_run_dtors(void) {
    for (int i = 0; i < MAX_KEYS; i++) {
        if (key_used[i] && tls_values[i] && tls_dtors[i]) {
            void *v = tls_values[i];
            tls_values[i] = NULL;
            tls_dtors[i](v);
        }
    }
}
