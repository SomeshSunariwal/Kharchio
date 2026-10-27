# Build and run from a fresh clone

These instructions start with a **Windows 11 x64 computer with no development tools installed** and build the Android ARM64 application, including all AI dependencies. The S23 Ultra is the tested Android device.

Internet is required during setup. The installed application processes AI offline. Public model and SDK downloads require no AI API key.

The repository must contain `setup.ps1`, this guide, and the Gradle wrapper. Commit and push your source changes before expecting another clone to include them. The setup script does not create commits.

## 1. Prepare disk space

Reserve roughly **80–100 GB free** for the project, Android tools, downloads, and Docker. This is a planning allowance: the previous project workspace alone reached about **40 GB**, excluding global SDKs, caches, and Docker images.

Git contains application source, model manifests, pinned download metadata, preparation scripts, and the Gradle wrapper. Large model weights, native SDKs, engine checkouts, local paths, and build outputs are regenerated.

## 2. Install Git and PowerShell 7

Install [Git for Windows](https://git-scm.com/install/windows) using its default options, including command-line access. Then install [PowerShell 7](https://learn.microsoft.com/en-us/powershell/scripting/install/install-powershell-on-windows).

Use **PowerShell 7** for the remaining commands unless a step explicitly asks for an administrator terminal.

## 3. Install Python 3.12, 64-bit

Download a **Python 3.12 Windows installer (64-bit)** from [Python's official Windows downloads](https://www.python.org/downloads/windows/). Use Python **3.12** for compatibility with the QAIRT conversion tools.

During installation:

- Include **pip**.
- Enable **Add Python to PATH**.
- Note the installation directory and actual `python.exe` path.

The examples below assume:

```text
C:\Tools\Python312\python.exe
```

Substitute your actual path if different. Use the installed executable rather than the Windows Store alias.

## 4. Install Java JDK 21

Install [Temurin JDK 21 for Windows x64](https://adoptium.net/temurin/releases/?version=21). Choose **JDK**, and note its installation directory.

The examples below assume:

```text
C:\Tools\jdk-21
```

Substitute your actual directory if different.

## 5. Install Flutter 3.47.8

Download **Flutter 3.47.8 for Windows** from the [Flutter SDK archive](https://docs.flutter.dev/install/archive).

Extract it so this file exists:

```text
C:\Tools\flutter\bin\flutter.bat
```

In Windows, search **Edit environment variables for your account**, edit your user `Path`, and add:

```text
C:\Tools\flutter\bin
```

Close and reopen PowerShell, then verify:

```powershell
git --version
flutter --version
```

Flutter must report **3.47.8**, which `setup.ps1` currently requires. Flutter includes the required Dart SDK; no separate Dart installation is needed.

## 6. Install Android Studio and SDK components

Install [Android Studio](https://developer.android.com/studio/install.html), open it, and complete its setup wizard.

Open **SDK Manager** from the welcome screen's **More Actions** menu or Android Studio's settings. Note the SDK location; normally:

```text
C:\Users\<your-user>\AppData\Local\Android\Sdk
```

Install these components, enabling **Show Package Details** where needed:

| Component | Required version |
|---|---|
| Android SDK Platform | API 37 |
| Android SDK Build-Tools | 36.0.0 |
| Android SDK Platform-Tools | Available version |
| Android SDK Command-line Tools | Latest |
| NDK (Side by side) | 28.2.13676358 |
| CMake | 3.22.1 |

Alternatively, after installing the command-line tools, run their `sdkmanager.bat` with these package arguments:

```powershell
sdkmanager.bat "platform-tools" "platforms;android-37.0" "build-tools;36.0.0" "ndk;28.2.13676358" "cmake;3.22.1"
```

This command requires `sdkmanager.bat` on PATH, or invocation using its full installed path. The Android platform may be installed under `android-37.0`; setup also accepts the `android-37` directory name.

Flutter requires its SDK separately from Android Studio's Flutter plugin. Resource: [Flutter Android setup guide](https://docs.flutter.dev/platform-integration/android/setup).

## 7. Configure tool paths and accept Android licenses

In PowerShell 7, set these variables using your actual installation paths:

```powershell
$pythonPath = 'C:\Tools\Python312\python.exe'
$env:JAVA_HOME = 'C:\Tools\jdk-21'
$env:ANDROID_HOME = "$env:LOCALAPPDATA\Android\Sdk"

$env:Path = "$env:JAVA_HOME\bin;$env:ANDROID_HOME\platform-tools;$env:Path"

flutter config --jdk-dir "$env:JAVA_HOME"
flutter config --android-sdk "$env:ANDROID_HOME"
flutter doctor --android-licenses
```

Accept the licenses, then verify:

```powershell
& $pythonPath --version
& $pythonPath -m pip --version
java -version
flutter doctor -v
```

Confirm Python reports **3.12**, Java reports **21**, and Flutter's Android toolchain check passes.

The PowerShell variables above apply to the current terminal session. Keep this terminal open for the remaining steps, or set them again in a new terminal.

## 8. Install and start Docker Desktop

In an **administrator PowerShell**, run:

```powershell
wsl --install
```

Restart Windows when prompted and complete any first-run WSL setup. Resource: [Microsoft WSL installation instructions](https://learn.microsoft.com/en-us/windows/wsl/install).

Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) using its **WSL 2 backend**. Start Docker Desktop and wait until its engine is running. It must use **Linux containers**.

In your regular PowerShell terminal, verify:

```powershell
docker info --format '{{.OSType}}'
```

It must print:

```text
linux
```

Keep Docker running while preparing Qwen's Hexagon backend. If Windows was restarted, reopen PowerShell 7 and set the variables from step 7 again.

## 9. Open the cloned repository and check prerequisites

Change to your clone's actual directory. For example:

```powershell
cd C:\Projects\Kharchio
```

Confirm `setup.ps1` exists in this directory, then run:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -PythonPath "$pythonPath" `
  -JavaHome "$env:JAVA_HOME" `
  -AndroidSdkPath "$env:ANDROID_HOME" `
  -CheckOnly
```

Resolve any reported missing prerequisite before continuing. `-CheckOnly` validates prerequisites without provisioning model or build files.

## 10. Download AI dependencies and build

Run from the repository root:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1 `
  -PythonPath "$pythonPath" `
  -JavaHome "$env:JAVA_HOME" `
  -AndroidSdkPath "$env:ANDROID_HOME" `
  -Build
```

The script performs these operations:

1. Writes ignored `android/local.properties` with this machine's tool paths.
2. Restores Flutter packages using the committed lockfile.
3. Fetches the exact llama.cpp and whisper.cpp revisions pinned in CMake.
4. Prepares GPU host tools and verified Whisper/Qwen GGML weights.
5. Downloads the pinned QAIRT SDK and S23 Ultra Whisper contexts, then exports the generic Qualcomm Whisper DLCs locally. Both speech options are included.
6. Builds Qwen's Hexagon libraries using the pinned Docker image.
7. Runs analysis and builds the ARM64 release APK.

Keep the terminal open. Initial downloads and model conversion can take substantial time. Omit `-Build` to prepare dependencies without building the APK.

The resulting APK is:

```text
build\app\outputs\flutter-apk\app-release.apk
```

Both Whisper NPU options, OpenCL/CPU fallback, and Qwen are bundled, so the APK is large (about **2 GB** in the last build). Generic NPU support depends on the device's HTP capabilities; the S23 Ultra path was tested on Snapdragon 8 Gen 2.

## 11. Install and use the app

With an authorized Android device already available through ADB, run:

```powershell
adb install -r .\build\app\outputs\flutter-apk\app-release.apk
```

Open **Kharchio** on the phone and grant microphone permission when requested. In **Profile**, select:

- **Speech processing → S23 Ultra** for the phone-specific Whisper NPU model.
- **Speech processing → NPU** to compare the generic Qualcomm Whisper model.
- **Expense AI processing → NPU** for Qwen's Hexagon backend.

The first AI operation may take longer while bundled models are copied and initialized.

The current release build uses the debug signing key for local installation. Store distribution requires your own release signing configuration. Replacing an installed APK also requires the same signing key to preserve app data.

## Later builds and cleanup

After setup, normal builds use:

```powershell
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Deleting `build/` only removes generated build outputs. Deleting all ignored files also removes downloaded models and native dependencies; rerun the setup command from step 10 with your tool paths to recreate them. Global Flutter, Android, Python, Java, Pub, Gradle, and Docker installations live outside the repository and are not part of its cleanup.

The setup script and instructions are prepared, but a complete fresh-machine rebuild has **not yet been validated end to end**.

## iOS

iOS requires macOS, Xcode, CocoaPods, Flutter, CMake, and the GGML model weights provisioned by `native/prepare_models.ps1` (PowerShell is available on macOS). Run `flutter pub get`, `pod install` in `ios/`, then build/sign with Flutter or Xcode. The pod invokes `native/build_ios.sh` for the native framework. iOS uses Metal/CPU rather than Qualcomm QNN. The complete iOS rebuild has not been validated in this Windows workspace.
