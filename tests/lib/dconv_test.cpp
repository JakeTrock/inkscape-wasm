#include <double-conversion/double-conversion.h>
#include <cassert>
#include <cstdio>
#include <string>

using namespace double_conversion;

int main() {
    DoubleToStringConverter c(
        DoubleToStringConverter::EMIT_TRAILING_DECIMAL_POINT, "inf", "nan", 'e',
        -6, 21, 6, 0);
    char buf[64];
    StringBuilder sb(buf, sizeof buf);
    c.ToShortest(3.14, &sb);
    assert(std::string(sb.Finalize()) == "3.14");
    std::printf("double-conversion ok\n");
    return 0;
}
