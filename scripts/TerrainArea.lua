
-- Terraform Plus - Terrain Area
-- Version: 0.0.7.0
-- 2D terrain grid and cut/fill volume estimation

TerrainArea = TerrainArea or {}

TerrainArea.DEFAULT_WIDTH = 10.0
TerrainArea.DEFAULT_STEP = 2.0

TerrainArea.MIN_WIDTH = 1.0
TerrainArea.MAX_WIDTH = 80.0

TerrainArea.MIN_STEP = 0.5
TerrainArea.MAX_STEP = 5.0

TerrainArea.MAX_LENGTH_SEGMENTS = 128
TerrainArea.MAX_WIDTH_SEGMENTS = 32


-- Erstellt ein 2D-Raster um die Linie A-B.
function TerrainArea.build(pointA, pointB, width, step)

    if pointA == nil or pointB == nil then
        return nil, "Beide Messpunkte erforderlich"
    end

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt) ~= "function" then
        return nil, "TerrainAdapter nicht verfuegbar"
    end

    width = width or TerrainArea.DEFAULT_WIDTH
    step = step or TerrainArea.DEFAULT_STEP

    if type(width) ~= "number"
        or width ~= width
        or width < TerrainArea.MIN_WIDTH
        or width > TerrainArea.MAX_WIDTH then

        return nil, "Arbeitsbreite muss zwischen 1 und 80 m liegen"
    end

    if type(step) ~= "number"
        or step ~= step
        or step < TerrainArea.MIN_STEP
        or step > TerrainArea.MAX_STEP then

        return nil, "Rasterabstand muss zwischen 0.5 und 5 m liegen"
    end

    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    -- Einheitsvektor senkrecht zur Messlinie
    local sideX = -dz / distance
    local sideZ = dx / distance

    -- Rasteraufloesung mit Sicherheitsgrenzen
    local lengthCells = math.min(
        TerrainArea.MAX_LENGTH_SEGMENTS,
        math.max(1, math.ceil(distance / step))
    )

    local widthCells = math.min(
        TerrainArea.MAX_WIDTH_SEGMENTS,
        math.max(1, math.ceil(width / step))
    )

    local cellLength = distance / lengthCells
    local cellWidth = width / widthCells

    local cellArea = cellLength * cellWidth

    local heightDifference =
        pointB.terrainY - pointA.terrainY

    local samples = {}

    local cutVolume = 0
    local fillVolume = 0

    local maxCutDepth = 0
    local maxFillDepth = 0

    local maxCutSample = nil
    local maxFillSample = nil

    local minHeight = math.huge
    local maxHeight = -math.huge

    -- Alle Zellen am jeweiligen Mittelpunkt abtasten
    for i = 1, lengthCells do

        local t = (i - 0.5) / lengthCells

        local centerX = pointA.x + dx * t
        local centerZ = pointA.z + dz * t

        -- Eine Ebene mit gleichmaessiger Steigung A -> B
        local targetHeight =
            pointA.terrainY + heightDifference * t

        for j = 1, widthCells do

            -- Querposition relativ zur Mittellinie
            local lateral =
                ((j - 0.5) / widthCells - 0.5) * width

            local x = centerX + sideX * lateral
            local z = centerZ + sideZ * lateral

            local success, height, err = pcall(
                TerrainAdapter.getHeightAt,
                x,
                z
            )

            if not success then
                return nil, "Terrainabfrage: " .. tostring(height)
            end

            if type(height) ~= "number" then
                return nil, "Terrainabfrage: " .. tostring(err)
            end

            -- Positive Differenz = Auftrag
            -- Negative Differenz = Abtrag
            local change = targetHeight - height

            local sample = {
                x = x,
                z = z,
                terrainY = height,
                referenceY = targetHeight,
                requiredChange = change,
                cellArea = cellArea,
                alongIndex = i,
                acrossIndex = j
            }

            samples[#samples + 1] = sample

            minHeight = math.min(minHeight, height)
            maxHeight = math.max(maxHeight, height)

            if change > 0 then

                fillVolume = fillVolume + change * cellArea

                if change > maxFillDepth then
                    maxFillDepth = change
                    maxFillSample = sample
                end

            elseif change < 0 then

                local depth = -change

                cutVolume = cutVolume + depth * cellArea

                if depth > maxCutDepth then
                    maxCutDepth = depth
                    maxCutSample = sample
                end
            end
        end
    end

    -- Eckpunkte der Soll-Ebene fuer die Visualisierung
    local function makeCorner(t, lateral)

        return {
            x = pointA.x + dx * t + sideX * lateral,
            z = pointA.z + dz * t + sideZ * lateral,
            y = pointA.terrainY + heightDifference * t
        }
    end

    local halfWidth = width * 0.5

    local corners = {
        makeCorner(0, -halfWidth),
        makeCorner(0, halfWidth),
        makeCorner(1, halfWidth),
        makeCorner(1, -halfWidth)
    }

    return {
        samples = samples,
        corners = corners,

        width = width,
        requestedStep = step,
        distance = distance,

        lengthCells = lengthCells,
        widthCells = widthCells,

        cellLength = cellLength,
        cellWidth = cellWidth,
        cellArea = cellArea,

        area = width * distance,

        cutVolume = cutVolume,
        fillVolume = fillVolume,
        netVolume = fillVolume - cutVolume,

        maxCutDepth = maxCutDepth,
        maxFillDepth = maxFillDepth,

        maxCutSample = maxCutSample,
        maxFillSample = maxFillSample,

        minHeight = minHeight,
        maxHeight = maxHeight
    }, nil
end
