#pragma once
#include <algorithm>
#include <array>
#include <cmath>
#include <complex>
#include <cstdint>
#include <fstream>
#include <stdexcept>
#include <string>
#include <vector>

namespace whisper_qnn
{
    inline std::string audio_metadata_path(const char *model)
    {
        const std::string path(model);
        const auto root = path.substr(0, path.find_last_of("/\\") + 1);
        const auto metadata = root + "whisper-small-metadata.dat";
        return std::ifstream(metadata, std::ios::binary).good() ? metadata : path;
    }

    inline void check_cancel(int32_t *cancel)
    {
        if (cancel && *static_cast<volatile int32_t *>(cancel))
            throw std::runtime_error("Cancelled");
    }

    // Read only the filters and byte vocabulary, never the GGML model weights.
    struct AudioMetadata
    {
        std::vector<float> filters;
        std::vector<std::string> vocab;
        explicit AudioMetadata(const char *path)
        {
            std::ifstream file(path, std::ios::binary);
            auto read = [&](void *dst, size_t bytes)
            {
                if (!file.read(static_cast<char *>(dst), bytes))
                    throw std::runtime_error("Invalid Whisper metadata");
            };
            uint32_t magic;
            read(&magic, 4);
            int32_t hp[11];
            read(hp, sizeof(hp));
            if (magic != 0x67676d6c || hp[0] != 51865 || hp[4] != 12 || hp[9] != 80)
                throw std::runtime_error("QNN requires multilingual Whisper Small metadata");
            int32_t mels, bins;
            read(&mels, 4);
            read(&bins, 4);
            if (mels != 80 || bins != 201)
                throw std::runtime_error("Invalid Whisper mel filters");
            filters.resize(mels * bins);
            read(filters.data(), filters.size() * 4);
            int32_t tokens;
            read(&tokens, 4);
            if (tokens < 50257 || tokens > 51865)
                throw std::runtime_error("Invalid Whisper vocabulary");
            for (int i = 0; i < tokens; ++i)
            {
                uint32_t bytes;
                read(&bytes, 4);
                if (bytes > 4096)
                    throw std::runtime_error("Invalid Whisper token");
                std::string token(bytes, '\0');
                read(token.data(), bytes);
                vocab.push_back(std::move(token));
            }
        }

        // Hugging Face WhisperFeatureExtractor: periodic Hann, centered reflect
        // padding, 400-point FFT, 160-sample hop, 30 s zero padding, Slaney filters.
        std::vector<float> mel(const float *pcm, int count, int32_t *cancel) const
        {
            constexpr int fft_size = 400, frames = 3000, samples = 480000;
            constexpr float pi = 3.14159265358979323846f;
            using C = std::complex<float>;
            std::array<C, fft_size> roots;
            std::array<float, fft_size> window;
            for (int i = 0; i < fft_size; ++i)
            {
                roots[i] = std::polar(1.0f, -2 * pi * i / fft_size);
                window[i] = 0.5f - 0.5f * std::cos(2 * pi * i / fft_size);
            }
            auto fft = [&](auto &&self, const C *input, int stride, int n, C *out) -> void
            {
                if (n == 1)
                {
                    out[0] = *input;
                    return;
                }
                const int radix = n % 2 == 0 ? 2 : 5, size = n / radix;
                std::array<C, fft_size> partial;
                for (int r = 0; r < radix; ++r)
                    self(self, input + r * stride, stride * radix, size, partial.data() + r * size);
                for (int k = 0; k < n; ++k)
                {
                    C sum = 0;
                    for (int r = 0; r < radix; ++r)
                        sum += partial[r * size + k % size] * roots[(r * k * (fft_size / n)) % fft_size];
                    out[k] = sum;
                }
            };
            std::vector<float> features(80 * frames);
            std::array<C, fft_size> input, spectrum;
            std::array<float, 201> power;
            for (int frame = 0; frame < frames; ++frame)
            {
                if (frame % 32 == 0)
                    check_cancel(cancel);
                for (int i = 0; i < fft_size; ++i)
                {
                    int pos = frame * 160 + i - 200;
                    if (pos < 0)
                        pos = -pos;
                    if (pos >= samples)
                        pos = 2 * samples - 2 - pos;
                    input[i] = (pos < count ? pcm[pos] : 0.0f) * window[i];
                }
                fft(fft, input.data(), 1, fft_size, spectrum.data());
                for (int k = 0; k < 201; ++k)
                    power[k] = std::norm(spectrum[k]);
                for (int m = 0; m < 80; ++m)
                {
                    double sum = 0;
                    for (int k = 0; k < 201; ++k)
                        sum += power[k] * filters[m * 201 + k];
                    features[m * frames + frame] = std::log10(std::max(1e-10, sum));
                }
            }
            const float floor = *std::max_element(features.begin(), features.end()) - 8.0f;
            for (float &f : features)
                f = (std::max(f, floor) + 4.0f) / 4.0f;
            return features;
        }
    };
}
