#include <cstdio>
#include <stdexcept>
#include <string>
#include <typeinfo>

struct Base { virtual ~Base() = default; virtual const char* name() const { return "base"; } };
struct Derived : Base { const char* name() const override { return "derived"; } };

int main() {
    Base* b = new Derived();
    if (std::string(typeid(*b).name()).find("Derived") == std::string::npos)
        throw std::logic_error("rtti broken");
    if (std::string(b->name()) != "derived")
        throw std::logic_error("vtable broken");
    delete b;
    try { throw std::runtime_error("expected"); }
    catch (const std::runtime_error& e) { std::printf("hello wasm: exceptions+rtti ok (%s)\n", e.what()); }
    return 0;
}
