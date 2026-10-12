#include <glib.h>
#include <glib-object.h>
#include <assert.h>
#include <stdio.h>

int main() {
    GString* s = g_string_new("hello");
    g_string_append(s, " glib");
    assert(g_strcmp0(s->str, "hello glib") == 0);
    g_string_free(s, TRUE);

    GHashTable* h = g_hash_table_new(g_str_hash, g_str_equal);
    g_hash_table_insert(h, "k", "v");
    assert(g_strcmp0(g_hash_table_lookup(h, "k"), "v") == 0);
    g_hash_table_destroy(h);

    GMainContext* ctx = g_main_context_default();
    assert(g_main_context_iteration(ctx, FALSE) == FALSE); // no sources: returns immediately

    GVariant* v = g_variant_new("(is)", 42, "x");
    gchar* t = g_variant_print(v, TRUE);
    assert(g_str_has_prefix(t, "(42,"));
    g_free(t);

    GObject* o = g_object_new(G_TYPE_OBJECT, NULL);
    assert(G_IS_OBJECT(o));
    g_object_unref(o);

    printf("glib ok (%u.%u.%u)\n", glib_major_version, glib_minor_version, glib_micro_version);
    return 0;
}
