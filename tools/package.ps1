# Release-ZIP mit modDesc.xml DIREKT im ZIP-Stamm erzeugen.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dist = Join-Path $repo 'dist'
$stage = Join-Path $dist '_staging'
$zip = Join-Path $dist 'FS25_TerraformPlus.zip'

New-Item -ItemType Directory -Force -Path $dist | Out-Null
if (Test-Path $stage) { Remove-Item -LiteralPath $stage -Force -Recurse }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'modDesc.xml') -Destination $stage
Copy-Item -LiteralPath (Join-Path $repo 'icon.png') -Destination $stage
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination $stage -Recurse
if (Test-Path $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Force -Recurse
Write-Host "Mod-ZIP erstellt: $zip" -ForegroundColor Green
