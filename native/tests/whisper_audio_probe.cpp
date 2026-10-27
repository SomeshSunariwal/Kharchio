#include "whisper_audio.h"
#include <iostream>
int main(int argc, char ** argv) {
    if (argc != 4) return 2;
    try {
        whisper_qnn::AudioMetadata metadata(argv[1]);
        std::ifstream input(argv[2], std::ios::binary | std::ios::ate);
        const auto bytes = input.tellg();
        if (bytes <= 0 || bytes > 480000 * 4) return 3;
        std::vector<float> pcm(static_cast<size_t>(bytes) / 4);
        input.seekg(0); input.read(reinterpret_cast<char *>(pcm.data()), bytes);
        int32_t cancel = 1;
        bool cancelled = false;
        try { metadata.mel(pcm.data(), pcm.size(), &cancel); }
        catch (const std::runtime_error & e) { cancelled = std::string(e.what()) == "Cancelled"; }
        if (!cancelled) return 4;
        cancel = 0;
        auto features = metadata.mel(pcm.data(), pcm.size(), &cancel);
        std::ofstream out(argv[3], std::ios::binary);
        out.write(reinterpret_cast<const char *>(features.data()), features.size() * 4);
        return out ? 0 : 5;
    } catch (const std::exception & e) { std::cerr << e.what(); return 1; }
}
