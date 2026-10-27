# Native AI

Runtime code lives in `src/`, pinned downloads in `config/`, build helpers in
`cmake/`, and export tooling in `tools/models/`. Generated dependencies stay in
ignored `vendor/` and `prebuilt/` directories.

- [Full application/AI code map](../docs/ai/CODE_MAP.md)
- [Model and runtime setup](../docs/ai/SETUP.md)
- [Whisper measurements](../docs/ai/WHISPER_BENCHMARKS.md)

Run preparation scripts from this directory before the first build. The app
itself performs no SDK downloads or Python exports.
