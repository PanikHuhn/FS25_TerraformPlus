
-- Terraform Plus - Terrain Cursor
-- Version: 0.0.9.0
-- Camera-centered terrain targeting

TerrainCursor = TerrainCursor or {}

TerrainCursor.MAX_DISTANCE = 500.0
TerrainCursor.lastHit = nil


-- Callback fuer den synchronen GIANTS-Raycast.
function TerrainCursor:onTerrainRaycast(
    nodeId, x, y, z,
    distance, nx, ny, nz
)
    self.lastHit = {
        x = x,
        y = y,
        z = z,
        distance = distance
    }

    return true
end


-- Liefert die Terrainposition in der Kameramitte.
function TerrainCursor.getGroundPoint()

    if g_cameraManager == nil
        or type(g_cameraManager.getActiveCamera)
            ~= "function" then

        return nil, "Kamera-Manager nicht verfuegbar"
    end

    if type(getWorldTranslation) ~= "function"
        or type(localDirectionToWorld) ~= "function" then

        return nil, "Kamera-API nicht verfuegbar"
    end

    if type(raycastClosest) ~= "function" then
        return nil, "Raycast-API nicht verfuegbar"
    end

    if CollisionFlag == nil
        or CollisionFlag.TERRAIN == nil then

        return nil, "Terrain-Kollisionsmaske fehlt"
    end

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt) ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local camera = g_cameraManager:getActiveCamera()

    if camera == nil or camera == 0 then
        return nil, "Keine aktive Kamera"
    end

    -- Ursprung des Strahls
    local ox, oy, oz = getWorldTranslation(camera)

    -- Blickrichtung der Kamera
    local dx, dy, dz =
        localDirectionToWorld(camera, 0, 0, -1)

    if type(ox) ~= "number"
        or type(oy) ~= "number"
        or type(oz) ~= "number"
        or type(dx) ~= "number"
        or type(dy) ~= "number"
        or type(dz) ~= "number" then

        return nil, "Ungueltige Kameraposition"
    end

    -- Richtung normalisieren
    local length = math.sqrt(
        dx * dx + dy * dy + dz * dz
    )

    if length < 0.00001 then
        return nil, "Ungueltige Kamerarichtung"
    end

    dx = dx / length
    dy = dy / length
    dz = dz / length

    -- Alten Treffer vor jeder Abfrage entfernen.
    TerrainCursor.lastHit = nil

    -- Ausschliesslich Terrain treffen.
    -- Fahrzeuge, Gebaeude und andere Objekte
    -- werden nicht als Zielpunkte verwendet.
    local success, err = pcall(
        raycastClosest,
        ox, oy, oz,
        dx, dy, dz,
        TerrainCursor.MAX_DISTANCE,
        "onTerrainRaycast",
        TerrainCursor,
        CollisionFlag.TERRAIN
    )

    if not success then
        return nil, "Raycast-Fehler: " .. tostring(err)
    end

    local hit = TerrainCursor.lastHit

    if hit == nil then
        return nil, "Kein Terrain getroffen - Kamera auf Boden richten"
    end

    -- Terrainhoehe direkt aus der Heightmap lesen.
    -- Dadurch bleiben alle Analysefunktionen
    -- konsistent mit TerrainAdapter.
    local ok, height, heightErr = pcall(
        TerrainAdapter.getHeightAt,
        hit.x,
        hit.z
    )

    if not ok then
        return nil, "Hoehenabfrage: " .. tostring(height)
    end

    if type(height) ~= "number" then
        return nil, tostring(
            heightErr or "Ungueltige Terrainhoehe"
        )
    end

    return {
        x = hit.x,
        z = hit.z,
        terrainY = height,
        rayDistance = hit.distance
    }, nil
end
