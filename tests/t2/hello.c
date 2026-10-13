/* T2: GTK hello world on broadway-over-bridge. Prints "button clicked" on
 * stdout (-> browser console) when the button is activated. main() returns;
 * the page's rAF tick drives g_main_context_iteration via bridge_frame(). */
#include <gtk/gtk.h>
#include <gdk/gdkbroadway.h>
#include <stdio.h>

static void on_clicked (GtkButton *b, gpointer user) {
    g_print ("button clicked\n");
}

int main (int argc, char **argv) {
    GtkWidget *win, *fixed, *label, *button;

    setenv ("GDK_BACKEND", "broadway", 1);
    setenv ("FONTCONFIG_FILE", "/fixtures/fonts.conf", 1);

    gtk_init (NULL, NULL);

    win = gtk_window_new (GTK_WINDOW_TOPLEVEL);
    gtk_window_set_default_size (GTK_WINDOW (win), 300, 200);
    gtk_window_move (GTK_WINDOW (win), 0, 0);

    fixed = gtk_fixed_new ();
    gtk_container_add (GTK_CONTAINER (win), fixed);

    label = gtk_label_new ("hello wasm");
    gtk_fixed_put (GTK_FIXED (fixed), label, 10, 10);

    button = gtk_button_new_with_label ("click me");
    gtk_fixed_put (GTK_FIXED (fixed), button, 20, 120);
    gtk_widget_set_size_request (button, 100, 40);
    g_signal_connect (button, "clicked", G_CALLBACK (on_clicked), NULL);

    gtk_widget_show_all (win);
    return 0; /* runtime stays alive (EXIT_RUNTIME=0); page drives the loop */
}
