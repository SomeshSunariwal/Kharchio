#!/usr/bin/env bash
set -euo pipefail
root=/workspace
build="$root/.tmp/hexagon-build"
source="$root/native/vendor/llama.cpp"
expected=d854d98bae598388ecea1ed84396587e5edc326d
actual=$(git -c safe.directory="$source" -C "$source" rev-parse HEAD)
if [ "$actual" != "$expected" ]; then
  echo "Hexagon must use the same pinned GGML revision as the app" >&2
  exit 1
fi
cmake -S "$source" -B "$build" -G Ninja \
  -DCMAKE_TOOLCHAIN_FILE="$ANDROID_NDK_ROOT/build/cmake/android.toolchain.cmake" \
  -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-24 \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF \
  -DGGML_BACKEND_DL=OFF -DGGML_NATIVE=OFF -DGGML_CPU=OFF \
  -DGGML_OPENCL=OFF -DGGML_VULKAN=OFF -DGGML_OPENMP=OFF \
  -DGGML_HEXAGON=ON -DHEXAGON_SDK_ROOT="$HEXAGON_SDK_ROOT" \
  -DHEXAGON_TOOLS_ROOT="$HEXAGON_TOOLS_ROOT" \
  -DPREBUILT_LIB_DIR=android_aarch64 \
  -DLLAMA_BUILD_TESTS=OFF -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF \
  -DLLAMA_BUILD_SERVER=OFF -DLLAMA_CURL=OFF -DLLAMA_OPENSSL=OFF
cmake --build "$build" --target ggml-hexagon htp-v73 htp-v75 htp-v79 htp-v81 -j 6
archive="$root/native/prebuilt/hexagon/arm64-v8a"
skels="$root/android/app/src/main/jniLibs/arm64-v8a"
mkdir -p "$archive" "$skels"
cp "$build/ggml/src/ggml-hexagon/libggml-hexagon.a" "$archive/"
for arch in v73 v75 v79 v81; do
  cp "$build/ggml/src/ggml-hexagon/libggml-htp-$arch.so" "$skels/"
done
printf '%s\n' "$expected" > "$archive/revision.txt"
echo 'Hexagon archive and DSP libraries ready for Android Gradle build.'
