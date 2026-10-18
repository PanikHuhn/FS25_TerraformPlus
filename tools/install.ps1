
# Terraform Plus - Development Installation
# Installiert den Mod in den konfigurierten LS25-Testordner.

$ErrorActionPreference = 'Stop'

# Pfade
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$desktop = [Environment]::GetFolderPath('Desktop')

$mods = Join-Path $desktop 'FS25_Mods\_ModTest'
$target = Join-Path $mods 'FS25_TerraformPlus'

# Pruefen, ob der konfigurierte Modordner existiert
if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Modverzeichnis nicht gefunden: $mods"
}

# Pruefen, ob alle notwendigen Quelldateien existieren
$required = @(
    'modDesc.xml'
    'icon.dds'
    'scripts'
)

foreach ($item in $required) {
    $source = Join-Path $repo $item

    if (-not (Test-Path -LiteralPath $source)) {
        throw "Erforderliche Datei oder Ordner fehlt: $source"
    }
}

# Zielordner erstellen
New-Item -ItemType Directory -Force -Path $target | Out-Null

# Alte Skripte entfernen, um veraltete Dateien zu vermeiden
$targetScripts = Join-Path $target 'scripts'

if (Test-Path -LiteralPath $targetScripts) {
    Remove-Item -LiteralPath $targetScripts -Recurse -Force
}

# Dateien kopieren
Copy-Item -LiteralPath (Join-Path $repo 'modDesc.xml') `
    -Destination $target -Force

Copy-Item -LiteralPath (Join-Path $repo 'icon.dds') `
    -Destination $target -Force

Copy-Item -LiteralPath (Join-Path $repo 'scripts') `
    -Destination $target -Recurse -Force

# Ausgabe
Write-Host ""
Write-Host "[Terraform Plus] Installation erfolgreich!" -ForegroundColor Green
Write-Host "Ziel: $target"
Write-Host "Spiel neu starten, um die Aenderungen zu laden."
