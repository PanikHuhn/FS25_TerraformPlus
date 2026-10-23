-- Terraform Plus
-- Version: 0.0.5.0
-- Terrain measurement and profile analysis

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.5.0"

TerraformPlus.COMMANDS = {
    "tpHeight",
    "tpSetA",
    "tpSetB",
    "tpMeasure",
    "tpClear",
    "tpVisual",
    "tpProfile"
}


-- Formatiert eine einzelne Gelaendehoehe.
function TerraformPlus:formatHeight(sample)

    return string.format(
        "[Terraform Plus] X=%.2f Z=%.2f | Terrainhoehe=%.3f m",
        sample.x,
        sample.z,
        sample.terrainY
    )
end


-- Ermittelt aktuelle Spielerposition und Terrainhoehe.
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
        return nil, tostring(
            err or "Unbekannter Fehler"
        )
    end

    return sample, nil
end


-- Berechnet Entfernung und Steigung zwischen A und B.
function TerraformPlus:calculateSlope(pointA, pointB)

    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    local distance = math.sqrt(
        dx * dx + dz * dz
    )

    local heightDifference =
        pointB.terrainY - pointA.terrainY

    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    local slopePercent =
        (heightDifference / distance) * 100

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


-- Erstellt eine unabhaengige Kopie eines Messpunkts.
function TerraformPlus:createPoint(sample)

    return {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }
end


-- Wird beim Laden der Karte ausgefuehrt.
function TerraformPlus:loadMap()

    -- Messdaten initialisieren
    self.pointA = nil
    self.pointB = nil
    self.measurement = nil
    self.profile = nil

    -- Visualisierung standardmaessig aktivieren
    self.visualEnabled = true
    self.commandsRegistered = false

    -- Konsolenbefehle registrieren
    addConsoleCommand(
        "tpHeight",
        "Zeigt die aktuelle Gelaendehoehe",
        "consoleCommandHeight",
        self
    )

    addConsoleCommand(
        "tpSetA",
        "Setzt Messpunkt A",
        "consoleCommandSetA",
        self
    )

    addConsoleCommand(
        "tpSetB",
        "Setzt Messpunkt B",
        "consoleCommandSetB",
        self
    )

    addConsoleCommand(
        "tpMeasure",
        "Berechnet Entfernung und Steigung",
        "consoleCommandMeasure",
        self
    )

    addConsoleCommand(
        "tpClear",
        "Loescht beide Messpunkte",
        "consoleCommandClear",
        self
    )

    addConsoleCommand(
        "tpVisual",
        "Schaltet die Visualisierung um",
        "consoleCommandVisual",
        self
    )

    addConsoleCommand(
        "tpProfile",
        "Zeigt die Analyse des Gelaendeprofils",
        "consoleCommandProfile",
        self
    )

    self.commandsRegistered = true

    print(
        "[Terraform Plus] Mod geladen - Version "
        .. self.VERSION
    )

    print("[Terraform Plus] TerrainVisualizer bereit")
    print("[Terraform Plus] TerrainProfile bereit")
end


-- Wird durch die GIANTS Engine beim Zeichnen aufgerufen.
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

    -- Renderfehler abfangen
    local success, err = pcall(
        TerrainVisualizer.draw,
        self.pointA,
        self.pointB,
        self.measurement,
        self.profile
    )

    if not success then

        self.visualEnabled = false

        print(
            "[Terraform Plus] Visualisierung deaktiviert: "
            .. tostring(err)
        )
    end
end


-- Konsolenbefehl: tpHeight
function TerraformPlus:consoleCommandHeight()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    return self:formatHeight(sample)
end


-- Konsolenbefehl: tpSetA
function TerraformPlus:consoleCommandSetA()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    -- Startpunkt speichern
    self.pointA = self:createPoint(sample)

    -- Alte Messungen entfernen
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


-- Konsolenbefehl: tpSetB
function TerraformPlus:consoleCommandSetB()

    if self.pointA == nil then

        return "[Terraform Plus] Zuerst Punkt A mit tpSetA setzen"
    end

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    -- Endpunkt speichern
    self.pointB = self:createPoint(sample)

    -- Alte Ergebnisse entfernen
    self.measurement = nil
    self.profile = nil

    -- Steigung zwischen A und B berechnen
    local result, calculationError =
        self:calculateSlope(
            self.pointA,
            self.pointB
        )

    self.measurement = result

    if result == nil then

        return "[Terraform Plus] Punkt B gesetzt, Fehler: "
            .. calculationError
    end

    -- Neues Gelaendeprofil berechnen
    if TerrainProfile ~= nil
        and type(TerrainProfile.build) == "function" then

        local success, profile, profileError = pcall(
            TerrainProfile.build,
            self.pointA,
            self.pointB
        )

        if success and profile ~= nil then

            self.profile = profile

            print(string.format(
                "[Terraform Plus] Terrainprofil: %d Samples",
                #profile.samples
            ))

        else

            local errorMessage =
                success and profileError or profile

            print(
                "[Terraform Plus] Profilberechnung fehlgeschlagen: "
                .. tostring(errorMessage)
            )
        end

    else

        print(
            "[Terraform Plus] TerrainProfile nicht geladen"
        )
    end

    return string.format(
        "[Terraform Plus] Punkt B gesetzt: X=%.2f Z=%.2f H=%.3f m",
        self.pointB.x,
        self.pointB.z,
        self.pointB.terrainY
    )
end


-- Konsolenbefehl: tpMeasure
function TerraformPlus:consoleCommandMeasure()

    if self.pointA == nil or self.pointB == nil then

        return "[Terraform Plus] Beide Messpunkte muessen gesetzt sein"
    end

    local result, err = self:calculateSlope(
        self.pointA,
        self.pointB
    )

    if result == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    -- Ergebnis aktualisieren
    self.measurement = result

    return string.format(
        "[Terraform Plus] A -> B | Distanz=%.2f m | DeltaH=%+.3f m | Steigung=%+.2f%% | Winkel=%+.2f Grad",
        result.distance,
        result.heightDifference,
        result.slopePercent,
        result.slopeAngle
    )
end


-- Konsolenbefehl: tpProfile
function TerraformPlus:consoleCommandProfile()

    if self.profile == nil then

        return "[Terraform Plus] Kein Profil vorhanden. tpSetA und tpSetB verwenden"
    end

    local p = self.profile

    return string.format(
        "[Terraform Plus] PROFIL | Samples=%d | Schritt=%.2f m | Min=%.3f m | Max=%.3f m | Ueber=+%.3f m | Unter=%.3f m | MaxAbweichung=%.3f m | SteilsterAbschnitt=%+.2f%%",
        #p.samples,
        p.step,
        p.minHeight,
        p.maxHeight,
        p.maxAbove,
        p.maxBelow,
        p.maxAbsDeviation,
        p.steepestSegment
    )
end


-- Konsolenbefehl: tpClear
function TerraformPlus:consoleCommandClear()

    self.pointA = nil
    self.pointB = nil
    self.measurement = nil
    self.profile = nil

    return "[Terraform Plus] Messpunkte geloescht"
end


-- Konsolenbefehl: tpVisual
function TerraformPlus:consoleCommandVisual()

    self.visualEnabled = not self.visualEnabled

    if self.visualEnabled then

        return "[Terraform Plus] Visualisierung aktiviert"
    end

    return "[Terraform Plus] Visualisierung deaktiviert"
end


-- Wird beim Verlassen der Karte ausgefuehrt.
function TerraformPlus:deleteMap()

    -- Alle Befehle entfernen
    if self.commandsRegistered then

        for _, command in ipairs(self.COMMANDS) do

            removeConsoleCommand(command)
        end

        self.commandsRegistered = false
    end

    -- Gespeicherte Daten zuruecksetzen
    self.pointA = nil
    self.pointB = nil
    self.measurement = nil
    self.profile = nil
    self.visualEnabled = false

    print("[Terraform Plus] Karte entladen")
end


-- Mod bei der GIANTS Engine registrieren
addModEventListener(TerraformPlus)
