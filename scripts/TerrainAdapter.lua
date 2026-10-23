
-- Terraform Plus - Terrain Adapter
-- Version: 0.0.2.1

TerrainAdapter = TerrainAdapter or {}

print("[Terraform Plus] TerrainAdapter.lua geladen")

-- Liest die Gelaendehoehe an einer Weltposition.
function TerrainAdapter.getHeightAt(x, z)

    if type(x) ~= "number" or type(z) ~= "number" then
        return nil, "Ungueltige Koordinaten"
    end

    local terrainNode = g_terrainNode

    if terrainNode == nil or terrainNode == 0 then
        return nil, "Terrain nicht geladen"
    end

    if type(getTerrainHeightAtWorldPos) ~= "function" then
        return nil, "Terrainhoehen-API nicht verfuegbar"
    end

    local height = getTerrainHeightAtWorldPos(
        terrainNode,
        x,
        0,
        z
    )

    if type(height) ~= "number" then
        return nil, "Keine gueltige Terrainhoehe erhalten"
    end

    return height, nil
end

-- Liest Position und Terrainhoehe des Spielers.
function TerrainAdapter.getHeightAtPlayer()

    local player = g_localPlayer

    if player == nil then
        return nil, "Spieler nicht geladen"
    end

    -- Szenengraph-Knoten des Spielers
    local rootNode = player.rootNode

    if rootNode == nil or rootNode == 0 then
        return nil, "Spieler-RootNode nicht verfuegbar"
    end

    if type(getWorldTranslation) ~= "function" then
        return nil, "Positions-API nicht verfuegbar"
    end

    -- Weltkoordinaten des Spielers ermitteln
    local x, y, z = getWorldTranslation(rootNode)

    if type(x) ~= "number"
        or type(y) ~= "number"
        or type(z) ~= "number" then
        return nil, "Ungueltige Spielerposition"
    end

    -- Terrainhoehe an der Spielerposition ermitteln
    local height, err = TerrainAdapter.getHeightAt(x, z)

    if height == nil then
        return nil, err
    end

    return {
        x = x,
        z = z,
        playerY = y,
        terrainY = height
    }, nil
end
