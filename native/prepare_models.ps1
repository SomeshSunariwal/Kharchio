$ErrorActionPreference = 'Stop'
$modelManifest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'config/models.lock.json') -Raw | ConvertFrom-Json
$modelDirectory = Join-Path (Split-Path $PSScriptRoot -Parent) 'assets/models'
New-Item -ItemType Directory -Force -Path $modelDirectory | Out-Null
foreach ($entry in $modelManifest.PSObject.Properties) {
    $model = $entry.Value
    $destination = Join-Path $modelDirectory $model.filename
    if ((Test-Path -LiteralPath $destination) -and
        (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $model.sha256) {
        Write-Output "$($entry.Name): verified"
        continue
    }
    $partial = "$destination.partial"
    Invoke-WebRequest -Uri $model.url -OutFile $partial
    if ((Get-Item -LiteralPath $partial).Length -ne $model.bytes -or
        (Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash -ne $model.sha256) {
        throw "$($entry.Name): model checksum did not match; final model was not replaced"
    }
    Move-Item -LiteralPath $partial -Destination $destination -Force
    Write-Output "$($entry.Name): installed and verified"
}
