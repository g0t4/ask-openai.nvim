// Persistent Qwen3-TTS worker. Based on llama.cpp's tools/tts/tts.cpp (MIT).
// stdin: one JSON request per line. stdout: JSON metadata line, then repeated
// uint32 little-endian length + PCM16LE payload. Zero length ends a response.
// stdout is exclusively protocol data; llama.cpp diagnostics go to stderr.
#include "arg.h"
#include "common.h"
#include "sampling.h"
#include "log.h"
#include "llama.h"
#include "mtmd.h"
#include "mtmd-helper.h"
#include "nlohmann/json.hpp"

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>

using json = nlohmann::json;

static void write_bytes(const void * data, size_t size) {
    if (size && fwrite(data, 1, size, stdout) != size) {
        throw std::runtime_error("stdout write failed");
    }
}

static void write_length(uint32_t size) {
    const unsigned char b[] = {
        (unsigned char)size, (unsigned char)(size >> 8),
        (unsigned char)(size >> 16), (unsigned char)(size >> 24)};
    write_bytes(b, sizeof(b));
}

static void write_json(const json & value) {
    const auto line = value.dump() + "\n";
    write_bytes(line.data(), line.size());
    fflush(stdout);
}

int main(int argc, char ** argv) {
    common_params params;
    common_init();
    if (!common_params_parse(argc, argv, params, LLAMA_EXAMPLE_TTS)) return 1;
    mtmd_helper_log_set(common_log_default_callback, nullptr);
    params.embedding = true;
    llama_backend_init();
    llama_numa_init(params.numa);
    auto init = common_init_from_params(params);
    auto * model = init->model();
    auto * lctx = init->context();
    auto * sampler = init->sampler(0);
    if (!model || !lctx || !sampler) return 1;
    auto mp = mtmd_context_params_default();
    mp.use_gpu = params.mmproj_use_gpu;
    mp.device = params.mmproj_device;
    mtmd::context_ptr mctx(mtmd_init_from_file(params.mmproj.path.c_str(), model, mp));
    if (!mctx) return 1;
    const auto info = mtmd_gen_audio_get_info(mctx.get());
    if (info.type != MTMD_GEN_AUDIO_TYPE_QWEN3TTS) {
        LOG_ERR("voiced worker requires Qwen3-TTS\n");
        return 1;
    }
    using gen_ptr = std::unique_ptr<mtmd_helper_gen_audio, decltype(&mtmd_helper_gen_audio_free)>;
    gen_ptr gen(mtmd_helper_gen_audio_init(lctx, mctx.get()), mtmd_helper_gen_audio_free);
    if (!gen) return 1;
    write_json({{"ready", true}, {"sample_rate", info.sample_rate}});

    std::string line;
    while (std::getline(std::cin, line)) {
        // A generation failure exits the worker rather than leaving an ambiguous
        // partial response or reusing potentially corrupted inference state.
        try {
            const auto req = json::parse(line);
            const auto text = req.at("text").get<std::string>();
            const auto lang = req.value("lang", std::string("en"));
            const auto speaker = req.value("speaker_file", params.tts_speaker_file);
            const int chunk_frames = req.value("chunk_frames", 6);
            if (text.empty() || chunk_frames < 1 || chunk_frames > 72) {
                throw std::runtime_error("invalid text or chunk_frames");
            }
            const int64_t start = ggml_time_us();
            llama_memory_clear(llama_get_memory(lctx), true);
            common_sampler_reset(sampler);
            mtmd::bitmap_ptr bitmap;
            if (!speaker.empty()) {
                auto loaded = mtmd_helper_bitmap_init_from_file(
                    mctx.get(), speaker.c_str(), false, mtmd_helper_init_opt_default());
                if (!loaded.bitmap) throw std::runtime_error("speaker reference load failed");
                bitmap.reset(loaded.bitmap);
            }
            mtmd_helper_gen_audio_inp inp{};
            inp.seq_id = 0;
            inp.prompt = text.c_str();
            inp.prompt_len = text.size();
            inp.speaker_ref = bitmap.get();
            inp.lang = lang.c_str();
            inp.top_k = params.sampling.top_k;
            inp.top_p = params.sampling.top_p;
            inp.seed = params.sampling.seed;
            inp.out_type = MTMD_HELPER_GEN_AUDIO_OUTTYPE_PCM;
            if (mtmd_helper_gen_audio_set_input(gen.get(), &inp)) {
                throw std::runtime_error("set_input failed");
            }
            for (;;) {
                const auto left = mtmd_helper_gen_audio_step_prompt(gen.get(), params.n_batch);
                if (left < 0) throw std::runtime_error("prompt processing failed");
                if (left == 0) break;
            }
            write_json({{"sample_rate", info.sample_rate}});
            size_t sent = 0;
            bool first = true;
            auto emit = [&]() {
                int32_t rate;
                const char * data;
                size_t size;
                // On the pinned llama.cpp revision this flushes buffered codes,
                // preserving the vocoder state, and returns cumulative float PCM.
                // Send only the newly appended samples. No llama.cpp patch needed.
                if (mtmd_helper_gen_audio_get_output(gen.get(), &rate, &data, &size, nullptr)) {
                    throw std::runtime_error("audio decode failed");
                }
                if (size < sent || size % sizeof(float) || rate != info.sample_rate) {
                    throw std::runtime_error("invalid PCM output");
                }
                if (size == sent) return;
                const auto * pcm = reinterpret_cast<const float *>(data + sent);
                const size_t count = (size - sent) / sizeof(float);
                std::vector<unsigned char> bytes(count * 2);
                for (size_t i = 0; i < count; ++i) {
                    const auto v = (int16_t)(std::clamp(pcm[i], -1.0f, 1.0f) * 32767.0f);
                    bytes[2*i] = (unsigned char)v;
                    bytes[2*i+1] = (unsigned char)((uint16_t)v >> 8);
                }
                if (!bytes.empty()) {
                    write_length(bytes.size());
                    write_bytes(bytes.data(), bytes.size());
                    fflush(stdout);
                    if (first) {
                        LOG_INF("voiced first PCM: %.3f s\n", (ggml_time_us() - start) / 1e6);
                        first = false;
                    }
                }
                sent = size;
            };
            auto sample = [&]() {
                auto token = common_sampler_sample(sampler, lctx, -1);
                common_sampler_accept(sampler, token, true);
                return token;
            };
            auto token = sample();
            const float * h = llama_get_embeddings_ith(lctx, -1);
            bool stop = false;
            const int limit = params.n_predict > 0 ? params.n_predict : 2048;
            int frames = 0;
            while (!stop && frames < limit) {
                const float * next = nullptr;
                if (mtmd_helper_gen_audio_step_gen(gen.get(), token, h, &next, &stop)) {
                    throw std::runtime_error("generation failed");
                }
                if (!next) break;
                ++frames;
                if (frames % chunk_frames == 0) emit();
                h = next;
                token = sample();
            }
            if (!stop && frames == limit) throw std::runtime_error("speech frame limit reached");
            emit();
            write_length(0);
            fflush(stdout);
            LOG_INF("voiced complete: %.3f s, %d frames, %.3f s audio\n",
                (ggml_time_us() - start) / 1e6, frames,
                double(sent / sizeof(float)) / info.sample_rate);
        } catch (const std::exception & e) {
            LOG_ERR("voiced worker: %s\n", e.what());
            return 1;
        }
    }
    return 0;
}
