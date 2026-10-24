
-- Terraform Plus
-- Version: 0.0.7.0
-- Terrain profile and 2D volume analysis

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.7.0"

TerraformPlus.COMMANDS = {
    {
        name = "tpHeight",
        description = "Zeigt die Gelaendehoehe",
        callback = "consoleCommandHeight"
    },
    {
        name = "tpSetA",
        description = "Setzt Messpunkt A",
        callback = "consoleCommandSetA"
    },
    {
        name = "tpSetB",
        description = "Setzt Messpunkt B",
        callback = "consoleCommandSetB"
    },
    {
        name = "tpMeasure",
        description = "Berechnet Entfernung und Steigung",
        callback = "consoleCommandMeasure"
    },
    {
        name = "tpProfile",
        description = "Zeigt die 1D-Profilanalyse",
        callback = "consoleCommandProfile"
    },
    {
        name = "tpPreview",
        description = "Schaltet die 1D-Vorschau um",
        callback = "consoleCommandPreview"
    },
    {
        name = "tpWidth",
        description = "Zeigt oder setzt die 2D-Arbeitsbreite",
        callback = "consoleCommandWidth"
    },
    {
        name = "tpGridStep",
        description = "Zeigt oder setzt den 2D-Rasterabstand",
        callback = "consoleCommandGridStep"
    },
    {
        name = "tpVolume",
        description = "Zeigt die 2D-Volumenanalyse",
        callback = "consoleCommandVolume"
    },
    {
        name = "tpAreaVisual",
        description = "Schaltet die 2D-Vorschau um",
        callback = "consoleCommandAreaVisual"
    },
    {
        name = "tpRefresh",
        description = "Berechnet alle Messdaten neu",
        callback = "consoleCommandRefresh"
    },
    {
        name = "tpVisual",
        description = "Schaltet alle Visualisierungen um",
        callback = "consoleCommandVisual"
    },
    {
        name = "tpClear",
        description = "Loescht beide Messpunkte",
        callback = "consoleCommandClear"
    }
}


-- Allgemeine Hilfsfunktion: aktuelle Spielerposition
function TerraformPlus:getCurrentSample()

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAtPlayer) ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local success, sample, err = pcall(
        TerrainAdapter.getHeightAtPlayer
    )

    if not success then
        return nil, "Lua-Fehler: " .. tostring(sample)
    end

    if sample == nil then
        return nil, tostring(err or "Unbekannter Fehler")
    end

    return sample, nil
end


-- Hilfsfunktion: aktuelle Hoehe an gespeicherten Koordinaten
function TerraformPlus:getHeightAtPoint(point)

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt) ~= "function" then

        return nil, "TerrainAdapter nicht verfuegbar"
    end

    local success, height, err = pcall(
        TerrainAdapter.getHeightAt,
        point.x,
        point.z
    )

    if not success then
        return nil, "Lua-Fehler: " .. tostring(height)
    end

    if type(height) ~= "number" then
        return nil, tostring(err or "Ungueltige Terrainhoehe")
    end

    return height, nil
end


-- Messpunkt als neue Tabelle speichern
function TerraformPlus:createPoint(sample)

    return {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }
end


-- Durchschnittliche Steigung berechnen
function TerraformPlus:calculateSlope(pointA, pointB)

    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    local distance = math.sqrt(dx * dx + dz * dz)

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    local heightDifference =
        pointB.terrainY - pointA.terrainY

    return {
        distance = distance,
        heightDifference = heightDifference,

        slopePercent =
            heightDifference / distance * 100,

        slopeAngle = math.deg(
            math.atan(heightDifference / distance)
        )
    }, nil
end


-- Berechnet nur das 2D-Raster mit den uebergebenen Einstellungen.
-- Bereits gespeicherte Ergebnisse werden dabei nicht veraendert.
function TerraformPlus:buildArea(pointA, pointB, width, step)

    if TerrainArea == nil
        or type(TerrainArea.build) ~= "function" then

        return nil, "TerrainArea nicht verfuegbar"
    end

    local success, area, err = pcall(
        TerrainArea.build,
        pointA,
        pointB,
        width,
        step
    )

    if not success then
        return nil, "Lua-Fehler: " .. tostring(area)
    end

    if area == nil then
        return nil, tostring(err or "Unbekannter Rasterfehler")
    end

    return area, nil
end


-- Berechnet alle Analysen, ohne die gespeicherten
-- Messpunkte und Ergebnisse vorzeitig zu veraendern.
function TerraformPlus:buildAnalysis(pointA, pointB)

    local measurement, err = self:calculateSlope(
        pointA,
        pointB
    )

    if measurement == nil then
        return nil, err
    end

    if TerrainProfile == nil
        or type(TerrainProfile.build) ~= "function" then

        return nil, "TerrainProfile nicht verfuegbar"
    end

    local success, profile, profileErr = pcall(
        TerrainProfile.build,
        pointA,
        pointB
    )

    if not success then
        return nil, "Profil-Lua-Fehler: " .. tostring(profile)
    end

    if profile == nil then
        return nil, tostring(profileErr)
    end

    local area, areaErr = self:buildArea(
        pointA,
        pointB,
        self.areaWidth,
        self.areaStep
    )

    if area == nil then
        return nil, areaErr
    end

    return {
        measurement = measurement,
        profile = profile,
        area = area
    }, nil
end


-- Uebernimmt eine vollstaendig erfolgreiche Berechnung.
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


-- Karteninitialisierung
function TerraformPlus:loadMap()

    self.pointA = nil
    self.pointB = nil

    self.measurement = nil
    self.profile = nil
    self.area = nil

    -- Standardeinstellungen fuer das Raster
    self.areaWidth = 10.0
    self.areaStep = 2.0

    self.visualEnabled = true
    self.previewEnabled = true
    self.areaEnabled = true

    self.commandsRegistered = false

    for _, command in ipairs(self.COMMANDS) do

        addConsoleCommand(
            command.name,
            command.description,
            command.callback,
            self
        )
    end

    self.commandsRegistered = true

    print(
        "[Terraform Plus] Mod geladen - Version "
        .. self.VERSION
    )

    print("[Terraform Plus] TerrainAdapter bereit")
    print("[Terraform Plus] TerrainProfile bereit")
    print("[Terraform Plus] TerrainArea bereit")
    print("[Terraform Plus] TerrainVisualizer bereit")
end


-- Render-Callback
function TerraformPlus:draw()

    if not self.visualEnabled
        or self.pointA == nil then

        return
    end

    if TerrainVisualizer == nil
        or type(TerrainVisualizer.draw) ~= "function" then

        self.visualEnabled = false

        print(
            "[Terraform Plus] TerrainVisualizer nicht verfuegbar"
        )

        return
    end

    local success, err = pcall(
        TerrainVisualizer.draw,
        self.pointA,
        self.pointB,
        self.measurement,
        self.profile,
        self.previewEnabled,
        self.area,
        self.areaEnabled
    )

    if not success then

        self.visualEnabled = false

        print(
            "[Terraform Plus] Visualisierung deaktiviert: "
            .. tostring(err)
        )
    end
end


-- tpHeight
function TerraformPlus:consoleCommandHeight()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] X=%.2f Z=%.2f | Terrainhoehe=%.3f m",
        sample.x,
        sample.z,
        sample.terrainY
    )
end


-- tpSetA
function TerraformPlus:consoleCommandSetA()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    self.pointA = self:createPoint(sample)

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

    if self.pointA == nil then
        return "[Terraform Plus] Zuerst Punkt A setzen"
    end

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    local pointB = self:createPoint(sample)

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

    if self.pointA == nil or self.pointB == nil then
        return "[Terraform Plus] Beide Messpunkte fehlen"
    end

    local result = self.measurement

    if result == nil then
        return "[Terraform Plus] Keine Messung vorhanden"
    end

    return string.format(
        "[Terraform Plus] A -> B | Distanz=%.2f m | DeltaH=%+.3f m | Steigung=%+.2f%% | Winkel=%+.2f Grad",
        result.distance,
        result.heightDifference,
        result.slopePercent,
        result.slopeAngle
    )
end


-- tpProfile
function TerraformPlus:consoleCommandProfile()

    if self.profile == nil then
        return "[Terraform Plus] Kein Profil vorhanden"
    end

    local p = self.profile

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


-- tpWidth [Meter]
function TerraformPlus:consoleCommandWidth(value)

    if value == nil or value == "" then

        return string.format(
            "[Terraform Plus] Arbeitsbreite: %.2f m (tpWidth 10)",
            self.areaWidth
        )
    end

    local width = tonumber(value)

    if width == nil
        or width ~= width
        or width < TerrainArea.MIN_WIDTH
        or width > TerrainArea.MAX_WIDTH then

        return "[Terraform Plus] Breite muss zwischen 1 und 80 m liegen"
    end

    -- Noch keine Punkte vorhanden
    if self.pointA == nil or self.pointB == nil then

        self.areaWidth = width

        return string.format(
            "[Terraform Plus] Arbeitsbreite: %.2f m",
            width
        )
    end

    -- Neues Raster zuerst berechnen
    local area, err = self:buildArea(
        self.pointA,
        self.pointB,
        width,
        self.areaStep
    )

    if area == nil then
        return "[Terraform Plus] Breite unveraendert: "
            .. tostring(err)
    end

    self.areaWidth = width
    self.area = area

    return string.format(
        "[Terraform Plus] Arbeitsbreite: %.2f m | %d Rasterzellen",
        width,
        #area.samples
    )
end


-- tpGridStep [Meter]
function TerraformPlus:consoleCommandGridStep(value)

    if value == nil or value == "" then

        return string.format(
            "[Terraform Plus] Rasterabstand: %.2f m (tpGridStep 2)",
            self.areaStep
        )
    end

    local step = tonumber(value)

    if step == nil
        or step ~= step
        or step < TerrainArea.MIN_STEP
        or step > TerrainArea.MAX_STEP then

        return "[Terraform Plus] Rasterabstand muss zwischen 0.5 und 5 m liegen"
    end

    if self.pointA == nil or self.pointB == nil then

        self.areaStep = step

        return string.format(
            "[Terraform Plus] Rasterabstand: %.2f m",
            step
        )
    end

    local area, err = self:buildArea(
        self.pointA,
        self.pointB,
        self.areaWidth,
        step
    )

    if area == nil then
        return "[Terraform Plus] Rasterabstand unveraendert: "
            .. tostring(err)
    end

    self.areaStep = step
    self.area = area

    return string.format(
        "[Terraform Plus] Rasterabstand: %.2f m | %d Rasterzellen",
        step,
        #area.samples
    )
end


-- tpVolume
function TerraformPlus:consoleCommandVolume()

    if self.area == nil then
        return "[Terraform Plus] Keine 2D-Analyse vorhanden"
    end

    local a = self.area

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
        "[Terraform Plus] VOLUMEN | Laenge=%.2f m | Breite=%.2f m | Flaeche=%.2f m2 | Raster=%dx%d | Zellen=%d | Zellgroesse=%.2fx%.2f m | Abtrag=%.3f m3 | Auftrag=%.3f m3 | Netto=%+.3f m3 | MaxAbtrag=%.3f m (%s) | MaxAuftrag=%.3f m (%s)",
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


-- tpPreview: 1D Cut/Fill
function TerraformPlus:consoleCommandPreview()

    self.previewEnabled = not self.previewEnabled

    if self.previewEnabled then
        return "[Terraform Plus] 1D-Vorschau aktiviert"
    end

    return "[Terraform Plus] 1D-Vorschau deaktiviert"
end


-- tpAreaVisual: 2D Cut/Fill
function TerraformPlus:consoleCommandAreaVisual()

    self.areaEnabled = not self.areaEnabled

    if self.areaEnabled then
        return "[Terraform Plus] 2D-Vorschau aktiviert"
    end

    return "[Terraform Plus] 2D-Vorschau deaktiviert"
end


-- tpRefresh
function TerraformPlus:consoleCommandRefresh()

    if self.pointA == nil or self.pointB == nil then
        return "[Terraform Plus] Beide Messpunkte erforderlich"
    end

    local heightA, errA = self:getHeightAtPoint(
        self.pointA
    )

    if heightA == nil then
        return "[Terraform Plus] Fehler bei A: " .. tostring(errA)
    end

    local heightB, errB = self:getHeightAtPoint(
        self.pointB
    )

    if heightB == nil then
        return "[Terraform Plus] Fehler bei B: " .. tostring(errB)
    end

    -- Neue Punktkopien, damit bei einem Fehler
    -- der bisherige Messstand erhalten bleibt.
    local pointA = {
        x = self.pointA.x,
        z = self.pointA.z,
        terrainY = heightA
    }

    local pointB = {
        x = self.pointB.x,
        z = self.pointB.z,
        terrainY = heightB
    }

    local result, err = self:applyAnalysis(
        pointA,
        pointB
    )

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

    if self.visualEnabled then
        return "[Terraform Plus] Visualisierung aktiviert"
    end

    return "[Terraform Plus] Visualisierung deaktiviert"
end


-- tpClear
function TerraformPlus:consoleCommandClear()

    self.pointA = nil
    self.pointB = nil

    self.measurement = nil
    self.profile = nil
    self.area = nil

    return "[Terraform Plus] Messpunkte geloescht"
end


-- Aufraeumen beim Verlassen der Karte
function TerraformPlus:deleteMap()

    if self.commandsRegistered then

        for _, command in ipairs(self.COMMANDS) do
            removeConsoleCommand(command.name)
        end

        self.commandsRegistered = false
    end

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
