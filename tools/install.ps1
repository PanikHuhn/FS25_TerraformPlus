
# Terraform Plus - strikte Entwicklungsinstallation
# Version: 0.0.15.0

$ErrorActionPreference = 'Stop'

$expectedVersion = '0.0.15.0'

$repo = (Resolve-Path (
    Join-Path $PSScriptRoot '..'
)).Path

$mods = Join-Path (
    [Environment]::GetFolderPath('Desktop')
) 'FS25_Mods\_ModTest'

$target = Join-Path $mods 'FS25_TerraformPlus'

# -------------------------------------------------
# 1. Verzeichnisse pruefen
# -------------------------------------------------

if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Test-Modordner fehlt: $mods"
}

$descPath = Join-Path $repo 'modDesc.xml'

if (-not (Test-Path -LiteralPath $descPath -PathType Leaf)) {
    throw "modDesc.xml fehlt: $descPath"
}

# -------------------------------------------------
# 2. Version und Lua-Registrierung
# -------------------------------------------------

[xml]$xml = Get-Content -LiteralPath $descPath -Raw

$version = ([string]$xml.modDesc.version).Trim()

if ($version -ne $expectedVersion) {
    throw "Falsche Mod-Version: $version (erwartet $expectedVersion)"
}

$declared = @(
    $xml.modDesc.extraSourceFiles.sourceFile |
        ForEach-Object {
            [string]$_.filename
        }
)

if ($declared.Count -eq 0) {
    throw 'Keine Lua-Dateien registriert'
}

$uniqueFiles = @($declared | Sort-Object -Unique)

if ($uniqueFiles.Count -ne $declared.Count) {
    throw 'Doppelte Lua-Eintraege in modDesc.xml'
}

# -------------------------------------------------
# 3. Pflichtmodule und Ladereihenfolge
# -------------------------------------------------

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
    'scripts/TerrainBatch.lua'
)

if ($declared.Count -ne $requiredModules.Count) {
    throw 'Unerwartete Anzahl Lua-Module in modDesc.xml'
}

for ($i = 0; $i -lt $requiredModules.Count; $i++) {
    if ($declared[$i] -cne $requiredModules[$i]) {
        throw "Lua-Ladereihenfolge abweichend an Stelle $($i + 1): $($declared[$i])"
    }
}

# -------------------------------------------------
# 4. Alle Quelldateien pruefen
# -------------------------------------------------

$required = @('modDesc.xml', 'icon.png') + $declared

foreach ($relative in $required) {

    if (
        $relative -like 'scripts/*' -and (
            $relative -notmatch '^scripts/[A-Za-z0-9_./-]+\.lua$' -or
            $relative -match '(^|/)\.\.(/|$)'
        )
    ) {
        throw "Ungueltiger Modulpfad: $relative"
    }

    $path = Join-Path $repo $relative

    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Pflichtdatei fehlt: $relative"
    }
}

# -------------------------------------------------
# 5. Nicht registrierte Lua-Dateien erkennen
# -------------------------------------------------

$sourceScripts = Join-Path $repo 'scripts'

$actualLua = @(
    Get-ChildItem `
        -LiteralPath $sourceScripts `
        -Filter '*.lua' `
        -File `
        -Recurse
)

foreach ($file in $actualLua) {

    $relative = $file.FullName.Substring(
        $repo.Length + 1
    ).Replace('\', '/')

    if ($declared -notcontains $relative) {
        throw "Neue Lua-Datei noch nicht in modDesc.xml: $relative"
    }
}

# -------------------------------------------------
# 6. Neue Batch-Funktionen pruefen
# -------------------------------------------------

$batchCode = Get-Content `
    -LiteralPath (Join-Path $repo 'scripts/TerrainBatch.lua') `
    -Raw

foreach ($method in @(
    'consoleCommandBatchApply',
    'consoleCommandBatchCancel',
    'consoleCommandBatchUndo',
    'consoleCommandBatchRedo',
    'consoleCommandBatchRecover',
    'setTerrainHeightAtWorldPos'
)) {
    if (-not $batchCode.Contains($method)) {
        throw "TerrainBatch-Funktion fehlt: $method"
    }
}

# -------------------------------------------------
# 7. Test-Mod installieren
# -------------------------------------------------

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

# -------------------------------------------------
# 8. SHA256-Dateipruefung
# -------------------------------------------------

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
        throw "SHA256-Abweichung nach Installation: $relative"
    }
}

# -------------------------------------------------
# 9. Ergebnis
# -------------------------------------------------

Write-Host "[Terraform Plus] Installation verifiziert: v$expectedVersion" `
    -ForegroundColor Green

Write-Host "[Terraform Plus] $($declared.Count) Lua-Dateien kontrolliert" `
    -ForegroundColor Green

Write-Host '[Terraform Plus] Batch: 256 Punkte, 8/Frame, max. 0.25 m' `
    -ForegroundColor Yellow

Write-Host "[Terraform Plus] Ziel: $target"

Write-Host 'LS25 neu starten; nur Kopie eines Testspielstands verwenden.'
