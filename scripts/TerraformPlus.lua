
-- Terraform Plus
-- Version: 0.0.8.0
-- Interactive selection and read-only terrain analysis

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.8.0"


-- Alle Konsolenbefehle
TerraformPlus.COMMANDS = {
    {"tpHeight", "Zeigt die Gelaendehoehe", "consoleCommandHeight"},
    {"tpSetA", "Setzt Messpunkt A", "consoleCommandSetA"},
    {"tpSetB", "Setzt Messpunkt B", "consoleCommandSetB"},
    {"tpMeasure", "Zeigt Entfernung und Steigung", "consoleCommandMeasure"},
    {"tpProfile", "Zeigt das 1D-Gelaendeprofil", "consoleCommandProfile"},
    {"tpPreview", "Schaltet die 1D-Vorschau um", "consoleCommandPreview"},
    {"tpWidth", "Setzt die Arbeitsbreite", "consoleCommandWidth"},
    {"tpGridStep", "Setzt den Rasterabstand", "consoleCommandGridStep"},
    {"tpVolume", "Zeigt die 2D-Volumenberechnung", "consoleCommandVolume"},
    {"tpAreaVisual", "Schaltet die 2D-Vorschau um", "consoleCommandAreaVisual"},
    {"tpRefresh", "Berechnet alle Analysen neu", "consoleCommandRefresh"},
    {"tpVisual", "Schaltet alle Visualisierungen um", "consoleCommandVisual"},
    {"tpClear", "Loescht die Messpunkte", "consoleCommandClear"},

    -- Neue Befehle
    {"tpSelect", "Startet interaktive Auswahl", "consoleCommandSelect"},
    {"tpAnchor", "Fixiert den Startpunkt der Auswahl", "consoleCommandAnchor"},
    {"tpConfirm", "Bestaetigt die Auswahl", "consoleCommandConfirm"},
    {"tpCancel", "Bricht die Auswahl ab", "consoleCommandCancel"},
    {"tpSelection", "Zeigt den Auswahlstatus", "consoleCommandSelection"}
}


-- Messpunkt als unabhaengige Tabelle speichern.
function TerraformPlus:createPoint(sample)

    return {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }
end


-- Spielerposition und Terrainhoehe abfragen.
function TerraformPlus:getCurrentSample()

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAtPlayer)
            ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local ok, sample, err = pcall(
        TerrainAdapter.getHeightAtPlayer
    )

    if not ok then
        return nil, "Lua-Fehler: " .. tostring(sample)
    end

    if sample == nil then
        return nil, tostring(
            err or "Spielerposition nicht verfuegbar"
        )
    end

    return sample, nil
end


-- Terrainhoehe an gespeicherten Koordinaten.
function TerraformPlus:getHeightAtPoint(point)

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt)
            ~= "function" then

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
        return nil, tostring(
            err or "Ungueltige Terrainhoehe"
        )
    end

    return height, nil
end


-- Durchschnittliche Steigung zwischen A und B.
function TerraformPlus:calculateSlope(a, b)

    local dx = b.x - a.x
    local dz = b.z - a.z

    local distance = math.sqrt(
        dx * dx + dz * dz
    )

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    local dh = b.terrainY - a.terrainY

    return {
        distance = distance,
        heightDifference = dh,

        slopePercent =
            dh / distance * 100,

        slopeAngle = math.deg(
            math.atan(dh / distance)
        )
    }, nil
end


-- Alle Analysen berechnen, ohne den Zustand zu veraendern.
-- gridStepOverride wird nur fuer Live-Vorschauen verwendet.
function TerraformPlus:buildAnalysis(
    pointA,
    pointB,
    gridStepOverride
)

    local measurement, err = self:calculateSlope(
        pointA,
        pointB
    )

    if measurement == nil then
        return nil, err
    end

    -- 1D-Profil
    if TerrainProfile == nil
        or type(TerrainProfile.build) ~= "function" then

        return nil, "TerrainProfile nicht geladen"
    end

    local ok, profile, profileErr = pcall(
        TerrainProfile.build,
        pointA,
        pointB
    )

    if not ok then
        return nil, "Profil-Lua-Fehler: " .. tostring(profile)
    end

    if profile == nil then
        return nil, tostring(profileErr)
    end

    -- 2D-Raster
    if TerrainArea == nil
        or type(TerrainArea.build) ~= "function" then

        return nil, "TerrainArea nicht geladen"
    end

    local step = gridStepOverride or self.areaStep

    local areaOk, area, areaErr = pcall(
        TerrainArea.build,
        pointA,
        pointB,
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


-- Erfolgreiche Analyse uebernehmen.
function TerraformPlus:applyAnalysis(pointA, pointB)

    local result, err = self:buildAnalysis(
        pointA,
        pointB
    )

    if result == nil then
        return nil, err
    end

    self.pointA = pointA
    self.pointB = pointB

    self.measurement = result.measurement
    self.profile = result.profile
    self.area = result.area

    return result, nil
end


-- Karte initialisieren.
function TerraformPlus:loadMap()

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

    self.visualEnabled = true
    self.previewEnabled = true
    self.areaEnabled = true

    self.commandsRegistered = false

    for _, command in ipairs(self.COMMANDS) do

        addConsoleCommand(
            command[1],
            command[2],
            command[3],
            self
        )
    end

    self.commandsRegistered = true

    print(
        "[Terraform Plus] Mod geladen - Version "
        .. self.VERSION
    )

    print("[Terraform Plus] Auswahlsteuerung bereit")
end


-- Live-Auswahl aktualisieren.
-- Keine direkte Eingabesteuerung.
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

        -- Bei einem unerwarteten Fehler Zustand restaurieren
        TerrainSelection.cancel(self)
    end
end


-- Zeichenfunktion
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

    local pointB = self.pointB
    local measurement = self.measurement
    local profile = self.profile
    local area = self.area

    -- Zwischenberechnete Auswahl anzeigen
    if active and selection.preview ~= nil then

        pointB = selection.preview.pointB
        measurement = selection.preview.measurement
        profile = selection.preview.profile
        area = selection.preview.area
    end

    -- Vorhandene Visualisierung verwenden
    if self.pointA ~= nil then

        local ok, err = pcall(
            TerrainVisualizer.draw,
            self.pointA,
            pointB,
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

    -- Interaktiven Cursor zusaetzlich zeichnen
    if active then

        local ok, err = pcall(
            TerrainSelection.draw,
            self
        )

        if not ok then

            self.visualEnabled = false

            print(
                "[Terraform Plus] Auswahlzeichnung deaktiviert: "
                .. tostring(err)
            )
        end
    end
end


-- tpHeight
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


-- tpSetA
function TerraformPlus:consoleCommandSetA()

    -- Im Auswahlmodus als tpAnchor verwenden
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


-- tpSetB
function TerraformPlus:consoleCommandSetB()

    -- Im Auswahlmodus als tpConfirm verwenden
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

    local pointB = self:createPoint(s)

    local result, analysisErr = self:applyAnalysis(
        self.pointA,
        pointB
    )

    if result == nil then

        return "[Terraform Plus] Analyse fehlgeschlagen: "
            .. tostring(analysisErr)
    end

    print(string.format(
        "[Terraform Plus] Terrainprofil: %d Samples",
        #self.profile.samples
    ))

    print(string.format(
        "[Terraform Plus] Terrainraster: %d x %d = %d Zellen",
        self.area.lengthCells,
        self.area.widthCells,
        #self.area.samples
    ))

    return string.format(
        "[Terraform Plus] Punkt B gesetzt: X=%.2f Z=%.2f H=%.3f m",
        self.pointB.x,
        self.pointB.z,
        self.pointB.terrainY
    )
end


-- tpMeasure
function TerraformPlus:consoleCommandMeasure()

    local m = self.measurement
    local prefix = "[Terraform Plus] A -> B"

    if m == nil
        and self.selection ~= nil
        and self.selection.preview ~= nil then

        m = self.selection.preview.measurement
        prefix = "[Terraform Plus] LIVE A -> B"
    end

    if m == nil then
        return "[Terraform Plus] Keine Messung vorhanden"
    end

    return string.format(
        "%s | Distanz=%.2f m | DeltaH=%+.3f m | Steigung=%+.2f%% | Winkel=%+.2f Grad",
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
    local prefix = "PROFIL"

    if p == nil
        and self.selection ~= nil
        and self.selection.preview ~= nil then

        p = self.selection.preview.profile
        prefix = "LIVE-PROFIL"
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
        "[Terraform Plus] %s | Samples=%d | Schritt=%.2f m | Min=%.3f m | Max=%.3f m | SteilsterAbschnitt=%+.2f%% | Abtrag=%.3f m2 | Auftrag=%.3f m2 | Netto=%+.3f m2 | MaxAbtrag=%.3f m bei %s | MaxAuftrag=%.3f m bei %s",
        prefix,
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
        prefix = "LIVE-VOLUMEN (grobes Raster)"
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


-- Gemeinsame Funktion fuer tpWidth und tpGridStep.
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

    -- Bestehende, bestaetigte Messung neu auswerten
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

    -- Bei interaktiver Auswahl die Live-Vorschau verwerfen
    if self.selection ~= nil
        and self.selection.active then

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
        .. (
            self.previewEnabled
            and "aktiviert"
            or "deaktiviert"
        )
end


-- tpAreaVisual
function TerraformPlus:consoleCommandAreaVisual()

    self.areaEnabled = not self.areaEnabled

    return "[Terraform Plus] 2D-Vorschau "
        .. (
            self.areaEnabled
            and "aktiviert"
            or "deaktiviert"
        )
end


-- tpRefresh
function TerraformPlus:consoleCommandRefresh()

    if self.selection ~= nil and self.selection.active then

        return "[Terraform Plus] Zuerst tpConfirm oder tpCancel ausfuehren"
    end

    if self.pointA == nil or self.pointB == nil then
        return "[Terraform Plus] Beide Messpunkte erforderlich"
    end

    local yA, errA = self:getHeightAtPoint(
        self.pointA
    )

    if yA == nil then
        return "[Terraform Plus] Fehler bei A: " .. tostring(errA)
    end

    local yB, errB = self:getHeightAtPoint(
        self.pointB
    )

    if yB == nil then
        return "[Terraform Plus] Fehler bei B: " .. tostring(errB)
    end

    -- Neue Punktkopien verwenden
    local a = {
        x = self.pointA.x,
        z = self.pointA.z,
        terrainY = yA
    }

    local b = {
        x = self.pointB.x,
        z = self.pointB.z,
        terrainY = yB
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
        .. (
            self.visualEnabled
            and "aktiviert"
            or "deaktiviert"
        )
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

    return "[Terraform Plus] Auswahl aktiv. Positionieren und tpAnchor ausfuehren"
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
        "[Terraform Plus] Startpunkt fixiert: X=%.2f Z=%.2f H=%.3f m | Jetzt zu B gehen und tpConfirm",
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

        return "[Terraform Plus] Auswahlmodus AUS (tpSelect zum Starten)"
    end

    if selection.stage == "A" then

        return "[Terraform Plus] Auswahlmodus EIN | Startpunkt mit tpAnchor fixieren"
    end

    return "[Terraform Plus] Auswahlmodus EIN | Endpunkt folgt Spieler | tpConfirm oder tpCancel"
end


-- Beim Kartenwechsel aufraeumen.
function TerraformPlus:deleteMap()

    if self.commandsRegistered then

        for _, command in ipairs(self.COMMANDS) do
            removeConsoleCommand(command[1])
        end

        self.commandsRegistered = false
    end

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


-- Registrierung bei der GIANTS Engine
addModEventListener(TerraformPlus)
