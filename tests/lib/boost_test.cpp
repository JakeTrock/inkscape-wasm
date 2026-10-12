#include <boost/optional.hpp>
#include <boost/variant.hpp>
#include <cassert>
#include <cstdio>

int main() {
    boost::optional<int> o = 3;
    assert(o && *o == 3);
    boost::variant<int, double> v = 2.5;
    assert(boost::get<double>(v) == 2.5);
    std::printf("boost ok\n");
    return 0;
}
