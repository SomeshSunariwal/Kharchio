# Native AI

Runtime code lives in `src/`, pinned downloads in `config/`, build helpers in
`cmake/`, and export tooling in `tools/models/`. Generated dependencies stay in
ignored `vendor/` and `prebuilt/` directories.

- [Full Android build and AI dependency setup](../BUILD.md)

Run `setup.ps1` from the repository root before the first build. The app
itself performs no SDK downloads or Python exports.
