# Native AI

Runtime code lives in `src/`, pinned downloads in `config/`, build helpers in
`cmake/`, and export tooling in `tools/models/`. Generated dependencies stay in
ignored `vendor/` and `prebuilt/` directories.

- [Full Android build and AI dependency setup](../BUILD.md)

Run `setup.ps1` from the repository root before the first build. The app
itself performs no SDK downloads or Python exports.

Offline speech retains the original English-output behavior: English transcribes
English; Automatic detects the spoken language and translates to English; Hinglish
uses Hindi/mixed recognition and translates to English. Offline Qwen also writes
English review cards. CPU/GPU and QNN share `src/whisper_language.h`.

Online-provider hybrid modes that use local Whisper (Claude and OpenRouter
fallback) use these same local English-output rules. Only actual online speech
models use the separate online speech-output behavior.
