
-- Terraform Plus
-- Version: 0.0.3.0
-- Terrain measurement system (read-only)

TerraformPlus = TerraformPlus or {}

TerraformPlus.VERSION = "0.0.3.0"

TerraformPlus.COMMANDS = {
    "tpHeight",
    "tpSetA",
    "tpSetB",
    "tpMeasure",
    "tpClear"
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


-- Ermittelt die aktuelle Position und Gelaendehoehe.
-- Fehler aus dem TerrainAdapter werden abgefangen.
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


-- Berechnet die Steigung zwischen zwei Messpunkten.
function TerraformPlus:calculateSlope(pointA, pointB)

    local dx = pointB.x - pointA.x
    local dz = pointB.z - pointA.z

    -- Horizontale Entfernung (XZ-Ebene)
    local distance = math.sqrt(
        dx * dx + dz * dz
    )

    -- Hoehenunterschied von A nach B
    local heightDifference =
        pointB.terrainY - pointA.terrainY

    -- Division durch nahezu 0 verhindern
    if distance < 0.01 then
        return nil, "Messpunkte liegen zu nah beieinander"
    end

    -- Steigung in Prozent
    local slopePercent =
        (heightDifference / distance) * 100

    -- Neigungswinkel in Grad
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


-- Wird beim Laden einer Karte aufgerufen.
function TerraformPlus:loadMap()

    -- Keine Messpunkte aus einem alten Spielstand uebernehmen
    self.pointA = nil
    self.pointB = nil

    -- Bestehender Befehl
    addConsoleCommand(
        "tpHeight",
        "Zeigt die Gelaendehoehe unter dem Spieler",
        "consoleCommandHeight",
        self
    )

    -- Neue Befehle
    addConsoleCommand(
        "tpSetA",
        "Setzt den ersten Messpunkt",
        "consoleCommandSetA",
        self
    )

    addConsoleCommand(
        "tpSetB",
        "Setzt den zweiten Messpunkt",
        "consoleCommandSetB",
        self
    )

    addConsoleCommand(
        "tpMeasure",
        "Berechnet Entfernung und Gelaendeneigung",
        "consoleCommandMeasure",
        self
    )

    addConsoleCommand(
        "tpClear",
        "Loescht beide Messpunkte",
        "consoleCommandClear",
        self
    )

    self.commandsRegistered = true

    print(
        "[Terraform Plus] Mod geladen - Version "
        .. self.VERSION
    )

    print("[Terraform Plus] Messsystem bereit")
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

    -- Startpunkt als Momentaufnahme speichern
    self.pointA = {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }

    -- Neuer Startpunkt macht alten Endpunkt ungueltig
    self.pointB = nil

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

    -- Endpunkt als Momentaufnahme speichern
    self.pointB = {
        x = sample.x,
        z = sample.z,
        terrainY = sample.terrainY
    }

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

    return string.format(
        "[Terraform Plus] A -> B | Distanz=%.2f m | DeltaH=%+.3f m | Steigung=%+.2f%% | Winkel=%+.2f Grad",
        result.distance,
        result.heightDifference,
        result.slopePercent,
        result.slopeAngle
    )
end


-- Konsolenbefehl: tpClear
function TerraformPlus:consoleCommandClear()

    self.pointA = nil
    self.pointB = nil

    return "[Terraform Plus] Messpunkte geloescht"
end


-- Wird beim Entladen der Karte ausgefuehrt.
function TerraformPlus:deleteMap()

    if self.commandsRegistered then

        for _, command in ipairs(self.COMMANDS) do
            removeConsoleCommand(command)
        end

        self.commandsRegistered = false
    end

    self.pointA = nil
    self.pointB = nil

    print("[Terraform Plus] Karte entladen")
end


-- Mod bei der GIANTS Engine registrieren
addModEventListener(TerraformPlus)
