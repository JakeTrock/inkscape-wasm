#include <cairomm/context.h>
#include <cairomm/surface.h>
#include <cassert>
#include <cstdio>

int main() {
    auto surf = Cairo::ImageSurface::create(Cairo::FORMAT_ARGB32, 8, 8);
    auto cr = Cairo::Context::create(surf);
    cr->set_source_rgb(1.0, 0.0, 0.0);
    cr->paint();
    assert(surf->get_data() != nullptr);
    assert(surf->get_data()[0] == 0); // BGRA premult: red pixel has B=0
    std::printf("cairomm ok\n");
    return 0;
}
