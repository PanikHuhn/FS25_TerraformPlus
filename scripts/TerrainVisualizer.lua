
-- Terraform Plus - Terrain Visualizer
-- Version: 0.0.6.0
-- World markers, terrain profile and cut/fill preview

TerrainVisualizer = TerrainVisualizer or {}

TerrainVisualizer.GROUND_OFFSET = 0.15
TerrainVisualizer.MARKER_HEIGHT = 1.5
TerrainVisualizer.MARKER_WIDTH = 0.35

-- Maximal angezeigte Cut/Fill-Hilfslinien
-- Die Profilberechnung selbst bleibt unveraendert genau.
TerrainVisualizer.MAX_PREVIEW_GUIDES = 64
TerrainVisualizer.MIN_PREVIEW_DIFFERENCE = 0.02

TerrainVisualizer.COLOR_A = {0.1, 1.0, 0.3}
TerrainVisualizer.COLOR_B = {1.0, 0.6, 0.1}

TerrainVisualizer.COLOR_PROFILE = {0.1, 0.9, 1.0}
TerrainVisualizer.COLOR_REFERENCE = {1.0, 0.25, 0.85}

TerrainVisualizer.COLOR_CUT = {1.0, 0.2, 0.2}
TerrainVisualizer.COLOR_FILL = {0.1, 1.0, 0.35}


-- Debug-Linie in Weltkoordinaten zeichnen.
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


-- Markierung fuer Punkt A oder B.
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

    -- X-Kreuz
    TerrainVisualizer.drawLine(
        x - halfWidth, topY, z,
        x + halfWidth, topY, z,
        r, g, b
    )

    -- Z-Kreuz
    TerrainVisualizer.drawLine(
        x, topY, z - halfWidth,
        x, topY, z + halfWidth,
        r, g, b
    )

    -- Beschriftung oberhalb des Messpunkts
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


-- Magentafarbene Soll-Linie.
function TerrainVisualizer.drawConnection(pointA, pointB)

    if pointA == nil or pointB == nil then
        return
    end

    local offset = TerrainVisualizer.GROUND_OFFSET + 0.15
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


-- Tuerkise Linie entlang der Ist-Hoehen.
function TerrainVisualizer.drawProfile(profile)

    if profile == nil or profile.samples == nil then
        return
    end

    local samples = profile.samples

    if #samples < 2 then
        return
    end

    local offset = TerrainVisualizer.GROUND_OFFSET + 0.15
    local color = TerrainVisualizer.COLOR_PROFILE

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


-- Zeichnet ein kleines Kreuz an einer Weltposition.
function TerrainVisualizer.drawCross(x, y, z, color, size)

    local r, g, b = color[1], color[2], color[3]

    TerrainVisualizer.drawLine(
        x - size, y, z,
        x + size, y, z,
        r, g, b
    )

    TerrainVisualizer.drawLine(
        x, y, z - size,
        x, y, z + size,
        r, g, b
    )
end


-- Einzelne Cut/Fill-Hilfslinie zeichnen.
function TerrainVisualizer.drawChangeGuide(sample)

    if sample == nil then
        return
    end

    local difference = sample.requiredChange

    if math.abs(difference)
        < TerrainVisualizer.MIN_PREVIEW_DIFFERENCE then
        return
    end

    local color

    if difference > 0 then
        -- Sollhoehe hoeher als Terrain: auffuellen
        color = TerrainVisualizer.COLOR_FILL
    else
        -- Sollhoehe niedriger als Terrain: abtragen
        color = TerrainVisualizer.COLOR_CUT
    end

    local offset = TerrainVisualizer.GROUND_OFFSET + 0.15

    local actualY = sample.terrainY + offset
    local targetY = sample.referenceY + offset

    TerrainVisualizer.drawLine(
        sample.x, actualY, sample.z,
        sample.x, targetY, sample.z,
        color[1], color[2], color[3]
    )

    -- Markierung an der angestrebten Hoehe
    TerrainVisualizer.drawCross(
        sample.x,
        targetY,
        sample.z,
        color,
        0.16
    )
end


-- Rote und gruene Hoehendifferenzen darstellen.
function TerrainVisualizer.drawPreview(profile)

    if profile == nil or profile.samples == nil then
        return
    end

    local samples = profile.samples

    if #samples < 3 then
        return
    end

    -- Darstellung auf maximal 64 regulaere Hilfslinien begrenzen.
    -- Die numerischen Messdaten werden nicht reduziert.
    local interiorCount = #samples - 2

    local stride = math.max(
        1,
        math.ceil(
            interiorCount
            / TerrainVisualizer.MAX_PREVIEW_GUIDES
        )
    )

    for i = 2, #samples - 1, stride do
        TerrainVisualizer.drawChangeGuide(samples[i])
    end

    -- Die groessten Cut/Fill-Abweichungen immer markieren,
    -- selbst wenn sie bei der Ausduennung uebersprungen wurden.
    if profile.maxCutIndex ~= nil then

        TerrainVisualizer.drawChangeGuide(
            samples[profile.maxCutIndex]
        )

        local s = samples[profile.maxCutIndex]

        TerrainVisualizer.drawCross(
            s.x,
            s.terrainY + TerrainVisualizer.GROUND_OFFSET + 0.15,
            s.z,
            TerrainVisualizer.COLOR_CUT,
            0.6
        )
    end

    if profile.maxFillIndex ~= nil then

        TerrainVisualizer.drawChangeGuide(
            samples[profile.maxFillIndex]
        )

        local s = samples[profile.maxFillIndex]

        TerrainVisualizer.drawCross(
            s.x,
            s.terrainY + TerrainVisualizer.GROUND_OFFSET + 0.15,
            s.z,
            TerrainVisualizer.COLOR_FILL,
            0.6
        )
    end
end


-- Text mit einem Schatten rendern.
function TerrainVisualizer.drawTextLine(
    x, y, value, size, color
)

    setTextColor(0, 0, 0, 0.9)

    renderText(
        x + 0.001,
        y - 0.001,
        size,
        value
    )

    setTextColor(
        color[1],
        color[2],
        color[3],
        1
    )

    renderText(x, y, size, value)
end


-- Messwerte und Vorschauinformationen im HUD anzeigen.
function TerrainVisualizer.drawHUD(
    pointA,
    pointB,
    measurement,
    profile,
    previewEnabled
)

    if pointA == nil then
        return
    end

    local lines = {
        "TERRAFORM PLUS - TERRAIN PREVIEW",

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
                "Steilster Abschnitt: %+.2f%%",
                profile.steepestSegment
            )
        )

        table.insert(
            lines,
            string.format(
                "ROT Abtrag: %.2f m2 | Max: %.2f m",
                profile.cutArea,
                profile.maxCutDepth
            )
        )

        table.insert(
            lines,
            string.format(
                "GRUEN Auftrag: %.2f m2 | Max: %.2f m",
                profile.fillArea,
                profile.maxFillDepth
            )
        )

        table.insert(
            lines,
            string.format(
                "Netto-Querschnitt: %+.2f m2",
                profile.netArea
            )
        )

        if previewEnabled then
            table.insert(lines, "Vorschau: EIN (tpPreview)")
        else
            table.insert(lines, "Vorschau: AUS (tpPreview)")
        end
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)

    for i, line in ipairs(lines) do

        local y = 0.945 - (i - 1) * 0.027
        local color = {1, 1, 1}

        if i == 1 then
            color = {0.2, 0.95, 0.75}
            setTextBold(true)

        elseif line:find("ROT Abtrag", 1, true) then
            color = TerrainVisualizer.COLOR_CUT
            setTextBold(false)

        elseif line:find("GRUEN Auftrag", 1, true) then
            color = TerrainVisualizer.COLOR_FILL
            setTextBold(false)

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
    profile,
    previewEnabled
)

    if pointA == nil then
        return
    end

    -- Startpunkt
    TerrainVisualizer.drawMarker(
        pointA,
        "A",
        TerrainVisualizer.COLOR_A
    )

    if pointB ~= nil then

        -- Endpunkt
        TerrainVisualizer.drawMarker(
            pointB,
            "B",
            TerrainVisualizer.COLOR_B
        )

        -- Soll-Linie
        TerrainVisualizer.drawConnection(
            pointA,
            pointB
        )

        -- Ist-Profil
        if profile ~= nil then

            TerrainVisualizer.drawProfile(profile)

            -- Cut/Fill-Vorschau
            if previewEnabled then
                TerrainVisualizer.drawPreview(profile)
            end
        end
    end

    TerrainVisualizer.drawHUD(
        pointA,
        pointB,
        measurement,
        profile,
        previewEnabled
    )
end
