#pragma once
#include <cstdint>
#include <string>

// Separate from GGML Hexagon: only Qualcomm's HTP runtime executes these graphs.
namespace whisper_qnn
{
    void prepare(const char *ggml_path, int32_t *cancel, bool portable);
    std::string transcribe(const char *ggml_path, const float *pcm, int32_t count,
                           const char *language, int32_t *cancel, bool portable);
    void release();
}
