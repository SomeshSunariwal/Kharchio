#pragma once

#include <string_view>

namespace kharchio {
// Restore the original offline task selection: English transcription, or
// Hindi/automatic-to-English translation. The same policy applies whenever
// local Whisper handles speech, including online-provider hybrid modes.
constexpr bool whisper_should_translate(std::string_view language) {
    return language != "en";
}

constexpr const char * whisper_input_language(std::string_view language) {
    return language == "en" ? "en"
        : language == "hinglish" || language == "hi" ? "hi" : "auto";
}

constexpr int whisper_task_token(std::string_view language) {
    return whisper_should_translate(language) ? 50358 : 50359;
}
}
