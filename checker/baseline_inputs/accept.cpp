#include <cstdio>
#include "math.hpp"
int main() {
    struct Test { int a, b, want; };
    const Test tests[] = {{19,23,42},{2,-3,-1},{-4,-5,-9},{0,0,0}};
    for (const auto &t : tests) {
        if (add(t.a,t.b) != t.want) return 1;
    }
    std::puts("CT_NATIVE_ACCEPTANCE_OK");
    return 0;
}
