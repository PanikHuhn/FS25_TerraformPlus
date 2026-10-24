
-- Terraform Plus - Terrain Selection
-- Version 0.0.8.0
-- Interactive selection without input interception

TerrainSelection = TerrainSelection or {}

TerrainSelection.CURSOR_INTERVAL_MS = 100
TerrainSelection.PREVIEW_INTERVAL_MS = 1500
TerrainSelection.PREVIEW_MIN_MOVEMENT = 0.75
TerrainSelection.PREVIEW_GRID_STEP = 4.0

TerrainSelection.COLOR_CURSOR = {1.0, 0.95, 0.15}
TerrainSelection.COLOR_GUIDE = {1.0, 0.95, 0.55}


local function horizontalDistance(a, b)

    local dx = b.x - a.x
    local dz = b.z - a.z

    return math.sqrt(dx * dx + dz * dz)
end


-- Startet eine neue Auswahl und sichert den alten Zustand.
function TerrainSelection.begin(owner)

    if owner.selection ~= nil and owner.selection.active then

        return nil,
            "Auswahl bereits aktiv. tpAnchor / tpConfirm / tpCancel"
    end

    local sample, err = owner:getCurrentSample()

    if sample == nil then
        return nil, err
    end

    owner.selection = {
        active = true,
        stage = "A",
        cursor = owner:createPoint(sample),

        cursorElapsed = 0,
        analysisElapsed = 0,

        preview = nil,
        error = nil,

        backup = {
            pointA = owner.pointA,
            pointB = owner.pointB,
            measurement = owner.measurement,
            profile = owner.profile,
            area = owner.area
        }
    }

    owner.pointA = nil
    owner.pointB = nil

    owner.measurement = nil
    owner.profile = nil
    owner.area = nil

    return true, nil
end


-- Fixiert den Startpunkt.
function TerrainSelection.anchor(owner)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return nil, "Kein Auswahlmodus aktiv. tpSelect verwenden"
    end

    local sample, err = owner:getCurrentSample()

    if sample == nil then
        return nil, err
    end

    owner.pointA = owner:createPoint(sample)
    owner.pointB = nil

    owner.measurement = nil
    owner.profile = nil
    owner.area = nil

    selection.stage = "B"
    selection.cursor = owner:createPoint(sample)

    selection.preview = nil
    selection.error = nil
    selection.analysisElapsed =
        TerrainSelection.PREVIEW_INTERVAL_MS

    return owner.pointA, nil
end


-- Bestaetigt die Auswahl mit voller Rastergenauigkeit.
function TerrainSelection.confirm(owner)

    local selection = owner.selection

    if selection == nil
        or not selection.active
        or selection.stage ~= "B" then

        return nil, "Zuerst tpSelect und tpAnchor verwenden"
    end

    local sample, err = owner:getCurrentSample()

    if sample == nil then
        return nil, err
    end

    local pointB = owner:createPoint(sample)

    if horizontalDistance(owner.pointA, pointB) < 0.01 then
        return nil, "A und B liegen zu nah beieinander"
    end

    local result, analysisError = owner:applyAnalysis(
        owner.pointA,
        pointB
    )

    if result == nil then
        return nil, analysisError
    end

    owner.selection = nil

    return result, nil
end


-- Bricht die Auswahl ohne Datenverlust ab.
function TerrainSelection.cancel(owner)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return false
    end

    local backup = selection.backup

    owner.pointA = backup.pointA
    owner.pointB = backup.pointB

    owner.measurement = backup.measurement
    owner.profile = backup.profile
    owner.area = backup.area

    owner.selection = nil

    return true
end


-- Verwirft die Vorschau nach Einstellungsveraenderungen.
function TerrainSelection.invalidate(owner)

    local selection = owner.selection

    if selection ~= nil and selection.active then

        selection.preview = nil
        selection.error = nil

        selection.analysisElapsed =
            TerrainSelection.PREVIEW_INTERVAL_MS
    end
end


-- Aktualisiert den Cursor und das Live-Gelaendeprofil.
-- dt wird von GIANTS in Millisekunden uebergeben.
function TerrainSelection.update(owner, dt)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return
    end

    dt = type(dt) == "number"
        and math.max(0, math.min(dt, 250))
        or 0

    selection.cursorElapsed =
        selection.cursorElapsed + dt

    selection.analysisElapsed =
        selection.analysisElapsed + dt

    -- Spielerposition hoechstens alle 100 ms abfragen
    if selection.cursorElapsed
        < TerrainSelection.CURSOR_INTERVAL_MS then

        return
    end

    selection.cursorElapsed = 0

    local sample = owner:getCurrentSample()

    if sample == nil then
        return
    end

    selection.cursor = owner:createPoint(sample)

    -- Ohne Startpunkt keine Flaechenanalyse
    if selection.stage ~= "B"
        or owner.pointA == nil then

        return
    end

    if horizontalDistance(
        owner.pointA,
        selection.cursor
    ) < 0.1 then

        selection.preview = nil
        return
    end

    -- Teure Analyse nur in festgelegten Intervallen
    if selection.analysisElapsed
        < TerrainSelection.PREVIEW_INTERVAL_MS then

        return
    end

    -- Nicht erneut berechnen, wenn sich B kaum bewegt hat
    if selection.preview ~= nil
        and horizontalDistance(
            selection.preview.pointB,
            selection.cursor
        ) < TerrainSelection.PREVIEW_MIN_MOVEMENT then

        return
    end

    selection.analysisElapsed = 0

    local candidate = owner:createPoint(selection.cursor)

    -- Fuer die Live-Vorschau groebere Rasteraufloesung
    local coarseStep = math.max(
        owner.areaStep,
        TerrainSelection.PREVIEW_GRID_STEP
    )

    local result, err = owner:buildAnalysis(
        owner.pointA,
        candidate,
        coarseStep
    )

    if result == nil then

        selection.preview = nil
        selection.error = tostring(err)

        return
    end

    selection.preview = {
        pointB = candidate,
        measurement = result.measurement,
        profile = result.profile,
        area = result.area
    }

    selection.error = nil
end


-- Zeichnet den interaktiven Cursor und den Auswahlstatus.
function TerrainSelection.draw(owner)

    local selection = owner.selection

    if selection == nil
        or not selection.active
        or selection.cursor == nil then

        return
    end

    if TerrainVisualizer == nil then
        return
    end

    -- Gelbe Positionsmarkierung
    TerrainVisualizer.drawMarker(
        selection.cursor,
        "CURSOR",
        TerrainSelection.COLOR_CURSOR
    )

    local distance = 0

    -- Hilfslinie von A zur aktuellen Cursorposition
    if selection.stage == "B"
        and owner.pointA ~= nil then

        distance = horizontalDistance(
            owner.pointA,
            selection.cursor
        )

        TerrainVisualizer.drawLine(
            owner.pointA.x,
            owner.pointA.terrainY + 1.9,
            owner.pointA.z,

            selection.cursor.x,
            selection.cursor.terrainY + 1.9,
            selection.cursor.z,

            TerrainSelection.COLOR_GUIDE[1],
            TerrainSelection.COLOR_GUIDE[2],
            TerrainSelection.COLOR_GUIDE[3]
        )
    end

    if type(renderText) ~= "function"
        or type(setTextColor) ~= "function" then

        return
    end

    local lines = {
        "TERRAFORM PLUS - INTERACTIVE SELECTION"
    }

    if selection.stage == "A" then

        lines[#lines + 1] =
            "Schritt 1: Position waehlen, dann tpAnchor"

    else

        lines[#lines + 1] = string.format(
            "Schritt 2: Endpunkt waehlen, dann tpConfirm | Distanz: %.2f m",
            distance
        )

        if selection.preview ~= nil then

            local area = selection.preview.area

            lines[#lines + 1] = string.format(
                "LIVE (grobes Raster): Abtrag %.1f m3 | Auftrag %.1f m3",
                area.cutVolume,
                area.fillVolume
            )

        else

            lines[#lines + 1] =
                "LIVE-Profil wird nach Positionswechsel berechnet"
        end
    end

    lines[#lines + 1] = string.format(
        "Arbeitsbreite: %.1f m | Zielraster: %.1f m | tpCancel zum Abbrechen",
        owner.areaWidth,
        owner.areaStep
    )

    if selection.error ~= nil then
        lines[#lines + 1] =
            "Vorschaufehler: " .. selection.error
    end

    if RenderText ~= nil
        and type(setTextAlignment) == "function" then

        setTextAlignment(RenderText.ALIGN_LEFT)
    end

    if type(setTextBold) == "function" then
        setTextBold(false)
    end

    -- Zusaetzliches HUD unten links
    for i, line in ipairs(lines) do

        local y = 0.23 - (i - 1) * 0.027

        setTextColor(0, 0, 0, 0.95)

        renderText(
            0.021,
            y - 0.001,
            0.018,
            line
        )

        setTextColor(1, 0.95, 0.35, 1)

        renderText(
            0.02,
            y,
            0.018,
            line
        )
    end

    setTextColor(1, 1, 1, 1)
end
