# Terraform Plus development installation for Windows / PowerShell.
# Kopiert nur bekannte Mod-Dateien in den einzelnen Terraform-Plus-Modordner.
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$documents = [Environment]::GetFolderPath('MyDocuments')
$mods = Join-Path $documents 'My Games\FarmingSimulator2025\mods'
$target = Join-Path $mods 'FS25_TerraformPlus'

if (-not (Test-Path (Join-Path $documents 'My Games\FarmingSimulator2025'))) {
    Write-Warning 'Das LS25-Benutzerverzeichnis wurde an diesem Pfad noch nicht gefunden. Pruefe den korrekten Dokumente-/Mods-Pfad.'
}
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -LiteralPath (Join-Path $repo 'modDesc.xml') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'icon.png') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination $target -Recurse -Force
Write-Host "Terraform Plus nach $target kopiert." -ForegroundColor Green
Write-Host 'Spiel neu starten und den Mod im Spielstand aktivieren.'
