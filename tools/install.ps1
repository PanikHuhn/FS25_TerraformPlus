
# ============================================================
# Terraform Plus - Development Installation
# Version: 0.0.14.0
#
# Funktionen:
# - Versionspruefung
# - Pruefung aller benoetigten Dateien
# - Erkennung doppelter Lua-Eintraege
# - Kontrolle der Lua-Ladereihenfolge
# - Erkennung nicht registrierter Lua-Dateien
# - Pruefung der TerrainWriter-Funktionen
# - Installation in den Test-Modordner
# - SHA256-Verifikation aller kopierten Dateien
# ============================================================

$ErrorActionPreference = 'Stop'

# ------------------------------------------------------------
# 1. Verzeichnisse und Version
# ------------------------------------------------------------

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

$mods = Join-Path `
    ([Environment]::GetFolderPath('Desktop')) `
    'FS25_Mods\_ModTest'

$target = Join-Path $mods 'FS25_TerraformPlus'

$expectedVersion = '0.0.14.0'

Write-Host ''
Write-Host '========================================'
Write-Host ' Terraform Plus - Mod Installation'
Write-Host " Version: $expectedVersion"
Write-Host '========================================'
Write-Host ''

# ------------------------------------------------------------
# 2. Test-Modverzeichnis pruefen
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Test-Modverzeichnis fehlt: $mods"
}

# ------------------------------------------------------------
# 3. modDesc.xml pruefen
# ------------------------------------------------------------

$descFile = Join-Path $repo 'modDesc.xml'

if (-not (Test-Path -LiteralPath $descFile -PathType Leaf)) {
    throw "modDesc.xml fehlt: $descFile"
}

[xml]$xml = Get-Content -LiteralPath $descFile -Raw

$version = ([string]$xml.modDesc.version).Trim()

if ($version -ne $expectedVersion) {
    throw "Versionsfehler: $version statt $expectedVersion"
}

Write-Host "[OK] Mod-Version: $version" -ForegroundColor Green

# ------------------------------------------------------------
# 4. Registrierte Lua-Dateien auslesen
# ------------------------------------------------------------

$declared = @(
    $xml.modDesc.extraSourceFiles.sourceFile |
        ForEach-Object {
            [string]$_.filename
        }
)

if ($declared.Count -eq 0) {
    throw 'Keine Lua-Module in modDesc.xml registriert'
}

# ------------------------------------------------------------
# 5. Doppelte Lua-Eintraege erkennen
# ------------------------------------------------------------

$uniqueFiles = @($declared | Sort-Object -Unique)

if ($uniqueFiles.Count -ne $declared.Count) {
    throw 'Doppelte Lua-Eintraege in modDesc.xml'
}

Write-Host '[OK] Keine doppelten Lua-Eintraege' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 6. Pflichtmodule
# ------------------------------------------------------------

$requiredModules = @(
    'scripts/TerrainAdapter.lua',
    'scripts/TerrainProfile.lua',
    'scripts/TerrainArea.lua',
    'scripts/TerrainVisualizer.lua',
    'scripts/TerrainCursor.lua',
    'scripts/TerrainSelection.lua',
    'scripts/TerrainDesign.lua',
    'scripts/TerrainPlan.lua',
    'scripts/TerrainToolUI.lua',
    'scripts/TerraformPlus.lua',
    'scripts/TerraformPlusUIBridge.lua',
    'scripts/TerrainWriter.lua'
)

foreach ($item in $requiredModules) {
    if ($declared -notcontains $item) {
        throw "Pflichtmodul fehlt in modDesc.xml: $item"
    }
}

Write-Host '[OK] Alle Pflichtmodule registriert' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 7. Ladereihenfolge pruefen
# ------------------------------------------------------------

# Die erforderlichen Module muessen in dieser Reihenfolge
# geladen werden. Weitere Module duerfen dazwischen liegen.

$lastIndex = -1

foreach ($module in $requiredModules) {
    $currentIndex = [array]::IndexOf($declared, $module)

    if ($currentIndex -le $lastIndex) {
        throw "Ungueltige Lua-Ladereihenfolge bei: $module"
    }

    $lastIndex = $currentIndex
}

Write-Host '[OK] Lua-Ladereihenfolge korrekt' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 8. Vorhandensein der Quelldateien pruefen
# ------------------------------------------------------------

$required = @(
    'modDesc.xml',
    'icon.png'
) + $declared

foreach ($relative in $required) {

    # Nur Lua-Dateien aus dem scripts-Verzeichnis erlauben.
    if ($relative -ne 'modDesc.xml' -and
        $relative -ne 'icon.png') {

        if ($relative -notmatch '^scripts/[A-Za-z0-9_./-]+\.lua$' -or
            $relative -match '(^|/)\.\.(/|$)') {

            throw "Ungueltiger Lua-Dateipfad: $relative"
        }
    }

    $path = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Pflichtdatei fehlt: $path"
    }
}

Write-Host '[OK] Alle Quelldateien vorhanden' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 9. Nicht registrierte Lua-Dateien erkennen
# ------------------------------------------------------------

$scriptsFolder = Join-Path $repo 'scripts'

if (-not (Test-Path -LiteralPath $scriptsFolder -PathType Container)) {
    throw "Scripts-Verzeichnis fehlt: $scriptsFolder"
}

$luaFiles = @(
    Get-ChildItem `
        -LiteralPath $scriptsFolder `
        -Recurse `
        -File `
        -Filter '*.lua'
)

foreach ($file in $luaFiles) {

    $relative = $file.FullName.Substring(
        $repo.Length + 1
    ).Replace('\', '/')

    if ($declared -notcontains $relative) {
        throw "Lua-Datei nicht in modDesc.xml registriert: $relative"
    }
}

Write-Host '[OK] Alle Lua-Dateien in modDesc.xml registriert' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 10. TerrainWriter-Funktionen pruefen
# ------------------------------------------------------------

$writerPath = Join-Path $repo 'scripts/TerrainWriter.lua'

$writer = Get-Content -LiteralPath $writerPath -Raw

$requiredMethods = @(
    'consoleCommandTerrainTest',
    'consoleCommandTerrainUndo',
    'consoleCommandTerrainRedo',
    'consoleCommandTerrainStatus',
    'setTerrainHeightAtWorldPos'
)

foreach ($method in $requiredMethods) {

    if (-not $writer.Contains($method)) {
        throw "TerrainWriter-Methode fehlt: $method"
    }
}

Write-Host '[OK] TerrainWriter-Funktionen vorhanden' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 11. Zielverzeichnis vorbereiten
# ------------------------------------------------------------

Write-Host ''
Write-Host '[INFO] Installation wird gestartet ...' `
    -ForegroundColor Cyan

New-Item `
    -ItemType Directory `
    -Path $target `
    -Force | Out-Null

$targetScripts = Join-Path $target 'scripts'

# Alte Scripts entfernen, um veraltete Lua-Dateien
# aus vorherigen Versionen zu vermeiden.

if (Test-Path -LiteralPath $targetScripts) {

    Remove-Item `
        -LiteralPath $targetScripts `
        -Recurse `
        -Force
}

# ------------------------------------------------------------
# 12. Dateien kopieren
# ------------------------------------------------------------

Copy-Item `
    -LiteralPath $descFile `
    -Destination $target `
    -Force

Copy-Item `
    -LiteralPath (Join-Path $repo 'icon.png') `
    -Destination $target `
    -Force

Copy-Item `
    -LiteralPath $scriptsFolder `
    -Destination $target `
    -Recurse `
    -Force

Write-Host '[OK] Dateien kopiert' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 13. SHA256-Verifikation
# ------------------------------------------------------------

Write-Host ''
Write-Host '[INFO] Datei-Integritaet wird geprueft ...' `
    -ForegroundColor Cyan

foreach ($relative in $required) {

    $sourcePath = Join-Path $repo $relative
    $targetPath = Join-Path $target $relative

    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Installierte Datei fehlt: $targetPath"
    }

    $sourceHash = (
        Get-FileHash `
            -LiteralPath $sourcePath `
            -Algorithm SHA256
    ).Hash

    $targetHash = (
        Get-FileHash `
            -LiteralPath $targetPath `
            -Algorithm SHA256
    ).Hash

    if ($sourceHash -ne $targetHash) {
        throw "Datei fehlerhaft kopiert: $relative"
    }
}

Write-Host '[OK] SHA256-Pruefung erfolgreich' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 14. Installation abgeschlossen
# ------------------------------------------------------------

Write-Host ''
Write-Host '========================================'
Write-Host ' INSTALLATION ERFOLGREICH'
Write-Host '========================================'

Write-Host "[Terraform Plus] Version: $expectedVersion" `
    -ForegroundColor Green

Write-Host "[Terraform Plus] $($declared.Count) Lua-Dateien kontrolliert" `
    -ForegroundColor Green

Write-Host '[Terraform Plus] Neue Terrain-Befehle:' `
    -ForegroundColor Cyan

Write-Host '  tpTerrainTest'
Write-Host '  tpTerrainUndo'
Write-Host '  tpTerrainRedo'
Write-Host '  tpTerrainStatus'

Write-Host ''
Write-Host "[Terraform Plus] Ziel: $target"

Write-Host ''
Write-Host 'HINWEIS: Echte Terrain-Schreibtests nur mit' `
    -ForegroundColor Yellow

Write-Host 'einer Kopie des Testspielstands durchfuehren.' `
    -ForegroundColor Yellow

Write-Host 'LS25 vollstaendig neu starten.'
Write-Host ''
