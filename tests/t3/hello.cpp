/* T3: gtkmm on broadway-over-bridge: signal handler fires (console log),
 * custom cairo draw paints a red rectangle. Window is heap-allocated and
 * leaked so it survives main() returning (the page drives the loop).
 *
 * Geometry note (for tests): same CSD margins as t2 — button event window
 * center is surface-relative (96,200); red rect at content (160,20). */
#include <gtkmm.h>
#include <cstdio>

class RedArea : public Gtk::DrawingArea {
protected:
    bool on_draw(const Cairo::RefPtr<Cairo::Context>& cr) override {
        cr->set_source_rgb(0.85, 0.1, 0.1);
        cr->rectangle(160, 20, 100, 50);
        cr->fill();
        return false;
    }
};

class HelloWindow : public Gtk::Window {
public:
    HelloWindow() {
        set_default_size(300, 200);
        move(0, 0);
        fixed_.put(area_, 0, 0);
        area_.set_size_request(300, 200);
        fixed_.put(label_, 10, 10);
        label_.set_text("hello gtkmm");
        fixed_.put(button_, 20, 120);
        button_.set_label("click me");
        button_.set_size_request(100, 40);
        button_.signal_clicked().connect([] () { g_print("signal fired\n"); });
        add(fixed_);
        show_all_children();
    }
private:
    Gtk::Fixed fixed_;
    RedArea area_;
    Gtk::Label label_;
    Gtk::Button button_;
};

int main(int argc, char** argv) {
    setenv("GDK_BACKEND", "broadway", 1);
    setenv("FONTCONFIG_FILE", "/fixtures/fonts.conf", 1);
    Glib::RefPtr<Gtk::Application> app = Gtk::Application::create(argc, argv);
    HelloWindow* w = new HelloWindow(); /* leak: keep alive after main */
    w->show_all();
    return 0;
}
