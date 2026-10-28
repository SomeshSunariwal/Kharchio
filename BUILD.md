# Local setup guide

Follow this guide to set up everything on your local machine, from installing tools and configuring environment variables to preparing dependencies, building, and running Kharchio.

## Setup from a fresh clone (Windows 11 x64)

Use **PowerShell 7** for the commands below. Install the prerequisites, configure the paths, then let `setup.ps1` prepare the Android/AI dependencies. The resource inventory and troubleshooting sections below cover individual dependencies and failures.

### 1. Install prerequisites

| Tool           | Required selection                                              | Download / instructions                                                                                                                               |
| -------------- | --------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| PowerShell     | 7 or later                                                      | [Install PowerShell](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell-on-windows)                                 |
| Git            | Git for Windows, available on PATH                              | [Install Git](https://git-scm.com/install/windows)                                                                                                    |
| Python         | **3.12 x64**, including pip                                     | [Python Windows downloads](https://www.python.org/downloads/windows/)                                                                                 |
| Java           | **JDK 21**, including javac                                     | [Temurin JDK 21](https://adoptium.net/temurin/releases/?version=21)                                                                                   |
| Flutter        | **3.47.8**, with its bundled Dart SDK                           | [Flutter SDK archive](https://docs.flutter.dev/install/archive)                                                                                       |
| Android Studio | Install its Android SDK and **SDK Command-line Tools (latest)** | [Android Studio](https://developer.android.com/studio/install)                                                                                        |
| Docker Desktop | Running with **Linux containers** using WSL 2                   | [Docker Desktop](https://docs.docker.com/desktop/setup/install/windows-install/) · [WSL setup](https://learn.microsoft.com/en-us/windows/wsl/install) |

In Android Studio's SDK Manager, note the SDK location and install **Android SDK Command-line Tools (latest)**. The required entry point is `<SDK>/cmdline-tools/latest/bin/sdkmanager.bat`. Setup can then install missing **API 37**, **Build-Tools 36.0.0**, **Platform-Tools**, **NDK 28.2.13676358**, and **CMake 3.22.1**. You can also preinstall these in SDK Manager using Show Package Details. Accept applicable SDK licenses when requested.

For IDE development, enable the **Flutter** and **Dart** plugins. No separate Gradle, Kotlin, Dart, or system C++ compiler installation is needed: the project uses its Gradle wrapper, Flutter's Dart SDK, and a verified project-local Windows compiler.

Allow roughly **80–100 GB free disk space** for tools, AI resources, native builds, and Docker storage. This is a planning estimate. Setup needs internet; the installed app's AI processing is offline. Keep Docker running. If WSL/virtualization setup requires a restart, complete it before continuing.

### 2. Configure paths

Replace these examples with your actual installations. Run in PowerShell 7:

```powershell
$env:KHARCHIO_PYTHON = 'C:\Users\Somes.Somesh\AppData\Local\Programs\Python\Python312\python.exe'
$env:JAVA_HOME = 'C:\Program Files\Java\jdk-21.0.12.1'
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"
$env:Path = "C:\Users\Somes.Somesh\Development\flutter-3.47.7\bin;$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"
```

These values apply to the current terminal. To reuse them across sessions, save `KHARCHIO_PYTHON`, `JAVA_HOME`, and `ANDROID_HOME` in Windows user environment variables and add Flutter's `bin` folder to your user Path. Reopen terminals and Android Studio afterward. Python must point to `python.exe`; Java and Android variables point to their installation roots.

Start Docker Desktop and confirm `docker info --format '{{.OSType}}'` reports `linux`. Check `flutter --version` reports **3.47.8**; a different Flutter already on PATH or Android Studio's bundled Java runtime may not match the required versions.

### 3. Clone and prepare

```powershell
git clone https://github.com/SomeshSunariwal/Kharchio.git
cd Kharchio
.\setup.ps1
```

Setup first checks installed base tools and stops if any fail. It then installs missing Android SDK build packages, prepares the Windows shader compiler, and validates the complete toolchain. Only after validation does it restore Flutter packages, fetch pinned native sources, download models/QAIRT, export Whisper models, and compile Hexagon libraries. SDK Manager can request license acceptance. Initial preparation can take substantial time and memory.

**Setup alone prepares dependencies. To also create the release APK:**

```powershell
.\setup.ps1 --build
```

PowerShell's usual spelling, `-Build`, is also supported. Building is opt-in; setup does not select a device, install the APK, or launch the app. Output: `build/app/outputs/flutter-apk/app-release.apk`. To inspect tools without downloading or preparing anything, use `.\setup.ps1 -CheckOnly`; a fresh clone can report missing build packages/local compiler until normal setup prepares them.

If script execution is blocked, run `pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 --build`. `pwsh` means PowerShell 7. This option applies to that process, not machine-wide policy.

### 4. Run the app

After setup, open the **repository root** in Android Studio, select the same Flutter SDK and **JDK 21**, open `lib/main.dart`, and use a **Flutter** run configuration with an Android phone/emulator. CLI development uses `flutter devices`, then `flutter run -d DEVICE_ID` with a listed ID.

To install the release APK on a USB-authorized ARM64 phone:

```powershell
& "$env:ANDROID_HOME\platform-tools\adb.exe" install -r .\build\app\outputs\flutter-apk\app-release.apk
```

Open Kharchio and grant microphone permission. Validate Qualcomm NPU features on a compatible physical phone; emulator success does not validate NPU behavior. The S23 Ultra / Snapdragon 8 Gen 2 is the reference device. Release currently uses debug signing for local installation; store distribution needs release signing.

A complete fresh-machine rebuild has not yet been validated end to end. The checker identifies tool readiness; it cannot guarantee remote download availability, memory/storage capacity, or device compatibility. See the troubleshooting and iOS sections below.

## Setup stages

1. **Validate installed base tools.** Check Windows x64, PowerShell 7, Git, Python 3.12 x64/pip, JDK 21/java/javac, Flutter 3.47.8/bundled Dart, the Android SDK root/command-line tools, Gradle wrapper files, and a running Linux Docker engine. Report independent failures together and stop on failure.
2. **Prepare build tools and validate again.** Use SDK Manager to install missing Android Platform-Tools, API 37, Build-Tools 36.0.0, NDK 28.2.13676358, and CMake 3.22.1. SDK Manager may request license acceptance. Prepare the project-local Windows GPU compiler. Then verify the full Android toolchain and smoke-test Windows C/C++ compilation/linking before AI work starts.
3. **Prepare AI/native dependencies.** Write local paths, restore Flutter packages, fetch/check engine revisions, download verified models/QAIRT, export generic Whisper DLCs, and build Hexagon libraries through Docker.
4. **Optional APK build.** Only with `-Build`/`--build`, run `flutter analyze` followed by `flutter build apk --release --target-platform android-arm64`.

Failure at either validation stage prevents model downloads, conversion, and application compilation. Missing system tools are reported; setup does not install/replace global Java, Python, Flutter, Git, PowerShell, Docker, or Android Studio. Broken existing Android packages are reported by the full check rather than silently overwritten.

Tool checks are inside **`setup.ps1`**; there is no separate checker script. Executable probes time out after 45 seconds each. They check versions, executable availability, Android metadata, and Docker readiness. Compiler probes build/run tiny C and C++ programs in a unique temporary directory, then remove their probe files. No application code is built by `-CheckOnly`.

A passing check does not validate network reachability, all future Python imports, SDK licenses, free memory/disk throughout conversion, IDE plugins, signing keys, or phone authorization. Flutter can initialize its own SDK on first use; resolve that initialization before retrying a timed-out version check.

## Paths and host requirements

| Input       | Resolution                                                                                              |
| ----------- | ------------------------------------------------------------------------------------------------------- |
| Python      | `-PythonPath`, otherwise `KHARCHIO_PYTHON`, otherwise `python` on PATH                                  |
| Java        | `-JavaHome`, otherwise `JAVA_HOME`                                                                      |
| Android SDK | `-AndroidSdkPath`, otherwise `ANDROID_HOME`, then `ANDROID_SDK_ROOT`, then `%LOCALAPPDATA%/Android/Sdk` |
| Flutter     | `flutter` selected on PATH                                                                              |

Explicit paths are also supported: `.\setup.ps1 -PythonPath 'C:\Tools\Python312\python.exe' -JavaHome 'C:\Tools\jdk-21' -AndroidSdkPath "$env:LOCALAPPDATA\Android\Sdk" --build`.

`android/local.properties` is ignored by Git and receives `flutter.sdk`, `sdk.dir`, and `native.python`. Setup also saves the selected JDK/Android SDK using `flutter config`, so Flutter uses those paths instead of preferring a different bundled IDE runtime. It restores its temporary Java/Android environment changes afterward; it does not persistently rewrite Windows user/system environment variables.

Plan roughly **80–100 GB free storage** across tools, project resources, build output, caches, and Docker. This is an estimate. Earlier workspaces reached about 40 GB before global caches/Docker images. Gradle's configured heap can use 8 GB, separate from Python, Docker, Android Studio, and an emulator. Close the emulator/use a phone if memory is tight.

Use `flutter config --jdk-dir "$env:JAVA_HOME"`, `flutter config --android-sdk "$env:ANDROID_HOME"`, `flutter doctor --android-licenses`, and `flutter doctor -v` to configure/inspect Flutter's Android toolchain. Review license prompts interactively. [Flutter Android setup](https://docs.flutter.dev/platform-integration/android/setup) · [SDK Manager reference](https://developer.android.com/tools/sdkmanager).

## Pinned build resources

The build pins engine revisions in [native/CMakeLists.txt](native/CMakeLists.txt), model downloads in [native/config](native/config), and the Qualcomm adaptation revision in [the generic Whisper exporter](native/tools/models/prepare_whisper_generic.py).

### Gradle and native sources

| Resource                  | Version / revision                         | Source of truth / upstream                                                                           |
| ------------------------- | ------------------------------------------ | ---------------------------------------------------------------------------------------------------- |
| Gradle                    | **9.8.2**                                  | `android/gradle/wrapper/gradle-wrapper.properties`                                                   |
| Android Gradle Plugin     | **9.4.1**                                  | `android/settings.gradle.kts`                                                                        |
| Kotlin Android dependency | **2.4.21**                                 | `android/settings.gradle.kts`                                                                        |
| Flutter plugin loader     | **1.0.0**                                  | `android/settings.gradle.kts`                                                                        |
| llama.cpp                 | `d854d98bae598388ecea1ed84396587e5edc326d` | `native/CMakeLists.txt`; [llama.cpp](https://github.com/ggml-org/llama.cpp)                          |
| whisper.cpp               | `231638a0717b7822784297e5980965ffcec05810` | Same CMake file; [whisper.cpp](https://github.com/ggml-org/whisper.cpp)                              |
| Vulkan-Headers            | `73814d006638aa00bd553215b054f0f02e457e22` | `native/cmake/AndroidVulkan.cmake`; [Vulkan-Headers](https://github.com/KhronosGroup/Vulkan-Headers) |
| Vulkan-Hpp                | `da4cb2bc27917f3e5ff40346e448f39515248c32` | Same CMake file; [Vulkan-Hpp](https://github.com/KhronosGroup/Vulkan-Hpp)                            |
| SPIRV-Headers             | `fbf86836a9b1966586faf7be7bb8a6440e156d62` | Same CMake file; [SPIRV-Headers](https://github.com/KhronosGroup/SPIRV-Headers)                      |
| OpenCL-Headers            | `82f60316cc142e7b21dc1d8983b26de18858fbd9` | `native/cmake/AndroidOpenCL.cmake`; [OpenCL-Headers](https://github.com/KhronosGroup/OpenCL-Headers) |

Use the committed Gradle wrapper; no global Gradle/Kotlin install is needed. Java source compatibility is 17, while setup requires JDK 21 to run the toolchain. These are different settings. Header downloads may occur when CMake configures the native build.

Setup verifies existing llama.cpp/whisper.cpp checkouts match the pins and have no local changes. It stops rather than overwriting modified/wrong engine checkouts. Preserve intentional vendor work before replacing it.

### Windows GPU host compiler

Vulkan shader generation needs a helper that runs on **Windows**, even when the APK targets Android. NDK Clang compiles Android libraries; it does not replace a complete Windows host compiler/linker environment.

- **w64devkit 2.10.1**, prepared by `native/prepare_gpu.ps1`.
- [Release](https://github.com/skeeto/w64devkit/releases/tag/v2.10.1) · [Pinned archive](https://github.com/skeeto/w64devkit/releases/download/v2.10.1/w64devkit-x64-2.10.1.7z.exe).
- SHA-256: `ADD1EDF984CE4D473CFEB7C52E0AB38DB73A855BBA6C7F564D5E16648EB2896A`.
- Required files: `.tmp/gpu-tools/w64devkit/bin/gcc.exe` and `g++.exe`.
- Compiler discovery: `native/cmake/AndroidVulkan.cmake`.

Keep this directory for later native builds. Its `.tmp` location does not make it disposable while developing. Setup smoke-tests C and C++ compile/link/run before AI preparation.

### Offline base models

Local model files and their licenses/manifests live in the root `models/` directory. Shared weights are grouped under `models/whisper/` and `models/qwen/`; Android NPU packages are under `models/whisper/android/whisper-qnn-sm8550/` and `models/whisper/android/whisper-qnn-generic/`. Preparation scripts write to these locations for model preparation and release publishing. Model binaries are ignored by Git and excluded from the APK; only the download manifest and licenses are bundled. Native runtime libraries remain bundled.

`models/manifest.json` pins the six GitHub Release URLs, installed relative paths, exact byte counts, and SHA-256 hashes. Publish binaries to the `model` release with these exact unique filenames. Keep this manifest in Git; when changing model releases, update it together with the preparation manifests. Downloads are streamed to private `.partial` files and are promoted only after size/hash verification. Interrupted downloads can resume; unavailable URLs and checksum/storage errors remain visible with Retry. Existing installed models are reused after verification.

Settings → Offline AI has independent GPU speech, NPU speech, and Qwen downloads. The NPU option downloads only the four generic/SM8550 encoder/decoder files. The app bundles `models/whisper/whisper-small-metadata.dat` (572,465 bytes of mel filters and vocabulary, with no tensor weights) so NPU inference does not need the GPU model. To regenerate it from verified local Whisper weights: `python native/tools/models/extract_whisper_metadata.py models/whisper/ggml-small-q5_1.bin models/whisper/whisper-small-metadata.dat`.

Each processing dropdown requires its own model family, and each Check requires the selected backend's files. Ready rows show a green status and red Delete button. Deleting NPU models also clears compiled contexts, without touching GPU weights; deleting GPU weights does not disable NPU speech. GPU/CPU fallback from NPU needs the separate GPU model; without it, unsupported NPU hardware produces an actionable error. Recording starts when the selected speech model is ready. Stop checks for Qwen before expense extraction and shows a model-download error if it is missing. Downloads run while the app process is alive; tap Resume after an interruption.

`native/prepare_models.ps1` reads `native/config/models.lock.json` and verifies exact byte counts and SHA-256 before installing files. The manifest contains authoritative hashes/URLs.

| Model                           | Installed under `models/<family>/` | Expected bytes | Resource                                                                                         |
| ------------------------------- | -------------------------------- | -------------: | ------------------------------------------------------------------------------------------------ |
| Multilingual Whisper Small Q5_1 | `ggml-small-q5_1.bin`            |    190,085,487 | [Whisper weights](https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-small-q5_1.bin) |
| Qwen3 0.6B Q8_0                 | `Qwen3-0.6B-Q8_0.gguf`           |    639,446,688 | [Qwen weights](https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf)    |

These total about 830 MB in decimal units. Downloaded models and compiled NPU contexts need additional device storage, separate from the APK. An earlier APK with bundled weights was about 2 GB; current builds exclude those weights. The manifest records MIT for Whisper and Apache-2.0 for Qwen; review upstream licenses/notices for distribution.

### Qualcomm Whisper / QAIRT

| Resource              | Selection / output                                                                            |
| --------------------- | --------------------------------------------------------------------------------------------- |
| QAIRT SDK             | **2.50.0.260828**; `native/prebuilt/qairt/qairt/2.50.0.260828/`                               |
| Precompiled model     | `qualcomm/Whisper-Small` **0.65.0**, float; SM8550 / Snapdragon 8 Gen 2 / HTP v73             |
| Context runtime build | **2.50.0.260828221209**, checked against context metadata                                     |
| S23 Ultra assets      | `models/whisper/android/whisper-qnn-sm8550/whisper-s23-encoder.bin`, `whisper-s23-decoder.bin`, `manifest.json` |
| Generic assets        | `models/whisper/android/whisper-qnn-generic/whisper-generic-encoder.dlc`, `whisper-generic-decoder.dlc`, `manifest.json` |
| Runtime libraries     | `android/app/src/main/jniLibs/arm64-v8a/libQnn*.so`                                           |

`native/config/whisper_qnn.lock.json` pins SDK/context URLs, hashes, device selection, and runtime versions. [QAIRT archive](https://softwarecenter.qualcomm.com/api/download/software/sdks/Qualcomm_AI_Runtime_Community/All/2.50.0.260828/v2.50.0.260828.zip) · [Context archive](https://qaihub-public-assets.s3.us-west-2.amazonaws.com/qai-hub-models/models/whisper_small/releases/v0.65.0/whisper_small-qnn_context_binary-float-qualcomm_qcs8550_proxy.zip) · [Qualcomm adapter sources](https://github.com/qualcomm/ai-hub-models) · [Whisper checkpoint](https://huggingface.co/openai/whisper-small).

`native/prepare_whisper_generic.ps1` provisions both Whisper NPU paths and installs converter dependencies under `.tmp/qnn-export/deps`:

| Dependency                | Version                                                                                          |
| ------------------------- | ------------------------------------------------------------------------------------------------ |
| PyTorch CPU               | **2.8.0**, from [CPU wheels](https://download.pytorch.org/whl/cpu)                               |
| Transformers              | **4.57.1**                                                                                       |
| ONNX / ONNX Script        | **1.19.0** / **0.5.3**                                                                           |
| NumPy / Pydantic / pandas | **1.26.4** / **2.11.7** / **2.2.3**                                                              |
| Additional support        | `pyyaml`, `packaging`, `tqdm`, `tabulate`, `mako`, `lxml`, `jsonschema`; not individually pinned |

Most converter packages come from [PyPI](https://pypi.org/). The exporter pins Qualcomm adapters to `1c23e6d6c6ab2e6edbfb671c07484855d2e2511b` and the checkpoint to `973afd24965f72e36ca33b3055d56a652f456b4d`; see `native/tools/models/prepare_whisper_generic.py`.

Local export can consume substantial RAM/time. No user audio is sent for cloud compilation. Generic DLCs compile for a supported phone HTP on first use and are cached. Runtime/driver support needs physical-device verification; the precompiled S23 contexts remain device-specific.

### Qwen Hexagon

`native/prepare_hexagon.ps1` uses this pinned Linux Docker image; Docker pulls it when absent:

```text
ghcr.io/snapdragon-toolchain/arm64-android@sha256:e39e5e9c0957550a92c0de756b7556d81196c7c7f7328ed80de252bfb4878adf
```

`native/tools/build_hexagon.sh` uses matching llama.cpp sources and the image's Android/Hexagon tools. It produces `native/prebuilt/hexagon/arm64-v8a/libggml-hexagon.a`, `revision.txt`, and `android/app/src/main/jniLibs/arm64-v8a/libggml-htp-v73.so` plus v75/v79/v81 variants. Docker must mount the project directory. Do not mix arbitrary GGML revisions or images with these outputs.

## IDE and device notes

Open the **root containing `pubspec.yaml`** in Android Studio, enable Flutter/Dart plugins, configure the selected Flutter SDK and Gradle JDK 21, and use a Flutter run configuration for `lib/main.dart`. Setup must complete before IDE Run; Run does not provision these AI resources. [Flutter IDE guide](https://docs.flutter.dev/tools/android-studio).

For Gradle tasks, use View → Tool Windows → Gradle. If empty, link `android/settings.gradle.kts` or `android/` as requested by that IDE version and sync. Root IDE settings should link `$PROJECT_DIR$/android`. IDE files are local/ignored. Flutter can invoke Gradle without a File-menu sync action, and successful sync does not prove native/model readiness.

The app config includes ARM64 and x86_64. Emulator builds still need the Windows shader compiler. Validate Qualcomm NPU features on compatible physical hardware; the S23 Ultra is the reference. After installation, grant microphone permission and inspect Profile's model readiness. First-use initialization can take longer.

For multiple ADB devices, add `-s DEVICE_SERIAL` before `install`; get actual serials with `adb devices`. `unauthorized`/`offline` devices require attention on the phone/cable/ADB connection. Release currently uses debug signing; store distribution requires release signing, and updating existing local data requires signing-key compatibility.

## Recovery and cleanup

Normal recovery is to correct the reported base-tool problem and rerun `.\setup.ps1`. For a single missing resource, the relevant scripts are `native/prepare_gpu.ps1`, `prepare_models.ps1`, `prepare_whisper_qnn.ps1` (S23/QAIRT only), `prepare_whisper_generic.ps1` (both NPU paths), and `prepare_hexagon.ps1`. Some use `exit`; invoke them in a child PowerShell. These scripts assume required source/local paths already exist; full setup handles ordering.

| Removed location                     | Consequence                                                                             |
| ------------------------------------ | --------------------------------------------------------------------------------------- |
| `build/` or Flutter build output     | Rebuild APK/intermediates; restore packages after `flutter clean`                       |
| `.tmp/gpu-tools/`                    | Removes required Windows compilers                                                      |
| `.tmp/qnn-export/`                   | Removes converter/checkpoint/intermediates; later export may redownload large resources |
| `native/vendor/`                     | Removes ignored engine/header sources                                                   |
| `native/prebuilt/`                   | Removes SDK extraction and Hexagon archive                                              |
| Ignored model/assets/`jniLibs` files | Removes offline weights, NPU models, runtime libraries                                  |

Avoid broad ignored-file cleanup: it removes essential inputs, not just output. Preserve intentional work first. Global SDKs, Pub/Gradle caches, and Docker images live outside the repository. If CMake cached a wrong compiler, restoring tools may also need a deliberate clean/reconfigure of the affected generated native build.

## Troubleshooting

| Failure                                                              | Check                                                                                                         |
| -------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- |
| PowerShell/script execution error                                    | Use PowerShell 7 and the process-scoped invocation above                                                      |
| Version mismatch                                                     | Selected Flutter on PATH, Python 3.12 x64, `JAVA_HOME` JDK 21; bundled IDE JBR can differ                     |
| Flutter probe timeout                                                | SDK initialization lock, another Flutter process, or first-use/network delay                                  |
| SDK tools missing                                                    | SDK root and `cmdline-tools/latest`; setup prepares missing build packages after base validation              |
| Docker unavailable/wrong OS                                          | Running engine, WSL readiness, Linux containers                                                               |
| API 37 unavailable                                                   | SDK Manager package availability; setup stops instead of substituting another API                             |
| Plugin directory missing                                             | Named Pub cache path and Flutter package restoration                                                          |
| `vulkan-shaders-gen` missing `-lkernel32` / `-luser32` / `-lmingw32` | Local w64devkit and generated host toolchain; NDK Clang selected for the Windows helper is the wrong fallback |
| Model checksum mismatch                                              | Named archive/partial file and lock manifest; preserve valid installed models                                 |
| QNN/Hexagon mismatch                                                 | Runtime/context versions and matching engine revision/image                                                   |
| Process killed under load                                            | Free RAM/disk, Python conversion, Docker/emulator resource use                                                |
| APK builds but NPU unavailable                                       | Physical device/HTP compatibility and Profile model/runtime readiness                                         |

Diagnostic evidence: `build/app/intermediates/cxx/<variant>/<hash>/logs/<abi>/build_stdout_kharchio_ai.txt` and stderr; generated host toolchains under `build/.cxx/`; `%USERPROFILE%/.gradle/daemon/<version>/daemon-*.out.log`; Android Studio Help → Show Log in Explorer; `flutter doctor -v`.

## iOS and validation limits

Windows setup targets Android. iOS needs macOS, Xcode/command-line tools, Flutter, CocoaPods, CMake, Git, and base GGML/GGUF weights. Deployment target: **iOS 15.0**. PowerShell on macOS can run `native/prepare_models.ps1`. General sequence: `flutter pub get`, `pod install` inside `ios/`, then `flutter build ios` from the root. The Podfile invokes `native/build_ios.sh` to create `ios/Frameworks/KharchioAI.xcframework`. Configure Xcode signing for physical devices. iOS uses Metal/CPU, not Android QNN/Hexagon. [Flutter iOS setup](https://docs.flutter.dev/platform-integration/ios/setup) · [Xcode](https://developer.apple.com/xcode/) · [CocoaPods](https://guides.cocoapods.org/using/getting-started.html) · [CMake](https://cmake.org/download/).

A complete fresh-machine rebuild and iOS rebuild have **not yet been validated end to end**. Syntax/tool checks are not an APK build. Remote availability, unpinned converter/transitive packages, and device drivers mean the process is not fully hermetic. Keep `pubspec.lock` and resource manifests. Update this guide and setup checks together when changing SDK/Gradle versions, native pins, model hashes, converter versions, or Docker digest.
