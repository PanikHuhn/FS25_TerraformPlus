-- Terraform Plus - Terrain Visualizer
-- Version: 0.0.5.0

TerrainVisualizer = TerrainVisualizer or {}

-- Darstellungsparameter
TerrainVisualizer.GROUND_OFFSET = 0.15
TerrainVisualizer.MARKER_HEIGHT = 1.5
TerrainVisualizer.MARKER_WIDTH = 0.35

-- Farben
TerrainVisualizer.COLOR_A = {0.1, 1.0, 0.3}
TerrainVisualizer.COLOR_B = {1.0, 0.6, 0.1}

TerrainVisualizer.COLOR_PROFILE = {0.1, 0.9, 1.0}
TerrainVisualizer.COLOR_REFERENCE = {1.0, 0.25, 0.85}


-- Zeichnet eine Linie zwischen zwei Weltpositionen.
function TerrainVisualizer.drawLine(
    x1, y1, z1,
    x2, y2, z2,
    r, g, b
)

    drawDebugLine(
        x1, y1, z1,
        r, g, b,

        x2, y2, z2,
        r, g, b,

        false
    )
end


-- Zeichnet einen farbigen Messpunkt.
function TerrainVisualizer.drawMarker(point, label, color)

    if point == nil then
        return
    end

    local x = point.x
    local y = point.terrainY
        + TerrainVisualizer.GROUND_OFFSET
    local z = point.z

    local topY = y + TerrainVisualizer.MARKER_HEIGHT
    local halfWidth = TerrainVisualizer.MARKER_WIDTH

    local r = color[1]
    local g = color[2]
    local b = color[3]

    -- Vertikale Linie
    TerrainVisualizer.drawLine(
        x, y, z,
        x, topY, z,
        r, g, b
    )

    -- Kreuz entlang X
    TerrainVisualizer.drawLine(
        x - halfWidth, topY, z,
        x + halfWidth, topY, z,
        r, g, b
    )

    -- Kreuz entlang Z
    TerrainVisualizer.drawLine(
        x, topY, z - halfWidth,
        x, topY, z + halfWidth,
        r, g, b
    )

    -- Beschriftung, falls API vorhanden
    if Utils ~= nil
        and type(Utils.renderTextAtWorldPosition)
            == "function" then

        Utils.renderTextAtWorldPosition(
            x,
            topY + 0.35,
            z,
            label,
            0.018,
            0,
            r, g, b, 1
        )
    end
end


-- Zeichnet die ideale Steigung zwischen A und B.
function TerrainVisualizer.drawConnection(pointA, pointB)

    if pointA == nil or pointB == nil then
        return
    end

    local offset =
        TerrainVisualizer.GROUND_OFFSET + 0.15

    local color = TerrainVisualizer.COLOR_REFERENCE

    TerrainVisualizer.drawLine(
        pointA.x,
        pointA.terrainY + offset,
        pointA.z,

        pointB.x,
        pointB.terrainY + offset,
        pointB.z,

        color[1],
        color[2],
        color[3]
    )
end


-- Zeichnet den tatsaechlichen Gelaendeverlauf.
function TerrainVisualizer.drawProfile(profile)

    if profile == nil or profile.samples == nil then
        return
    end

    local samples = profile.samples

    if #samples < 2 then
        return
    end

    local offset =
        TerrainVisualizer.GROUND_OFFSET + 0.15

    local color = TerrainVisualizer.COLOR_PROFILE

    -- Aufeinanderfolgende Samples verbinden
    for i = 1, #samples - 1 do

        local current = samples[i]
        local nextSample = samples[i + 1]

        TerrainVisualizer.drawLine(
            current.x,
            current.terrainY + offset,
            current.z,

            nextSample.x,
            nextSample.terrainY + offset,
            nextSample.z,

            color[1],
            color[2],
            color[3]
        )
    end
end


-- Text mit Schatten darstellen.
function TerrainVisualizer.drawTextLine(
    x,
    y,
    value,
    size,
    color
)

    -- Textschatten
    setTextColor(0, 0, 0, 0.9)

    renderText(
        x + 0.001,
        y - 0.001,
        size,
        value
    )

    -- Eigentliche Textfarbe
    setTextColor(
        color[1],
        color[2],
        color[3],
        1
    )

    renderText(x, y, size, value)
end


-- Zeichnet das HUD mit den Messergebnissen.
function TerrainVisualizer.drawHUD(
    pointA,
    pointB,
    measurement,
    profile
)

    if pointA == nil then
        return
    end

    local lines = {
        "TERRAFORM PLUS - TERRAIN MEASUREMENT",

        string.format(
            "A (Gruen): %.3f m",
            pointA.terrainY
        )
    }

    -- Punkt B
    if pointB ~= nil then

        table.insert(
            lines,
            string.format(
                "B (Orange): %.3f m",
                pointB.terrainY
            )
        )

    else

        table.insert(
            lines,
            "B: Noch nicht gesetzt"
        )
    end

    -- Steigungsberechnung
    if measurement ~= nil then

        table.insert(
            lines,
            string.format(
                "Distanz: %.2f m | DeltaH: %+.3f m",
                measurement.distance,
                measurement.heightDifference
            )
        )

        table.insert(
            lines,
            string.format(
                "Steigung: %+.2f%% | Winkel: %+.2f Grad",
                measurement.slopePercent,
                measurement.slopeAngle
            )
        )
    end

    -- Neue Profilinformationen
    if profile ~= nil then

        table.insert(
            lines,
            string.format(
                "Profil: %d Samples | Schritt: %.2f m",
                #profile.samples,
                profile.step
            )
        )

        table.insert(
            lines,
            string.format(
                "Abweichung: +%.2f m / %.2f m",
                profile.maxAbove,
                profile.maxBelow
            )
        )

        table.insert(
            lines,
            string.format(
                "Steilster Abschnitt: %+.2f%%",
                profile.steepestSegment
            )
        )

        table.insert(
            lines,
            string.format(
                "Min/Max: %.2f / %.2f m",
                profile.minHeight,
                profile.maxHeight
            )
        )
    end

    -- HUD ausgeben
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)

    for i, line in ipairs(lines) do

        local y = 0.945 - (i - 1) * 0.028

        local color = {1, 1, 1}

        if i == 1 then

            color = {0.2, 0.95, 0.75}
            setTextBold(true)

        else

            setTextBold(false)
        end

        TerrainVisualizer.drawTextLine(
            0.025,
            y,
            line,
            0.018,
            color
        )
    end

    -- Renderzustand zuruecksetzen
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end


-- Einstiegspunkt fuer die gesamte Visualisierung.
function TerrainVisualizer.draw(
    pointA,
    pointB,
    measurement,
    profile
)

    if pointA == nil then
        return
    end

    -- Punkt A
    TerrainVisualizer.drawMarker(
        pointA,
        "A",
        TerrainVisualizer.COLOR_A
    )

    if pointB ~= nil then

        -- Punkt B
        TerrainVisualizer.drawMarker(
            pointB,
            "B",
            TerrainVisualizer.COLOR_B
        )

        -- Ideale Steigung (Magenta)
        TerrainVisualizer.drawConnection(
            pointA,
            pointB
        )

        -- Echtes Gelaendeprofil (Tuerkis)
        if profile ~= nil then

            TerrainVisualizer.drawProfile(
                profile
            )
        end
    end

    -- Messwerte einblenden
    TerrainVisualizer.drawHUD(
        pointA,
        pointB,
        measurement,
        profile
    )
end
