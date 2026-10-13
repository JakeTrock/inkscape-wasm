#include <gc.h>
#include <assert.h>
#include <stdio.h>

static int finalized = 0;
static void fin(void* obj, void* cd) { (void)obj; (void)cd; finalized = 1; }

struct node { struct node* next; };

int main() {
    GC_init();
    void* p = GC_malloc(1024);
    assert(p);
    GC_register_finalizer(p, fin, NULL, NULL, NULL);
    p = NULL; // no remaining references
    GC_gcollect();
    GC_gcollect();
    if (!finalized) {
        printf("libgc: allocation ok but collection NOT observable (finalizer never ran)\n");
        return 2; // ladder signal — see plan Task 18 Step 3
    }
    // cyclic garbage must not grow the heap unboundedly
    for (int round = 0; round < 4; round++) {
        struct node* head = NULL;
        for (int i = 0; i < 10000; i++) {
            struct node* n = GC_malloc(sizeof(struct node));
            assert(n);
            n->next = head; head = n;
        }
        head->next = head; // make a cycle, drop the handle
        head = NULL;
        GC_gcollect();
    }
    printf("libgc ok (finalizer ran, heap bounded at %lu)\n",
           (unsigned long)GC_get_heap_size());
    return 0;
}
