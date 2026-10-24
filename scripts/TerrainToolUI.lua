
-- Terraform Plus - Terrain Tool UI
-- Version: 0.0.10.0 (close button, camera-only UI)
-- Self-contained, clickable overlay. Does not modify terrain.

TerrainToolUI = TerrainToolUI or {}

TerrainToolUI.X = 0.675
TerrainToolUI.Y = 0.18
TerrainToolUI.W = 0.305
TerrainToolUI.H = 0.61
TerrainToolUI.RIGHT_BUTTON = 3 -- Input.MOUSE_BUTTON_RIGHT in FS25

TerrainToolUI.COLORS = {
    panel   = {0.035, 0.055, 0.075, 0.93},
    header  = {0.045, 0.22, 0.23, 0.96},
    button  = {0.13, 0.19, 0.24, 0.96},
    active  = {0.11, 0.48, 0.37, 0.97},
    warning = {0.55, 0.24, 0.20, 0.95},
    disabled= {0.10, 0.12, 0.15, 0.65},
    text    = {0.94, 0.97, 1.0, 1.0},
    muted   = {0.67, 0.74, 0.79, 1.0},
    cut     = {1.0, 0.40, 0.40, 1.0},
    fill    = {0.35, 1.0, 0.61, 1.0}
}

local function isMenuOpen()
    return g_gui ~= nil
        and type(g_gui.getIsGuiVisible) == "function"
        and g_gui:getIsGuiVisible()
end

function TerrainToolUI.initialize(owner)
    TerrainToolUI.owner = owner
    TerrainToolUI.visible = false -- UI zuerst bewusst oeffnen
    TerrainToolUI.mouseActive = false
    TerrainToolUI.frozenSample = nil
    TerrainToolUI.lockedInput = nil
    TerrainToolUI.inputWasLocked = false
    TerrainToolUI.rightHeld = false
    TerrainToolUI.previousMouseVisible = false
    TerrainToolUI.buttons = {}
    TerrainToolUI.pressedButton = nil
    TerrainToolUI.initialized = true

    if TerrainToolUI.rectangle ~= nil then
        TerrainToolUI.rectangle:delete()
        TerrainToolUI.rectangle = nil
    end

    if g_overlayManager ~= nil
        and g_plainColorSliceId ~= nil
        and type(g_overlayManager.createOverlay) == "function" then
        local ok, result = pcall(
            g_overlayManager.createOverlay,
            g_overlayManager, g_plainColorSliceId,
            0, 0, 0, 0
        )
        if ok then
            TerrainToolUI.rectangle = result
        end
    end

    if TerrainToolUI.rectangle == nil then
        print("[Terraform Plus] UI WARNUNG: Farb-Overlay nicht verfuegbar")
    end
    print("[Terraform Plus] TerrainToolUI initialisiert")
end

-- Liefert nur den lokalen Spielerinput; beabsichtigt fuer Spieler zu Fuss.
local function getPlayerInput()
    if g_localPlayer == nil then
        return nil, "Lokaler Spieler nicht verfuegbar"
    end
    if type(g_localPlayer.getCurrentVehicle) == "function"
        and g_localPlayer:getCurrentVehicle() ~= nil then
        return nil, "UI-Kamerasperre nur zu Fuss verfuegbar"
    end
    local input = g_localPlayer.inputComponent
    if input == nil or type(input.lock) ~= "function"
        or type(input.unlock) ~= "function" then
        return nil, "PlayerInputComponent nicht verfuegbar"
    end
    return input, nil
end

-- Gibt den Mauszeiger frei und stellt die Spielersteuerung wieder her.
function TerrainToolUI.disableMouse()
    if not TerrainToolUI.mouseActive then
        return
    end

    TerrainToolUI.mouseActive = false
    TerrainToolUI.pressedButton = nil
    TerrainToolUI.frozenSample = nil

    -- Eigene Sperre nur aufheben, wenn wir sie selbst gesetzt haben.
    -- Beim offenen Spielmenue hat die Engine Vorrang.
    local input = TerrainToolUI.lockedInput
    if input ~= nil
        and not TerrainToolUI.inputWasLocked
        and not isMenuOpen() then
        local ok, err = pcall(input.unlock, input)
        if not ok then
            print("[Terraform Plus] Input-Unlock-Fehler: " .. tostring(err))
        end
    end
    TerrainToolUI.lockedInput = nil
    TerrainToolUI.inputWasLocked = false

    if not isMenuOpen() and g_inputBinding ~= nil
        and type(g_inputBinding.setShowMouseCursor) == "function" then
        g_inputBinding:setShowMouseCursor(
            TerrainToolUI.previousMouseVisible or false
        )
    end
    print("[Terraform Plus] Kamerasteuerung wieder freigegeben")
end

function TerrainToolUI.toggle()
    TerrainToolUI.visible = not TerrainToolUI.visible
    if not TerrainToolUI.visible then
        TerrainToolUI.disableMouse()
        TerrainToolUI.rightHeld = false
    end
    return TerrainToolUI.visible
end

-- Aktiviert die Bedienmaus und blockiert dabei die Kamerasteuerung.
-- Die aktuelle Zielposition wird VOR dem Sperren gespeichert.
function TerrainToolUI.toggleMouse()
    if TerrainToolUI.mouseActive then
        TerrainToolUI.disableMouse()
        return true, false
    end
    if isMenuOpen() then
        return false, "Zuerst das Spielmenue schliessen"
    end
    if g_inputBinding == nil
        or type(g_inputBinding.getShowMouseCursor) ~= "function"
        or type(g_inputBinding.setShowMouseCursor) ~= "function" then
        return false, "Maus-API nicht verfuegbar"
    end

    local input, err = getPlayerInput()
    if input == nil then
        return false, err
    end
    if input.locked then
        return false, "Spielersteuerung ist bereits gesperrt"
    end

    local owner = TerrainToolUI.owner
    local sample = nil
    local sampleErr = nil
    if owner ~= nil then
        local ok, result, message = pcall(owner.getSelectionSample, owner)
        if ok and result ~= nil then
            sample = {
                x = result.x, z = result.z,
                terrainY = result.terrainY
            }
        else
            sampleErr = ok and message or result
        end
    end

    local previousVisible = g_inputBinding:getShowMouseCursor()
    local locked, lockErr = pcall(input.lock, input)
    if not locked then
        return false, "Kamerasperre fehlgeschlagen: " .. tostring(lockErr)
    end

    if type(input.resetState) == "function" then
        pcall(input.resetState, input)
    end

    local shown, showErr = pcall(
        g_inputBinding.setShowMouseCursor,
        g_inputBinding, true
    )
    if not shown then
        pcall(input.unlock, input)
        return false, "Cursor-Aktivierung fehlgeschlagen: " .. tostring(showErr)
    end

    TerrainToolUI.previousMouseVisible = previousVisible
    TerrainToolUI.lockedInput = input
    TerrainToolUI.inputWasLocked = false
    TerrainToolUI.frozenSample = sample
    TerrainToolUI.mouseActive = true
    TerrainToolUI.visible = true
    print("[Terraform Plus] Kamerasteuerung gesperrt (UI-Mausmodus)")

    if sample == nil then
        print("[Terraform Plus] Kein fixiertes Kameraziel: "
            .. tostring(sampleErr or "Boden nicht anvisiert"))
    end
    return true, true
end

-- Einmal je Frame: Rechtsklick-Flanke erkennen.
-- Damit funktioniert der Wechsel auch, wenn mouseEvent den Rechtsklick
-- wegen anderer LS25-Eingabebelegungen nicht erhaelt.
function TerrainToolUI.update(owner)
    if TerrainToolUI.mouseActive and isMenuOpen() then
        TerrainToolUI.disableMouse()
    end

    if not TerrainToolUI.visible or isMenuOpen() then
        TerrainToolUI.rightHeld = false
        return
    end

    if Input == nil or type(Input.isMouseButtonPressed) ~= "function" then
        return
    end

    local right = Input.MOUSE_BUTTON_RIGHT or TerrainToolUI.RIGHT_BUTTON
    local ok, pressed = pcall(Input.isMouseButtonPressed, right)
    if not ok then
        return
    end

    if pressed and not TerrainToolUI.rightHeld then
        TerrainToolUI.rightHeld = true
        print(owner:consoleCommandUIMouse())
    elseif not pressed then
        TerrainToolUI.rightHeld = false
    end
end

function TerrainToolUI.drawRect(x, y, w, h, color)
    local overlay = TerrainToolUI.rectangle
    if overlay == nil then
        return
    end
    overlay:setPosition(x, y)
    overlay:setDimension(w, h)
    overlay:setColor(color[1], color[2], color[3], color[4])
    overlay:render()
end

function TerrainToolUI.drawText(x, y, value, size, color, centered)
    setTextAlignment(centered and RenderText.ALIGN_CENTER or RenderText.ALIGN_LEFT)
    setTextColor(color[1], color[2], color[3], color[4])
    renderText(x, y, size or 0.014, tostring(value))
end

function TerrainToolUI.button(id, label, x, y, w, h, enabled, variant)
    local c = TerrainToolUI.COLORS
    local bg = not enabled and c.disabled
        or variant == "active" and c.active
        or variant == "warning" and c.warning
        or c.button
    TerrainToolUI.drawRect(x, y, w, h, bg)
    TerrainToolUI.drawText(
        x + w / 2, y + h * 0.29,
        label, 0.013, enabled and c.text or c.muted, true
    )
    TerrainToolUI.buttons[#TerrainToolUI.buttons + 1] = {
        id = id, x = x, y = y, w = w, h = h,
        enabled = enabled
    }
end

function TerrainToolUI.draw(owner)
    if not TerrainToolUI.visible or isMenuOpen() then
        return
    end
    if RenderText == nil or type(renderText) ~= "function" then
        return
    end

    local c = TerrainToolUI.COLORS
    TerrainToolUI.buttons = {}
    TerrainToolUI.drawRect(0.675, 0.18, 0.305, 0.61, c.panel)
    TerrainToolUI.drawRect(0.675, 0.746, 0.305, 0.044, c.header)
    TerrainToolUI.drawText(0.690, 0.757, "TERRAFORM PLUS  0.0.10.0", 0.017, c.text)

    -- X schliesst das Fenster UND beendet bei Bedarf den UI-Mausmodus.
    TerrainToolUI.button(
        "close", "X",
        0.938, 0.752,
        0.027, 0.031,
        true, "warning"
    )

    local selection = owner.selection
    local selecting = selection ~= nil and selection.active
    local stage = not selecting and "BEREIT"
        or selection.stage == "A" and "STARTPUNKT"
        or "ENDPUNKT"

    TerrainToolUI.drawText(0.690, 0.718, "STATUS: " .. stage, 0.014, c.text)
    local status = TerrainToolUI.mouseActive
        and (TerrainToolUI.frozenSample ~= nil
            and "MAUS: EIN | ZIEL FIXIERT" or "MAUS: EIN | KEIN ZIEL")
        or "RECHTSKLICK: UI-MAUS UMSCHALTEN"
    TerrainToolUI.drawText(0.690, 0.692, status, 0.012, c.muted)

    local area = owner.area
    local isLive = false
    if selecting then
        area = selection.preview ~= nil and selection.preview.area or nil
        isLive = area ~= nil
    end

    if area ~= nil then
        TerrainToolUI.drawText(
            0.690, 0.659,
            string.format(
                "%s: %.1f m2 / %d Zellen",
                isLive and "LIVE" or "FLAECHE",
                area.area,
                #area.samples
            ),
            0.013, c.text
        )
        TerrainToolUI.drawText(
            0.690, 0.632,
            string.format("ABTRAG: %.2f m3", area.cutVolume),
            0.014, c.cut
        )
        TerrainToolUI.drawText(
            0.690, 0.607,
            string.format("AUFTRAG: %.2f m3", area.fillVolume),
            0.014, c.fill
        )
    else
        TerrainToolUI.drawText(
            0.690, 0.640,
            "Noch keine Flaechenanalyse",
            0.014, c.muted
        )
    end

    TerrainToolUI.button(
        "start", "START",
        0.690, 0.548,
        0.132, 0.040,
        not selecting, "active"
    )

    TerrainToolUI.button(
        "anchor", "PUNKT A",
        0.833, 0.548,
        0.132, 0.040,
        selecting and selection.stage == "A"
            and (
                not TerrainToolUI.mouseActive
                or TerrainToolUI.frozenSample ~= nil
            )
    )

    TerrainToolUI.button(
        "confirm", "BESTAETIGEN",
        0.690, 0.501,
        0.132, 0.040,
        selecting and selection.stage == "B"
            and (
                not TerrainToolUI.mouseActive
                or TerrainToolUI.frozenSample ~= nil
            ),
        "active"
    )

    TerrainToolUI.button(
        "cancel", "ABBRECHEN",
        0.833, 0.501,
        0.132, 0.040,
        selecting, "warning"
    )

    TerrainToolUI.drawText(
        0.690, 0.477,
        "ARBEITSBREITE",
        0.013, c.muted
    )

    TerrainToolUI.button(
        "widthMinus", "-",
        0.690, 0.439,
        0.052, 0.033,
        owner.areaWidth > TerrainArea.MIN_WIDTH
    )

    TerrainToolUI.drawText(
        0.824, 0.447,
        string.format("%.2f m", owner.areaWidth),
        0.014, c.text, true
    )

    TerrainToolUI.button(
        "widthPlus", "+",
        0.909, 0.439,
        0.056, 0.033,
        owner.areaWidth < TerrainArea.MAX_WIDTH
    )

    TerrainToolUI.drawText(
        0.690, 0.412,
        "RASTERABSTAND",
        0.013, c.muted
    )

    TerrainToolUI.button(
        "stepMinus", "-",
        0.690, 0.374,
        0.052, 0.033,
        owner.areaStep > TerrainArea.MIN_STEP
    )

    TerrainToolUI.drawText(
        0.824, 0.383,
        string.format("%.2f m", owner.areaStep),
        0.014, c.text, true
    )

    TerrainToolUI.button(
        "stepPlus", "+",
        0.909, 0.374,
        0.056, 0.033,
        owner.areaStep < TerrainArea.MAX_STEP
    )

    -- Kein Kamera/Spieler-Umschalter mehr.
    -- Der Aktualisieren-Button nutzt die volle Breite.
    TerrainToolUI.button(
        "refresh", "AKTUALISIEREN",
        0.690, 0.325,
        0.275, 0.041,
        not selecting
            and owner.pointA ~= nil
            and owner.pointB ~= nil
    )

    TerrainToolUI.button(
        "preview",
        owner.previewEnabled and "1D: EIN" or "1D: AUS",
        0.690, 0.277,
        0.132, 0.041,
        true,
        owner.previewEnabled and "active" or nil
    )

    TerrainToolUI.button(
        "areaVisual",
        owner.areaEnabled and "2D: EIN" or "2D: AUS",
        0.833, 0.277,
        0.132, 0.041,
        true,
        owner.areaEnabled and "active" or nil
    )

    TerrainToolUI.button(
        "mouse",
        TerrainToolUI.mouseActive
            and "ZUR KAMERA (RECHTSKLICK)"
            or "RECHTSKLICK: MAUS",
        0.690, 0.201,
        0.275, 0.042,
        true
    )

    setTextColor(1, 1, 1, 1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

function TerrainToolUI.findButton(x, y)
    for _, b in ipairs(TerrainToolUI.buttons or {}) do
        if x >= b.x and x <= b.x + b.w
            and y >= b.y and y <= b.y + b.h then
            return b
        end
    end
    return nil
end

function TerrainToolUI.perform(owner, id)
    local actions = {
        start = "consoleCommandSelect",
        anchor = "consoleCommandAnchor",
        confirm = "consoleCommandConfirm",
        cancel = "consoleCommandCancel",
        refresh = "consoleCommandRefresh",
        preview = "consoleCommandPreview",
        areaVisual = "consoleCommandAreaVisual",
        mouse = "consoleCommandUIMouse",
        close = "consoleCommandUI"
    }

    local fn = actions[id]
    local result

    if fn ~= nil then
        result = owner[fn](owner)

    elseif id == "widthMinus" then
        result = owner:consoleCommandWidth(
            tostring(math.max(
                TerrainArea.MIN_WIDTH,
                owner.areaWidth - 2
            ))
        )

    elseif id == "widthPlus" then
        result = owner:consoleCommandWidth(
            tostring(math.min(
                TerrainArea.MAX_WIDTH,
                owner.areaWidth + 2
            ))
        )

    elseif id == "stepMinus" then
        result = owner:consoleCommandGridStep(
            tostring(math.max(
                TerrainArea.MIN_STEP,
                owner.areaStep - 0.5
            ))
        )

    elseif id == "stepPlus" then
        result = owner:consoleCommandGridStep(
            tostring(math.min(
                TerrainArea.MAX_STEP,
                owner.areaStep + 0.5
            ))
        )
    end

    if result ~= nil then
        print(tostring(result))
    end
end

function TerrainToolUI.mouseEvent(owner, x, y, down, up, button, used)

    if TerrainToolUI.visible and not isMenuOpen()
        and button == (
            Input ~= nil and Input.MOUSE_BUTTON_RIGHT
            or TerrainToolUI.RIGHT_BUTTON
        ) then

        if down and not TerrainToolUI.rightHeld then
            TerrainToolUI.rightHeld = true
            print(owner:consoleCommandUIMouse())
        end

        -- Bei aktivem Polling erfolgt der Reset
        -- erst beim Loslassen.
        if up and (
            Input == nil
            or type(Input.isMouseButtonPressed) ~= "function"
        ) then
            TerrainToolUI.rightHeld = false
        end

        return true
    end

    if used or not TerrainToolUI.visible
        or not TerrainToolUI.mouseActive
        or isMenuOpen() then

        return used or false
    end

    local left = Input ~= nil
        and Input.MOUSE_BUTTON_LEFT or 1

    if button ~= left then
        return false
    end

    local hit = TerrainToolUI.findButton(x, y)

    local inPanel =
        x >= TerrainToolUI.X
        and x <= TerrainToolUI.X + TerrainToolUI.W
        and y >= TerrainToolUI.Y
        and y <= TerrainToolUI.Y + TerrainToolUI.H

    if down and hit ~= nil and hit.enabled then
        TerrainToolUI.pressedButton = hit.id
        return true
    end

    if up and TerrainToolUI.pressedButton ~= nil then

        local pressed = TerrainToolUI.pressedButton
        TerrainToolUI.pressedButton = nil

        if hit ~= nil and hit.enabled
            and hit.id == pressed then

            TerrainToolUI.perform(owner, pressed)
        end

        return true
    end

    return (down or up) and inPanel or false
end

function TerrainToolUI.delete()
    TerrainToolUI.disableMouse()

    if TerrainToolUI.rectangle ~= nil then
        TerrainToolUI.rectangle:delete()
        TerrainToolUI.rectangle = nil
    end

    TerrainToolUI.visible = false
    TerrainToolUI.initialized = false
    TerrainToolUI.buttons = {}
    TerrainToolUI.owner = nil
end
