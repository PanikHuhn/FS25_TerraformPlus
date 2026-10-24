
-- Terraform Plus
-- Version: 0.0.6.0
-- Terrain measurement, profile analysis and cut/fill preview

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.6.0"


-- Registrierte Konsolenbefehle
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
        description = "Zeigt das Gelaendeprofil und Cut/Fill-Werte",
        callback = "consoleCommandProfile"
    },
    {
        name = "tpPreview",
        description = "Schaltet die Cut/Fill-Vorschau um",
        callback = "consoleCommandPreview"
    },
    {
        name = "tpRefresh",
        description = "Berechnet das Profil erneut",
        callback = "consoleCommandRefresh"
    },
    {
        name = "tpVisual",
        description = "Schaltet die gesamte Visualisierung um",
        callback = "consoleCommandVisual"
    },
    {
        name = "tpClear",
        description = "Loescht alle Messpunkte",
        callback = "consoleCommandClear"
    }
}


-- Formatiert eine Gelaendehoehe.
function TerraformPlus:formatHeight(sample)

    return string.format(
        "[Terraform Plus] X=%.2f Z=%.2f | Terrainhoehe=%.3f m",
        sample.x,
        sample.z,
        sample.terrainY
    )
end


-- Liest die aktuelle Spielerposition.
function TerraformPlus:getCurrentSample()

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAtPlayer)
            ~= "function" then

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


-- Liest die Gelaendehoehe an einem gespeicherten Punkt.
function TerraformPlus:getHeightAtPoint(point)

    if TerrainAdapter == nil
        or type(TerrainAdapter.getHeightAt)
            ~= "function" then

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


-- Erstellt eine unabhaengige Kopie eines Messpunkts.
function TerraformPlus:createPoint(sample)

    return {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }
end


-- Berechnet die durchschnittliche Steigung.
function TerraformPlus:calculateSlope(pointA, pointB)

    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    local distance = math.sqrt(
        dx * dx + dz * dz
    )

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    local heightDifference =
        pointB.terrainY - pointA.terrainY

    local slopePercent =
        heightDifference / distance * 100

    local slopeAngle = math.deg(
        math.atan(heightDifference / distance)
    )

    return {
        distance = distance,
        heightDifference = heightDifference,
        slopePercent = slopePercent,
        slopeAngle = slopeAngle
    }, nil
end


-- Berechnet alle Messdaten neu.
function TerraformPlus:rebuildAnalysis()

    self.measurement = nil
    self.profile = nil

    if self.pointA == nil or self.pointB == nil then
        return nil, "Beide Messpunkte muessen gesetzt sein"
    end

    -- Durchschnittliche Steigung
    local measurement, measurementError =
        self:calculateSlope(
            self.pointA,
            self.pointB
        )

    if measurement == nil then
        return nil, measurementError
    end

    self.measurement = measurement

    -- Gelaendeprofil
    if TerrainProfile == nil
        or type(TerrainProfile.build) ~= "function" then

        return nil, "TerrainProfile nicht verfuegbar"
    end

    local success, profile, profileError = pcall(
        TerrainProfile.build,
        self.pointA,
        self.pointB
    )

    if not success then
        return nil, "Lua-Fehler: " .. tostring(profile)
    end

    if profile == nil then
        return nil, tostring(profileError)
    end

    self.profile = profile

    return profile, nil
end


-- Initialisierung beim Laden der Karte.
function TerraformPlus:loadMap()

    self.pointA = nil
    self.pointB = nil

    self.measurement = nil
    self.profile = nil

    self.visualEnabled = true
    self.previewEnabled = true

    self.commandsRegistered = false

    -- Alle Konsolenbefehle registrieren
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

    print("[Terraform Plus] TerrainVisualizer bereit")
    print("[Terraform Plus] TerrainProfile bereit")
    print("[Terraform Plus] Cut/Fill-Vorschau bereit")
end


-- Visualisierung im Renderzyklus zeichnen.
function TerraformPlus:draw()

    if not self.visualEnabled then
        return
    end

    if self.pointA == nil then
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
        self.previewEnabled
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
        return "[Terraform Plus] Fehler: " .. err
    end

    return self:formatHeight(sample)
end


-- tpSetA
function TerraformPlus:consoleCommandSetA()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    self.pointA = self:createPoint(sample)

    -- Alten Endpunkt und alte Ergebnisse entfernen
    self.pointB = nil
    self.measurement = nil
    self.profile = nil

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
        return "[Terraform Plus] Zuerst Punkt A mit tpSetA setzen"
    end

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    self.pointB = self:createPoint(sample)

    -- Vollstaendiges Profil inklusive Cut/Fill neu berechnen
    local profile, profileError = self:rebuildAnalysis()

    if profile == nil then

        return "[Terraform Plus] Punkt B gesetzt, Profilfehler: "
            .. tostring(profileError)
    end

    print(string.format(
        "[Terraform Plus] Terrainprofil: %d Samples",
        #profile.samples
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
        return "[Terraform Plus] Beide Messpunkte muessen gesetzt sein"
    end

    local result, err = self:calculateSlope(
        self.pointA,
        self.pointB
    )

    if result == nil then
        return "[Terraform Plus] Fehler: " .. tostring(err)
    end

    self.measurement = result

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
        return "[Terraform Plus] Kein Profil vorhanden. tpSetA und tpSetB verwenden"
    end

    local p = self.profile

    local cutPosition = "keine"
    local fillPosition = "keine"

    if p.maxCutIndex ~= nil then

        local sample = p.samples[p.maxCutIndex]

        cutPosition = string.format(
            "%.2f m ab A (X=%.2f Z=%.2f)",
            sample.distanceFromA,
            sample.x,
            sample.z
        )
    end

    if p.maxFillIndex ~= nil then

        local sample = p.samples[p.maxFillIndex]

        fillPosition = string.format(
            "%.2f m ab A (X=%.2f Z=%.2f)",
            sample.distanceFromA,
            sample.x,
            sample.z
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


-- tpPreview
function TerraformPlus:consoleCommandPreview()

    self.previewEnabled = not self.previewEnabled

    if self.previewEnabled then
        return "[Terraform Plus] Cut/Fill-Vorschau aktiviert"
    end

    return "[Terraform Plus] Cut/Fill-Vorschau deaktiviert"
end


-- tpRefresh
-- Liest die Hoehen an den gespeicherten Punkten neu aus
-- und berechnet das gesamte Profil erneut.
function TerraformPlus:consoleCommandRefresh()

    if self.pointA == nil or self.pointB == nil then
        return "[Terraform Plus] Beide Messpunkte muessen gesetzt sein"
    end

    local heightA, errA = self:getHeightAtPoint(self.pointA)

    if heightA == nil then
        return "[Terraform Plus] Fehler bei Punkt A: "
            .. tostring(errA)
    end

    local heightB, errB = self:getHeightAtPoint(self.pointB)

    if heightB == nil then
        return "[Terraform Plus] Fehler bei Punkt B: "
            .. tostring(errB)
    end

    -- Erst aktualisieren, wenn beide Abfragen erfolgreich waren
    self.pointA.terrainY = heightA
    self.pointB.terrainY = heightB

    local profile, err = self:rebuildAnalysis()

    if profile == nil then
        return "[Terraform Plus] Aktualisierung fehlgeschlagen: "
            .. tostring(err)
    end

    return string.format(
        "[Terraform Plus] Profil aktualisiert | Samples=%d | Abtrag=%.3f m2 | Auftrag=%.3f m2",
        #profile.samples,
        profile.cutArea,
        profile.fillArea
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

    return "[Terraform Plus] Messpunkte geloescht"
end


-- Aufraeumen beim Verlassen der Karte.
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

    self.visualEnabled = false
    self.previewEnabled = false

    print("[Terraform Plus] Karte entladen")
end


-- GIANTS-Mod-Eventlistener registrieren
addModEventListener(TerraformPlus)
