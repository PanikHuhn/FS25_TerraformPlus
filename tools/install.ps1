# Terraform Plus - strict development installation
# Version: 0.0.10.0
$ErrorActionPreference = 'Stop'

$repo = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mods = Join-Path ([Environment]::GetFolderPath('Desktop')) 'FS25_Mods\_ModTest'
$target = Join-Path $mods 'FS25_TerraformPlus'

$requiredFiles = @(
    'modDesc.xml', 'icon.png',
    'scripts/TerrainAdapter.lua',
    'scripts/TerrainProfile.lua',
    'scripts/TerrainArea.lua',
    'scripts/TerrainVisualizer.lua',
    'scripts/TerrainCursor.lua',
    'scripts/TerrainSelection.lua',
    'scripts/TerrainToolUI.lua',
    'scripts/TerraformPlus.lua',
    'scripts/TerraformPlusUIBridge.lua'
)

if (-not (Test-Path -LiteralPath $mods -PathType Container)) {
    throw "Test-Modordner fehlt: $mods"
}

foreach ($relative in $requiredFiles) {
    $path = Join-Path $repo $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Pflichtdatei fehlt: $path"
    }
}

[xml]$xml = Get-Content -LiteralPath (Join-Path $repo 'modDesc.xml') -Raw
$version = $xml.modDesc.version.Trim()
if ($version -ne '0.0.10.0') {
    throw "Falsche Quellversion: $version (erwartet: 0.0.10.0)"
}

$described = @($xml.modDesc.extraSourceFiles.sourceFile | ForEach-Object { $_.filename })
foreach ($relative in ($requiredFiles | Where-Object { $_ -like 'scripts/*' })) {
    if ($described -notcontains $relative) {
        throw "Lua-Datei fehlt in modDesc.xml: $relative"
    }
}

$bridgePath = Join-Path $repo 'scripts/TerraformPlusUIBridge.lua'
$bridgeCode = Get-Content -LiteralPath $bridgePath -Raw
foreach ($method in @('consoleCommandUI','consoleCommandUIMouse','onInputUI','onInputMouse')) {
    if ($bridgeCode -notmatch [regex]::Escape($method)) {
        throw "UI-Methode nicht in Bridge vorhanden: $method"
    }
}

New-Item -ItemType Directory -Path $target -Force | Out-Null
$targetScripts = Join-Path $target 'scripts'
if (Test-Path -LiteralPath $targetScripts) {
    Remove-Item -LiteralPath $targetScripts -Recurse -Force
}

Copy-Item -LiteralPath (Join-Path $repo 'modDesc.xml') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'icon.png') -Destination $target -Force
Copy-Item -LiteralPath (Join-Path $repo 'scripts') -Destination $target -Recurse -Force

foreach ($relative in $requiredFiles) {
    $sourceHash = (Get-FileHash -LiteralPath (Join-Path $repo $relative) -Algorithm SHA256).Hash
    $targetHash = (Get-FileHash -LiteralPath (Join-Path $target $relative) -Algorithm SHA256).Hash
    if ($sourceHash -ne $targetHash) {
        throw "Kopie fehlerhaft: $relative"
    }
}

Write-Host '[Terraform Plus] Installation verifiziert: v0.0.10.0' -ForegroundColor Green
Write-Host '[Terraform Plus] UI-Befehle: tpUI, tpUIMouse' -ForegroundColor Green
Write-Host "[Terraform Plus] Ziel: $target"
Write-Host 'Spiel vollstaendig neu starten.'
