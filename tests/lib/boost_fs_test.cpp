/* boost::filesystem smoke: the component Inkscape hard-requires. */
#include <boost/filesystem.hpp>
#include <cstdio>

int main() {
    boost::filesystem::path p = boost::filesystem::temp_directory_path() / "bfst";
    boost::filesystem::remove(p);
    boost::filesystem::create_directories(p / "a" / "b");
    std::size_t n = 0;
    for (auto &e : boost::filesystem::recursive_directory_iterator(p)) { (void)e; ++n; }
    boost::filesystem::remove_all(p);
    std::printf("boost::filesystem ok (walked %zu entries)\n", n);
    return n == 2 ? 0 : 1;
}
