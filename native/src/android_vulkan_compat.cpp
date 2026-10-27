#include <vulkan/vulkan.h>
#include <dlfcn.h>

// Vulkan 1.1 entry points are not in Android's API-24 linker stub. Resolve this
// upstream direct call at runtime so older phones can still load the CPU path.
extern "C" VKAPI_ATTR void VKAPI_CALL vkGetPhysicalDeviceFeatures2(
    VkPhysicalDevice device, VkPhysicalDeviceFeatures2 * features) {
    static void * loader = dlopen("libvulkan.so", RTLD_NOW | RTLD_LOCAL);
    static auto query = loader ? reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures2>(
        dlsym(loader, "vkGetPhysicalDeviceFeatures2")) : nullptr;
    if (query) {
        query(device, features);
    } else {
        vkGetPhysicalDeviceFeatures(device, &features->features);
    }
}
