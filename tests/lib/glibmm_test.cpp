#include <glibmm/ustring.h>
#include <glibmm/miscutils.h>
#include <cassert>
#include <cstdio>

int main() {
    Glib::ustring u("hello");
    u += " glibmm";
    assert(u == "hello glibmm");
    assert(Glib::ustring("h\xc3\xa9llo").bytes() == 7);
    std::printf("glibmm ok\n");
    return 0;
}
