cmake_minimum_required(VERSION 3.22.1)
project("loader")

set(CMAKE_CXX_STANDARD 23)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

add_definitions(-DZKSU_VERSION=\"${ZKSU_VERSION}\")

add_subdirectory(external)

# Release-only link optimisations, supplied by loader/build.gradle.kts as a ;-separated
# list. add_link_options keeps them on the link step only (never on compiles, which would
# warn -Wunused-command-line-argument) and, placed after add_subdirectory(external), applies
# them to our own targets below but not to the vendored code in external/. It appends to the
# flags the NDK toolchain already sets rather than replacing them.
if(DEFINED LOADER_EXTRA_LINK_FLAGS)
    add_link_options(${LOADER_EXTRA_LINK_FLAGS})
endif()

aux_source_directory(common COMMON_SRC_LIST)
add_library(common STATIC ${COMMON_SRC_LIST})
target_include_directories(common PRIVATE include external/lzma)
target_link_libraries(common log lzma)

# From-scratch module loader (keeps Zygisk/ZN modules out of the dynamic
# linker's solist; see linker/linker.hpp).
aux_source_directory(linker LINKER_SRC_LIST)
add_library(modlinker STATIC ${LINKER_SRC_LIST})
target_include_directories(modlinker PRIVATE include linker)
target_link_libraries(modlinker log)

aux_source_directory(injector INJECTOR_SRC_LIST)
add_library(zygisk SHARED ${INJECTOR_SRC_LIST})
target_compile_options(zygisk PRIVATE -Wno-invalid-offsetof -Wno-unused-private-field)
target_include_directories(zygisk PRIVATE include external/lzma linker)
target_link_libraries(zygisk log common modlinker lsplt_static lzma)
if(NOT ANDROID_ABI STREQUAL "riscv64")
    target_include_directories(zygisk PRIVATE external/dobby/include external/bhook/bytehook/src/main/cpp/include)
    target_link_libraries(zygisk dobby bytehook_static)
else()
    target_include_directories(zygisk PRIVATE external/rv64hook/compat)
    target_link_libraries(zygisk rv64hook-static)
endif()

aux_source_directory(ptracer PTRACER_SRC_LIST)
add_executable(libzygisk_ptrace.so ${PTRACER_SRC_LIST})
target_include_directories(libzygisk_ptrace.so PRIVATE include)
target_link_libraries(libzygisk_ptrace.so log common)
