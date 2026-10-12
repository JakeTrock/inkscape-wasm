#include <gsl/gsl_vector.h>
#include <gsl/gsl_blas.h>
#include <assert.h>
#include <stdio.h>

int main() {
    gsl_vector* v = gsl_vector_alloc(3);
    gsl_vector* w = gsl_vector_alloc(3);
    gsl_vector_set_all(v, 2.0);
    gsl_vector_set_all(w, 3.0);
    double d = 0;
    assert(gsl_blas_ddot(v, w, &d) == 0);
    assert(d == 18.0); // 3 * 2*3
    gsl_vector_free(v); gsl_vector_free(w);
    printf("gsl ok (ddot=%.1f)\n", d);
    return 0;
}
