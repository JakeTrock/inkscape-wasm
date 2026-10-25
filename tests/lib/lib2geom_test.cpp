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
    // Circle made of 4 arcs on the same ellipse exercises EllipticalArc::intersect's
    // internal catch(InfinitelyManySolutions&) — fails if lib2geom lacks -fexceptions.
    Geom::PathVector circle = Geom::parse_svg_path(
        "M 100,50 A 50,50 0 0 1 50,100 A 50,50 0 0 1 0,50 A 50,50 0 0 1 50,0 A 50,50 0 0 1 100,50 Z");
    assert(circle.intersectSelf().empty());
    std::printf("lib2geom ok (parsed path, bounds %.1fx%.1f)\n", r->width(), r->height());
    return 0;
}
