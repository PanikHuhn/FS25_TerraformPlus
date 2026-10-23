
-- Terraform Plus
-- Version: 0.0.4.0

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.4.0"

TerraformPlus.COMMANDS = {
    "tpHeight",
    "tpSetA",
    "tpSetB",
    "tpMeasure",
    "tpClear",
    "tpVisual"
}


-- Formatiert die Terrainhoehe.
function TerraformPlus:formatHeight(sample)

    return string.format(
        "[Terraform Plus] X=%.2f Z=%.2f | Terrainhoehe=%.3f m",
        sample.x,
        sample.z,
        sample.terrainY
    )
end


-- Fragt den TerrainAdapter sicher ab.
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


-- Berechnet Entfernung, Hoehenunterschied und Steigung.
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


-- Erzeugt eine Kopie der Messwerte.
function TerraformPlus:createPoint(sample)

    return {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }
end


-- Beim Laden einer Karte.
function TerraformPlus:loadMap()

    self.pointA = nil
    self.pointB = nil
    self.measurement = nil

    -- Visualisierung standardmaessig aktivieren
    self.visualEnabled = true
    self.commandsRegistered = false

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

    self.commandsRegistered = true

    print(
        "[Terraform Plus] Mod geladen - Version "
        .. self.VERSION
    )

    print("[Terraform Plus] TerrainVisualizer bereit")
end


-- Zeichnet die Visualisierung in jedem Renderzyklus.
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

    -- Renderfehler abfangen, damit sie nicht dauerhaft
    -- in jedem einzelnen Frame auftreten.
    local success, err = pcall(
        TerrainVisualizer.draw,
        self.pointA,
        self.pointB,
        self.measurement
    )

    if not success then

        self.visualEnabled = false

        print(
            "[Terraform Plus] Visualisierung deaktiviert: "
            .. tostring(err)
        )
    end
end


-- tpHeight: Aktuelle Terrainhoehe auslesen.
function TerraformPlus:consoleCommandHeight()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    return self:formatHeight(sample)
end


-- tpSetA: Startpunkt festlegen.
function TerraformPlus:consoleCommandSetA()

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    self.pointA = self:createPoint(sample)

    -- Alten Endpunkt und alte Messung verwerfen
    self.pointB = nil
    self.measurement = nil

    return string.format(
        "[Terraform Plus] Punkt A gesetzt: X=%.2f Z=%.2f H=%.3f m",
        self.pointA.x,
        self.pointA.z,
        self.pointA.terrainY
    )
end


-- tpSetB: Endpunkt festlegen.
function TerraformPlus:consoleCommandSetB()

    if self.pointA == nil then
        return "[Terraform Plus] Zuerst Punkt A mit tpSetA setzen"
    end

    local sample, err = self:getCurrentSample()

    if sample == nil then
        return "[Terraform Plus] Fehler: " .. err
    end

    self.pointB = self:createPoint(sample)

    -- Messergebnis direkt aktualisieren
    local result, calculationError = self:calculateSlope(
        self.pointA,
        self.pointB
    )

    self.measurement = result

    if result == nil then
        return "[Terraform Plus] Punkt B gesetzt, Messung nicht moeglich: "
            .. calculationError
    end

    return string.format(
        "[Terraform Plus] Punkt B gesetzt: X=%.2f Z=%.2f H=%.3f m",
        self.pointB.x,
        self.pointB.z,
        self.pointB.terrainY
    )
end


-- tpMeasure: Aktuelles Messergebnis ausgeben.
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

    self.measurement = result

    return string.format(
        "[Terraform Plus] A -> B | Distanz=%.2f m | DeltaH=%+.3f m | Steigung=%+.2f%% | Winkel=%+.2f Grad",
        result.distance,
        result.heightDifference,
        result.slopePercent,
        result.slopeAngle
    )
end


-- tpClear: Messpunkte entfernen.
function TerraformPlus:consoleCommandClear()

    self.pointA = nil
    self.pointB = nil
    self.measurement = nil

    return "[Terraform Plus] Messpunkte geloescht"
end


-- tpVisual: Anzeige aktivieren/deaktivieren.
function TerraformPlus:consoleCommandVisual()

    self.visualEnabled = not self.visualEnabled

    if self.visualEnabled then
        return "[Terraform Plus] Visualisierung aktiviert"
    end

    return "[Terraform Plus] Visualisierung deaktiviert"
end


-- Beim Verlassen der Karte.
function TerraformPlus:deleteMap()

    if self.commandsRegistered then

        for _, command in ipairs(self.COMMANDS) do
            removeConsoleCommand(command)
        end

        self.commandsRegistered = false
    end

    self.pointA = nil
    self.pointB = nil
    self.measurement = nil
    self.visualEnabled = false

    print("[Terraform Plus] Karte entladen")
end


-- GIANTS-Engine-Eventlistener
addModEventListener(TerraformPlus)
