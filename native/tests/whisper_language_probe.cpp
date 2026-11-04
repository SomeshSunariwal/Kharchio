#include "whisper_language.h"

static_assert(!kharchio::whisper_should_translate("en"));
static_assert(kharchio::whisper_should_translate("hinglish"));
static_assert(kharchio::whisper_should_translate("hi"));
static_assert(kharchio::whisper_should_translate("auto"));
static_assert(kharchio::whisper_task_token("en") == 50359);
static_assert(kharchio::whisper_task_token("hinglish") == 50358);
static_assert(kharchio::whisper_task_token("hi") == 50358);
static_assert(kharchio::whisper_task_token("auto") == 50358);
static_assert(std::string_view(kharchio::whisper_input_language("en")) == "en");
static_assert(std::string_view(kharchio::whisper_input_language("hinglish")) == "hi");
static_assert(std::string_view(kharchio::whisper_input_language("auto")) == "auto");

int main() { return 0; }
