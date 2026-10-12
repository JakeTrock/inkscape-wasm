#include <ffi.h>
#include <assert.h>
#include <stdio.h>

static int add_i32(int a, int b) { return a + b; }
static void double_it(ffi_cif* cif, void* ret, void** args, void* ud) {
    *(ffi_sarg*)ret = *(int*)args[0] * 2;
}

int main() {
    // 1. plain call
    ffi_cif cif;
    ffi_type* args[2] = { &ffi_type_sint32, &ffi_type_sint32 };
    int a = 3, b = 4; void* vals[2] = { &a, &b }; int rc = 0;
    assert(ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 2, &ffi_type_sint32, args) == FFI_OK);
    ffi_call(&cif, FFI_FN(add_i32), &rc, vals);
    assert(rc == 7);
    printf("libffi plain call ok (3+4=%d)\n", rc);

    // 2. closure (the wasm hazard)
    void* code = NULL;
    ffi_closure* clo = ffi_closure_alloc(sizeof(ffi_closure), &code);
    assert(clo && code);
    ffi_cif ccif; int x = 5; void* cvals[1] = { &x };
    ffi_type* cargs[1] = { &ffi_type_sint32 };
    assert(ffi_prep_cif(&ccif, FFI_DEFAULT_ABI, 1, &ffi_type_sint32, cargs) == FFI_OK);
    assert(ffi_prep_closure_loc(clo, &ccif, double_it, NULL, code) == FFI_OK);
    int (*fn)(int) = (int(*)(int))code;
    int result = fn(5);
    assert(result == 10);
    printf("libffi closure ok (5*2=%d)\n", result);
    return 0;
}
