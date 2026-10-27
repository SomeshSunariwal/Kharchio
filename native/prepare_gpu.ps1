param([string]$PythonPath)
$ErrorActionPreference = 'Stop'
$workspace = Split-Path $PSScriptRoot -Parent
$tools = Join-Path $workspace '.tmp/gpu-tools'
$compiler = Join-Path $tools 'w64devkit/bin/g++.exe'
if ($PythonPath) {
    if (-not (Test-Path -LiteralPath $PythonPath -PathType Leaf)) { throw 'Python executable not found.' }
    $python = (Resolve-Path -LiteralPath $PythonPath).Path.Replace('\', '/')
    $properties = Join-Path $workspace 'android/local.properties'
    $contents = if (Test-Path -LiteralPath $properties) { Get-Content -LiteralPath $properties -Raw } else { '' }
    $contents = [regex]::Replace($contents, '(?m)^native\.python=.*(?:\r?\n|$)', '')
    Set-Content -LiteralPath $properties -Value ($contents.TrimEnd() + "`r`nnative.python=$python`r`n")
}
if (Test-Path -LiteralPath $compiler) {
    Write-Output 'GPU shader host compiler is ready.'
    exit 0
}
New-Item -ItemType Directory -Path $tools -Force | Out-Null
$archive = Join-Path $tools 'w64devkit-x64-2.10.1.7z.exe'
$url = 'https://github.com/skeeto/w64devkit/releases/download/v2.10.1/w64devkit-x64-2.10.1.7z.exe'
$expected = 'ADD1EDF984CE4D473CFEB7C52E0AB38DB73A855BBA6C7F564D5E16648EB2896A'
if (-not (Test-Path -LiteralPath $archive)) {
    Invoke-WebRequest $url -OutFile $archive
}
if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expected) {
    throw 'GPU compiler archive checksum mismatch. Remove the archive and retry.'
}
$process = Start-Process -FilePath $archive -ArgumentList @('-y', ('-o"' + $tools + '"')) -WindowStyle Hidden -Wait -PassThru
if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $compiler)) {
    throw 'Could not prepare the GPU shader host compiler.'
}
Write-Output 'GPU shader host compiler is ready. Vulkan headers are pinned by CMake.'
