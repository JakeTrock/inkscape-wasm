#include <sigc++/sigc++.h>
#include <cassert>
#include <cstdio>

int main() {
    sigc::signal<int(int)> s;
    s.connect([](int x) { return x + 1; });
    assert(s.emit(41) == 42);
    std::printf("sigc++ ok\n");
    return 0;
}
