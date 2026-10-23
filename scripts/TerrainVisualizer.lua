-- Terraform Plus - Terrain Visualizer
-- Version: 0.0.4.0

TerrainVisualizer = TerrainVisualizer or {}

TerrainVisualizer.GROUND_OFFSET = 0.15
TerrainVisualizer.MARKER_HEIGHT = 1.5
TerrainVisualizer.MARKER_WIDTH = 0.35

-- Farben im RGB-Format (Werte von 0 bis 1)
TerrainVisualizer.COLOR_A = {0.1, 1.0, 0.3}
TerrainVisualizer.COLOR_B = {1.0, 0.6, 0.1}


-- Zeichnet eine Linie zwischen zwei Weltpositionen.
function TerrainVisualizer.drawLine(
    x1, y1, z1,
    x2, y2, z2,
    r, g, b
)

    drawDebugLine(
        x1, y1, z1, r, g, b,
        x2, y2, z2, r, g, b,
        false
    )
end


-- Zeichnet eine farbige Markierung an einem Messpunkt.
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

    -- Vertikale Markierung
    TerrainVisualizer.drawLine(
        x, y, z,
        x, topY, z,
        r, g, b
    )

    -- Horizontales Kreuz entlang der X-Achse
    TerrainVisualizer.drawLine(
        x - halfWidth, topY, z,
        x + halfWidth, topY, z,
        r, g, b
    )

    -- Horizontales Kreuz entlang der Z-Achse
    TerrainVisualizer.drawLine(
        x, topY, z - halfWidth,
        x, topY, z + halfWidth,
        r, g, b
    )

    -- Beschriftung oberhalb der Markierung
    if Utils ~= nil
        and type(Utils.renderTextAtWorldPosition) == "function" then

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


-- Zeichnet eine Verbindung zwischen A und B.
function TerrainVisualizer.drawConnection(pointA, pointB)

    if pointA == nil or pointB == nil then
        return
    end

    local offset = TerrainVisualizer.GROUND_OFFSET
        + TerrainVisualizer.MARKER_HEIGHT * 0.5

    -- Verbindung mit Farbverlauf von A nach B
    drawDebugLine(
        pointA.x,
        pointA.terrainY + offset,
        pointA.z,
        0.1, 1.0, 0.3,

        pointB.x,
        pointB.terrainY + offset,
        pointB.z,
        1.0, 0.6, 0.1,

        false
    )
end


-- Gibt eine Textzeile auf dem Bildschirm aus.
function TerrainVisualizer.drawTextLine(x, y, value, size, color)

    -- Dunkler Schatten fuer bessere Lesbarkeit
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


-- Zeichnet die Messergebnisse als HUD.
function TerrainVisualizer.drawHUD(pointA, pointB, measurement)

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

    if pointB ~= nil then
        table.insert(
            lines,
            string.format(
                "B (Orange): %.3f m",
                pointB.terrainY
            )
        )
    else
        table.insert(lines, "B: Noch nicht gesetzt")
    end

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

    -- Textzustand fuer andere Spielkomponenten zuruecksetzen
    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end


-- Gemeinsamer Einstiegspunkt fuer alle Zeichenvorgaenge.
function TerrainVisualizer.draw(pointA, pointB, measurement)

    if pointA == nil then
        return
    end

    TerrainVisualizer.drawMarker(
        pointA,
        "A",
        TerrainVisualizer.COLOR_A
    )

    if pointB ~= nil then

        TerrainVisualizer.drawMarker(
            pointB,
            "B",
            TerrainVisualizer.COLOR_B
        )

        TerrainVisualizer.drawConnection(pointA, pointB)
    end

    TerrainVisualizer.drawHUD(pointA, pointB, measurement)
end
