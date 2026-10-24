
-- Terraform Plus - Terrain Profile
-- Version: 0.0.6.0
-- Read-only terrain profiling and cut/fill analysis

TerrainProfile = TerrainProfile or {}

TerrainProfile.TARGET_STEP = 2.0
TerrainProfile.MAX_SEGMENTS = 128


-- Berechnet die Schnittflaechen eines Teilabschnitts.
-- deviation = Terrainhoehe - Sollhoehe
-- Positiv: Abtragen (Cut)
-- Negativ: Auffuellen (Fill)
local function calculateSegmentAreas(a, b, width)

    if a >= 0 and b >= 0 then
        return (a + b) * 0.5 * width, 0
    end

    if a <= 0 and b <= 0 then
        return 0, -(a + b) * 0.5 * width
    end

    -- Vorzeichenwechsel: Nullstelle linear interpolieren.
    -- Dadurch werden Cut und Fill getrennt integriert.
    local fraction = math.abs(a) / (math.abs(a) + math.abs(b))

    local firstArea =
        0.5 * math.abs(a) * width * fraction

    local secondArea =
        0.5 * math.abs(b) * width * (1 - fraction)

    if a > 0 then
        return firstArea, secondArea
    end

    return secondArea, firstArea
end


function TerrainProfile.build(pointA, pointB)

    if pointA == nil or pointB == nil then
        return nil, "Beide Messpunkte werden benoetigt"
    end

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt) ~= "function" then
        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    local segments = math.min(
        TerrainProfile.MAX_SEGMENTS,
        math.max(
            1,
            math.ceil(distance / TerrainProfile.TARGET_STEP)
        )
    )

    local step = distance / segments
    local heightDelta = pointB.terrainY - pointA.terrainY

    local samples = {}

    local minHeight = math.huge
    local maxHeight = -math.huge

    local maxAbove = 0
    local maxBelow = 0

    local maxCutIndex = nil
    local maxFillIndex = nil

    local steepestSegment = 0
    local steepestSegmentIndex = nil

    local cutArea = 0
    local fillArea = 0

    for i = 0, segments do

        local t = i / segments

        local x = pointA.x + dx * t
        local z = pointA.z + dz * t

        local height

        if i == 0 then

            height = pointA.terrainY

        elseif i == segments then

            height = pointB.terrainY

        else

            local success, result, err = pcall(
                TerrainAdapter.getHeightAt,
                x,
                z
            )

            if not success then
                return nil, "Terrainabfrage: " .. tostring(result)
            end

            if type(result) ~= "number" then
                return nil, "Terrainabfrage: " .. tostring(err)
            end

            height = result
        end

        -- Gerade Sollhoehe zwischen A und B
        local referenceHeight =
            pointA.terrainY + heightDelta * t

        -- Positiv = Gelaende ueber der Sollhoehe
        local deviation = height - referenceHeight

        -- Positiv = Gelaende muss angehoben werden
        local requiredChange = referenceHeight - height

        local sampleIndex = #samples + 1

        local sample = {
            x = x,
            z = z,
            terrainY = height,
            referenceY = referenceHeight,
            deviation = deviation,
            requiredChange = requiredChange,
            distanceFromA = distance * t
        }

        samples[sampleIndex] = sample

        minHeight = math.min(minHeight, height)
        maxHeight = math.max(maxHeight, height)

        if deviation > maxAbove then
            maxAbove = deviation
            maxCutIndex = sampleIndex
        end

        if deviation < maxBelow then
            maxBelow = deviation
            maxFillIndex = sampleIndex
        end

        if sampleIndex > 1 then

            local previous = samples[sampleIndex - 1]

            -- Lokale Steigung in Prozent
            local localSlope =
                (height - previous.terrainY) / step * 100

            if math.abs(localSlope)
                > math.abs(steepestSegment) then

                steepestSegment = localSlope
                steepestSegmentIndex = sampleIndex - 1
            end

            -- Cut/Fill-Querschnitt entlang der Messlinie
            local segmentCut, segmentFill =
                calculateSegmentAreas(
                    previous.deviation,
                    deviation,
                    step
                )

            cutArea = cutArea + segmentCut
            fillArea = fillArea + segmentFill
        end
    end

    return {
        samples = samples,
        distance = distance,
        step = step,
        segments = segments,

        minHeight = minHeight,
        maxHeight = maxHeight,

        maxAbove = maxAbove,
        maxBelow = maxBelow,

        maxCutDepth = maxAbove,
        maxFillDepth = -maxBelow,

        maxCutIndex = maxCutIndex,
        maxFillIndex = maxFillIndex,

        maxAbsDeviation = math.max(maxAbove, -maxBelow),

        steepestSegment = steepestSegment,
        steepestSegmentIndex = steepestSegmentIndex,

        -- Querschnittsflaechen, keine Volumenwerte
        cutArea = cutArea,
        fillArea = fillArea,
        netArea = fillArea - cutArea
    }, nil
end
