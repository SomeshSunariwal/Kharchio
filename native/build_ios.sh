#!/bin/bash
set -euo pipefail
native_root="$(cd "$(dirname "$0")" && pwd)"
output="$native_root/../ios/Frameworks/KharchioAI.xcframework"
revision="$(shasum -a 256 "$native_root/CMakeLists.txt" "$native_root/src/kharchio_ai.cpp" "$native_root/src/whisper_qnn.cpp" "$native_root/src/whisper_qnn.h" "$native_root/src/whisper_audio.h" | shasum -a 256 | cut -d ' ' -f 1)"
if [[ -f "$output/.build-revision" ]] && [[ "$(cat "$output/.build-revision")" == "$revision" ]]; then exit 0; fi
command -v cmake >/dev/null || { echo 'CMake is required to prepare the offline AI iOS library.' >&2; exit 1; }
archives=()
for sdk in iphoneos iphonesimulator; do
  build="$native_root/../build/ios-ai/$sdk"
  archs=arm64
  if [[ "$sdk" == iphonesimulator ]]; then archs='arm64;x86_64'; fi
  cmake -S "$native_root" -B "$build" -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
    -DCMAKE_OSX_ARCHITECTURES="$archs" -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 \
    -DCMAKE_XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED=NO
  cmake --build "$build" --config Release --target kharchio_ai --parallel 4
  libs=()
  while IFS= read -r -d '' archive; do libs+=("$archive"); done < <(find "$build" -name '*.a' ! -name 'KharchioAI.a' -print0)
  xcrun libtool -static -o "$build/KharchioAI.a" "${libs[@]}"
  archives+=( -library "$build/KharchioAI.a" )
done
mkdir -p "$(dirname "$output")"
staging="$native_root/../build/ios-ai/KharchioAI.xcframework"
if [[ -d "$staging" ]]; then rm -rf -- "$staging"; fi
xcodebuild -create-xcframework "${archives[@]}" -output "$staging"
if [[ -d "$output" ]]; then rm -rf -- "$output"; fi
mv "$staging" "$output"
printf '%s\n' "$revision" > "$output/.build-revision"
