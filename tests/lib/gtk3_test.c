/* T5 gate test: GTK3 initializes with the Broadway backend, creates a window
 * with a label, renders it to the broadway surface, and runs one main-loop
 * iteration — all in-node, no browser yet.
 */
#include <gtk/gtk.h>
#include <gdk/gdkbroadway.h>
#include <assert.h>
#include <stdio.h>
#include <string.h>

static int expose_count = 0;
static gboolean on_draw(GtkWidget* w, cairo_t* cr, gpointer data) {
    expose_count++;
    cairo_set_source_rgb(cr, 1, 0, 0);
    cairo_paint(cr);
    return FALSE;
}

int main(int argc, char** argv) {
    // broadway gets its display from GDK_BACKEND or defaults; force it
    setenv("GDK_BACKEND", "broadway", 1);
    // no broadwayd daemon yet — use the memory ("broadway without socket") path?
    // For leg A we only require init + widget tree; rendering via broadway
    // surface happens in leg B with the byte-pipe bridge.
    gtk_init(NULL, NULL);
    assert(gdk_display_get_default() != NULL);
    assert(GDK_IS_BROADWAY_DISPLAY(gdk_display_get_default()));

    GtkWidget* win = gtk_window_new(GTK_WINDOW_TOPLEVEL);
    GtkWidget* label = gtk_label_new("hello broadway");
    gtk_container_add(GTK_CONTAINER(win), label);
    gtk_widget_set_size_request(win, 64, 32);
    gtk_widget_realize(win);
    gtk_widget_show_all(win);

    g_signal_connect(win, "draw", G_CALLBACK(on_draw), NULL);
    while (gtk_events_pending()) gtk_main_iteration(); // drain initial events
    assert(expose_count > 0); // at least one draw pass happened

    printf("gtk-broadway ok (display %s, drew %d frames)\n",
           G_OBJECT_TYPE_NAME(gdk_display_get_default()), expose_count);
    return 0;
}
