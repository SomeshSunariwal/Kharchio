# Windows Android setup, including both Whisper NPU models and Qwen Hexagon.
[CmdletBinding()]
param(
    [string]$PythonPath = $(if ($env:KHARCHIO_PYTHON) { $env:KHARCHIO_PYTHON } else { 'python' }),
    [string]$AndroidSdkPath,
    [string]$JavaHome = $env:JAVA_HOME,
    [switch]$CheckOnly,
    [Alias('-build')]
    [switch]$Build
)
$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

function Invoke-Checked {
    param([string]$Command, [string[]]$Arguments)
    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) { throw "Command failed ($LASTEXITCODE): $Command $($Arguments -join ' ')" }
}

function Test-Tools {
    param(
        [string]$PythonPath = $(if ($env:KHARCHIO_PYTHON) { $env:KHARCHIO_PYTHON } else { 'python' }),
        [string]$AndroidSdkPath,
        [string]$JavaHome = $env:JAVA_HOME,
        [switch]$BaseToolsOnly,
        [switch]$PassThru
    )
    $ErrorActionPreference = 'Stop'
    $failures = [System.Collections.Generic.List[string]]::new()
    $resolved = @{}

    function Test-Requirement {
        param([string]$Name, [scriptblock]$Check)
        try {
            $detail = & $Check
            Write-Host "[PASS] ${Name}: $detail" -ForegroundColor Green
        } catch {
            $failures.Add("${Name}: $($_.Exception.Message)")
            Write-Host "[FAIL] ${Name}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }

    function Invoke-Probe {
        param([string]$Executable, [string[]]$Arguments, [int]$TimeoutSeconds = 45)
        $start = [System.Diagnostics.ProcessStartInfo]::new()
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        if ([IO.Path]::GetExtension($Executable) -in @('.bat', '.cmd')) {
            # Only fixed version arguments use this branch. Reject cmd expansion in paths.
            if ($Executable -match '[%"\r\n]' -or ($Arguments -join ' ') -match '[&|<>^%!"\r\n]') {
                throw 'Unsupported command-shell characters in probe path or arguments.'
            }
            $start.FileName = $env:ComSpec
            $start.Arguments = '/d /s /c ""' + $Executable + '" ' + ($Arguments -join ' ') + '"'
        } else {
            $start.FileName = $Executable
            foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        }
        $process = [System.Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            [void]$process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
                $process.Kill($true)
                $process.WaitForExit()
                throw "Probe timed out after ${TimeoutSeconds}s: $Executable"
            }
            $output = ($stdout.GetAwaiter().GetResult() + "`n" + $stderr.GetAwaiter().GetResult()).Trim()
            if ($process.ExitCode -ne 0) { throw "Exit $($process.ExitCode): $output" }
            return $output
        } finally { $process.Dispose() }
    }

    function Require-File {
        param([string]$Path)
        if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing $Path" }
        return (Resolve-Path -LiteralPath $Path).Path
    }

    Write-Host 'Kharchio tool validation (no downloads or app build)'
    if ($PSVersionTable.PSVersion.Major -lt 7) { throw 'Open PowerShell 7, not Windows PowerShell 5.1. See BUILD.md.' }
    Test-Requirement 'Windows x64 / PowerShell 7' {
        if (-not $IsWindows -or [System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -ne 'X64') {
            throw 'This setup supports Windows x64.'
        }
        "PowerShell $($PSVersionTable.PSVersion)"
    }
    Test-Requirement 'Git' { Invoke-Probe (Get-Command git -ErrorAction Stop).Source @('--version') }
    Test-Requirement 'Python 3.12 x64 and pip' {
        $resolved.Python = (Get-Command $PythonPath -ErrorAction Stop).Source
        $version = Invoke-Probe $resolved.Python @('-c', 'import sys,struct; print(str(sys.version_info.major)+"."+str(sys.version_info.minor)+"/"+str(struct.calcsize("P")*8))')
        if ($version -ne '3.12/64') { throw "Expected 3.12/64; found $version. Set KHARCHIO_PYTHON to Python 3.12's full executable path." }
        [void](Invoke-Probe $resolved.Python @('-m', 'pip', '--version'))
        "$version at $($resolved.Python)"
    }
    Test-Requirement 'JDK 21 (java and javac)' {
        if (-not $JavaHome) { throw 'Set JAVA_HOME to the JDK 21 folder.' }
        $resolved.JavaHome = (Resolve-Path -LiteralPath $JavaHome).Path
        $version = Invoke-Probe (Require-File (Join-Path $resolved.JavaHome 'bin/java.exe')) @('-version')
        if ($version -notmatch 'version "21[.\"]') { throw "Expected JDK 21; found $version" }
        $compiler = Invoke-Probe (Require-File (Join-Path $resolved.JavaHome 'bin/javac.exe')) @('-version')
        if ($compiler -notmatch 'javac 21(?:\.|\s|$)') { throw "Expected javac 21; found $compiler" }
        "$compiler at $($resolved.JavaHome)"
    }
    Test-Requirement 'Flutter 3.47.8 and bundled Dart' {
        $flutter = (Get-Command flutter -ErrorAction Stop).Source
        $version = (Invoke-Probe $flutter @('--version', '--machine')) | ConvertFrom-Json
        if ($version.flutterVersion -ne '3.47.8') { throw "Expected Flutter 3.47.8; found $($version.flutterVersion) at $flutter" }
        $resolved.FlutterSdk = Split-Path (Split-Path $flutter -Parent) -Parent
        $dart = Invoke-Probe (Require-File (Join-Path $resolved.FlutterSdk 'bin/cache/dart-sdk/bin/dart.exe')) @('--version')
        "Flutter $($version.flutterVersion); $dart"
    }
    if (-not $AndroidSdkPath) {
        $AndroidSdkPath = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } elseif ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } else { Join-Path $env:LOCALAPPDATA 'Android/Sdk' }
    }
    if ($BaseToolsOnly) {
        Test-Requirement 'Android SDK root and command-line tools' {
            $resolved.AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdkPath).Path
            Require-File (Join-Path $resolved.AndroidSdk 'cmdline-tools/latest/bin/sdkmanager.bat')
        }
    } else {
    Test-Requirement 'Android SDK platform API 37' {
        $resolved.AndroidSdk = (Resolve-Path -LiteralPath $AndroidSdkPath).Path
        $platform = @('platforms/android-37.0/android.jar', 'platforms/android-37/android.jar') |
            ForEach-Object { Join-Path $resolved.AndroidSdk $_ } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
        if (-not $platform) { throw "Install API 37 using SDK Manager in $AndroidSdkPath" }
        $platform
    }
    Test-Requirement 'Android Build-Tools 36.0.0' {
        foreach ($file in @('aapt2.exe', 'zipalign.exe', 'apksigner.bat')) {
            [void](Require-File (Join-Path $AndroidSdkPath "build-tools/36.0.0/$file"))
        }
        Invoke-Probe (Join-Path $AndroidSdkPath 'build-tools/36.0.0/aapt2.exe') @('version')
    }
    Test-Requirement 'Android platform-tools / ADB' {
        Invoke-Probe (Require-File (Join-Path $AndroidSdkPath 'platform-tools/adb.exe')) @('version')
    }
    Test-Requirement 'Android command-line tools' {
        Require-File (Join-Path $AndroidSdkPath 'cmdline-tools/latest/bin/sdkmanager.bat')
    }
    Test-Requirement 'NDK 28.2.13676358 and shader compiler' {
        $ndk = Join-Path $AndroidSdkPath 'ndk/28.2.13676358'
        [void](Require-File (Join-Path $ndk 'build/cmake/android.toolchain.cmake'))
        $properties = Get-Content -LiteralPath (Join-Path $ndk 'source.properties') -Raw
        if ($properties -notmatch 'Pkg.Revision\s*=\s*28\.2\.13676358(?:\s|$)') { throw 'NDK package revision mismatch.' }
        [void](Invoke-Probe (Require-File (Join-Path $ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin/clang.exe')) @('--version'))
        [void](Invoke-Probe (Require-File (Join-Path $ndk 'shader-tools/windows-x86_64/glslc.exe')) @('--version'))
        'NDK compiler, Android toolchain, and glslc are available'
    }
    Test-Requirement 'CMake 3.22.1 and Ninja' {
        $cmake = Join-Path $AndroidSdkPath 'cmake/3.22.1/bin'
        $version = Invoke-Probe (Require-File (Join-Path $cmake 'cmake.exe')) @('--version')
        if ($version -notmatch 'cmake version 3\.22\.1(?:[-+\s]|$)') { throw "Expected CMake 3.22.1; found $version" }
        [void](Invoke-Probe (Require-File (Join-Path $cmake 'ninja.exe')) @('--version'))
        'CMake 3.22.1; Ninja runs successfully'
    }
    }
    Test-Requirement 'Gradle wrapper files' {
        foreach ($file in @('android/gradlew.bat', 'android/gradle/wrapper/gradle-wrapper.jar', 'android/gradle/wrapper/gradle-wrapper.properties')) {
            [void](Require-File (Join-Path $PSScriptRoot $file))
        }
        'Repository wrapper present; Gradle distribution download is deferred to the build'
    }
    Test-Requirement 'Docker engine / Linux containers' {
        $docker = (Get-Command docker -ErrorAction Stop).Source
        $os = Invoke-Probe $docker @('info', '--format', '{{.OSType}}')
        if ($os -ne 'linux') { throw "Expected linux; found $os. Start Docker Desktop with Linux containers." }
        'Docker engine responds and uses Linux containers'
    }
    if (-not $BaseToolsOnly) {
        Test-Requirement 'Windows GPU host compiler (C and C++ link/run)' {
            $bin = Join-Path $PSScriptRoot '.tmp/gpu-tools/w64devkit/bin'
            foreach ($compiler in @('gcc.exe', 'g++.exe')) {
                [void](Invoke-Probe (Require-File (Join-Path $bin $compiler)) @('--version'))
            }
            $probeDir = Join-Path ([IO.Path]::GetTempPath()) ('kharchio-tools-' + [guid]::NewGuid().ToString('N'))
            [void](New-Item -ItemType Directory -Path $probeDir)
            try {
                $binary = Join-Path $probeDir 'probe.exe'
                [IO.File]::WriteAllText((Join-Path $probeDir 'probe.c'), 'int main(void) { return 0; }')
                [IO.File]::WriteAllText((Join-Path $probeDir 'probe.cpp'), "#include <vector>`nint main() { std::vector<int> values(1); return values[0]; }")
                foreach ($compiler in @('gcc.exe', 'g++.exe')) {
                    $source = Join-Path $probeDir $(if ($compiler -eq 'gcc.exe') { 'probe.c' } else { 'probe.cpp' })
                    [void](Invoke-Probe (Join-Path $bin $compiler) @($source, '-o', $binary))
                    [void](Invoke-Probe $binary @())
                }
            } finally {
                # Remove only files in this uniquely created directory; no recursive deletion.
                foreach ($file in @('probe.c', 'probe.cpp', 'probe.exe')) {
                    Remove-Item -LiteralPath (Join-Path $probeDir $file) -Force -ErrorAction SilentlyContinue
                }
                Remove-Item -LiteralPath $probeDir -ErrorAction SilentlyContinue
            }
            'Both compilers can build and run a Windows executable'
        }
    }
    if ($failures.Count -gt 0) {
        throw ("Tool validation failed ($($failures.Count) checks). No model preparation or app build may proceed.`n - " + ($failures -join "`n - ") + "`nSee BUILD.md for installation and recovery commands.")
    }
    Write-Host 'All requested tool checks passed.' -ForegroundColor Green
    Write-Host 'Model files, network access, SDK license acceptance, and device readiness are separate checks; see BUILD.md.'
    if ($PassThru) {
        [pscustomobject]@{ Python = $resolved.Python; JavaHome = $resolved.JavaHome; AndroidSdk = $resolved.AndroidSdk; FlutterSdk = $resolved.FlutterSdk }
    }
}

function Initialize-AndroidTools {
    param([string]$SdkPath, [string]$JdkPath)
    $sdkManager = Join-Path $SdkPath 'cmdline-tools/latest/bin/sdkmanager.bat'
    $requiredPackages = [ordered]@{
        'platform-tools' = 'platform-tools/adb.exe'
        'build-tools;36.0.0' = 'build-tools/36.0.0/aapt2.exe'
        'ndk;28.2.13676358' = 'ndk/28.2.13676358/build/cmake/android.toolchain.cmake'
        'cmake;3.22.1' = 'cmake/3.22.1/bin/cmake.exe'
    }
    $missing = @($requiredPackages.Keys | Where-Object {
        -not (Test-Path -LiteralPath (Join-Path $SdkPath $requiredPackages[$_]) -PathType Leaf)
    })
    $needsPlatform = -not ((Test-Path -LiteralPath (Join-Path $SdkPath 'platforms/android-37/android.jar')) -or
        (Test-Path -LiteralPath (Join-Path $SdkPath 'platforms/android-37.0/android.jar')))
    $originalJavaHome = $env:JAVA_HOME
    try {
        $env:JAVA_HOME = $JdkPath
        if ($needsPlatform) {
            $available = & $sdkManager "--sdk_root=$SdkPath" --list 2>&1 | Out-String
            if ($LASTEXITCODE -ne 0) { throw "SDK Manager could not list packages: $available" }
            $platform = [regex]::Match($available, '(?m)^\s*(platforms;android-37(?:\.0)?)\s*\|')
            if (-not $platform.Success) { throw 'API 37 is not available in SDK Manager. No substitute API will be installed.' }
            $missing += $platform.Groups[1].Value
        }
        if ($missing.Count) {
            Write-Host "Installing missing Android build packages: $($missing -join ', ')"
            Write-Host 'SDK Manager may ask you to accept the applicable Android SDK licenses.'
            Invoke-Checked $sdkManager (@("--sdk_root=$SdkPath", '--install') + $missing)
        } else { Write-Host 'Required Android build packages are already present.' }
    } finally { $env:JAVA_HOME = $originalJavaHome }
}

$toolParameters = @{ PythonPath = $PythonPath; AndroidSdkPath = $AndroidSdkPath; JavaHome = $JavaHome }
if ($CheckOnly) {
    Test-Tools @toolParameters
    return
}

Write-Host 'Stage 1/4: Validate installed base tools.'
$tools = Test-Tools @toolParameters -BaseToolsOnly -PassThru
$python = $tools.Python
$flutterSdk = $tools.FlutterSdk
$JavaHome = $tools.JavaHome
$AndroidSdkPath = $tools.AndroidSdk
$shell = (Get-Process -Id $PID).Path
Write-Host 'Stage 2/4: Prepare missing Android build packages and the Windows GPU compiler; validate all tools.'
Initialize-AndroidTools -SdkPath $AndroidSdkPath -JdkPath $JavaHome
Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', (Join-Path $root 'native/prepare_gpu.ps1'))
Test-Tools -PythonPath $python -AndroidSdkPath $AndroidSdkPath -JavaHome $JavaHome
Write-Host 'Tool validation passed. Starting dependency preparation.'

# Read engine URLs and exact revisions from the same CMake file as the app.
$cmake = Get-Content -LiteralPath (Join-Path $root 'native/CMakeLists.txt') -Raw
$engines = foreach ($name in @('llama', 'whisper')) {
    $match = [regex]::Match($cmake, "(?s)FetchContent_Declare\($name\s+GIT_REPOSITORY\s+(\S+)\s+GIT_TAG\s+([a-f0-9]{40})")
    if (-not $match.Success) { throw "Could not read pinned $name source from CMakeLists.txt." }
    @{ Name = $name; Url = $match.Groups[1].Value; Revision = $match.Groups[2].Value }
}
Write-Host 'Stage 3/4: Prepare pinned engines, models, QAIRT, and Hexagon.'

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
    # Flutter can prefer Android Studio's bundled JBR over JAVA_HOME unless configured.
    Invoke-Checked 'flutter' @('config', '--jdk-dir', $JavaHome)
    Invoke-Checked 'flutter' @('config', '--android-sdk', $AndroidSdkPath)
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
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_models.ps1')
    # This also provisions the S23 Ultra contexts and the shared QAIRT runtime.
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_whisper_generic.ps1', '-Python', $python)
    Invoke-Checked $shell @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'native/prepare_hexagon.ps1')
    # APK generation is opt-in; setup alone prepares the environment/resources.
    if ($Build) {
        Write-Host 'Stage 4/4: Analyze Flutter source and build the ARM64 release APK.'
        Invoke-Checked 'flutter' @('analyze')
        Invoke-Checked 'flutter' @('build', 'apk', '--release', '--target-platform', 'android-arm64')
        Write-Output 'APK: build/app/outputs/flutter-apk/app-release.apk'
    } else {
        Write-Host 'Stage 4/4: Build skipped. Use -Build (or --build) to create the APK.'
        Write-Output 'Setup complete. Build: flutter build apk --release --target-platform android-arm64'
    }
} finally {
    $env:JAVA_HOME = $previousJavaHome
    $env:ANDROID_HOME = $previousAndroidHome
    $env:JAVA_TOOL_OPTIONS = $previousJavaOptions
    Pop-Location
}
