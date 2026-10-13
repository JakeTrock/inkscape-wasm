#include <2geom/point.h>
#include <2geom/path.h>
#include <2geom/svg-path-parser.h>
#include <2geom/pathvector.h>
#include <cassert>
#include <cstdio>

int main() {
    Geom::Point p(1.5, 2.5);
    assert(p.x() == 1.5 && p.y() == 2.5);
    Geom::PathVector pv = Geom::parse_svg_path("M 0,0 L 10,10 L 20,0 Z");
    assert(pv.size() == 1);
    Geom::OptRect r = pv[0].boundsFast();
    assert(r && r->width() == 20 && r->height() == 10);
    std::printf("lib2geom ok (parsed path, bounds %.1fx%.1f)\n", r->width(), r->height());
    return 0;
}
