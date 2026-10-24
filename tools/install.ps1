# Terraform Plus - strikte Testinstallation v0.0.13.0
$ErrorActionPreference = 'Stop'
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mods = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FS25_Mods\_ModTest'
$target = Join-Path $mods 'FS25_TerraformPlus'
$expectedVersion = '0.0.13.0'

if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Test-Modverzeichnis fehlt: $mods"
}
$descFile = Join-Path $repo 'modDesc.xml'
if (-not (Test-Path -LiteralPath $descFile -PathType Leaf)) {
    throw "modDesc.xml fehlt: $descFile"
}
[xml]$xml = Get-Content -LiteralPath $descFile -Raw
$version = ([string]$xml.modDesc.version).Trim()
if ($version -ne $expectedVersion) {
    throw "Versionsfehler: $version statt $expectedVersion"
}
$declared = @($xml.modDesc.extraSourceFiles.sourceFile | ForEach-Object {
    [string]$_.filename
})
if ($declared.Count -eq 0) { throw 'Keine Lua-Module registriert' }
if (@($declared | Select-Object -Unique).Count -ne $declared.Count) {
    throw 'Doppelte Lua-Eintraege in modDesc.xml'
}
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
    'scripts/TerraformPlusUIBridge.lua'
)
foreach ($item in $requiredModules) {
    if ($declared -notcontains $item) {
        throw "Pflichtmodul fehlt in modDesc.xml: $item"
    }
}
$planIndex = [array]::IndexOf($declared, 'scripts/TerrainPlan.lua')
$designIndex = [array]::IndexOf($declared, 'scripts/TerrainDesign.lua')
$uiIndex = [array]::IndexOf($declared, 'scripts/TerrainToolUI.lua')
$coreIndex = [array]::IndexOf($declared, 'scripts/TerraformPlus.lua')
$bridgeIndex = [array]::IndexOf($declared, 'scripts/TerraformPlusUIBridge.lua')
if (-not ($designIndex -lt $bridgeIndex -and $planIndex -lt $bridgeIndex `
    -and $uiIndex -lt $bridgeIndex -and $coreIndex -lt $bridgeIndex)) {
    throw 'Ungueltige Lua-Ladereihenfolge'
}
$required = @('modDesc.xml', 'icon.png') + $declared
foreach ($relative in $required) {
    $p = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) {
        throw "Pflichtdatei fehlt: $p"
    }
}
$files = Get-ChildItem -LiteralPath (Join-Path $repo 'scripts') -Recurse -File -Filter '*.lua'
foreach ($f in $files) {
    $relative = $f.FullName.Substring($repo.Length+1).Replace('\', '/')
    if ($declared -notcontains $relative) {
        throw "Lua-Datei nicht in modDesc.xml registriert: $relative"
    }
}
$bridge = Get-Content -LiteralPath (Join-Path $repo 'scripts/TerraformPlusUIBridge.lua') -Raw
foreach ($method in @('consoleCommandPlanPrepare', 'consoleCommandDesignUndo',
                      'consoleCommandDesignRedo', 'consoleCommandPlanRun')) {
    if (-not $bridge.Contains($method)) {
        throw "Neue Methode fehlt in UI-Bridge: $method"
    }
}
New-Item -ItemType Directory -Path $target -Force | Out-Null
$targetScripts = Join-Path $target 'scripts'
if (Test-Path -LiteralPath $targetScripts) {
    Remove-Item -LiteralPath $targetScripts -Recurse -Force
}
Copy-Item -LiteralPath $descFile -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'icon.png') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination $target -Recurse -Force
foreach ($relative in $required) {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath (Join-Path $target $relative) -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) {
        throw "Datei fehlerhaft kopiert: $relative"
    }
}
Write-Host "[Terraform Plus] Installation verifiziert: v$expectedVersion" -ForegroundColor Green
Write-Host "[Terraform Plus] $($declared.Count) Lua-Dateien und Ladefolge kontrolliert" -ForegroundColor Green
Write-Host '[Terraform Plus] Undo/Redo und lesendes Pruefraster registriert' -ForegroundColor Green
Write-Host "[Terraform Plus] Ziel: $target"
Write-Host 'LS25 vollstaendig neu starten.'
