# Windows Android setup, including both Whisper NPU models and Qwen Hexagon.
[CmdletBinding()]
param(
    [string]$PythonPath = 'python',
    [string]$AndroidSdkPath,
    [string]$JavaHome = $env:JAVA_HOME,
    [switch]$CheckOnly,
    [switch]$Build
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')" }
}

foreach ($command in @('git', 'flutter', 'docker')) {
    if (-not (Get-Command $command -ErrorAction SilentlyContinue)) { throw "Install $command and add it to PATH. See BUILD.md." }
}
$python = (Get-Command $PythonPath -ErrorAction Stop).Source
$pythonVersion = & $python -c 'import sys; print("%d.%d" % sys.version_info[:2])'
if ($LASTEXITCODE -ne 0 -or $pythonVersion -ne '3.12') { throw 'Use 64-bit Python 3.12 with pip; pass -PythonPath with its executable path.' }
Invoke-Checked $python @('-m', 'pip', '--version')
$flutterCommand = (Get-Command flutter).Source
$flutterSdk = Split-Path (Split-Path $flutterCommand -Parent) -Parent
$flutterVersion = (& flutter --version --machine) | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $flutterVersion.flutterVersion -ne '3.47.8') { throw 'Use Flutter 3.47.8 for this pinned build.' }
if (-not $AndroidSdkPath) {
    $AndroidSdkPath = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
}
$AndroidSdkPath = (Resolve-Path -LiteralPath $AndroidSdkPath).Path
if (-not ((Test-Path -LiteralPath (Join-Path $AndroidSdkPath 'platforms/android-37.0/android.jar')) -or
          (Test-Path -LiteralPath (Join-Path $AndroidSdkPath 'platforms/android-37/android.jar')))) {
    throw 'Android SDK platform 37 is missing. See BUILD.md.'
}
foreach ($required in @('build-tools/36.0.0/aapt2.exe', 'ndk/28.2.13676358/build/cmake/android.toolchain.cmake', 'cmake/3.22.1/bin/cmake.exe')) {
    if (-not (Test-Path -LiteralPath (Join-Path $AndroidSdkPath $required))) { throw "Android SDK component missing: $required. See BUILD.md." }
}
if (-not $JavaHome) { throw 'Set JAVA_HOME to JDK 21, or pass -JavaHome. See BUILD.md.' }
$JavaHome = (Resolve-Path -LiteralPath $JavaHome).Path
$java = Join-Path $JavaHome 'bin/java.exe'
$javaVersion = (& $java -version 2>&1 | Out-String)
if ($LASTEXITCODE -ne 0 -or $javaVersion -notmatch 'version "21[\."]') { throw 'Use JDK 21 for the Android build.' }
$dockerOS = & docker info --format '{{.OSType}}'
if ($LASTEXITCODE -ne 0 -or $dockerOS -ne 'linux') { throw 'Start Docker Desktop with Linux containers enabled.' }

# Read engine URLs and exact revisions from the same CMake file as the app.
$cmake = Get-Content -LiteralPath (Join-Path $root 'native/CMakeLists.txt') -Raw
$engines = foreach ($name in @('llama', 'whisper')) {
    $match = [regex]::Match($cmake, "(?s)FetchContent_Declare\($name\s+GIT_REPOSITORY\s+(\S+)\s+GIT_TAG\s+([a-f0-9]{40})")
    if (-not $match.Success) { throw "Could not read pinned $name source from CMakeLists.txt." }
    @{ Name = $name; Url = $match.Groups[1].Value; Revision = $match.Groups[2].Value }
}
Write-Output 'Prerequisites ready. Setup provisions pinned engines, GPU tools, GGML models, both Whisper QNN models, and Qwen Hexagon.'
if ($CheckOnly) { return }

Push-Location $root
$previousJavaHome = $env:JAVA_HOME
$previousAndroidHome = $env:ANDROID_HOME
$previousJavaOptions = $env:JAVA_TOOL_OPTIONS
try {
    $env:JAVA_HOME = $JavaHome
    $env:ANDROID_HOME = $AndroidSdkPath
    $temporary = Join-Path $root '.tmp'
    New-Item -ItemType Directory -Path $temporary -Force | Out-Null
    $env:JAVA_TOOL_OPTIONS = "$previousJavaOptions -Djdk.net.unixdomain.tmpdir=`"$temporary`" -Djava.io.tmpdir=`"$temporary`""
    $properties = Join-Path $root 'android/local.properties'
    $contents = if (Test-Path -LiteralPath $properties) { Get-Content -LiteralPath $properties -Raw } else { '' }
    foreach ($pair in @(@('flutter.sdk', $flutterSdk), @('sdk.dir', $AndroidSdkPath), @('native.python', $python))) {
        $contents = [regex]::Replace($contents, '(?m)^' + [regex]::Escape($pair[0]) + '=.*(?:\r?\n|$)', '')
        $contents = $contents.TrimEnd() + "`n$($pair[0])=$($pair[1].Replace('\', '/'))`n"
    }
    Set-Content -LiteralPath $properties -Value $contents -Encoding utf8
    Invoke-Checked 'flutter' @('pub', 'get')
    foreach ($engine in $engines) {
        $destination = Join-Path $root "native/vendor/$($engine.Name).cpp"
        if (-not (Test-Path -LiteralPath $destination)) {
            Invoke-Checked 'git' @('init', $destination)
            Invoke-Checked 'git' @('-C', $destination, 'fetch', '--depth', '1', $engine.Url, $engine.Revision)
            Invoke-Checked 'git' @('-C', $destination, 'checkout', '--detach', 'FETCH_HEAD')
        }
        $actual = & git -C $destination rev-parse HEAD
        if ($LASTEXITCODE -ne 0 -or $actual -ne $engine.Revision) { throw "Wrong engine revision in $destination. Expected $($engine.Revision)." }
        $changes = & git -C $destination status --porcelain
        if ($LASTEXITCODE -ne 0 -or $changes) { throw "Engine checkout has local changes: $destination. Preserve or resolve them before setup." }
    }
    # Child PowerShell isolates preparation scripts that use 'exit'.
    $shell = (Get-Process -Id $PID).Path
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_gpu.ps1', '-PythonPath', $python)
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_models.ps1')
    # This also provisions the S23 Ultra contexts and the shared QAIRT runtime.
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_whisper_generic.ps1', '-Python', $python)
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_hexagon.ps1')
    if ($Build) {
        Invoke-Checked 'flutter' @('analyze')
        Invoke-Checked 'flutter' @('build', 'apk', '--release', '--target-platform', 'android-arm64')
        Write-Output 'APK: build/app/outputs/flutter-apk/app-release.apk'
    } else {
        Write-Output 'Setup complete. Build: flutter build apk --release --target-platform android-arm64'
    }
} finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
    Pop-Location
}
