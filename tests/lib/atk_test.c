#include <atk/atk.h>
#include <assert.h>
#include <stdio.h>

static int signal_count = 0;
static void on_children_changed(AtkObject* obj, gpointer change, gpointer data) {
    signal_count++;
}

int main() {
    AtkObject* parent = atk_no_op_object_new(NULL);
    assert(ATK_IS_OBJECT(parent));
    atk_object_set_name(parent, "test-parent");
    assert(g_strcmp0(atk_object_get_name(parent), "test-parent") == 0);
    atk_object_set_role(parent, ATK_ROLE_PANEL);
    assert(atk_object_get_role(parent) == ATK_ROLE_PANEL);

    AtkObject* child = atk_no_op_object_new(NULL);
    g_signal_connect(parent, "children-changed::add",
                     G_CALLBACK(on_children_changed), NULL);
    atk_object_set_parent(child, parent);
    printf("atk ok (name/role/parent set, signals wired: %d)\n", signal_count);
    return 0;
}
