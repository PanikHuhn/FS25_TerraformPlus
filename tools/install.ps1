
# Terraform Plus - strikte Testinstallation
# Version: 0.0.12.0
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mods = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FS25_Mods\_ModTest'
$target = Join-Path $mods 'FS25_TerraformPlus'
$expectedVersion = '0.0.12.0'

if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Test-Modverzeichnis fehlt: $mods"
}

$desc = Join-Path $repo 'modDesc.xml'
if (-not (Test-Path -LiteralPath $desc -PathType Leaf)) {
    throw "modDesc.xml fehlt: $desc"
}
[xml]$xml = Get-Content -LiteralPath $desc -Raw
$version = [string]$xml.modDesc.version
if ($version.Trim() -ne $expectedVersion) {
    throw "Versionsfehler: modDesc.xml=$version, erwartet=$expectedVersion"
}

$required = @('modDesc.xml', 'icon.png')
$declared = @($xml.modDesc.extraSourceFiles.sourceFile | ForEach-Object {
    [string]$_.filename
})
if ($declared.Count -eq 0) { throw 'Keine Lua-Dateien in modDesc.xml registriert' }
if (($declared | Select-Object -Unique).Count -ne $declared.Count) {
    throw 'Doppelte Lua-Eintraege in modDesc.xml'
}

# Kritische Module muessen vorhanden und in der richtigen Reihenfolge geladen sein.
$needed = @(
    'scripts/TerrainAdapter.lua', 'scripts/TerrainProfile.lua',
    'scripts/TerrainArea.lua', 'scripts/TerrainVisualizer.lua',
    'scripts/TerrainCursor.lua', 'scripts/TerrainSelection.lua',
    'scripts/TerrainDesign.lua', 'scripts/TerrainToolUI.lua',
    'scripts/TerraformPlus.lua', 'scripts/TerraformPlusUIBridge.lua'
)
foreach ($relative in $needed) {
    if ($declared -notcontains $relative) {
        throw "Pflichtmodul fehlt in modDesc.xml: $relative"
    }
}
$designIndex = [array]::IndexOf($declared,'scripts/TerrainDesign.lua')
$uiIndex = [array]::IndexOf($declared,'scripts/TerrainToolUI.lua')
$coreIndex = [array]::IndexOf($declared,'scripts/TerraformPlus.lua')
$bridgeIndex = [array]::IndexOf($declared,'scripts/TerraformPlusUIBridge.lua')
if (-not ($designIndex -lt $uiIndex -and $uiIndex -lt $bridgeIndex `
    -and $coreIndex -lt $bridgeIndex)) {
    throw 'Ladereihenfolge in modDesc.xml ungueltig'
}

$required += $declared
foreach ($relative in $required) {
    $source = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Pflichtdatei fehlt: $source"
    }
}

# Neue Lua-Dateien duerfen nicht stillschweigend vergessen werden.
$luaFiles = Get-ChildItem -LiteralPath (Join-Path $repo 'scripts') `
    -Filter '*.lua' -File -Recurse
foreach ($file in $luaFiles) {
    $relative = $file.FullName.Substring($repo.Length + 1).Replace('\','/')
    if ($declared -notcontains $relative) {
        throw "Neue Lua-Datei noch nicht in modDesc.xml: $relative"
    }
}

$bridge = Get-Content -LiteralPath `
    (Join-Path $repo 'scripts/TerraformPlusUIBridge.lua') -Raw
foreach ($method in @(
    'consoleCommandUI', 'consoleCommandUIMouse',
    'consoleCommandChangeLimit', 'consoleCommandDesignCheck'
)) {
    if (-not $bridge.Contains($method)) {
        throw "Methode fehlt in TerraformPlusUIBridge.lua: $method"
    }
}

New-Item -Path $target -ItemType Directory -Force | Out-Null
$targetScripts = Join-Path $target 'scripts'
if (Test-Path -LiteralPath $targetScripts) {
    Remove-Item -LiteralPath $targetScripts -Recurse -Force
}
Copy-Item -LiteralPath $desc -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'icon.png') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination $target -Recurse -Force

foreach ($relative in $required) {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $repo $relative) `
        -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath (Join-Path $target $relative) `
        -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) {
        throw "Datei fehlerhaft kopiert: $relative"
    }
}

Write-Host "[Terraform Plus] Installation verifiziert: v$expectedVersion" `
    -ForegroundColor Green
Write-Host "[Terraform Plus] $($declared.Count) Lua-Dateien kontrolliert" `
    -ForegroundColor Green
Write-Host '[Terraform Plus] Neue Befehle: tpChangeLimit, tpDesignCheck' `
    -ForegroundColor Green
Write-Host "[Terraform Plus] Ziel: $target"
Write-Host 'LS25 vollstaendig neu starten.'
