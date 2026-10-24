
-- Terraform Plus
-- Version: 0.0.9.0
-- Camera targeting, interactive selection and terrain analysis

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.9.0"

TerraformPlus.COMMANDS = {
    {"tpHeight", "Gelaendehoehe", "consoleCommandHeight"},
    {"tpSetA", "Setzt Messpunkt A", "consoleCommandSetA"},
    {"tpSetB", "Setzt Messpunkt B", "consoleCommandSetB"},
    {"tpMeasure", "Zeigt die Steigung", "consoleCommandMeasure"},
    {"tpProfile", "Zeigt das Terrainprofil", "consoleCommandProfile"},
    {"tpPreview", "Schaltet die 1D-Vorschau um", "consoleCommandPreview"},
    {"tpWidth", "Setzt die Arbeitsbreite", "consoleCommandWidth"},
    {"tpGridStep", "Setzt den Rasterabstand", "consoleCommandGridStep"},
    {"tpVolume", "Zeigt das Volumen", "consoleCommandVolume"},
    {"tpAreaVisual", "Schaltet die 2D-Vorschau um", "consoleCommandAreaVisual"},
    {"tpRefresh", "Aktualisiert die Analyse", "consoleCommandRefresh"},
    {"tpVisual", "Schaltet die Visualisierung um", "consoleCommandVisual"},
    {"tpClear", "Loescht Messpunkte", "consoleCommandClear"},

    {"tpSelect", "Startet die Auswahl", "consoleCommandSelect"},
    {"tpAnchor", "Fixiert Startpunkt A", "consoleCommandAnchor"},
    {"tpConfirm", "Bestaetigt Punkt B", "consoleCommandConfirm"},
    {"tpCancel", "Bricht die Auswahl ab", "consoleCommandCancel"},
    {"tpSelection", "Zeigt den Auswahlstatus", "consoleCommandSelection"},

    {"tpAim", "Zeigt das Kameraziel", "consoleCommandAim"},
    {"tpCursorMode", "Waehlt den Cursormodus", "consoleCommandCursorMode"}
}


-- Eigene GIANTS-Input-Actions
TerraformPlus.INPUT_ACTIONS = {
    {
        name = "TP_TOOL_SELECT",
        callback = "onInputSelect",
        label = "Terraform Plus: Auswahl starten"
    },
    {
        name = "TP_TOOL_PLACE",
        callback = "onInputPlace",
        label = "Terraform Plus: Punkt setzen"
    },
    {
        name = "TP_TOOL_CANCEL",
        callback = "onInputCancel",
        label = "Terraform Plus: Auswahl abbrechen"
    }
}


-- Erstellt eine Kopie eines Messpunkts.
function TerraformPlus:createPoint(sample)

    return {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }
end


-- Spielerposition und Gelaendehoehe lesen.
function TerraformPlus:getCurrentSample()

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAtPlayer) ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local ok, sample, err = pcall(
        TerrainAdapter.getHeightAtPlayer
    )

    if not ok then
        return nil, "Lua-Fehler: " .. tostring(sample)
    end

    if sample == nil then
        return nil, tostring(err or "Keine Spielerposition")
    end

    return sample, nil
end


-- Zielquelle fuer die interaktive Auswahl.
function TerraformPlus:getSelectionSample()

    if self.cursorMode == "camera" then

        if TerrainCursor == nil
            or type(TerrainCursor.getGroundPoint) ~= "function" then

            return nil, "TerrainCursor nicht geladen"
        end

        return TerrainCursor.getGroundPoint()
    end

    return self:getCurrentSample()
end


-- Gespeicherte Terrainhoehe neu auslesen.
function TerraformPlus:getHeightAtPoint(point)

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt) ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local ok, height, err = pcall(
        TerrainAdapter.getHeightAt,
        point.x,
        point.z
    )

    if not ok then
        return nil, "Lua-Fehler: " .. tostring(height)
    end

    if type(height) ~= "number" then
        return nil, tostring(err or "Ungueltige Hoehe")
    end

    return height, nil
end


-- Durchschnittliche Steigung.
function TerraformPlus:calculateSlope(a, b)

    local dx = b.x - a.x
    local dz = b.z - a.z

    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    local dh = b.terrainY - a.terrainY

    return {
        distance = distance,
        heightDifference = dh,
        slopePercent = dh / distance * 100,
        slopeAngle = math.deg(math.atan(dh / distance))
    }, nil
end


-- Vollstaendige Analyse, ohne den Spielstand zu veraendern.
function TerraformPlus:buildAnalysis(a, b, stepOverride)

    local measurement, err = self:calculateSlope(a, b)

    if measurement == nil then
        return nil, err
    end

    if TerrainProfile == nil
        or type(TerrainProfile.build) ~= "function" then

        return nil, "TerrainProfile nicht geladen"
    end

    if TerrainArea == nil
        or type(TerrainArea.build) ~= "function" then

        return nil, "TerrainArea nicht geladen"
    end

    local ok, profile, profileErr = pcall(
        TerrainProfile.build,
        a,
        b
    )

    if not ok then
        return nil, "Profil-Lua-Fehler: " .. tostring(profile)
    end

    if profile == nil then
        return nil, tostring(profileErr)
    end

    local step = stepOverride or self.areaStep

    local areaOk, area, areaErr = pcall(
        TerrainArea.build,
        a,
        b,
        self.areaWidth,
        step
    )

    if not areaOk then
        return nil, "Raster-Lua-Fehler: " .. tostring(area)
    end

    if area == nil then
        return nil, tostring(areaErr)
    end

    return {
        measurement = measurement,
        profile = profile,
        area = area
    }, nil
end


-- Ergebnisse nur nach erfolgreicher Analyse uebernehmen.
function TerraformPlus:applyAnalysis(a, b)

    local result, err = self:buildAnalysis(a, b)

    if result == nil then
        return nil, err
    end

    self.pointA = a
    self.pointB = b

    self.measurement = result.measurement
    self.profile = result.profile
    self.area = result.area

    return result, nil
end


-- Registrierung der optionalen Input-Events.
-- Aufruf aus dem Spieler-Eingabekontext.
function TerraformPlus.registerPlayerActions(playerInput)

    if not TerraformPlus.mapActive then
        return
    end

    if playerInput == nil
        or playerInput.player == nil
        or not playerInput.player.isOwner then

        return
    end

    if g_inputBinding == nil
        or type(g_inputBinding.registerActionEvent)
            ~= "function" then

        return
    end

    TerraformPlus.actionEventIds = {}

    for _, action in ipairs(TerraformPlus.INPUT_ACTIONS) do

        local actionName = action.name

        if InputAction ~= nil
            and InputAction[actionName] ~= nil then

            actionName = InputAction[actionName]
        end

        local ok, success, eventId = pcall(
            g_inputBinding.registerActionEvent,
            g_inputBinding,
            actionName,
            TerraformPlus,
            TerraformPlus[action.callback],
            false,
            true,
            false,
            true
        )

        if ok and success and eventId ~= nil then

            table.insert(
                TerraformPlus.actionEventIds,
                eventId
            )

            if type(g_inputBinding.setActionEventText)
                == "function" then

                pcall(
                    g_inputBinding.setActionEventText,
                    g_inputBinding,
                    eventId,
                    action.label
                )
            end

        else

            print(
                "[Terraform Plus] Tastenzuweisung nicht aktiv: "
                .. action.name
            )
        end
    end
end


-- Input-Integration nur einmal installieren.
function TerraformPlus:installInputHook()

    if self.inputHookInstalled then
        return
    end

    if PlayerInputComponent == nil
        or type(PlayerInputComponent.registerGlobalPlayerActionEvents)
            ~= "function"
        or Utils == nil
        or type(Utils.appendedFunction) ~= "function" then

        print(
            "[Terraform Plus] Input-Hook nicht verfuegbar; Konsolenbefehle bleiben nutzbar"
        )

        return
    end

    PlayerInputComponent.registerGlobalPlayerActionEvents =
        Utils.appendedFunction(
            PlayerInputComponent.registerGlobalPlayerActionEvents,
            TerraformPlus.registerPlayerActions
        )

    self.inputHookInstalled = true

    print("[Terraform Plus] Eingabesteuerung registriert")
end


-- Karte laden.
function TerraformPlus:loadMap()

    self.mapActive = true

    self.pointA = nil
    self.pointB = nil

    self.measurement = nil
    self.profile = nil
    self.area = nil

    self.selection = nil

    self.areaWidth =
        TerrainArea ~= nil
        and TerrainArea.DEFAULT_WIDTH
        or 10.0

    self.areaStep =
        TerrainArea ~= nil
        and TerrainArea.DEFAULT_STEP
        or 2.0

    self.cursorMode = "camera"

    self.visualEnabled = true
    self.previewEnabled = true
    self.areaEnabled = true

    self.commandsRegistered = false
    self.actionEventIds = {}

    for _, command in ipairs(self.COMMANDS) do

        addConsoleCommand(
            command[1],
            command[2],
            command[3],
            self
        )
    end

    self.commandsRegistered = true

    self:installInputHook()

    print(
        "[Terraform Plus] Mod geladen - Version "
        .. self.VERSION
    )

    print("[Terraform Plus] Kamera-Cursor bereit")
end


-- Interaktive Auswahl aktualisieren.
function TerraformPlus:update(dt)

    if self.selection == nil
        or not self.selection.active then

        return
    end

    local ok, err = pcall(
        TerrainSelection.update,
        self,
        dt
    )

    if not ok then

        print(
            "[Terraform Plus] Auswahlfehler: "
            .. tostring(err)
        )

        TerrainSelection.cancel(self)
    end
end


-- Visualisierung.
function TerraformPlus:draw()

    if not self.visualEnabled then
        return
    end

    if TerrainVisualizer == nil
        or type(TerrainVisualizer.draw) ~= "function" then

        return
    end

    local selection = self.selection

    local active =
        selection ~= nil and selection.active

    local b = self.pointB
    local measurement = self.measurement
    local profile = self.profile
    local area = self.area

    if active and selection.preview ~= nil then

        b = selection.preview.pointB
        measurement = selection.preview.measurement
        profile = selection.preview.profile
        area = selection.preview.area
    end

    if self.pointA ~= nil then

        local ok, err = pcall(
            TerrainVisualizer.draw,
            self.pointA,
            b,
            measurement,
            profile,
            self.previewEnabled,
            area,
            self.areaEnabled
        )

        if not ok then

            self.visualEnabled = false

            print(
                "[Terraform Plus] Visualisierung deaktiviert: "
                .. tostring(err)
            )

            return
        end
    end

    if active then

        local ok, err = pcall(
            TerrainSelection.draw,
            self
        )

        if not ok then

            self.visualEnabled = false

            print(
                "[Terraform Plus] Cursordarstellung deaktiviert: "
                .. tostring(err)
            )
        end
    end
end


-- tpHeight: Spielerposition.
function TerraformPlus:consoleCommandHeight()

    local s, err = self:getCurrentSample()

    if s == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] X=%.2f Z=%.2f | Terrainhoehe=%.3f m",
        s.x,
        s.z,
        s.terrainY
    )
end


-- tpAim: Terrainposition in der Bildschirmmitte.
function TerraformPlus:consoleCommandAim()

    if TerrainCursor == nil then
        return "[Terraform Plus] TerrainCursor nicht geladen"
    end

    local s, err = TerrainCursor.getGroundPoint()

    if s == nil then
        return "[Terraform Plus] Ziel nicht verfuegbar: "
            .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] AIM | X=%.2f Z=%.2f | H=%.3f m | Entfernung=%.2f m",
        s.x,
        s.z,
        s.terrainY,
        s.rayDistance
    )
end


-- tpCursorMode [camera/player]
function TerraformPlus:consoleCommandCursorMode(mode)

    if mode == nil or mode == "" then

        return "[Terraform Plus] Cursormodus: "
            .. tostring(self.cursorMode)
    end

    mode = string.lower(tostring(mode))

    if mode ~= "camera" and mode ~= "player" then

        return "[Terraform Plus] Gueltig: tpCursorMode camera / player"
    end

    self.cursorMode = mode

    if TerrainSelection ~= nil then
        TerrainSelection.invalidate(self)
    end

    if self.selection ~= nil then
        self.selection.cursor = nil
    end

    return "[Terraform Plus] Cursormodus: " .. mode
end


-- tpSetA: manuelle Messung oder Auswahl.
function TerraformPlus:consoleCommandSetA()

    if self.selection ~= nil and self.selection.active then
        return self:consoleCommandAnchor()
    end

    local s, err = self:getCurrentSample()

    if s == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    self.pointA = self:createPoint(s)

    self.pointB = nil
    self.measurement = nil
    self.profile = nil
    self.area = nil

    return string.format(
        "[Terraform Plus] Punkt A gesetzt: X=%.2f Z=%.2f H=%.3f m",
        self.pointA.x,
        self.pointA.z,
        self.pointA.terrainY
    )
end


-- tpSetB: manuelle Messung oder Auswahl.
function TerraformPlus:consoleCommandSetB()

    if self.selection ~= nil and self.selection.active then
        return self:consoleCommandConfirm()
    end

    if self.pointA == nil then
        return "[Terraform Plus] Zuerst Punkt A setzen"
    end

    local s, err = self:getCurrentSample()

    if s == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    local result, analysisErr = self:applyAnalysis(
        self.pointA,
        self:createPoint(s)
    )

    if result == nil then
        return "[Terraform Plus] Analyse fehlgeschlagen: "
            .. tostring(analysisErr)
    end

    return string.format(
        "[Terraform Plus] Punkt B gesetzt: X=%.2f Z=%.2f H=%.3f m | Zellen=%d",
        self.pointB.x,
        self.pointB.z,
        self.pointB.terrainY,
        #self.area.samples
    )
end


-- tpMeasure
function TerraformPlus:consoleCommandMeasure()

    local m = self.measurement
    local prefix = "A -> B"

    if m == nil
        and self.selection ~= nil
        and self.selection.preview ~= nil then

        m = self.selection.preview.measurement
        prefix = "LIVE A -> B"
    end

    if m == nil then
        return "[Terraform Plus] Keine Messung vorhanden"
    end

    return string.format(
        "[Terraform Plus] %s | Distanz=%.2f m | DeltaH=%+.3f m | Steigung=%+.2f%% | Winkel=%+.2f Grad",
        prefix,
        m.distance,
        m.heightDifference,
        m.slopePercent,
        m.slopeAngle
    )
end


-- tpProfile
function TerraformPlus:consoleCommandProfile()

    local p = self.profile

    if p == nil
        and self.selection ~= nil
        and self.selection.preview ~= nil then

        p = self.selection.preview.profile
    end

    if p == nil then
        return "[Terraform Plus] Kein Profil vorhanden"
    end

    local cutPosition = "keine"
    local fillPosition = "keine"

    if p.maxCutIndex ~= nil then

        local s = p.samples[p.maxCutIndex]

        cutPosition = string.format(
            "%.2f m ab A (X=%.2f Z=%.2f)",
            s.distanceFromA,
            s.x,
            s.z
        )
    end

    if p.maxFillIndex ~= nil then

        local s = p.samples[p.maxFillIndex]

        fillPosition = string.format(
            "%.2f m ab A (X=%.2f Z=%.2f)",
            s.distanceFromA,
            s.x,
            s.z
        )
    end

    return string.format(
        "[Terraform Plus] PROFIL | Samples=%d | Schritt=%.2f m | Min=%.3f m | Max=%.3f m | SteilsterAbschnitt=%+.2f%% | Abtrag=%.3f m2 | Auftrag=%.3f m2 | Netto=%+.3f m2 | MaxAbtrag=%.3f m bei %s | MaxAuftrag=%.3f m bei %s",
        #p.samples,
        p.step,
        p.minHeight,
        p.maxHeight,
        p.steepestSegment,
        p.cutArea,
        p.fillArea,
        p.netArea,
        p.maxCutDepth,
        cutPosition,
        p.maxFillDepth,
        fillPosition
    )
end


-- tpVolume
function TerraformPlus:consoleCommandVolume()

    local a = self.area
    local prefix = "VOLUMEN"

    if a == nil
        and self.selection ~= nil
        and self.selection.preview ~= nil then

        a = self.selection.preview.area
        prefix = "LIVE-VOLUMEN"
    end

    if a == nil then
        return "[Terraform Plus] Keine 2D-Analyse vorhanden"
    end

    local cutPosition = "keine"
    local fillPosition = "keine"

    if a.maxCutSample ~= nil then

        cutPosition = string.format(
            "X=%.2f Z=%.2f",
            a.maxCutSample.x,
            a.maxCutSample.z
        )
    end

    if a.maxFillSample ~= nil then

        fillPosition = string.format(
            "X=%.2f Z=%.2f",
            a.maxFillSample.x,
            a.maxFillSample.z
        )
    end

    return string.format(
        "[Terraform Plus] %s | Laenge=%.2f m | Breite=%.2f m | Flaeche=%.2f m2 | Raster=%dx%d | Zellen=%d | Zellgroesse=%.2fx%.2f m | Abtrag=%.3f m3 | Auftrag=%.3f m3 | Netto=%+.3f m3 | MaxAbtrag=%.3f m (%s) | MaxAuftrag=%.3f m (%s)",
        prefix,
        a.distance,
        a.width,
        a.area,
        a.lengthCells,
        a.widthCells,
        #a.samples,
        a.cellLength,
        a.cellWidth,
        a.cutVolume,
        a.fillVolume,
        a.netVolume,
        a.maxCutDepth,
        cutPosition,
        a.maxFillDepth,
        fillPosition
    )
end


-- Gemeinsame Konfiguration fuer Breite und Raster.
function TerraformPlus:changeAreaConfig(
    field,
    value,
    minValue,
    maxValue,
    description
)

    if value == nil or value == "" then

        return string.format(
            "[Terraform Plus] %s: %.2f m",
            description,
            self[field]
        )
    end

    local number = tonumber(value)

    if number == nil
        or number ~= number
        or number < minValue
        or number > maxValue then

        return string.format(
            "[Terraform Plus] %s muss zwischen %.1f und %.1f m liegen",
            description,
            minValue,
            maxValue
        )
    end

    local newWidth =
        field == "areaWidth" and number or self.areaWidth

    local newStep =
        field == "areaStep" and number or self.areaStep

    -- Vorhandene bestaetigte Messung aktualisieren.
    if self.pointA ~= nil and self.pointB ~= nil then

        local ok, area, err = pcall(
            TerrainArea.build,
            self.pointA,
            self.pointB,
            newWidth,
            newStep
        )

        if not ok then
            return "[Terraform Plus] Rasterfehler: "
                .. tostring(area)
        end

        if area == nil then
            return "[Terraform Plus] Rasterfehler: "
                .. tostring(err)
        end

        self.area = area
    end

    self[field] = number

    if TerrainSelection ~= nil then
        TerrainSelection.invalidate(self)
    end

    return string.format(
        "[Terraform Plus] %s: %.2f m",
        description,
        number
    )
end


-- tpWidth
function TerraformPlus:consoleCommandWidth(value)

    return self:changeAreaConfig(
        "areaWidth",
        value,
        TerrainArea.MIN_WIDTH,
        TerrainArea.MAX_WIDTH,
        "Arbeitsbreite"
    )
end


-- tpGridStep
function TerraformPlus:consoleCommandGridStep(value)

    return self:changeAreaConfig(
        "areaStep",
        value,
        TerrainArea.MIN_STEP,
        TerrainArea.MAX_STEP,
        "Rasterabstand"
    )
end


-- tpPreview
function TerraformPlus:consoleCommandPreview()

    self.previewEnabled = not self.previewEnabled

    return "[Terraform Plus] 1D-Vorschau "
        .. (self.previewEnabled and "aktiviert" or "deaktiviert")
end


-- tpAreaVisual
function TerraformPlus:consoleCommandAreaVisual()

    self.areaEnabled = not self.areaEnabled

    return "[Terraform Plus] 2D-Vorschau "
        .. (self.areaEnabled and "aktiviert" or "deaktiviert")
end


-- tpRefresh
function TerraformPlus:consoleCommandRefresh()

    if self.selection ~= nil and self.selection.active then
        return "[Terraform Plus] Zuerst tpConfirm oder tpCancel"
    end

    if self.pointA == nil or self.pointB == nil then
        return "[Terraform Plus] Beide Messpunkte erforderlich"
    end

    local heightA, errA = self:getHeightAtPoint(
        self.pointA
    )

    if heightA == nil then
        return "[Terraform Plus] Fehler A: " .. tostring(errA)
    end

    local heightB, errB = self:getHeightAtPoint(
        self.pointB
    )

    if heightB == nil then
        return "[Terraform Plus] Fehler B: " .. tostring(errB)
    end

    local a = {
        x = self.pointA.x,
        z = self.pointA.z,
        terrainY = heightA
    }

    local b = {
        x = self.pointB.x,
        z = self.pointB.z,
        terrainY = heightB
    }

    local result, err = self:applyAnalysis(a, b)

    if result == nil then
        return "[Terraform Plus] Aktualisierung fehlgeschlagen: "
            .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] Profil aktualisiert | 1D=%d Samples | 2D=%d Zellen | Abtrag=%.3f m3 | Auftrag=%.3f m3",
        #self.profile.samples,
        #self.area.samples,
        self.area.cutVolume,
        self.area.fillVolume
    )
end


-- tpVisual
function TerraformPlus:consoleCommandVisual()

    self.visualEnabled = not self.visualEnabled

    return "[Terraform Plus] Visualisierung "
        .. (self.visualEnabled and "aktiviert" or "deaktiviert")
end


-- tpClear
function TerraformPlus:consoleCommandClear()

    self.selection = nil

    self.pointA = nil
    self.pointB = nil

    self.measurement = nil
    self.profile = nil
    self.area = nil

    return "[Terraform Plus] Messpunkte geloescht"
end


-- tpSelect
function TerraformPlus:consoleCommandSelect()

    if TerrainSelection == nil then
        return "[Terraform Plus] TerrainSelection nicht geladen"
    end

    local ok, err = TerrainSelection.begin(self)

    if not ok then
        return "[Terraform Plus] " .. tostring(err)
    end

    self.visualEnabled = true

    return "[Terraform Plus] Auswahl aktiv ("
        .. self.cursorMode
        .. "). tpAnchor zum Fixieren von A"
end


-- tpAnchor
function TerraformPlus:consoleCommandAnchor()

    if TerrainSelection == nil then
        return "[Terraform Plus] TerrainSelection nicht geladen"
    end

    local point, err = TerrainSelection.anchor(self)

    if point == nil then
        return "[Terraform Plus] " .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] Startpunkt fixiert: X=%.2f Z=%.2f H=%.3f m | tpConfirm fuer B",
        point.x,
        point.z,
        point.terrainY
    )
end


-- tpConfirm
function TerraformPlus:consoleCommandConfirm()

    if TerrainSelection == nil then
        return "[Terraform Plus] TerrainSelection nicht geladen"
    end

    local result, err = TerrainSelection.confirm(self)

    if result == nil then
        return "[Terraform Plus] Auswahl nicht bestaetigt: "
            .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] Auswahl bestaetigt | Distanz=%.2f m | Breite=%.2f m | Zellen=%d | Abtrag=%.3f m3 | Auftrag=%.3f m3",
        self.measurement.distance,
        self.areaWidth,
        #self.area.samples,
        self.area.cutVolume,
        self.area.fillVolume
    )
end


-- tpCancel
function TerraformPlus:consoleCommandCancel()

    if TerrainSelection ~= nil
        and TerrainSelection.cancel(self) then

        return "[Terraform Plus] Auswahl abgebrochen; vorherige Messung wiederhergestellt"
    end

    return "[Terraform Plus] Keine aktive Auswahl"
end


-- tpSelection
function TerraformPlus:consoleCommandSelection()

    local selection = self.selection

    if selection == nil or not selection.active then
        return "[Terraform Plus] Auswahlmodus AUS"
    end

    if selection.stage == "A" then

        return "[Terraform Plus] Auswahlmodus EIN ("
            .. self.cursorMode
            .. ") | Punkt A mit tpAnchor setzen"
    end

    return "[Terraform Plus] Auswahlmodus EIN ("
        .. self.cursorMode
        .. ") | Punkt B mit tpConfirm setzen"
end


-- Callback: Starten oder Abbrechen.
function TerraformPlus:onInputSelect()

    local message

    if self.selection ~= nil and self.selection.active then
        message = self:consoleCommandCancel()
    else
        message = self:consoleCommandSelect()
    end

    print(message)
end


-- Callback: A oder B setzen.
function TerraformPlus:onInputPlace()

    local selection = self.selection

    if selection == nil or not selection.active then
        print("[Terraform Plus] Erst Auswahl starten")
        return
    end

    local message

    if selection.stage == "A" then
        message = self:consoleCommandAnchor()
    else
        message = self:consoleCommandConfirm()
    end

    print(message)
end


-- Callback: Auswahl abbrechen.
function TerraformPlus:onInputCancel()

    print(self:consoleCommandCancel())
end


-- Karte entladen.
function TerraformPlus:deleteMap()

    self.mapActive = false

    if self.commandsRegistered then

        for _, command in ipairs(self.COMMANDS) do
            removeConsoleCommand(command[1])
        end

        self.commandsRegistered = false
    end

    if g_inputBinding ~= nil
        and type(g_inputBinding.removeActionEvent)
            == "function" then

        for _, eventId in ipairs(self.actionEventIds or {}) do

            pcall(
                g_inputBinding.removeActionEvent,
                g_inputBinding,
                eventId
            )
        end
    end

    self.actionEventIds = {}

    self.selection = nil

    self.pointA = nil
    self.pointB = nil
    self.measurement = nil
    self.profile = nil
    self.area = nil

    self.visualEnabled = false
    self.previewEnabled = false
    self.areaEnabled = false

    print("[Terraform Plus] Karte entladen")
end


addModEventListener(TerraformPlus)
