# Resolve driver symbols lazily. Missing vendor OpenCL must not prevent the app
# from loading on devices where Vulkan or CPU is the available backend.
set(OpenCL_FOUND TRUE)
set(OpenCL_INCLUDE_DIRS "${opencl_headers_SOURCE_DIR}")
set(OpenCL_LIBRARIES kharchio_opencl_loader)
set(OpenCL_VERSION_STRING "3.0")
