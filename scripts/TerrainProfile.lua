-- Terraform Plus - Terrain Profile
-- Version: 0.0.5.0
-- Berechnet das Hoehenprofil zwischen zwei Punkten.

TerrainProfile = TerrainProfile or {}

-- Gewuenschter Abstand zwischen Messpunkten in Metern
TerrainProfile.TARGET_STEP = 2.0

-- Maximale Anzahl an Teilabschnitten
TerrainProfile.MAX_SEGMENTS = 128


-- Erstellt ein Gelaendeprofil von A nach B.
function TerrainProfile.build(pointA, pointB)

    if pointA == nil or pointB == nil then
        return nil, "Beide Messpunkte werden benoetigt"
    end

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt) ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    -- Horizontale Entfernung berechnen
    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    local distance = math.sqrt(
        dx * dx + dz * dz
    )

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    -- Anzahl der Teilabschnitte bestimmen
    local segments = math.min(
        TerrainProfile.MAX_SEGMENTS,
        math.max(
            1,
            math.ceil(distance / TerrainProfile.TARGET_STEP)
        )
    )

    local step = distance / segments

    local heightDelta =
        pointB.terrainY - pointA.terrainY

    -- Messwerte speichern
    local samples = {}

    -- Auswertungsvariablen
    local minHeight = math.huge
    local maxHeight = -math.huge

    local maxAbove = 0
    local maxBelow = 0

    local steepestSegment = 0

    -- Alle Messpunkte abarbeiten
    for i = 0, segments do

        local t = i / segments

        -- Position zwischen A und B interpolieren
        local x = pointA.x + dx * t
        local z = pointA.z + dz * t

        local height = nil

        -- Startpunkt
        if i == 0 then

            height = pointA.terrainY

        -- Endpunkt
        elseif i == segments then

            height = pointB.terrainY

        -- Zwischenpunkte
        else

            local success, result, err = pcall(
                TerrainAdapter.getHeightAt,
                x,
                z
            )

            if not success then
                return nil,
                    "Terrainabfrage fehlgeschlagen: "
                    .. tostring(result)
            end

            if type(result) ~= "number" then
                return nil,
                    "Ungueltige Terrainhoehe: "
                    .. tostring(err)
            end

            height = result
        end

        -- Ideale Hoehe bei gleichmaessiger Steigung
        local referenceHeight =
            pointA.terrainY + heightDelta * t

        -- Abweichung vom idealen Gelaende
        local deviation =
            height - referenceHeight

        -- Minimale und maximale Hoehe aktualisieren
        minHeight = math.min(minHeight, height)
        maxHeight = math.max(maxHeight, height)

        -- Hoechste positive/negative Abweichung
        maxAbove = math.max(maxAbove, deviation)
        maxBelow = math.min(maxBelow, deviation)

        -- Steigung des aktuellen Teilabschnitts
        if i > 0 then

            -- Lua-Arrays beginnen bei Index 1.
            local previous = samples[i]

            local localSlope =
                (height - previous.terrainY)
                / step * 100

            if math.abs(localSlope)
                > math.abs(steepestSegment) then

                steepestSegment = localSlope
            end
        end

        -- Messpunkt abspeichern
        samples[#samples + 1] = {
            x = x,
            z = z,
            terrainY = height,
            referenceY = referenceHeight,
            deviation = deviation
        }
    end

    -- Vollstaendiges Profil zurueckgeben
    return {
        samples = samples,
        distance = distance,
        step = step,
        minHeight = minHeight,
        maxHeight = maxHeight,
        maxAbove = maxAbove,
        maxBelow = maxBelow,
        maxAbsDeviation = math.max(
            maxAbove,
            -maxBelow
        ),
        steepestSegment = steepestSegment
    }, nil
end
