
# ============================================================
# Terraform Plus - Development Installation
# Version: 0.0.16.0
# ============================================================

$ErrorActionPreference = 'Stop'

$expectedVersion = '0.0.16.0'

$repo = (Resolve-Path (
        Join-Path $PSScriptRoot '..'
    )).Path

$mods = Join-Path `
([Environment]::GetFolderPath('Desktop')) `
    'FS25_Mods\_ModTest'

$target = Join-Path $mods 'FS25_TerraformPlus'

Write-Host ''
Write-Host "Terraform Plus v$expectedVersion - Installation" `
    -ForegroundColor Cyan

# ------------------------------------------------------------
# 1. Basisverzeichnisse pruefen
# ------------------------------------------------------------

if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Test-Modordner fehlt: $mods"
}

$descPath = Join-Path $repo 'modDesc.xml'
$sourceScripts = Join-Path $repo 'scripts'

if (-not (Test-Path -LiteralPath $descPath -PathType Leaf)) {
    throw 'modDesc.xml fehlt'
}

if (-not (Test-Path -LiteralPath $sourceScripts -PathType Container)) {
    throw 'scripts-Verzeichnis fehlt'
}

# ------------------------------------------------------------
# 2. Versionspruefung
# ------------------------------------------------------------

[xml]$xml = Get-Content -LiteralPath $descPath -Raw

$version = ([string]$xml.modDesc.version).Trim()

if ($version -ne $expectedVersion) {
    throw "Versionsfehler: $version statt $expectedVersion"
}

Write-Host "[OK] Mod-Version: $version" -ForegroundColor Green

# ------------------------------------------------------------
# 3. Lua-Eintraege aus modDesc.xml
# ------------------------------------------------------------

$declared = @(
    $xml.modDesc.extraSourceFiles.sourceFile |
    ForEach-Object {
        [string]$_.filename
    }
)

if ($declared.Count -eq 0) {
    throw 'Keine Lua-Module registriert'
}

# Doppelte Lua-Eintraege erkennen.

$uniqueFiles = @($declared | Sort-Object -Unique)

if ($uniqueFiles.Count -ne $declared.Count) {
    throw 'Doppelte Lua-Eintraege in modDesc.xml'
}

# ------------------------------------------------------------
# 4. Pflichtmodule und korrekte Ladereihenfolge
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
    'scripts/TerrainWriter.lua',
    'scripts/TerrainBatch.lua',
    'scripts/TerrainStability.lua'
)

if ($declared.Count -ne $requiredModules.Count) {
    throw "Unerwartete Modulanzahl: $($declared.Count)"
}

if ($declared.Count -lt $requiredModules.Count) {
    throw ("Es fehlen Module: erwartet {0}, deklariert {1}." -f $requiredModules.Count, $declared.Count)
}

for ($i = 0; $i -lt $requiredModules.Count; $i++) {
    if ($declared[$i] -cne $requiredModules[$i]) {
        throw ("Ladereihenfolge ungueltig bei Modul {0}: erwartet '{1}', deklariert '{2}'." -f ($i + 1), $requiredModules[$i], $declared[$i])
    }
}

Write-Host '[OK] Alle 14 Module korrekt registriert' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 5. Quelldateien kontrollieren
# ------------------------------------------------------------

$required = @('modDesc.xml', 'icon.png') + $declared

foreach ($relative in $required) {

    if ($relative -notin @('modDesc.xml', 'icon.png')) {

        if (
            $relative -notmatch '^scripts/[A-Za-z0-9_./-]+\.lua$' -or
            $relative -match '(^|/)\.\.(/|$)'
        ) {
            throw "Ungueltiger Lua-Pfad: $relative"
        }
    }

    $path = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Quelldatei fehlt: $relative"
    }
}

# Nicht registrierte Lua-Dateien erkennen.

$actualLua = @(
    Get-ChildItem `
        -LiteralPath $sourceScripts `
        -Filter '*.lua' `
        -Recurse `
        -File
)

foreach ($file in $actualLua) {
    $relative = $file.FullName.Substring(
        $repo.Length + 1
    ).Replace('\', '/')

    if ($declared -notcontains $relative) {
        throw "Lua-Datei nicht registriert: $relative"
    }
}

Write-Host '[OK] Alle Quelldateien vorhanden' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 6. Neue Stabilitaetsfunktionen pruefen
# ------------------------------------------------------------

$stabilityPath = Join-Path `
    $repo 'scripts/TerrainStability.lua'

$stability = Get-Content `
    -LiteralPath $stabilityPath `
    -Raw

$requiredMethods = @(
    'checkNeighbors',
    'beforeSave',
    'consoleCommandNeighborCheck',
    'consoleCommandSaveGuardStatus',
    'startSaveCurrentGame',
    'saveSavegame'
)

foreach ($method in $requiredMethods) {
    if (-not $stability.Contains($method)) {
        throw "TerrainStability-Funktion fehlt: $method"
    }
}

$batchPath = Join-Path $repo 'scripts/TerrainBatch.lua'
$batch = Get-Content -LiteralPath $batchPath -Raw

foreach ($method in @(
        'consoleCommandBatchApply',
        'consoleCommandBatchUndo',
        'consoleCommandBatchRecover',
        'setTerrainHeightAtWorldPos'
    )) {
    if (-not $batch.Contains($method)) {
        throw "TerrainBatch-Funktion fehlt: $method"
    }
}

Write-Host '[OK] Stabilitaets- und Batch-Funktionen vorhanden' `
    -ForegroundColor Green

# ------------------------------------------------------------
# 7. Installation
# ------------------------------------------------------------

New-Item `
    -ItemType Directory `
    -Path $target `
    -Force | Out-Null

$targetScripts = Join-Path $target 'scripts'

if (Test-Path -LiteralPath $targetScripts) {
    Remove-Item `
        -LiteralPath $targetScripts `
        -Recurse `
        -Force
}

Copy-Item `
    -LiteralPath $descPath `
    -Destination $target `
    -Force

Copy-Item `
    -LiteralPath (Join-Path $repo 'icon.png') `
    -Destination $target `
    -Force

Copy-Item `
    -LiteralPath $sourceScripts `
    -Destination $target `
    -Recurse `
    -Force

# ------------------------------------------------------------
# 8. SHA256-Verifikation
# ------------------------------------------------------------

foreach ($relative in $required) {

    $sourcePath = Join-Path $repo $relative
    $targetPath = Join-Path $target $relative

    if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
        throw "Installierte Datei fehlt: $relative"
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
        throw "SHA256-Fehler: $relative"
    }
}

# ------------------------------------------------------------
# 9. Ergebnis
# ------------------------------------------------------------

Write-Host ''
Write-Host '========================================'
Write-Host ' INSTALLATION ERFOLGREICH'
Write-Host '========================================' -ForegroundColor Green

Write-Host "[Terraform Plus] Version: $expectedVersion"
Write-Host "[Terraform Plus] $($declared.Count) Lua-Dateien verifiziert"
Write-Host '[Terraform Plus] UI, Nachbarschaft und Saveguard installiert'
Write-Host "[Terraform Plus] Ziel: $target"

Write-Host ''
Write-Host 'WICHTIG: Nur mit kopiertem Testspielstand verwenden!' `
    -ForegroundColor Yellow
Write-Host 'LS25 vollstaendig neu starten.'
