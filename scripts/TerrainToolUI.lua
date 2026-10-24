
-- Terraform Plus 0.0.11.0 - Terrain tool UI
-- Two pages: Area selection and target terrain design
-- Update: "Bereich loeschen" uses tpClear instead of tpCancel

TerrainToolUI = TerrainToolUI or {}

TerrainToolUI.X, TerrainToolUI.Y = 0.675, 0.18
TerrainToolUI.W, TerrainToolUI.H = 0.305, 0.61
TerrainToolUI.RIGHT_BUTTON = 3

TerrainToolUI.COLORS = {
    panel = {0.035, 0.055, 0.075, 0.93},
    header = {0.045, 0.22, 0.23, 0.96},
    button = {0.13, 0.19, 0.24, 0.96},
    active = {0.11, 0.48, 0.37, 0.97},
    warning = {0.55, 0.24, 0.20, 0.95},
    disabled = {0.10, 0.12, 0.15, 0.65},
    text = {0.94, 0.97, 1, 1},
    muted = {0.67, 0.74, 0.79, 1},
    cut = {1, 0.4, 0.4, 1},
    fill = {0.35, 1, 0.61, 1}
}


local function menuOpen()
    return g_gui ~= nil
        and type(g_gui.getIsGuiVisible) == "function"
        and g_gui:getIsGuiVisible()
end


local function playerInput()
    if g_localPlayer == nil then
        return nil, "Spieler nicht geladen"
    end

    if type(g_localPlayer.getCurrentVehicle) == "function"
        and g_localPlayer:getCurrentVehicle() ~= nil then

        return nil, "Mausmodus nur zu Fuss verfuegbar"
    end

    local input = g_localPlayer.inputComponent

    if input == nil
        or type(input.lock) ~= "function"
        or type(input.unlock) ~= "function" then

        return nil, "PlayerInputComponent fehlt"
    end

    return input
end


function TerrainToolUI.initialize(owner)
    TerrainToolUI.owner = owner
    TerrainToolUI.visible = false
    TerrainToolUI.mouseActive = false
    TerrainToolUI.frozenSample = nil
    TerrainToolUI.lockedInput = nil
    TerrainToolUI.rightHeld = false
    TerrainToolUI.previousMouseVisible = false
    TerrainToolUI.pressedButton = nil
    TerrainToolUI.buttons = {}
    TerrainToolUI.page = "select"
    TerrainToolUI.initialized = true

    if TerrainToolUI.rectangle ~= nil then
        TerrainToolUI.rectangle:delete()
        TerrainToolUI.rectangle = nil
    end

    if g_overlayManager ~= nil
        and g_plainColorSliceId ~= nil
        and type(g_overlayManager.createOverlay) == "function" then

        local ok, rect = pcall(
            g_overlayManager.createOverlay,
            g_overlayManager,
            g_plainColorSliceId,
            0, 0, 0, 0
        )

        if ok then
            TerrainToolUI.rectangle = rect
        end
    end

    print(
        "[Terraform Plus] TerrainToolUI initialisiert (0.0.11.0)"
    )
end


function TerrainToolUI.disableMouse()
    if not TerrainToolUI.mouseActive then
        return
    end

    TerrainToolUI.mouseActive = false
    TerrainToolUI.pressedButton = nil
    TerrainToolUI.frozenSample = nil

    local input = TerrainToolUI.lockedInput
    TerrainToolUI.lockedInput = nil

    if input ~= nil and not menuOpen() then
        local ok, err = pcall(input.unlock, input)

        if not ok then
            print(
                "[Terraform Plus] Input-Unlock-Fehler: "
                .. tostring(err)
            )
        end
    end

    if not menuOpen()
        and g_inputBinding ~= nil
        and type(g_inputBinding.setShowMouseCursor)
            == "function" then

        g_inputBinding:setShowMouseCursor(
            TerrainToolUI.previousMouseVisible or false
        )
    end

    print(
        "[Terraform Plus] Kamerasteuerung wieder freigegeben"
    )
end


function TerrainToolUI.toggle()
    TerrainToolUI.visible = not TerrainToolUI.visible

    if not TerrainToolUI.visible then
        TerrainToolUI.disableMouse()
        TerrainToolUI.rightHeld = false
    end

    return TerrainToolUI.visible
end


function TerrainToolUI.toggleMouse()
    if TerrainToolUI.mouseActive then
        TerrainToolUI.disableMouse()
        return true, false
    end

    if menuOpen() then
        return false, "Zuerst Spielmenue schliessen"
    end

    if g_inputBinding == nil
        or type(g_inputBinding.getShowMouseCursor)
            ~= "function"
        or type(g_inputBinding.setShowMouseCursor)
            ~= "function" then

        return false, "Maus-API nicht verfuegbar"
    end

    local input, err = playerInput()

    if input == nil then
        return false, err
    end

    if input.locked then
        return false, "Spielersteuerung bereits gesperrt"
    end

    -- Kamera-Zielpunkt vor dem Mausmodus speichern.
    local sample = nil
    local sampleErr = nil

    local owner = TerrainToolUI.owner

    if owner ~= nil then
        local ok, result, message = pcall(
            owner.getSelectionSample,
            owner
        )

        if ok and result ~= nil then
            sample = {
                x = result.x,
                z = result.z,
                terrainY = result.terrainY
            }
        else
            sampleErr = ok and message or result
        end
    end

    local wasVisible =
        g_inputBinding:getShowMouseCursor()

    local ok, lockErr = pcall(input.lock, input)

    if not ok then
        return false,
            "Kamerasperre: " .. tostring(lockErr)
    end

    if type(input.resetState) == "function" then
        pcall(input.resetState, input)
    end

    local shown, showErr = pcall(
        g_inputBinding.setShowMouseCursor,
        g_inputBinding,
        true
    )

    if not shown then
        pcall(input.unlock, input)

        return false,
            "Mauszeiger: " .. tostring(showErr)
    end

    TerrainToolUI.previousMouseVisible = wasVisible
    TerrainToolUI.lockedInput = input
    TerrainToolUI.frozenSample = sample
    TerrainToolUI.mouseActive = true
    TerrainToolUI.visible = true

    print(
        "[Terraform Plus] Kamerasteuerung gesperrt (UI-Mausmodus)"
    )

    if sample == nil then
        print(
            "[Terraform Plus] Kein fixiertes Kameraziel: "
            .. tostring(sampleErr)
        )
    end

    return true, true
end


function TerrainToolUI.update(owner)
    if TerrainToolUI.mouseActive and menuOpen() then
        TerrainToolUI.disableMouse()
    end

    if not TerrainToolUI.visible or menuOpen() then
        TerrainToolUI.rightHeld = false
        return
    end

    if Input == nil
        or type(Input.isMouseButtonPressed) ~= "function" then

        return
    end

    local right =
        Input.MOUSE_BUTTON_RIGHT or TerrainToolUI.RIGHT_BUTTON

    local ok, pressed = pcall(
        Input.isMouseButtonPressed,
        right
    )

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


function TerrainToolUI.rect(x, y, w, h, color)
    local r = TerrainToolUI.rectangle

    if r == nil then
        return
    end

    r:setPosition(x, y)
    r:setDimension(w, h)
    r:setColor(
        color[1], color[2],
        color[3], color[4]
    )
    r:render()
end


function TerrainToolUI.text(
    x, y, value, size, color, center
)
    setTextAlignment(
        center
        and RenderText.ALIGN_CENTER
        or RenderText.ALIGN_LEFT
    )

    setTextColor(
        color[1], color[2],
        color[3], color[4]
    )

    renderText(
        x, y,
        size or 0.013,
        tostring(value)
    )
end


function TerrainToolUI.button(
    id, label, x, y, w, h, enabled, kind
)
    local c = TerrainToolUI.COLORS

    local color =
        not enabled and c.disabled
        or kind == "active" and c.active
        or kind == "warning" and c.warning
        or c.button

    TerrainToolUI.rect(
        x, y, w, h, color
    )

    TerrainToolUI.text(
        x + w / 2,
        y + h * 0.30,
        label,
        0.0125,
        enabled and c.text or c.muted,
        true
    )

    table.insert(TerrainToolUI.buttons, {
        id = id,
        x = x,
        y = y,
        w = w,
        h = h,
        enabled = enabled
    })
end


function TerrainToolUI.setting(
    id, label, value, y,
    minimum, maximum, unit
)
    local c = TerrainToolUI.COLORS

    TerrainToolUI.text(
        0.690, y + 0.045,
        label, 0.0125, c.muted
    )

    TerrainToolUI.button(
        id .. "Minus", "-",
        0.690, y,
        0.050, 0.036,
        value > minimum
    )

    TerrainToolUI.text(
        0.824, y + 0.012,
        string.format(
            "%.2f %s",
            value,
            unit or "m"
        ),
        0.0135,
        c.text,
        true
    )

    TerrainToolUI.button(
        id .. "Plus", "+",
        0.909, y,
        0.055, 0.036,
        value < maximum
    )
end


function TerrainToolUI.draw(owner)
    if not TerrainToolUI.visible
        or menuOpen() then

        return
    end

    if RenderText == nil
        or type(renderText) ~= "function" then

        return
    end

    local c = TerrainToolUI.COLORS
    TerrainToolUI.buttons = {}

    TerrainToolUI.rect(
        0.675, 0.18,
        0.305, 0.61,
        c.panel
    )

    TerrainToolUI.rect(
        0.675, 0.746,
        0.305, 0.044,
        c.header
    )

    TerrainToolUI.text(
        0.690, 0.757,
        "TERRAFORM PLUS  0.0.11.0",
        0.016,
        c.text
    )

    TerrainToolUI.button(
        "close", "X",
        0.939, 0.752,
        0.026, 0.031,
        true, "warning"
    )

    TerrainToolUI.button(
        "tabSelect", "BEREICH",
        0.690, 0.696,
        0.132, 0.040,
        true,
        TerrainToolUI.page == "select"
            and "active"
    )

    TerrainToolUI.button(
        "tabDesign", "GESTALTUNG",
        0.833, 0.696,
        0.132, 0.040,
        true,
        TerrainToolUI.page == "design"
            and "active"
    )

    local selection = owner.selection

    local selecting =
        selection ~= nil and selection.active

    local baseArea = nil

    if selecting then
        baseArea =
            selection.preview
            and selection.preview.area
            or nil
    else
        baseArea = owner.area
    end

    -- ============================================
    -- REITER: BEREICH
    -- ============================================

    if TerrainToolUI.page == "select" then

        local state =
            not selecting and "Kein Bereich aktiv"
            or selection.stage == "A"
                and "Startpunkt anvisieren"
            or "Endpunkt anvisieren"

        TerrainToolUI.text(
            0.690, 0.663,
            state,
            0.014,
            c.text
        )

        TerrainToolUI.text(
            0.690, 0.632,

            TerrainToolUI.mouseActive
                and "MAUS AKTIV - Ziel eingefroren"
                or "Rechtsklick: Maus einschalten",

            0.012,
            c.muted
        )

        if baseArea ~= nil then

            TerrainToolUI.text(
                0.690, 0.601,

                string.format(
                    "Bereich: %.1f m2 | %d Zellen",
                    baseArea.area,
                    #baseArea.samples
                ),

                0.013,
                c.text
            )

            TerrainToolUI.text(
                0.690, 0.571,

                string.format(
                    "Abtrag %.1f m3 / Auftrag %.1f m3",
                    baseArea.cutVolume,
                    baseArea.fillVolume
                ),

                0.012,
                c.text
            )

        else
            TerrainToolUI.text(
                0.690, 0.583,
                "Noch keine Berechnung",
                0.013,
                c.muted
            )
        end

        TerrainToolUI.button(
            "start", "NEUER BEREICH",
            0.690, 0.511,
            0.132, 0.042,
            not selecting,
            "active"
        )

        TerrainToolUI.button(
            "refresh", "NEU BERECHNEN",
            0.833, 0.511,
            0.132, 0.042,

            not selecting
                and owner.pointA ~= nil
                and owner.pointB ~= nil
        )

        TerrainToolUI.button(
            "anchor", "STARTPUNKT SETZEN",
            0.690, 0.459,
            0.132, 0.042,

            selecting
                and selection.stage == "A"
        )

        TerrainToolUI.button(
            "confirm", "ENDPUNKT SETZEN",
            0.833, 0.459,
            0.132, 0.042,

            selecting
                and selection.stage == "B"
        )

        -- ========================================
        -- GEANDERT:
        -- Der Button entfernt jetzt alle Messpunkte
        -- wie tpClear, auch nach einer Bestaetigung.
        -- ========================================

        local hasArea =
            selecting
            or owner.pointA ~= nil
            or owner.pointB ~= nil
            or owner.area ~= nil

        TerrainToolUI.button(
            "clear", "BEREICH LOESCHEN",
            0.690, 0.406,
            0.275, 0.042,

            hasArea,
            "warning"
        )

        TerrainToolUI.setting(
            "width",
            "BREITE DES BEREICHS",
            owner.areaWidth,
            0.340,
            TerrainArea.MIN_WIDTH,
            TerrainArea.MAX_WIDTH,
            "m"
        )

        TerrainToolUI.setting(
            "step",
            "RASTERGROESSE (KLEINER = GENAUER)",
            owner.areaStep,
            0.275,
            TerrainArea.MIN_STEP,
            TerrainArea.MAX_STEP,
            "m"
        )

        TerrainToolUI.button(
            "preview",

            owner.previewEnabled
                and "HOEHENPROFIL AN"
                or "HOEHENPROFIL AUS",

            0.690, 0.201,
            0.132, 0.044,

            true,

            owner.previewEnabled
                and "active"
        )

        TerrainToolUI.button(
            "areaVisual",

            owner.areaEnabled
                and "3D-VORSCHAU AN"
                or "3D-VORSCHAU AUS",

            0.833, 0.201,
            0.132, 0.044,

            true,

            owner.areaEnabled
                and "active"
        )

    -- ============================================
    -- REITER: GESTALTUNG
    -- ============================================

    else

        local d = owner.design or {
            offset = 0,
            slope = 0,
            feather = 0,
            mode = "all",
            enabled = true
        }

        local atA =
            owner.pointA
            and owner.pointA.terrainY + d.offset
            or nil

        local designArea, err =
            owner:getDesignArea()

        TerrainToolUI.text(
            0.690, 0.661,

            atA
                and string.format(
                    "Zielhoehe bei A: %.2f m",
                    atA
                )
                or "Zuerst Start- und Endpunkt setzen",

            0.013,
            c.text
        )

        TerrainToolUI.setting(
            "height",
            "ZIELHOEHE VERSCHIEBEN",
            d.offset,
            0.594,
            TerrainDesign.MIN_OFFSET,
            TerrainDesign.MAX_OFFSET,
            "m"
        )

        TerrainToolUI.setting(
            "slope",
            "ZIELSTEIGUNG",
            d.slope,
            0.522,
            TerrainDesign.MIN_SLOPE,
            TerrainDesign.MAX_SLOPE,
            "%"
        )

        TerrainToolUI.setting(
            "feather",
            "WEICHER RAND",
            d.feather,
            0.450,
            TerrainDesign.MIN_FEATHER,
            TerrainDesign.MAX_FEATHER,
            "m"
        )

        TerrainToolUI.text(
            0.690, 0.426,
            "ART DER GELAENDEAENDERUNG",
            0.012,
            c.muted
        )

        TerrainToolUI.button(
            "modeAll", "BEIDES",
            0.690, 0.383,
            0.088, 0.036,
            true,
            d.mode == "all" and "active"
        )

        TerrainToolUI.button(
            "modeCut", "NUR ABTRAG",
            0.782, 0.383,
            0.088, 0.036,
            true,
            d.mode == "cut" and "active"
        )

        TerrainToolUI.button(
            "modeFill", "NUR AUFTRAG",
            0.874, 0.383,
            0.091, 0.036,
            true,
            d.mode == "fill" and "active"
        )

        if designArea ~= nil then

            TerrainToolUI.text(
                0.690, 0.347,

                string.format(
                    "Vorschau: %d Rasterzellen",
                    #designArea.samples
                ),

                0.012,
                c.muted
            )

            TerrainToolUI.text(
                0.690, 0.320,

                string.format(
                    "Abtrag: %.2f m3",
                    designArea.cutVolume
                ),

                0.014,
                c.cut
            )

            TerrainToolUI.text(
                0.690, 0.292,

                string.format(
                    "Auftrag: %.2f m3",
                    designArea.fillVolume
                ),

                0.014,
                c.fill
            )

            TerrainToolUI.text(
                0.690, 0.266,

                string.format(
                    "Netto: %+.2f m3",
                    designArea.netVolume
                ),

                0.013,
                c.text
            )

        else
            TerrainToolUI.text(
                0.690, 0.321,
                err or "Keine Flaeche vorhanden",
                0.012,
                c.muted
            )
        end

        TerrainToolUI.button(
            "designVisual",

            d.enabled
                and "SOLL-VORSCHAU AN"
                or "SOLL-VORSCHAU AUS",

            0.690, 0.210,
            0.170, 0.039,

            true,

            d.enabled and "active"
        )

        TerrainToolUI.button(
            "resetDesign", "ZURUECKSETZEN",
            0.869, 0.210,
            0.096, 0.039,
            true
        )
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1, 1, 1, 1)
end


function TerrainToolUI.findButton(x, y)
    for _, b in ipairs(TerrainToolUI.buttons or {}) do

        if x >= b.x
            and x <= b.x + b.w
            and y >= b.y
            and y <= b.y + b.h then

            return b
        end
    end

    return nil
end


function TerrainToolUI.perform(owner, id)
    if id == "tabSelect" then
        TerrainToolUI.page = "select"
        return
    end

    if id == "tabDesign" then
        TerrainToolUI.page = "design"
        return
    end

    local fn = {
        close = "consoleCommandUI",
        start = "consoleCommandSelect",
        anchor = "consoleCommandAnchor",
        confirm = "consoleCommandConfirm",

        -- GEANDERT:
        -- UI-Button "Bereich loeschen" verwendet tpClear.
        clear = "consoleCommandClear",

        refresh = "consoleCommandRefresh",
        preview = "consoleCommandPreview",
        areaVisual = "consoleCommandAreaVisual",
        designVisual = "consoleCommandDesignVisual"
    }

    local result

    if fn[id] ~= nil then

        result = owner[fn[id]](owner)

    elseif id == "widthMinus" then

        result = owner:consoleCommandWidth(
            tostring(
                math.max(
                    TerrainArea.MIN_WIDTH,
                    owner.areaWidth - 2
                )
            )
        )

    elseif id == "widthPlus" then

        result = owner:consoleCommandWidth(
            tostring(
                math.min(
                    TerrainArea.MAX_WIDTH,
                    owner.areaWidth + 2
                )
            )
        )

    elseif id == "stepMinus" then

        result = owner:consoleCommandGridStep(
            tostring(
                math.max(
                    TerrainArea.MIN_STEP,
                    owner.areaStep - 0.5
                )
            )
        )

    elseif id == "stepPlus" then

        result = owner:consoleCommandGridStep(
            tostring(
                math.min(
                    TerrainArea.MAX_STEP,
                    owner.areaStep + 0.5
                )
            )
        )

    elseif id == "heightMinus"
        or id == "heightPlus" then

        local delta =
            id == "heightPlus" and 0.5 or -0.5

        result = owner:consoleCommandTargetOffset(
            tostring(owner.design.offset + delta)
        )

    elseif id == "slopeMinus"
        or id == "slopePlus" then

        local delta =
            id == "slopePlus" and 1 or -1

        result = owner:consoleCommandTargetSlope(
            tostring(owner.design.slope + delta)
        )

    elseif id == "featherMinus"
        or id == "featherPlus" then

        local delta =
            id == "featherPlus" and 1 or -1

        result = owner:consoleCommandEdgeBlend(
            tostring(owner.design.feather + delta)
        )

    elseif id == "modeAll" then

        result = owner:consoleCommandWorkMode("all")

    elseif id == "modeCut" then

        result = owner:consoleCommandWorkMode("cut")

    elseif id == "modeFill" then

        result = owner:consoleCommandWorkMode("fill")

    elseif id == "resetDesign" then

        result = owner:consoleCommandDesignReset()
    end

    if result ~= nil then
        print(result)
    end
end


function TerrainToolUI.mouseEvent(
    owner, x, y,
    down, up,
    button, used
)

    if TerrainToolUI.visible
        and not menuOpen()
        and button == (
            Input ~= nil
            and Input.MOUSE_BUTTON_RIGHT
            or TerrainToolUI.RIGHT_BUTTON
        ) then

        if down and not TerrainToolUI.rightHeld then
            TerrainToolUI.rightHeld = true
            print(owner:consoleCommandUIMouse())
        end

        if up and (
            Input == nil
            or type(Input.isMouseButtonPressed) ~= "function"
        ) then

            TerrainToolUI.rightHeld = false
        end

        return true
    end

    if used
        or not TerrainToolUI.visible
        or not TerrainToolUI.mouseActive
        or menuOpen() then

        return used or false
    end

    local left =
        Input ~= nil
        and Input.MOUSE_BUTTON_LEFT
        or 1

    if button ~= left then
        return false
    end

    local hit = TerrainToolUI.findButton(x, y)

    local panel =
        x >= TerrainToolUI.X
        and x <= TerrainToolUI.X + TerrainToolUI.W
        and y >= TerrainToolUI.Y
        and y <= TerrainToolUI.Y + TerrainToolUI.H

    if down and hit ~= nil and hit.enabled then

        TerrainToolUI.pressedButton = hit.id

        return true
    end

    if up and TerrainToolUI.pressedButton ~= nil then

        local pressed =
            TerrainToolUI.pressedButton

        TerrainToolUI.pressedButton = nil

        if hit ~= nil
            and hit.enabled
            and hit.id == pressed then

            TerrainToolUI.perform(owner, pressed)
        end

        return true
    end

    return (down or up) and panel or false
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
