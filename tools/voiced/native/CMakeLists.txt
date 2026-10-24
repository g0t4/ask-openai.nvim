cmake_minimum_required(VERSION 3.20)
project(voiced_tts_worker LANGUAGES C CXX)

# Link an existing llama.cpp build; leave its source and other services alone.
set(LLAMA_SOURCE "$ENV{HOME}/repos/github/ggml-org/llama.cpp" CACHE PATH "llama.cpp source")
set(LLAMA_BUILD "${LLAMA_SOURCE}/build" CACHE PATH "llama.cpp build")
set(VOICED_MTMD_SOURCE "" CACHE PATH "Isolated llama.cpp source with the short-chunk decoder fix")
add_executable(voiced-tts-worker tts_worker.cpp)
target_compile_features(voiced-tts-worker PRIVATE cxx_std_17)
target_include_directories(voiced-tts-worker PRIVATE
    "${LLAMA_SOURCE}/include" "${LLAMA_SOURCE}/ggml/include"
    "${LLAMA_SOURCE}/common" "${LLAMA_SOURCE}/tools/mtmd" "${LLAMA_SOURCE}/vendor")
foreach(lib llama-common llama ggml ggml-base)
    find_library(LIB_${lib} NAMES ${lib} PATHS "${LLAMA_BUILD}/bin" NO_DEFAULT_PATH REQUIRED)
    target_link_libraries(voiced-tts-worker PRIVATE "${LIB_${lib}}")
endforeach()
if(VOICED_MTMD_SOURCE)
    # Compile only mtmd, reusing the existing CUDA-enabled llama/ggml libraries.
    # The patched library is static and private to this worker.
    foreach(lib llama ggml)
        add_library(${lib} SHARED IMPORTED)
        set_target_properties(${lib} PROPERTIES IMPORTED_LOCATION "${LIB_${lib}}"
            INTERFACE_INCLUDE_DIRECTORIES "${LLAMA_SOURCE}/include;${LLAMA_SOURCE}/ggml/include")
    endforeach()
    set(BUILD_SHARED_LIBS OFF)
    set(LLAMA_SUBPROCESS ON)
    set(LLAMA_BUILD_COMMON OFF)
    set(LLAMA_BUILD_TOOLS OFF)
    set(LLAMA_VERSION_BASE 0.6.0)
    set(LLAMA_VERSION_MAJOR 0)
    # Vendor targets call llama.cpp's optional warning-flags hook.
    function(llama_add_compile_flags)
    endfunction()
    add_subdirectory("${VOICED_MTMD_SOURCE}/vendor" vendor)
    add_subdirectory("${VOICED_MTMD_SOURCE}/tools/mtmd" mtmd)
    target_link_libraries(voiced-tts-worker PRIVATE mtmd)
else()
    find_library(LIB_mtmd NAMES mtmd PATHS "${LLAMA_BUILD}/bin" NO_DEFAULT_PATH REQUIRED)
    target_link_libraries(voiced-tts-worker PRIVATE "${LIB_mtmd}")
endif()
target_link_libraries(voiced-tts-worker PRIVATE "${LLAMA_BUILD}/common/libllama-common-base.a")
set_target_properties(voiced-tts-worker PROPERTIES BUILD_RPATH "${LLAMA_BUILD}/bin")
