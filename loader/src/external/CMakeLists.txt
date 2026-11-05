project(external)

# Vendored third-party code (lsplt, bytehook, dobby, rv64hook, lzma). It is not maintained
# in this repo, so compiling it under the loader's -Wall -Wextra (inherited from
# CMAKE_CXX_FLAGS) only produces noise -- it accounted for the bulk of the non-linker
# warnings (reorder-ctor, sign-compare, unused-parameter, ...). Silence warnings for this
# subtree only; our own targets outside external/ keep full warnings.
add_compile_options(-w)

option(LSPLT_BUILD_SHARED OFF)
add_subdirectory(lsplt/lsplt/src/main/jni)

if(NOT ANDROID_ABI STREQUAL "riscv64")
    add_subdirectory(bhook)
endif()

# Dobby has no riscv64 backend; inline hook is unavailable there.
if(NOT ANDROID_ABI STREQUAL "riscv64")
    option(DOBBY_BUILD_SHARED OFF)
    option(DOBBY_GENERATE_SHARED OFF)
    add_subdirectory(dobby)
else()
    add_subdirectory(rv64hook)
endif()

add_subdirectory(lzma)
