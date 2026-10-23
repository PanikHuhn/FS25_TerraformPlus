
-- Terraform Plus
-- Version: 0.0.2.1

TerraformPlus = {}

TerraformPlus.VERSION = "0.0.2.1"

-- Formatiert die gemessene Gelaendehoehe.
function TerraformPlus:formatHeight(sample)

    return string.format(
        "[Terraform Plus] X=%.2f Z=%.2f | Terrainhoehe=%.3f m",
        sample.x,
        sample.z,
        sample.terrainY
    )
end

-- Wird beim Laden einer Karte ausgefuehrt.
function TerraformPlus:loadMap()

    print("[Terraform Plus] Mod geladen - Version " .. self.VERSION)

    addConsoleCommand(
        "tpHeight",
        "Zeigt die Gelaendehoehe unter dem Spieler",
        "consoleCommandHeight",
        self
    )

end

-- Konsolenbefehl: tpHeight
function TerraformPlus:consoleCommandHeight()

    if TerrainAdapter == nil then
        return "[Terraform Plus] TerrainAdapter nicht geladen"
    end

    local success, sample, err = pcall(
        TerrainAdapter.getHeightAtPlayer
    )

    if not success then
        return "[Terraform Plus] Lua-Fehler: " .. tostring(sample)
    end

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    return self:formatHeight(sample)
end

-- Wird beim Verlassen der Karte ausgefuehrt.
function TerraformPlus:deleteMap()

    removeConsoleCommand("tpHeight")

    print("[Terraform Plus] Karte entladen")
end

addModEventListener(TerraformPlus)
