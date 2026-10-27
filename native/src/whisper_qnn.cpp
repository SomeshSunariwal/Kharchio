#include "whisper_qnn.h"
#include "whisper_audio.h"
#include <cctype>
#include <cstring>
#include <memory>
#include <filesystem>

#if defined(__ANDROID__) && defined(KHARCHIO_HAS_QNN)
#include "QnnInterface.h"
#include "System/QnnSystemInterface.h"
#include "ggml.h"
#include <dlfcn.h>
#include <android/log.h>
#include <sys/system_properties.h>
#include <unordered_map>

namespace whisper_qnn
{
    namespace
    {
        void checked(Qnn_ErrorHandle_t status, const char *operation)
        {
            if (status != QNN_SUCCESS)
                throw std::runtime_error(std::string("QNN ") + operation + " failed (" + std::to_string(status) + ")");
        }
        struct Library
        {
            void *handle;
            explicit Library(const char *name) : handle(dlopen(name, RTLD_NOW | RTLD_LOCAL))
            {
                if (!handle)
                    throw std::runtime_error(std::string("Cannot load ") + name);
            }
            ~Library() { dlclose(handle); }
            template <class T>
            T symbol(const char *name)
            {
                auto fn = reinterpret_cast<T>(dlsym(handle, name));
                if (!fn)
                    throw std::runtime_error(std::string("Missing QNN symbol ") + name);
                return fn;
            }
        };
        struct Runtime
        {
            Library htp{"libQnnHtp.so"}, system{"libQnnSystem.so"};
            QNN_INTERFACE_VER_TYPE api{};
            QnnInterface_t provider{};
            QNN_SYSTEM_INTERFACE_VER_TYPE sys{};
            Qnn_BackendHandle_t backend = nullptr;
            Qnn_DeviceHandle_t device = nullptr;
            Qnn_LogHandle_t logger = nullptr;
            Runtime()
            {
                const QnnInterface_t **providers = nullptr;
                uint32_t count = 0;
                checked(htp.symbol<decltype(&QnnInterface_getProviders)>("QnnInterface_getProviders")(&providers, &count), "providers");
                bool found = false;
                for (uint32_t i = 0; i < count; ++i)
                {
                    auto version = providers[i]->apiVersion.coreApiVersion;
                    if (providers[i]->backendId == 6 && version.major == QNN_API_VERSION_MAJOR && version.minor >= QNN_API_VERSION_MINOR)
                    {
                        api = providers[i]->QNN_INTERFACE_VER_NAME;
                        provider = *providers[i];
                        found = true;
                        break;
                    }
                }
                if (!found)
                    throw std::runtime_error("Incompatible QNN HTP API");
                const QnnSystemInterface_t **systems = nullptr;
                checked(system.symbol<decltype(&QnnSystemInterface_getProviders)>("QnnSystemInterface_getProviders")(&systems, &count), "system providers");
                found = false;
                for (uint32_t i = 0; i < count; ++i)
                {
                    auto version = systems[i]->systemApiVersion;
                    if (version.major == QNN_SYSTEM_API_VERSION_MAJOR && version.minor >= QNN_SYSTEM_API_VERSION_MINOR)
                    {
                        sys = systems[i]->QNN_SYSTEM_INTERFACE_VER_NAME;
                        found = true;
                        break;
                    }
                }
                if (!found)
                    throw std::runtime_error("Incompatible QNN System API");
                api.logCreate([](const char * fmt, QnnLog_Level_t, uint64_t, va_list args) {
                    __android_log_vprint(ANDROID_LOG_WARN, "WhisperQNN", fmt, args);
                }, QNN_LOG_LEVEL_WARN, &logger);
                try
                {
                    checked(api.backendCreate(logger, nullptr, &backend), "HTP backend creation");
                    checked(api.deviceCreate(logger, nullptr, &device), "HTP device creation");
                }
                catch (...)
                {
                    if (backend) api.backendFree(backend);
                    backend = nullptr;
                    if (logger) api.logFree(logger);
                    throw;
                }
            }
            ~Runtime()
            {
                if (device)
                    api.deviceFree(device);
                if (backend)
                    api.backendFree(backend);
                if (logger)
                    api.logFree(logger);
            }
        };
        template <class F>
        auto tensor_field(Qnn_Tensor_t &t, F f)
        {
            if (t.version == QNN_TENSOR_VERSION_1)
                return f(t.v1);
            if (t.version == QNN_TENSOR_VERSION_2)
                return f(t.v2);
            throw std::runtime_error("Unsupported QNN tensor version");
        }
        struct Tensor
        {
            Qnn_Tensor_t value;
            std::vector<uint32_t> buffer;
            std::string name;
            size_t elements = 1;
            Qnn_DataType_t type;
            explicit Tensor(Qnn_Tensor_t source) : value(source)
            {
                tensor_field(value, [&](auto &t)
                             {
            name = t.name; type = t.dataType;
            for (uint32_t i = 0; i < t.rank; ++i) {
                if (!t.dimensions[i] || elements > (1u << 28) / t.dimensions[i]) throw std::runtime_error("Invalid QNN tensor dimensions");
                elements *= t.dimensions[i];
            }
            if (type != QNN_DATATYPE_FLOAT_32 && type != QNN_DATATYPE_FLOAT_16 && type != QNN_DATATYPE_INT_32)
                throw std::runtime_error("Whisper QNN profile requires float or int32 I/O");
            const size_t bytes = elements * (type == QNN_DATATYPE_FLOAT_16 ? 2 : 4);
            buffer.resize((bytes + 3) / 4);
            t.memType = QNN_TENSORMEMTYPE_RAW;
            t.clientBuf = {buffer.data(), static_cast<uint32_t>(bytes)}; });
            }
            float get(size_t i) const
            {
                if (type == QNN_DATATYPE_FLOAT_16)
                    return ggml_fp16_to_fp32(reinterpret_cast<const ggml_fp16_t *>(buffer.data())[i]);
                if (type == QNN_DATATYPE_INT_32)
                    return reinterpret_cast<const int32_t *>(buffer.data())[i];
                return reinterpret_cast<const float *>(buffer.data())[i];
            }
            void set(size_t i, float f)
            {
                if (type == QNN_DATATYPE_FLOAT_16)
                    reinterpret_cast<ggml_fp16_t *>(buffer.data())[i] = ggml_fp32_to_fp16(f);
                else if (type == QNN_DATATYPE_INT_32)
                    reinterpret_cast<int32_t *>(buffer.data())[i] = static_cast<int32_t>(f);
                else
                    reinterpret_cast<float *>(buffer.data())[i] = f;
            }
            void copy(const Tensor &from)
            {
                if (elements != from.elements)
                    throw std::runtime_error("Whisper QNN cache shape mismatch: " + name);
                if (type == from.type)
                    std::memcpy(buffer.data(), from.buffer.data(), elements * (type == QNN_DATATYPE_FLOAT_16 ? 2 : 4));
                else
                    for (size_t i = 0; i < elements; ++i)
                        set(i, from.get(i));
            }
        };
        struct Graph
        {
            Runtime &rt;
            QnnSystemContext_Handle_t metadata = nullptr;
            Qnn_ContextHandle_t context = nullptr;
            Qnn_GraphHandle_t graph = nullptr;
            QnnSystemDlc_Handle_t dlc = nullptr;
            QnnSystemContext_GraphInfo_t * dlc_graphs = nullptr;
            uint32_t dlc_graph_count = 0;
            std::vector<std::unique_ptr<Tensor>> inputs, outputs;
            std::vector<Qnn_Tensor_t> input_values, output_values;
            explicit Graph(Runtime &runtime) : rt(runtime) {}
            ~Graph()
            {
                if (context)
                    rt.api.contextFree(context, nullptr);
                if (metadata)
                    rt.sys.systemContextFree(metadata);
                if (dlc_graphs) {
                    for (uint32_t i = 0; i < dlc_graph_count; ++i) {
                        std::free(const_cast<char *>(dlc_graphs[i].graphInfoV1.graphName));
                        std::free(dlc_graphs[i].graphInfoV1.graphInputs);
                        std::free(dlc_graphs[i].graphInfoV1.graphOutputs);
                    }
                    std::free(dlc_graphs);
                }
                if (dlc) rt.sys.systemDlcFree(dlc);
            }
            void load(const std::string &path, int32_t *cancel, bool s23 = true)
            {
                check_cancel(cancel);
                std::ifstream file(path, std::ios::binary | std::ios::ate);
                const auto size = file.tellg();
                if (!file || size <= 0 || size > 1024LL * 1024 * 1024)
                    throw std::runtime_error("Missing or invalid QNN context: " + path);
                std::vector<char> binary(static_cast<size_t>(size));
                file.seekg(0);
                if (!file.read(binary.data(), size))
                    throw std::runtime_error("Incomplete QNN context: " + path);
                checked(rt.sys.systemContextCreate(&metadata), "metadata creation");
                const QnnSystemContext_BinaryInfo_t *info = nullptr;
                Qnn_ContextBinarySize_t info_size = 0;
                checked(rt.sys.systemContextGetBinaryInfo(metadata, binary.data(), binary.size(), &info, &info_size), "metadata read");
                if (info->version != QNN_SYSTEM_CONTEXT_BINARY_INFO_VERSION_3 ||
                    info->contextBinaryInfoV3.backendId != 6 || (s23 && info->contextBinaryInfoV3.socModel != 43))
                    throw std::runtime_error("Whisper context does not match the requested HTP profile");
                QnnSystemContext_GraphInfo_t *graphs = nullptr;
                uint32_t count = 0;
                if (info->version == QNN_SYSTEM_CONTEXT_BINARY_INFO_VERSION_1)
                {
                    graphs = info->contextBinaryInfoV1.graphs;
                    count = info->contextBinaryInfoV1.numGraphs;
                }
                else if (info->version == QNN_SYSTEM_CONTEXT_BINARY_INFO_VERSION_2)
                {
                    graphs = info->contextBinaryInfoV2.graphs;
                    count = info->contextBinaryInfoV2.numGraphs;
                }
                else if (info->version == QNN_SYSTEM_CONTEXT_BINARY_INFO_VERSION_3)
                {
                    graphs = info->contextBinaryInfoV3.graphs;
                    count = info->contextBinaryInfoV3.numGraphs;
                }
                if (count != 1)
                    throw std::runtime_error("Expected one graph per Whisper context");
                std::string name;
                auto read_graph = [&](auto &g)
                {
                    name = g.graphName;
                    for (uint32_t i = 0; i < g.numGraphInputs; ++i)
                        inputs.push_back(std::make_unique<Tensor>(g.graphInputs[i]));
                    for (uint32_t i = 0; i < g.numGraphOutputs; ++i)
                        outputs.push_back(std::make_unique<Tensor>(g.graphOutputs[i]));
                };
                if (graphs->version == QNN_SYSTEM_CONTEXT_GRAPH_INFO_VERSION_1)
                    read_graph(graphs->graphInfoV1);
                else if (graphs->version == QNN_SYSTEM_CONTEXT_GRAPH_INFO_VERSION_2)
                    read_graph(graphs->graphInfoV2);
                else if (graphs->version == QNN_SYSTEM_CONTEXT_GRAPH_INFO_VERSION_3)
                    read_graph(graphs->graphInfoV3);
                else
                    throw std::runtime_error("Unsupported QNN graph metadata");
                check_cancel(cancel);
                checked(rt.api.contextCreateFromBinary(rt.backend, rt.device, nullptr, binary.data(), binary.size(), &context, nullptr), "context load");
                checked(rt.api.graphRetrieve(context, name.c_str(), &graph), "graph retrieval");
                for (auto &t : inputs)
                    input_values.push_back(t->value);
                for (auto &t : outputs)
                    output_values.push_back(t->value);
            }
            void load_portable(const std::string & path, const std::string & cache, int32_t * cancel) {
                if (std::filesystem::exists(cache)) {
                    try { load(cache, cancel, false); return; }
                    catch (...) {
                        if (context) { rt.api.contextFree(context, nullptr); context = nullptr; }
                        if (metadata) { rt.sys.systemContextFree(metadata); metadata = nullptr; }
                        inputs.clear(); outputs.clear(); input_values.clear(); output_values.clear();
                        check_cancel(cancel);
                        std::remove(cache.c_str());
                    }
                }
                check_cancel(cancel);
                checked(rt.sys.systemDlcCreateFromFile(nullptr, path.c_str(), &dlc), "portable DLC load");
                checked(rt.api.contextCreate(rt.backend, rt.device, nullptr, &context), "portable context creation");
                checked(rt.sys.systemDlcComposeGraphs(dlc, nullptr, 0, rt.backend, context, rt.provider,
                    QNN_SYSTEM_CONTEXT_GRAPH_INFO_VERSION_1, &dlc_graphs, &dlc_graph_count), "portable graph composition");
                if (dlc_graph_count != 1 || dlc_graphs->version != QNN_SYSTEM_CONTEXT_GRAPH_INFO_VERSION_1)
                    throw std::runtime_error("Expected one graph per Whisper DLC");
                auto & g = dlc_graphs->graphInfoV1;
                checked(rt.api.graphRetrieve(context, g.graphName, &graph), "portable graph retrieval");
                check_cancel(cancel);
                checked(rt.api.graphFinalize(graph, nullptr, nullptr), "portable HTP compilation");
                check_cancel(cancel);
                for (uint32_t i = 0; i < g.numGraphInputs; ++i) inputs.push_back(std::make_unique<Tensor>(g.graphInputs[i]));
                for (uint32_t i = 0; i < g.numGraphOutputs; ++i) outputs.push_back(std::make_unique<Tensor>(g.graphOutputs[i]));
                for (auto & t : inputs) input_values.push_back(t->value);
                for (auto & t : outputs) output_values.push_back(t->value);
                // Cache failures do not prevent NPU inference. A bad or stale cache
                // is recompiled from the portable graph at the next load.
                Qnn_ContextBinarySize_t size = 0, written = 0;
                if (rt.api.contextGetBinarySize(context, &size) == QNN_SUCCESS && size > 0 && size < 1024LL * 1024 * 1024) {
                    std::vector<char> bytes(size);
                    if (rt.api.contextGetBinary(context, bytes.data(), size, &written) == QNN_SUCCESS) {
                        auto partial = cache + ".partial";
                        std::ofstream output(partial, std::ios::binary);
                        output.write(bytes.data(), written); output.close();
                        if (output) std::rename(partial.c_str(), cache.c_str());
                    }
                }
            }
            Tensor &input(const std::string &name) { return find(inputs, name); }
            Tensor &output(const std::string &name) { return find(outputs, name); }
            static Tensor &find(std::vector<std::unique_ptr<Tensor>> &tensors, const std::string &name)
            {
                for (auto &t : tensors)
                    if (t->name == name)
                        return *t;
                throw std::runtime_error("Missing Whisper QNN tensor: " + name);
            }
            void execute(int32_t *cancel)
            {
                check_cancel(cancel);
                checked(rt.api.graphExecute(graph, input_values.data(), input_values.size(), output_values.data(), output_values.size(), nullptr, nullptr), "HTP execution");
                check_cancel(cancel);
            }
        };
        struct Session
        {
            std::string path;
            bool portable;
            AudioMetadata audio;
            Runtime runtime;
            Graph encoder{runtime}, decoder{runtime};
            Session(const char *ggml, int32_t *cancel, bool generic) : path(ggml), portable(generic), audio(audio_metadata_path(ggml).c_str())
            {
                const auto root = path.substr(0, path.find_last_of("/\\") + 1);
                if (portable) {
                    const auto folder = root + "whisper-qnn-generic/";
                    std::string revision;
                    std::ifstream version(folder + "revision.txt"); version >> revision;
                    if (revision.size() != 64 || revision.find_first_not_of("0123456789abcdef") != std::string::npos)
                        throw std::runtime_error("Portable Whisper DLC is not installed");
                    char soc[PROP_VALUE_MAX]{}, build[PROP_VALUE_MAX]{};
                    __system_property_get("ro.soc.model", soc);
                    __system_property_get("ro.build.version.incremental", build);
                    std::string device = std::string(soc) + build;
                    device.erase(std::remove_if(device.begin(), device.end(), [](unsigned char c) { return !std::isalnum(c); }), device.end());
                    if (device.size() > 64) device.resize(64);
                    const auto cache = folder + "cache/" + device + "-qairt250-" + revision;
                    std::filesystem::create_directories(folder + "cache");
                    encoder.load_portable(folder + "encoder.dlc", cache + "-encoder.bin", cancel);
                    decoder.load_portable(folder + "decoder.dlc", cache + "-decoder.bin", cancel);
                } else {
                    const auto folder = root + "whisper-qnn-sm8550/";
                    encoder.load(folder + "encoder.bin", cancel);
                    decoder.load(folder + "decoder.bin", cancel);
                }
                // Reject a different export contract before reporting NPU readiness.
                if (encoder.input("input_features").elements != 80 * 3000 || decoder.input("attention_mask").elements != 200 ||
                    decoder.output("logits").elements != 51865 || decoder.input("input_ids").elements != 1 || decoder.input("position_ids").elements != 1)
                    throw std::runtime_error("Wrong Whisper QNN model profile");
                for (int layer = 0; layer < 12; ++layer)
                    for (const char *prefix : {"k", "v"})
                    {
                        auto cross = std::string(prefix) + "_cache_cross_" + std::to_string(layer);
                        if (encoder.output(cross).elements != decoder.input(cross).elements)
                            throw std::runtime_error("Wrong Whisper cross cache profile");
                        auto self = std::string(prefix) + "_cache_self_" + std::to_string(layer);
                        if (decoder.output(self + "_out").elements != decoder.input(self + "_in").elements)
                            throw std::runtime_error("Wrong Whisper self cache profile");
                    }
            }
            std::string chunk(const float *pcm, int count, const std::string &language, int32_t *cancel)
            {
                auto features = audio.mel(pcm, count, cancel);
                auto &mel = encoder.input("input_features");
                for (size_t i = 0; i < features.size(); ++i)
                    mel.set(i, features[i]);
                encoder.execute(cancel);
                for (auto &t : decoder.inputs)
                    std::fill(t->buffer.begin(), t->buffer.end(), 0);
                for (int layer = 0; layer < 12; ++layer)
                    for (const char *prefix : {"k", "v"})
                    {
                        auto name = std::string(prefix) + "_cache_cross_" + std::to_string(layer);
                        decoder.input(name).copy(encoder.output(name));
                    }
                auto &mask = decoder.input("attention_mask");
                for (size_t i = 0; i < mask.elements; ++i)
                    mask.set(i, -100.0f);
                auto step = [&](int token, int pos) -> Tensor &
                {
                    decoder.input("input_ids").set(0, token);
                    decoder.input("position_ids").set(0, pos);
                    mask.set(199 - pos, 0);
                    decoder.execute(cancel);
                    for (int layer = 0; layer < 12; ++layer)
                        for (const char *prefix : {"k", "v"})
                        {
                            auto name = std::string(prefix) + "_cache_self_" + std::to_string(layer);
                            decoder.input(name + "_in").copy(decoder.output(name + "_out"));
                        }
                    return decoder.output("logits");
                };
                auto argmax = [](Tensor &logits, int begin, int end)
                {
                    int token = begin;
                    float best = -INFINITY;
                    for (int i = begin; i < end; ++i)
                        if (std::isfinite(logits.get(i)) && logits.get(i) > best)
                        {
                            best = logits.get(i);
                            token = i;
                        }
                    if (!std::isfinite(best))
                        throw std::runtime_error("Invalid Whisper QNN logits");
                    return token;
                };
                // Multilingual Whisper Small token IDs. Match the existing English
                // transcription / Hindi-to-English translation behavior.
                auto &first = step(50258, 0);
                int lang = language == "en" ? 50259 : language == "hinglish" || language == "hi" ? 50276
                                                                                                 : argmax(first, 50259, 50358);
                step(lang, 1);
                step(language == "en" ? 50359 : 50358, 2);
                Tensor *logits = &step(50363, 3); // no timestamps
                std::string text;
                for (int pos = 4; pos < 199; ++pos)
                {
                    const int token = argmax(*logits, 0, 50258); // text or EOT only
                    if (token == 50257)
                        return text;
                    if (token < static_cast<int>(audio.vocab.size()))
                        text += audio.vocab[token];
                    logits = &step(token, pos);
                }
                // Never return an apparently successful but truncated recording.
                throw std::runtime_error("Whisper QNN decoder reached its 200-token context; using fallback");
            }
        };
        std::unique_ptr<Session> session;
    }
    void prepare(const char *path, int32_t *cancel, bool portable)
    {
        check_cancel(cancel);
        char soc[PROP_VALUE_MAX]{};
        __system_property_get("ro.soc.model", soc);
        // Qualcomm QCS8550 Proxy and SM8550 share SoC model 43 / HTP v73.
        std::string model(soc);
        std::transform(model.begin(), model.end(), model.begin(), [](unsigned char c)
                       { return std::toupper(c); });
        if (!portable && model.find("SM8550") == std::string::npos)
            throw std::runtime_error("Whisper QNN profile targets SM8550 (Snapdragon 8 Gen 2); device is " + model);
        if (!session || session->path != path || session->portable != portable) {
            session.reset();
            session = std::make_unique<Session>(path, cancel, portable);
        }
        check_cancel(cancel);
    }
    std::string transcribe(const char *path, const float *pcm, int32_t count, const char *language, int32_t *cancel, bool portable)
    {
        if (!pcm || count <= 0 || count > 90 * 16000)
            throw std::runtime_error("Whisper expects 1–90 seconds of 16 kHz audio");
        prepare(path, cancel, portable);
        std::string text;
        for (int offset = 0; offset < count; offset += 480000)
        {
            auto chunk = session->chunk(pcm + offset, std::min(480000, count - offset), language, cancel);
            if (!text.empty() && !chunk.empty())
                text += ' ';
            text += chunk;
        }
        return text;
    }
    void release() { session.reset(); }
}
#else
namespace whisper_qnn
{
    void prepare(const char *, int32_t *, bool) { throw std::runtime_error("QNN runtime is not packaged for this platform"); }
    std::string transcribe(const char *, const float *, int32_t, const char *, int32_t *, bool) { throw std::runtime_error("QNN runtime unavailable"); }
    void release() {}
}
#endif
