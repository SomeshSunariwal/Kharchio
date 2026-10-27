param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$workspaceRoot = Split-Path $PSScriptRoot -Parent
$dependencies = Join-Path $workspaceRoot '.tmp/qnn-export/deps'
& $Python (Join-Path $PSScriptRoot 'tools/models/prepare_whisper_qnn.py') --include-converter
if ($LASTEXITCODE -ne 0) { throw 'QAIRT provisioning failed' }
if (!(Test-Path -LiteralPath (Join-Path $dependencies 'torch/__init__.py'))) {
    & $Python -m pip install --target $dependencies --index-url https://download.pytorch.org/whl/cpu 'torch==2.8.0'
    if ($LASTEXITCODE -ne 0) { throw 'Whisper export dependency installation failed' }
}
& $Python -m pip install --target $dependencies --upgrade 'transformers==4.57.1' 'onnx==1.19.0' 'onnxscript==0.5.3' 'numpy==1.26.4' 'pydantic==2.11.7' 'pandas==2.2.3' pyyaml packaging tqdm tabulate mako lxml jsonschema
if ($LASTEXITCODE -ne 0) { throw 'Whisper conversion dependency installation failed' }
$env:PYTHONUTF8 = '1'
& $Python (Join-Path $PSScriptRoot 'tools/models/prepare_whisper_generic.py')
if ($LASTEXITCODE -ne 0) { throw 'Portable Whisper DLC export failed' }
