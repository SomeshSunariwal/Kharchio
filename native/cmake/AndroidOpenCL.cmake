set(_cl_revision 82f60316cc142e7b21dc1d8983b26de18858fbd9)
set(_cl_source "${CMAKE_CURRENT_LIST_DIR}/../vendor/OpenCL-Headers-${_cl_revision}")
if(EXISTS "${_cl_source}/CL/cl.h")
  set(FETCHCONTENT_SOURCE_DIR_OPENCL_HEADERS "${_cl_source}")
endif()
FetchContent_Declare(opencl_headers
  URL "https://codeload.github.com/KhronosGroup/OpenCL-Headers/zip/${_cl_revision}"
  SOURCE_DIR "${_cl_source}")
FetchContent_GetProperties(opencl_headers)
if(NOT opencl_headers_POPULATED)
  FetchContent_Populate(opencl_headers)
endif()
find_package(Python3 COMPONENTS Interpreter REQUIRED)
set(_loader "${CMAKE_CURRENT_BINARY_DIR}/opencl-loader.cpp")
execute_process(COMMAND "${Python3_EXECUTABLE}"
  "${CMAKE_CURRENT_LIST_DIR}/../tools/generate_opencl_loader.py"
  "${opencl_headers_SOURCE_DIR}/CL/cl.h"
  "${CMAKE_CURRENT_LIST_DIR}/../vendor/llama.cpp/ggml/src/ggml-opencl" "${_loader}"
  RESULT_VARIABLE _loader_result)
if(NOT _loader_result EQUAL 0)
  message(FATAL_ERROR "Could not generate the optional OpenCL loader")
endif()
add_library(kharchio_opencl_loader STATIC "${_loader}")
target_include_directories(kharchio_opencl_loader PUBLIC "${opencl_headers_SOURCE_DIR}")
target_link_libraries(kharchio_opencl_loader PRIVATE dl)
target_compile_options(kharchio_opencl_loader PRIVATE -O3 -fvisibility=hidden)
list(PREPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_LIST_DIR}")
