$ErrorActionPreference = 'Stop'
$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
# Pin SDK/compiler image as well as the engine revision used by the application.
$image = 'ghcr.io/snapdragon-toolchain/arm64-android@sha256:e39e5e9c0957550a92c0de756b7556d81196c7c7f7328ed80de252bfb4878adf'
& docker run --rm --mount "type=bind,source=$workspace,target=/workspace" -w /workspace $image bash native/tools/build_hexagon.sh
if ($LASTEXITCODE -ne 0) { throw 'Hexagon build failed. Existing artifacts were preserved.' }
