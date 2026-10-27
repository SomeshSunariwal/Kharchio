param([string]$Python = 'python')
$ErrorActionPreference = 'Stop'
& $Python (Join-Path $PSScriptRoot 'tools/models/prepare_whisper_qnn.py')
if ($LASTEXITCODE -ne 0) { throw 'Whisper QNN provisioning failed' }
