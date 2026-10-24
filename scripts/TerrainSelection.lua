
-- Terraform Plus - Terrain Selection
-- Version: 0.0.9.0
-- Interactive selection with camera or player cursor

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


-- Auswahlmodus beginnen.
function TerrainSelection.begin(owner)

    if owner.selection ~= nil
        and owner.selection.active then

        return nil, "Auswahl bereits aktiv"
    end

    local sample, err = owner:getSelectionSample()

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

    -- Vorherige Messung ist gesichert.
    owner.pointA = nil
    owner.pointB = nil
    owner.measurement = nil
    owner.profile = nil
    owner.area = nil

    return true, nil
end


-- Aktuelles Ziel als Startpunkt fixieren.
function TerrainSelection.anchor(owner)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return nil, "Kein Auswahlmodus aktiv"
    end

    local sample, err = owner:getSelectionSample()

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


-- Aktuelles Ziel als Endpunkt bestaetigen.
function TerrainSelection.confirm(owner)

    local selection = owner.selection

    if selection == nil
        or not selection.active
        or selection.stage ~= "B" then

        return nil, "Zuerst tpSelect und tpAnchor verwenden"
    end

    local sample, err = owner:getSelectionSample()

    if sample == nil then
        return nil, err
    end

    local pointB = owner:createPoint(sample)

    if horizontalDistance(
        owner.pointA,
        pointB
    ) < 0.01 then

        return nil, "A und B liegen zu nah beieinander"
    end

    -- Finale Analyse mit voller eingestellter Aufloesung.
    local result, analysisErr = owner:applyAnalysis(
        owner.pointA,
        pointB
    )

    if result == nil then
        return nil, analysisErr
    end

    owner.selection = nil

    return result, nil
end


-- Auswahl abbrechen und alte Messung wiederherstellen.
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


-- Live-Vorschau nach Einstellungswechsel verwerfen.
function TerrainSelection.invalidate(owner)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return
    end

    selection.preview = nil
    selection.error = nil

    selection.analysisElapsed =
        TerrainSelection.PREVIEW_INTERVAL_MS
end


-- Cursorposition und Live-Analyse aktualisieren.
function TerrainSelection.update(owner, dt)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return
    end

    if type(dt) ~= "number" then
        dt = 0
    end

    dt = math.max(0, math.min(dt, 250))

    selection.cursorElapsed =
        selection.cursorElapsed + dt

    selection.analysisElapsed =
        selection.analysisElapsed + dt

    if selection.cursorElapsed
        < TerrainSelection.CURSOR_INTERVAL_MS then

        return
    end

    selection.cursorElapsed = 0

    -- Neu: wahlweise Kamera- oder Spielerposition.
    local sample, err = owner:getSelectionSample()

    if sample == nil then

        -- Niemals mit einem veralteten Ziel bestaetigen.
        selection.cursor = nil
        selection.preview = nil
        selection.error = err

        return
    end

    selection.cursor = owner:createPoint(sample)
    selection.error = nil

    -- Vor dem Fixieren von A nur Cursor anzeigen.
    if selection.stage ~= "B"
        or owner.pointA == nil then

        return
    end

    local distance = horizontalDistance(
        owner.pointA,
        selection.cursor
    )

    if distance < 0.1 then

        selection.preview = nil
        return
    end

    -- Aufwendige Analyse zeitlich begrenzen.
    if selection.analysisElapsed
        < TerrainSelection.PREVIEW_INTERVAL_MS then

        return
    end

    -- Nur neu berechnen, wenn sich das Ziel
    -- ausreichend verschoben hat.
    if selection.preview ~= nil
        and horizontalDistance(
            selection.preview.pointB,
            selection.cursor
        ) < TerrainSelection.PREVIEW_MIN_MOVEMENT then

        return
    end

    selection.analysisElapsed = 0

    local candidate = owner:createPoint(
        selection.cursor
    )

    local coarseStep = math.max(
        owner.areaStep,
        TerrainSelection.PREVIEW_GRID_STEP
    )

    local result, analysisErr = owner:buildAnalysis(
        owner.pointA,
        candidate,
        coarseStep
    )

    if result == nil then

        selection.preview = nil
        selection.error = tostring(analysisErr)

        return
    end

    selection.preview = {
        pointB = candidate,
        measurement = result.measurement,
        profile = result.profile,
        area = result.area
    }
end


-- Zusatz-HUD und Cursor zeichnen.
function TerrainSelection.draw(owner)

    local selection = owner.selection

    if selection == nil or not selection.active then
        return
    end

    if TerrainVisualizer == nil then
        return
    end

    local cursor = selection.cursor

    if cursor ~= nil then

        TerrainVisualizer.drawMarker(
            cursor,
            "CURSOR",
            TerrainSelection.COLOR_CURSOR
        )

        if selection.stage == "B"
            and owner.pointA ~= nil then

            TerrainVisualizer.drawLine(
                owner.pointA.x,
                owner.pointA.terrainY + 1.9,
                owner.pointA.z,

                cursor.x,
                cursor.terrainY + 1.9,
                cursor.z,

                TerrainSelection.COLOR_GUIDE[1],
                TerrainSelection.COLOR_GUIDE[2],
                TerrainSelection.COLOR_GUIDE[3]
            )
        end
    end

    if type(renderText) ~= "function"
        or type(setTextColor) ~= "function" then

        return
    end

    local lines = {
        "TERRAFORM PLUS - CURSOR SELECTION"
    }

    if selection.stage == "A" then

        lines[#lines + 1] =
            "Schritt 1: Boden anvisieren und tpAnchor"

    else

        lines[#lines + 1] =
            "Schritt 2: Ziel anvisieren und tpConfirm"

        if owner.pointA ~= nil and cursor ~= nil then

            lines[#lines + 1] = string.format(
                "Aktuelle Distanz: %.2f m",
                horizontalDistance(owner.pointA, cursor)
            )
        end

        if selection.preview ~= nil then

            local area = selection.preview.area

            lines[#lines + 1] = string.format(
                "LIVE: Abtrag %.1f m3 | Auftrag %.1f m3",
                area.cutVolume,
                area.fillVolume
            )
        end
    end

    lines[#lines + 1] = string.format(
        "Cursor: %s | Breite: %.1f m | Raster: %.1f m",
        owner.cursorMode,
        owner.areaWidth,
        owner.areaStep
    )

    if selection.error ~= nil then

        lines[#lines + 1] =
            "Hinweis: " .. tostring(selection.error)
    end

    lines[#lines + 1] =
        "Strg+Alt+G: Setzen | Strg+Alt+X: Abbrechen"

    if RenderText ~= nil
        and type(setTextAlignment) == "function" then

        setTextAlignment(RenderText.ALIGN_LEFT)
    end

    if type(setTextBold) == "function" then
        setTextBold(false)
    end

    -- Informationen unten links darstellen.
    for i, line in ipairs(lines) do

        local y = 0.25 - (i - 1) * 0.027

        setTextColor(0, 0, 0, 0.9)

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

    -- Fadenkreuz in der Bildschirmmitte
    -- nur fuer den Kameramodus.
    if owner.cursorMode == "camera"
        and RenderText ~= nil
        and type(setTextAlignment) == "function" then

        setTextAlignment(RenderText.ALIGN_CENTER)

        if cursor ~= nil then
            setTextColor(1, 0.95, 0.2, 1)
        else
            setTextColor(1, 0.2, 0.2, 1)
        end

        renderText(0.5, 0.5, 0.028, "+")

        setTextAlignment(RenderText.ALIGN_LEFT)
    end

    setTextColor(1, 1, 1, 1)
end
