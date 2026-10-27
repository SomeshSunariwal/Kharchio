#include "llama.h"
#include "whisper.h"
#include "whisper_qnn.h"
#include "ggml-backend.h"
#ifdef KHARCHIO_HAS_HEXAGON
#include "ggml-hexagon.h"
#endif
#include <algorithm>
#include <cstdlib>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <vector>
#include <chrono>
#include <cstdio>
#include <cctype>
#ifdef __ANDROID__
#include <android/log.h>
#endif

#define EXPORT extern "C" __attribute__((visibility("default")))
static std::mutex inference_mutex;
// 0 = CPU, 1 = GPU, 2 = generic NPU, 3 = S23 Ultra speech NPU.
static int processing_mode = 1;
static std::string last_backend = "Not run";
static void diagnostic(const std::string & message) {
#ifdef __ANDROID__
    __android_log_print(ANDROID_LOG_INFO, "KharchioAI", "%s", message.c_str());
#else
    std::fprintf(stderr, "KharchioAI: %s\n", message.c_str());
#endif
}
struct InferenceTimer {
    const char * stage;
    std::chrono::steady_clock::time_point start = std::chrono::steady_clock::now();
    ~InferenceTimer() {
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - start).count();
        diagnostic(std::string(stage) + " finished in " + std::to_string(ms) + " ms");
    }
};
struct GpuSelection { ggml_backend_dev_t device = nullptr; int whisper_index = 0; };
static bool adreno_gpu(GpuSelection gpu) {
    return gpu.device && std::string(ggml_backend_dev_description(gpu.device)).find("Adreno") != std::string::npos;
}
static std::vector<GpuSelection> available_accelerators(bool whisper_only = false) {
    static std::once_flag backend;
    std::call_once(backend, [] {
        auto log = [](enum ggml_log_level level, const char * text, void *) {
            if (level == GGML_LOG_LEVEL_WARN || level == GGML_LOG_LEVEL_ERROR) diagnostic(text);
        };
        llama_log_set(log, nullptr);
        whisper_log_set(log, nullptr);
        llama_backend_init();
        ggml_backend_load_all();
    });
    if (processing_mode == 0) return {};
#ifdef KHARCHIO_HAS_HEXAGON
    if (processing_mode == 2 && !whisper_only) {
        static std::once_flag hexagon;
        std::call_once(hexagon, [] {
            auto reg = ggml_backend_hexagon_reg();
            if (reg) ggml_backend_register(reg);
            else diagnostic("Qualcomm Hexagon driver unavailable");
        });
    }
#endif
    // Diagnostic override permits a fair CPU/GPU comparison using the same binary.
    const char * override = std::getenv("KHARCHIO_AI_BACKEND");
    if (override && std::string(override) == "cpu") return {};
    int gpu_index = 0;
    std::vector<GpuSelection> npu, opencl_devices, other_gpu;
    for (size_t i = 0; i < ggml_backend_dev_count(); ++i) {
        auto * device = ggml_backend_dev_get(i);
        auto type = ggml_backend_dev_type(device);
        if (type != GGML_BACKEND_DEVICE_TYPE_GPU && type != GGML_BACKEND_DEVICE_TYPE_IGPU) continue;
        std::string description = ggml_backend_dev_description(device);
        std::transform(description.begin(), description.end(), description.begin(),
            [](unsigned char c) { return std::tolower(c); });
        const bool software = description.find("swiftshader") != std::string::npos ||
            description.find("llvmpipe") != std::string::npos || description.find("lavapipe") != std::string::npos;
        const std::string name = ggml_backend_dev_name(device);
        const bool opencl = name.find("OpenCL") != std::string::npos;
        const bool hexagon = name.find("HTP") != std::string::npos || name.find("Hexagon") != std::string::npos;
        const bool requested = !override ||
            (std::string(override) == "opencl" && opencl) ||
            (std::string(override) == "vulkan" && name.find("Vulkan") != std::string::npos) ||
            (std::string(override) == "npu" && (whisper_only ? opencl : hexagon));
        if (!software && requested) {
            const GpuSelection selected{device, gpu_index};
            if (hexagon) npu.push_back(selected);
            else if (opencl) opencl_devices.push_back(selected);
            else other_gpu.push_back(selected);
        }
        ++gpu_index;
    }
    std::vector<GpuSelection> candidates;
    if (!whisper_only && (processing_mode == 2 || (override && std::string(override) == "npu"))) {
        candidates = npu;
        if (npu.empty()) diagnostic("Hexagon NPU unavailable; trying OpenCL then CPU");
    }
    candidates.insert(candidates.end(), opencl_devices.begin(), opencl_devices.end());
    if (processing_mode == 1) candidates.insert(candidates.end(), other_gpu.begin(), other_gpu.end());
#ifdef __APPLE__
    // Hexagon/OpenCL do not exist on Apple; retain the platform Metal backend.
    if (processing_mode >= 2) candidates.insert(candidates.end(), other_gpu.begin(), other_gpu.end());
#endif
    return candidates;
}
static void prepare_gpu(GpuSelection gpu) {
    if (!gpu.device || std::string(ggml_backend_dev_name(gpu.device)).find("OpenCL") == std::string::npos) return;
    // Whisper asks for weight-buffer alignment before initializing a backend.
    // OpenCL needs its device context first. Keep it warm across live updates.
    static std::unique_ptr<ggml_backend, decltype(&ggml_backend_free)> backend(nullptr, ggml_backend_free);
    static ggml_backend_dev_t initialized = nullptr;
    if (!backend || initialized != gpu.device) {
        backend.reset(ggml_backend_dev_init(gpu.device, nullptr));
        if (!backend) throw std::runtime_error("Could not initialize the OpenCL GPU");
        initialized = gpu.device;
    }
}
static bool cancelled(void * data) {
    return data && *static_cast<volatile int32_t *>(data) != 0;
}
static char * result(const std::string & text) {
    auto * out = static_cast<char *>(std::malloc(text.size() + 1));
    if (out) std::memcpy(out, text.c_str(), text.size() + 1);
    return out;
}
EXPORT void kharchio_free(char * text) { std::free(text); }

struct ModelSession {
    std::unique_ptr<whisper_context, decltype(&whisper_free)> whisper{nullptr, whisper_free};
    std::unique_ptr<llama_model, decltype(&llama_model_free)> qwen{nullptr, llama_model_free};
    std::string whisper_path, qwen_path;
    ggml_backend_dev_t whisper_device = nullptr, qwen_device = nullptr;
    void unload_whisper() {
        whisper_qnn::release();
        if (whisper) diagnostic("Whisper weights unloaded");
        whisper.reset(); whisper_path.clear();
    }
    void unload_qwen() {
        if (qwen) diagnostic("Qwen weights unloaded");
        qwen.reset(); qwen_path.clear();
    }
};
static ModelSession & model_session() { static ModelSession session; return session; }

static whisper_context * load_whisper(const char * path, GpuSelection gpu, int32_t * cancel) {
    auto & session = model_session();
    session.unload_qwen();
    if (session.whisper && session.whisper_path == path && session.whisper_device == gpu.device) return session.whisper.get();
    session.unload_whisper();
    if (cancelled(cancel)) throw std::runtime_error("Cancelled");
    auto params = whisper_context_default_params();
    params.use_gpu = gpu.device != nullptr;
    params.gpu_device = gpu.whisper_index;
    session.whisper.reset(whisper_init_from_file_with_params(path, params));
    if (!session.whisper) throw std::runtime_error("Could not load the multilingual Whisper model");
    if (cancelled(cancel) || !whisper_is_multilingual(session.whisper.get())) {
        session.unload_whisper();
        throw std::runtime_error(cancelled(cancel) ? "Cancelled" : "Use a multilingual Whisper model, not an .en model");
    }
    session.whisper_path = path;
    session.whisper_device = gpu.device;
    diagnostic(std::string("Whisper weights loaded on ") + (gpu.device ? ggml_backend_dev_name(gpu.device) : "CPU"));
    return session.whisper.get();
}
static llama_model * load_qwen(const char * path, GpuSelection gpu, int32_t * cancel) {
    auto & session = model_session();
    session.unload_whisper();
    if (session.qwen && session.qwen_path == path && session.qwen_device == gpu.device) return session.qwen.get();
    session.unload_qwen();
    if (cancelled(cancel)) throw std::runtime_error("Cancelled");
    auto params = llama_model_default_params();
    ggml_backend_dev_t devices[] = {gpu.device, nullptr};
    params.devices = devices;
    params.n_gpu_layers = gpu.device ? -1 : 0;
    params.split_mode = LLAMA_SPLIT_MODE_NONE;
    params.progress_callback = [](float, void * data) { return !cancelled(data); };
    params.progress_callback_user_data = cancel;
    session.qwen.reset(llama_model_load_from_file(path, params));
    if (!session.qwen) throw std::runtime_error(cancelled(cancel) ? "Cancelled" : "Could not load the Qwen GGUF model");
    session.qwen_path = path;
    session.qwen_device = gpu.device;
    diagnostic(std::string("Qwen weights loaded on ") + (gpu.device ? ggml_backend_dev_name(gpu.device) : "CPU"));
    return session.qwen.get();
}

static std::string transcribe(const char * model_path, const float * pcm,
    int32_t count, const char * language, int32_t threads, int32_t * cancel, GpuSelection gpu) {
        if (cancelled(cancel)) throw std::runtime_error("Cancelled");
        diagnostic(std::string("Whisper backend: ") + (gpu.device ? ggml_backend_dev_description(gpu.device) : "CPU"));
        auto * ctx = load_whisper(model_path, gpu, cancel);
        const std::string requested_language = language;
        const bool hinglish = requested_language == "hinglish";
        auto p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
        p.greedy.best_of = 1;
        // Avoid repeated temperature retries and unbounded hallucinated output
        // on short code-switched phrases. These retries stall live updates.
        p.temperature_inc = 0;
        p.max_tokens = std::clamp(count / 16000 * 12 + 48, 96, 448);
        p.n_threads = std::clamp(threads, 1, 4);
        // Whisper's translate task emits English from Hindi/mixed speech,
        // matching the English review/card flow and avoiding script-dependent
        // token truncation before Qwen sees the complete purchases.
        p.translate = requested_language != "en";
        p.no_context = true;
        p.no_timestamps = true;
        p.print_progress = false;
        p.print_realtime = false;
        p.print_timestamps = false;
        p.print_special = false;
        p.language = hinglish ? "hi" : (std::strlen(language) ? language : "auto");
        // Hinglish uses Hindi-language decoding and emits an English translation.
        // Do not seed synthetic expense text: weak multilingual decodes can
        // repeat that prompt instead of the actual speech.
        p.initial_prompt = nullptr;
        p.abort_callback = cancelled;
        p.abort_callback_user_data = cancel;
        if (whisper_full(ctx, p, pcm, count) != 0 || cancelled(cancel)) {
            model_session().unload_whisper();
            throw std::runtime_error(cancelled(cancel) ? "Cancelled" : "Whisper transcription failed");
        }
        std::string text;
        for (int i = 0; i < whisper_full_n_segments(ctx); ++i) {
            text += whisper_full_get_segment_text(ctx, i);
        }
        return text;
}

static std::string extract(const char * model_path, const char * prompt, const char * grammar,
    int32_t threads, int32_t * cancel, GpuSelection gpu) {
        if (cancelled(cancel)) throw std::runtime_error("Cancelled");
        diagnostic(std::string("Qwen backend: ") + (gpu.device ? ggml_backend_dev_description(gpu.device) : "CPU"));
        auto * model = load_qwen(model_path, gpu, cancel);
        const auto * vocab = llama_model_get_vocab(model);
        int n = -llama_tokenize(vocab, prompt, std::strlen(prompt), nullptr, 0, true, true);
        if (n <= 0 || n > 2600) throw std::runtime_error("Transcript is too long; split it into shorter recordings");
        std::vector<llama_token> tokens(n);
        if (llama_tokenize(vocab, prompt, std::strlen(prompt), tokens.data(), n, true, true) < 0) {
            throw std::runtime_error("Could not tokenize transcript");
        }
        auto cp = llama_context_default_params();
        cp.n_ctx = std::max(2048, n + 1400);
        constexpr int batch_size = 256;
        cp.n_batch = batch_size;
        cp.n_threads = cp.n_threads_batch = std::clamp(threads, 1, 4);
        cp.offload_kqv = cp.op_offload = gpu.device != nullptr;
        // Standard attention keeps Qwen's small decode graph on OpenCL;
        // this is faster than the mixed CPU/GPU fused-attention graph here.
        if (adreno_gpu(gpu)) cp.flash_attn_type = LLAMA_FLASH_ATTN_TYPE_DISABLED;
        cp.abort_callback = cancelled;
        cp.abort_callback_data = cancel;
        std::unique_ptr<llama_context, decltype(&llama_free)> ctx(
            llama_init_from_model(model, cp), llama_free);
        if (!ctx) throw std::runtime_error("Not enough memory to create the Qwen context");
        std::unique_ptr<llama_sampler, decltype(&llama_sampler_free)> sampler(
            llama_sampler_chain_init(llama_sampler_chain_default_params()), llama_sampler_free);
        auto * constrained = llama_sampler_init_grammar(vocab, grammar, "root");
        if (!constrained) throw std::runtime_error("Could not initialize expense JSON grammar");
        llama_sampler_chain_add(sampler.get(), constrained);
        llama_sampler_chain_add(sampler.get(), llama_sampler_init_greedy());
        for (int pos = 0; pos < n; pos += batch_size) {
            if (cancelled(cancel)) throw std::runtime_error("Cancelled");
            auto batch = llama_batch_get_one(tokens.data() + pos, std::min(batch_size, n - pos));
            if (llama_decode(ctx.get(), batch) != 0) throw std::runtime_error("Qwen prompt evaluation failed");
        }
        std::string text;
        for (int i = 0; i < 1400; ++i) {
            if (cancelled(cancel)) throw std::runtime_error("Cancelled");
            auto token = llama_sampler_sample(sampler.get(), ctx.get(), -1);
            if (llama_vocab_is_eog(vocab, token)) return text;
            char piece[1024];
            int length = llama_token_to_piece(vocab, token, piece, sizeof(piece), 0, true);
            if (length < 0) throw std::runtime_error("Generated token exceeds buffer");
            text.append(piece, length);
            auto batch = llama_batch_get_one(&token, 1);
            if (llama_decode(ctx.get(), batch) != 0) throw std::runtime_error("Qwen generation failed");
        }
        throw std::runtime_error("Expense extraction exceeded the output limit; use a shorter recording");
}

template<typename Run> static char * run_inference(const char * stage, int32_t * cancel, Run run) {
    std::lock_guard<std::mutex> lock(inference_mutex);
    InferenceTimer timer{stage};
    try {
        std::vector<GpuSelection> candidates;
        try { candidates = available_accelerators(); }
        catch (const std::exception & e) { diagnostic(std::string("Accelerators unavailable: ") + e.what()); }
        for (auto gpu : candidates) {
            try {
                prepare_gpu(gpu);
                auto text = run(gpu);
                last_backend = ggml_backend_dev_name(gpu.device);
                return result(text);
            }
            catch (const std::exception & e) {
                if (cancelled(cancel)) throw;
                diagnostic(std::string(stage) + " " + ggml_backend_dev_name(gpu.device) + " failed; trying next backend: " + e.what());
                model_session().unload_whisper();
                model_session().unload_qwen();
            }
        }
        auto text = run({});
        last_backend = "CPU";
        return result(text);
    } catch (const std::exception & e) { return result(std::string("ERROR:") + e.what()); }
}

// Whisper owns its backend chain. Qwen's GGML Hexagon/Vulkan selection above
// is unchanged. Explicit GPU/CPU preferences still allow diagnostic comparisons.
template<typename NpuRun, typename Run>
static char * run_whisper(int32_t * cancel, NpuRun npu_run, Run run) {
    std::lock_guard<std::mutex> lock(inference_mutex);
    InferenceTimer timer{"Whisper"};
    last_backend = "Not run";
    try {
        if (cancelled(cancel)) throw std::runtime_error("Cancelled");
#ifdef __ANDROID__
        const char * override = std::getenv("KHARCHIO_AI_BACKEND");
        const std::string requested = override ? override : "";
        if ((processing_mode == 2 || processing_mode == 3) && (requested.empty() || requested == "npu")) {
            try {
                model_session().unload_qwen();
                if (model_session().whisper) model_session().unload_whisper();
                auto text = npu_run();
                last_backend = processing_mode == 3 ? "QNN/QAIRT HTP NPU (S23 Ultra)" : "QNN/QAIRT HTP NPU (Generic DLC)";
                return result(text);
            } catch (const std::exception & e) {
                whisper_qnn::release();
                if (cancelled(cancel)) throw;
                diagnostic(std::string("Whisper QNN failed; trying OpenCL then CPU: ") + e.what());
            }
        }
#endif
        std::vector<GpuSelection> candidates;
        try { candidates = available_accelerators(true); }
        catch (const std::exception & e) { diagnostic(std::string("Whisper GPU unavailable: ") + e.what()); }
        for (auto gpu : candidates) {
            const std::string name = ggml_backend_dev_name(gpu.device);
#ifdef __ANDROID__
            if (name.find("OpenCL") == std::string::npos) continue;
#else
            if (name.find("Metal") == std::string::npos) continue;
#endif
            try {
                prepare_gpu(gpu);
                auto text = run(gpu);
                last_backend = name;
                return result(text);
            } catch (const std::exception & e) {
                model_session().unload_whisper();
                if (cancelled(cancel)) throw;
                diagnostic("Whisper " + name + " failed; trying CPU: " + e.what());
            }
        }
        auto text = run({});
        last_backend = "CPU";
        return result(text);
    } catch (const std::exception & e) { return result(std::string("ERROR:") + e.what()); }
}

EXPORT char * kharchio_transcribe(const char * model_path, const float * pcm,
    int32_t count, const char * language, int32_t threads, int32_t * cancel) {
    return run_whisper(cancel, [&] {
        return whisper_qnn::transcribe(model_path, pcm, count, language, cancel, processing_mode == 2);
    }, [&](GpuSelection gpu) {
        return transcribe(model_path, pcm, count, language, threads, cancel, gpu);
    });
}
EXPORT char * kharchio_extract(const char * model_path, const char * prompt, const char * grammar,
    int32_t threads, int32_t * cancel) {
    return run_inference("Qwen", cancel, [&](GpuSelection gpu) {
        return extract(model_path, prompt, grammar, threads, cancel, gpu);
    });
}
EXPORT char * kharchio_prepare_whisper(const char * path, int32_t * cancel) {
    return run_whisper(cancel, [&] {
        whisper_qnn::prepare(path, cancel, processing_mode == 2); return std::string("ready");
    }, [&](GpuSelection gpu) {
        load_whisper(path, gpu, cancel); return std::string("ready");
    });
}
EXPORT char * kharchio_prepare_qwen(const char * path, int32_t * cancel) {
    return run_inference("Qwen load", cancel, [&](GpuSelection gpu) {
        load_qwen(path, gpu, cancel); return std::string("ready");
    });
}
EXPORT void kharchio_release_models() {
    std::lock_guard<std::mutex> lock(inference_mutex);
    model_session().unload_whisper();
    model_session().unload_qwen();
}
EXPORT void kharchio_set_processing(int32_t gpu) {
    std::lock_guard<std::mutex> lock(inference_mutex);
    const int selected = std::clamp(gpu, 0, 3);
    if (selected != processing_mode) {
        model_session().unload_whisper();
        model_session().unload_qwen();
    }
    processing_mode = selected;
    diagnostic(std::string("Processing preference: ") + (selected == 3 ? "S23 Ultra NPU -> OpenCL -> CPU" : selected == 2 ? "NPU -> OpenCL -> CPU" : selected == 1 ? "GPU with CPU fallback" : "CPU only"));
}
EXPORT char * kharchio_last_backend() {
    std::lock_guard<std::mutex> lock(inference_mutex);
    return result(last_backend);
}
