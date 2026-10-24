
-- Terraform Plus - Terrain Visualizer
-- Version: 0.0.7.0

TerrainVisualizer = TerrainVisualizer or {}

TerrainVisualizer.GROUND_OFFSET = 0.15
TerrainVisualizer.MARKER_HEIGHT = 1.5
TerrainVisualizer.MARKER_WIDTH = 0.35

TerrainVisualizer.MAX_PREVIEW_GUIDES = 64
TerrainVisualizer.MAX_AREA_GUIDES = 120
TerrainVisualizer.MIN_PREVIEW_DIFFERENCE = 0.02

TerrainVisualizer.COLOR_A = {0.1, 1.0, 0.3}
TerrainVisualizer.COLOR_B = {1.0, 0.6, 0.1}

TerrainVisualizer.COLOR_PROFILE = {0.1, 0.9, 1.0}
TerrainVisualizer.COLOR_REFERENCE = {1.0, 0.25, 0.85}

TerrainVisualizer.COLOR_CUT = {1.0, 0.2, 0.2}
TerrainVisualizer.COLOR_FILL = {0.1, 1.0, 0.35}
TerrainVisualizer.COLOR_AREA = {1.0, 0.8, 0.2}


-- Debug-Linie in Weltkoordinaten
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


-- Kreuz auf den X- und Z-Achsen
function TerrainVisualizer.drawCross(
    x, y, z, color, size
)

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


-- Messpunkt A/B darstellen
function TerrainVisualizer.drawMarker(point, label, color)

    if point == nil then
        return
    end

    local x = point.x
    local y = point.terrainY + TerrainVisualizer.GROUND_OFFSET
    local z = point.z

    local topY = y + TerrainVisualizer.MARKER_HEIGHT

    TerrainVisualizer.drawLine(
        x, y, z,
        x, topY, z,
        color[1], color[2], color[3]
    )

    TerrainVisualizer.drawCross(
        x,
        topY,
        z,
        color,
        TerrainVisualizer.MARKER_WIDTH
    )

    if Utils ~= nil
        and type(Utils.renderTextAtWorldPosition) == "function" then

        Utils.renderTextAtWorldPosition(
            x,
            topY + 0.35,
            z,
            label,
            0.018,
            0,
            color[1], color[2], color[3], 1
        )
    end
end


-- Ideale Steigung zwischen A und B
function TerrainVisualizer.drawConnection(pointA, pointB)

    if pointA == nil or pointB == nil then
        return
    end

    local offset = TerrainVisualizer.GROUND_OFFSET + 0.15
    local color = TerrainVisualizer.COLOR_REFERENCE

    TerrainVisualizer.drawLine(
        pointA.x, pointA.terrainY + offset, pointA.z,
        pointB.x, pointB.terrainY + offset, pointB.z,
        color[1], color[2], color[3]
    )
end


-- Gelaendeprofil entlang A-B
function TerrainVisualizer.drawProfile(profile)

    if profile == nil or profile.samples == nil then
        return
    end

    local samples = profile.samples
    local offset = TerrainVisualizer.GROUND_OFFSET + 0.15
    local color = TerrainVisualizer.COLOR_PROFILE

    for i = 1, #samples - 1 do

        local a = samples[i]
        local b = samples[i + 1]

        TerrainVisualizer.drawLine(
            a.x, a.terrainY + offset, a.z,
            b.x, b.terrainY + offset, b.z,
            color[1], color[2], color[3]
        )
    end
end


-- Eine einzelne Differenz zwischen Ist und Soll
function TerrainVisualizer.drawChangeGuide(sample, size)

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
        color = TerrainVisualizer.COLOR_FILL
    else
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

    TerrainVisualizer.drawCross(
        sample.x,
        actualY,
        sample.z,
        color,
        size or 0.16
    )
end


-- 1D Cut/Fill-Vorschau
function TerrainVisualizer.drawPreview(profile)

    if profile == nil or profile.samples == nil then
        return
    end

    local samples = profile.samples

    local interiorCount = #samples - 2

    if interiorCount <= 0 then
        return
    end

    local stride = math.max(
        1,
        math.ceil(
            interiorCount
            / TerrainVisualizer.MAX_PREVIEW_GUIDES
        )
    )

    for i = 2, #samples - 1, stride do
        TerrainVisualizer.drawChangeGuide(samples[i], 0.16)
    end

    if profile.maxCutIndex ~= nil then

        TerrainVisualizer.drawChangeGuide(
            samples[profile.maxCutIndex],
            0.6
        )
    end

    if profile.maxFillIndex ~= nil then

        TerrainVisualizer.drawChangeGuide(
            samples[profile.maxFillIndex],
            0.6
        )
    end
end


-- Begrenzung der 2D-Soll-Ebene
function TerrainVisualizer.drawAreaBoundary(area)

    if area == nil or area.corners == nil then
        return
    end

    local corners = area.corners
    local color = TerrainVisualizer.COLOR_AREA

    local offset = TerrainVisualizer.GROUND_OFFSET + 0.15

    for i = 1, 4 do

        local nextIndex = i % 4 + 1

        local a = corners[i]
        local b = corners[nextIndex]

        TerrainVisualizer.drawLine(
            a.x, a.y + offset, a.z,
            b.x, b.y + offset, b.z,
            color[1], color[2], color[3]
        )
    end
end


-- 2D-Rastervorschau
function TerrainVisualizer.drawAreaPreview(area)

    if area == nil or area.samples == nil then
        return
    end

    -- Umriss der Soll-Ebene
    TerrainVisualizer.drawAreaBoundary(area)

    local samples = area.samples
    local total = #samples

    if total == 0 then
        return
    end

    local stride = math.max(
        1,
        math.ceil(
            total / TerrainVisualizer.MAX_AREA_GUIDES
        )
    )

    -- Stichprobe fuer die Darstellung.
    -- Alle Zellen sind trotzdem bereits berechnet.
    for i = 1, total, stride do

        TerrainVisualizer.drawChangeGuide(
            samples[i],
            0.12
        )
    end

    -- Groesste Abweichungen immer markieren
    TerrainVisualizer.drawChangeGuide(
        area.maxCutSample,
        0.65
    )

    TerrainVisualizer.drawChangeGuide(
        area.maxFillSample,
        0.65
    )
end


-- Text mit Schatten
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


-- HUD fuer Profil- und Volumenanalyse
function TerrainVisualizer.drawHUD(
    pointA,
    pointB,
    measurement,
    profile,
    previewEnabled,
    area,
    areaEnabled
)

    if pointA == nil then
        return
    end

    local lines = {
        "TERRAFORM PLUS - AREA ANALYSIS",

        string.format(
            "A: %.3f m",
            pointA.terrainY
        )
    }

    if pointB ~= nil then

        table.insert(
            lines,
            string.format(
                "B: %.3f m",
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
                "1D-Profil: %d Samples | %.2f m Schritt",
                #profile.samples,
                profile.step
            )
        )

        table.insert(
            lines,
            string.format(
                "1D Cut: %.2f m2 | Fill: %.2f m2",
                profile.cutArea,
                profile.fillArea
            )
        )
    end

    if area ~= nil then

        table.insert(
            lines,
            string.format(
                "2D-Raster: %d x %d = %d Zellen",
                area.lengthCells,
                area.widthCells,
                #area.samples
            )
        )

        table.insert(
            lines,
            string.format(
                "Breite: %.2f m | Flaeche: %.2f m2",
                area.width,
                area.area
            )
        )

        table.insert(
            lines,
            string.format(
                "Zellgroesse: %.2f x %.2f m",
                area.cellLength,
                area.cellWidth
            )
        )

        table.insert(
            lines,
            string.format(
                "2D ROT Abtrag: %.2f m3",
                area.cutVolume
            )
        )

        table.insert(
            lines,
            string.format(
                "2D GRUEN Auftrag: %.2f m3",
                area.fillVolume
            )
        )

        table.insert(
            lines,
            string.format(
                "Netto-Volumen: %+.2f m3",
                area.netVolume
            )
        )

        table.insert(
            lines,
            areaEnabled
                and "2D-Vorschau: EIN (tpAreaVisual)"
                or "2D-Vorschau: AUS (tpAreaVisual)"
        )
    end

    if profile ~= nil then

        table.insert(
            lines,
            previewEnabled
                and "1D-Vorschau: EIN (tpPreview)"
                or "1D-Vorschau: AUS (tpPreview)"
        )
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextBold(false)

    for i, line in ipairs(lines) do

        local y = 0.945 - (i - 1) * 0.026
        local color = {1, 1, 1}

        if i == 1 then
            color = {0.2, 0.95, 0.75}
            setTextBold(true)

        elseif line:find("2D ROT", 1, true) then
            color = TerrainVisualizer.COLOR_CUT
            setTextBold(false)

        elseif line:find("2D GRUEN", 1, true) then
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

    setTextBold(false)
    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end


-- Gesamte Visualisierung
function TerrainVisualizer.draw(
    pointA,
    pointB,
    measurement,
    profile,
    previewEnabled,
    area,
    areaEnabled
)

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

        TerrainVisualizer.drawConnection(
            pointA,
            pointB
        )

        if profile ~= nil then

            TerrainVisualizer.drawProfile(profile)

            if previewEnabled then
                TerrainVisualizer.drawPreview(profile)
            end
        end

        if areaEnabled and area ~= nil then

            TerrainVisualizer.drawAreaPreview(area)
        end
    end

    TerrainVisualizer.drawHUD(
        pointA,
        pointB,
        measurement,
        profile,
        previewEnabled,
        area,
        areaEnabled
    )
end
