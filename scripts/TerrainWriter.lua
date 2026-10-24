
-- Terraform Plus v0.0.14.0
-- Experimenteller Terrain-Schreibtest:
-- maximal 9 Punkte, maximal 0.20 m je Punkt.
-- Ruecklesetest, Terrain-Undo/Redo, Rollback bei Fehlern.
-- Nur auf Kopien von Einzelspieler-Testspielstaenden.

TerrainWriter = TerrainWriter or {}

TerrainWriter.MAX_TEST_POINTS = 9
TerrainWriter.MAX_TEST_DELTA = 0.20
TerrainWriter.READ_TOLERANCE = 0.04
TerrainWriter.MIN_EFFECT = 0.03

TerrainWriter.transaction = nil
TerrainWriter.armed = false

local function finite(v)
    return type(v) == "number" and v == v
        and v ~= math.huge and v ~= -math.huge
end

local function readHeight(x, z)
    if g_terrainNode == nil or g_terrainNode == 0
        or type(getTerrainHeightAtWorldPos) ~= "function" then
        return nil, "Terrain nicht verfuegbar"
    end

    local ok, value = pcall(
        getTerrainHeightAtWorldPos,
        g_terrainNode, x, 0, z
    )

    if not ok or not finite(value) then
        return nil, "Terrain-Lesefehler: " .. tostring(value)
    end

    return value
end

local function setHeight(x, z, height)
    if type(setTerrainHeightAtWorldPos) ~= "function" then
        return false, "Terrain-Schreibfunktion nicht verfuegbar"
    end

    if not (finite(x) and finite(z) and finite(height)) then
        return false, "Nicht-endlicher Schreibwert"
    end

    local ok, err = pcall(
        setTerrainHeightAtWorldPos,
        g_terrainNode, x, 0, z, height
    )

    if not ok then
        return false, tostring(err)
    end

    return true
end

local function validateCurrent(points, field)
    for i, p in ipairs(points) do
        local actual, err = readHeight(p.x, p.z)

        if actual == nil then
            return false, err
        end

        if math.abs(actual - p[field])
            > TerrainWriter.READ_TOLERANCE then

            return false, string.format(
                "Rasterpunkt %d geaendert: Ist=%.3f Erwartet=%.3f",
                i, actual, p[field]
            )
        end
    end

    return true
end

-- Schreibt die gewuenschten Werte mit direktem Ruecklesetest.
-- Bei einem Fehler wird versucht, bereits geschriebene Werte
-- auf ihren vorherigen Zustand zurueckzusetzen.
local function writeTransaction(points, targetField, rollbackField)
    local completed = 0

    for i, p in ipairs(points) do
        local ok, err = setHeight(
            p.x, p.z, p[targetField]
        )

        if not ok then
            local failures = 0

            for k = i, 1, -1 do
                local previous = points[k]
                local restored = setHeight(
                    previous.x,
                    previous.z,
                    previous[rollbackField]
                )

                if not restored then
                    failures = failures + 1
                end
            end

            return false,
                "Schreibfehler an Punkt " .. i
                .. ": " .. tostring(err)
                .. " | Rollback-Fehler: " .. failures
        end

        completed = i

        local actual, readErr = readHeight(p.x, p.z)

        if actual == nil
            or math.abs(actual - p[targetField])
                > TerrainWriter.READ_TOLERANCE then

            local failures = 0

            for k = completed, 1, -1 do
                local previous = points[k]

                local restored = setHeight(
                    previous.x,
                    previous.z,
                    previous[rollbackField]
                )

                if not restored then
                    failures = failures + 1
                end
            end

            return false, string.format(
                "Ruecklesetest fehlgeschlagen an Punkt %d: %s (Rollback-Fehler=%d)",
                i,
                tostring(readErr or actual),
                failures
            )
        end
    end

    return true
end

-- Originalhoehen unabhaengig vom aktuellen Terrainzustand
-- erneut schreiben und danach ueberpruefen.
local function restoreBackup(points)
    local failed = 0

    for _, p in ipairs(points) do
        local ok = setHeight(p.x, p.z, p.before)

        if not ok then
            failed = failed + 1
        end
    end

    local errors = 0

    for _, p in ipairs(points) do
        local actual = readHeight(p.x, p.z)

        if actual == nil
            or math.abs(actual - p.before)
                > TerrainWriter.READ_TOLERANCE then

            errors = errors + 1
        end
    end

    if failed > 0 or errors > 0 then
        return false, string.format(
            "Wiederherstellung: %d Schreibfehler, %d Abweichungen",
            failed, errors
        )
    end

    return true
end

local function refreshAnalysis(owner)
    if type(owner.consoleCommandRefresh) ~= "function" then
        return
    end

    local ok, message = pcall(
        owner.consoleCommandRefresh,
        owner
    )

    if ok then
        print("[Terraform Plus] " .. tostring(message))
    else
        print(
            "[Terraform Plus] Analyse nicht aktualisiert: "
            .. tostring(message)
        )
    end
end

local function isSingleplayerServer()
    if g_currentMission == nil
        or type(g_currentMission.getIsServer)
            ~= "function"
        or not g_currentMission:getIsServer() then

        return false
    end

    local info = g_currentMission.missionInfo
    local dynamic = g_currentMission.missionDynamicInfo

    if (info ~= nil and info.isMultiplayer)
        or (dynamic ~= nil and dynamic.isMultiplayer) then

        return false
    end

    return true
end

function TerrainWriter.check(owner)
    if not isSingleplayerServer() then
        return nil, "Nur lokale Einzelspieler-Testkarte erlaubt"
    end

    if type(setTerrainHeightAtWorldPos) ~= "function" then
        return nil, "GIANTS-Terrain-Schreibfunktion fehlt"
    end

    local tx = TerrainWriter.transaction

    if tx ~= nil
        and (tx.state == "applied"
            or tx.state == "uncertain") then

        return nil,
            "Vor neuem Test erst Terrain-Undo ausfuehren"
    end

    if TerrainPlan == nil
        or not TerrainPlan.isFresh(owner) then

        return nil,
            "Pruefplan fehlt/veraltet: tpPlanPrepare ausfuehren"
    end

    local plan = owner.terrainPlan

    if not plan.approved then
        return nil,
            "Pruefplan nicht freigegeben: tpPlanApprove CONFIRM"
    end

    if not finite(plan.unit)
        or math.abs(plan.unit - 1.0) > 0.01 then

        return nil,
            "Schreibtest derzeit nur fuer 1,000-m-Heightmaps"
    end

    if #plan.points == 0 then
        return nil, "Keine bearbeitbaren Punkte"
    end

    return plan
end

-- Waehlt maximal 9 betroffene Punkte moeglichst nahe
-- an der Mitte der ausgewaehlten Linie A-B.
function TerrainWriter.buildTestPoints(owner, plan)
    local a = owner.pointA
    local b = owner.pointB

    local cx = (a.x + b.x) * 0.5
    local cz = (a.z + b.z) * 0.5

    local ranked = {}

    for _, p in ipairs(plan.points) do
        local dx = p.x - cx
        local dz = p.z - cz

        ranked[#ranked + 1] = {
            source = p,
            dist = dx * dx + dz * dz
        }
    end

    table.sort(ranked, function(left, right)
        if left.dist ~= right.dist then
            return left.dist < right.dist
        end

        if left.source.x ~= right.source.x then
            return left.source.x < right.source.x
        end

        return left.source.z < right.source.z
    end)

    local points = {}

    for _, entry in ipairs(ranked) do
        if #points >= TerrainWriter.MAX_TEST_POINTS then
            break
        end

        local source = entry.source

        local delta = math.max(
            -TerrainWriter.MAX_TEST_DELTA,
            math.min(
                TerrainWriter.MAX_TEST_DELTA,
                source.after - source.before
            )
        )

        if math.abs(delta) >= TerrainWriter.MIN_EFFECT then
            points[#points + 1] = {
                x = source.x,
                z = source.z,
                before = source.before,
                after = source.before + delta
            }
        end
    end

    if #points == 0 then
        return nil, "Kein Testpunkt mit messbarer Aenderung"
    end

    return points
end

function TerrainWriter.apply(owner, token)
    if token ~= "CONFIRM" then
        return nil,
            "Sicherheitsbefehl: tpTerrainTest CONFIRM"
    end

    local plan, err = TerrainWriter.check(owner)

    if plan == nil then
        return nil, err
    end

    local points, buildErr =
        TerrainWriter.buildTestPoints(owner, plan)

    if points == nil then
        return nil, buildErr
    end

    -- Pruefen, ob sich die Hoehen seit dem Pruefplan
    -- zwischenzeitlich veraendert haben.
    local valid, message = validateCurrent(
        points, "before"
    )

    if not valid then
        return nil,
            "Schreibvorgang abgelehnt: " .. tostring(message)
    end

    -- Originalwerte protokollieren, bevor geschrieben wird.
    for i, p in ipairs(points) do
        print(string.format(
            "[Terraform Plus] Testpunkt %d: X=%.2f Z=%.2f Y=%.3f -> %.3f",
            i, p.x, p.z, p.before, p.after
        ))
    end

    local tx = {
        points = points,
        state = "applied"
    }

    -- Auch bei einem Fehler bleibt die Sicherung erhalten.
    TerrainWriter.transaction = tx

    local written, writeErr = writeTransaction(
        points, "after", "before"
    )

    if not written then
        tx.state = "uncertain"
        TerrainWriter.armed = false

        return nil,
            tostring(writeErr)
            .. " | Terrainzustand unsicher: NICHT speichern!"
    end

    TerrainWriter.armed = false
    TerrainPlan.invalidate(owner)
    refreshAnalysis(owner)

    return true, string.format(
        "ECHTER TESTSCHREIBVORGANG: %d Punkte, max. %.2f m pro Punkt | Terrain-Undo verfuegbar",
        #points,
        TerrainWriter.MAX_TEST_DELTA
    )
end

function TerrainWriter.undo(owner, token)
    if token ~= "CONFIRM" then
        return nil,
            "Sicherheitsbefehl: tpTerrainUndo CONFIRM"
    end

    local tx = TerrainWriter.transaction

    if tx == nil
        or (tx.state ~= "applied"
            and tx.state ~= "uncertain") then

        return nil,
            "Kein Terrain-Eingriff zum Rueckgaengigmachen"
    end

    if not isSingleplayerServer() then
        return nil, "Nur Einzelspieler"
    end

    if tx.state == "applied" then
        local valid, err = validateCurrent(
            tx.points, "after"
        )

        if not valid then
            return nil,
                "Terrain-Undo verweigert: " .. tostring(err)
        end
    end

    local ok, err = restoreBackup(tx.points)

    if not ok then
        tx.state = "uncertain"

        return nil,
            "Terrain-Undo fehlgeschlagen: " .. tostring(err)
    end

    tx.state = "undone"
    TerrainWriter.armed = false

    TerrainPlan.invalidate(owner)
    refreshAnalysis(owner)

    return true, string.format(
        "Terrain-Undo erfolgreich: %d Punkte wiederhergestellt",
        #tx.points
    )
end

function TerrainWriter.redo(owner, token)
    if token ~= "CONFIRM" then
        return nil,
            "Sicherheitsbefehl: tpTerrainRedo CONFIRM"
    end

    local tx = TerrainWriter.transaction

    if tx == nil or tx.state ~= "undone" then
        return nil, "Kein Terrain-Redo verfuegbar"
    end

    if not isSingleplayerServer() then
        return nil, "Nur Einzelspieler"
    end

    local valid, err = validateCurrent(
        tx.points, "before"
    )

    if not valid then
        return nil,
            "Terrain-Redo verweigert: " .. tostring(err)
    end

    local ok, writeErr = writeTransaction(
        tx.points, "after", "before"
    )

    if not ok then
        tx.state = "uncertain"

        return nil,
            "Terrain-Redo fehlgeschlagen: " .. tostring(writeErr)
    end

    tx.state = "applied"

    TerrainPlan.invalidate(owner)
    refreshAnalysis(owner)

    return true, string.format(
        "Terrain-Redo erfolgreich: %d Punkte",
        #tx.points
    )
end

function TerrainWriter.status()
    local tx = TerrainWriter.transaction

    if tx == nil then
        return "Noch kein echter Terrain-Schreibtest"
    end

    return string.format(
        "Terrain-Zustand=%s | Gesicherte Punkte=%d | Limit=%.2f m",
        tx.state,
        #tx.points,
        TerrainWriter.MAX_TEST_DELTA
    )
end

-- Neue Befehle vor loadMap() zur Befehlsliste hinzufuegen.
local function addCommand(name, description, method)
    for _, command in ipairs(TerraformPlus.COMMANDS or {}) do
        if command[1] == name then
            return
        end
    end

    table.insert(
        TerraformPlus.COMMANDS,
        {name, description, method}
    )
end

TerraformPlus.VERSION = "0.0.14.0"

function TerraformPlus:consoleCommandTerrainTest(token)
    local ok, message = TerrainWriter.apply(self, token)
    return "[Terraform Plus] " .. tostring(message)
end

function TerraformPlus:consoleCommandTerrainUndo(token)
    local ok, message = TerrainWriter.undo(self, token)
    return "[Terraform Plus] " .. tostring(message)
end

function TerraformPlus:consoleCommandTerrainRedo(token)
    local ok, message = TerrainWriter.redo(self, token)
    return "[Terraform Plus] " .. tostring(message)
end

function TerraformPlus:consoleCommandTerrainStatus()
    return "[Terraform Plus] " .. TerrainWriter.status()
end

addCommand(
    "tpTerrainTest",
    "Maximal neun Hoehenpunkte probeweise schreiben",
    "consoleCommandTerrainTest"
)

addCommand(
    "tpTerrainUndo",
    "Originalhoehen des Tests wiederherstellen",
    "consoleCommandTerrainUndo"
)

addCommand(
    "tpTerrainRedo",
    "Letzten Hoehentest wiederholen",
    "consoleCommandTerrainRedo"
)

addCommand(
    "tpTerrainStatus",
    "Terrain-Teststatus ausgeben",
    "consoleCommandTerrainStatus"
)

-- Kartenstart: Testhistorie zuruecksetzen.
local oldLoadMap = TerraformPlus.loadMap

function TerraformPlus:loadMap(...)
    TerrainWriter.transaction = nil
    TerrainWriter.armed = false

    return oldLoadMap(self, ...)
end

-- Bei Kartenwechsel einen aktiven Test rueckgaengig machen,
-- soweit das Terrain zu diesem Zeitpunkt noch verfuegbar ist.
local oldDeleteMap = TerraformPlus.deleteMap

function TerraformPlus:deleteMap(...)
    local tx = TerrainWriter.transaction

    if tx ~= nil
        and (tx.state == "applied"
            or tx.state == "uncertain") then

        local ok, message = TerrainWriter.undo(
            self, "CONFIRM"
        )

        print(
            "[Terraform Plus] Auto-Ruecknahme beim Kartenwechsel: "
            .. tostring(message)
        )

        if not ok then
            print(
                "[Terraform Plus] WARNUNG: Testterrain nicht vollstaendig wiederhergestellt"
            )
        end
    end

    TerrainWriter.transaction = nil
    TerrainWriter.armed = false

    return oldDeleteMap(self, ...)
end

-- Bestehende UI erweitern.
-- Bereich und Gestaltung bleiben unveraendert.
local originalDrawUI = TerrainToolUI.draw

function TerrainToolUI.draw(owner)
    originalDrawUI(owner)

    if not TerrainToolUI.visible
        or (g_gui ~= nil
            and type(g_gui.getIsGuiVisible) == "function"
            and g_gui:getIsGuiVisible()) then
        return
    end

    local c = TerrainToolUI.COLORS

    -- Versionsnummer im bestehenden Titel aktualisieren.
    TerrainToolUI.rect(
        0.679, 0.747, 0.246, 0.040, c.header
    )

    TerrainToolUI.text(
        0.690, 0.757,
        "TERRAFORM PLUS  0.0.14.0",
        0.016, c.text
    )

    if TerrainToolUI.page ~= "review" then
        return
    end

    -- Alten Inhalt des Pruefungsreiters ueberzeichnen.
    TerrainToolUI.rect(
        0.676, 0.121,
        0.302, 0.567,
        c.panel
    )

    TerrainToolUI.buttons = {}

    TerrainToolUI.button(
        "close", "X",
        0.939, 0.752, 0.026, 0.031,
        true, "warning"
    )

    TerrainToolUI.button(
        "tabSelect", "BEREICH",
        0.690, 0.700, 0.087, 0.036,
        true
    )

    TerrainToolUI.button(
        "tabDesign", "GESTALTUNG",
        0.783, 0.700, 0.087, 0.036,
        true
    )

    TerrainToolUI.button(
        "tabReview", "PRUEFUNG",
        0.876, 0.700, 0.089, 0.036,
        true, "active"
    )

    local fresh = TerrainPlan.isFresh(owner)

    local plan =
        fresh and owner.terrainPlan or nil

    local tx = TerrainWriter.transaction

    TerrainToolUI.text(
        0.690, 0.653,
        "PRUEFEN UND TESTEN (EINZELSPIELER)",
        0.012, c.text
    )

    if plan == nil then
        TerrainToolUI.text(
            0.690, 0.609,
            "Kein aktueller Pruefplan",
            0.012, c.muted
        )
    else
        TerrainToolUI.text(
            0.690, 0.609,

            string.format(
                "%d Pruefpunkte / %.3f m Raster",
                plan.checked,
                plan.unit
            ),

            0.012, c.text
        )

        TerrainToolUI.text(
            0.690, 0.580,

            string.format(
                "%d betroffene Punkte / %.1f m3 Auftrag",
                #plan.points,
                plan.fillVolume
            ),

            0.012, c.muted
        )
    end

    TerrainToolUI.button(
        "prepare", "PRUEFRASTER ERSTELLEN",
        0.690, 0.520, 0.275, 0.040,

        owner.selection == nil
            and owner.pointA ~= nil
            and owner.pointB ~= nil
    )

    TerrainToolUI.button(
        "approve", "PLAN FREIGEBEN",
        0.690, 0.472, 0.275, 0.040,

        plan ~= nil and not plan.approved
    )

    TerrainToolUI.button(
        "run", "PROBELAUF OHNE AENDERUNG",
        0.690, 0.424, 0.275, 0.040,

        plan ~= nil and plan.approved
    )

    local canWrite =
        plan ~= nil
        and plan.approved
        and (tx == nil or tx.state == "undone")

    TerrainToolUI.button(
        "terrainTest",

        TerrainWriter.armed
            and "ACHTUNG: SCHREIBTEST BESTAETIGEN"
            or "ECHTER TEST: MAX. 9 PUNKTE",

        0.690, 0.352, 0.275, 0.043,
        canWrite, "warning"
    )

    TerrainToolUI.text(
        0.690, 0.318,
        "Hoehenaenderung max. 0,20 m pro Punkt",
        0.011, c.muted
    )

    TerrainToolUI.button(
        "terrainUndo", "TERRAIN ZURUECKSETZEN",
        0.690, 0.263, 0.275, 0.039,

        tx ~= nil
            and (tx.state == "applied"
                or tx.state == "uncertain"),

        "active"
    )

    TerrainToolUI.button(
        "terrainRedo", "TERRAIN WIEDERHOLEN",
        0.690, 0.214, 0.275, 0.039,

        tx ~= nil and tx.state == "undone"
    )

    TerrainToolUI.text(
        0.690, 0.156,
        "Nur auf Kopie eines Spielstands testen!",
        0.011, c.cut
    )
end

-- Die neuen UI-Buttons mit den Schreibfunktionen verbinden.
local originalPerform = TerrainToolUI.perform

function TerrainToolUI.perform(owner, id)
    if id == "terrainTest" then

        if not TerrainWriter.armed then
            TerrainWriter.armed = true

            print(
                "[Terraform Plus] Achtung: ECHTE Gelaendeaenderung! Test-Button erneut klicken"
            )
        else
            TerrainWriter.armed = false

            print(
                owner:consoleCommandTerrainTest("CONFIRM")
            )
        end

        return

    elseif id == "terrainUndo" then
        TerrainWriter.armed = false

        print(
            owner:consoleCommandTerrainUndo("CONFIRM")
        )

        return

    elseif id == "terrainRedo" then
        TerrainWriter.armed = false

        print(
            owner:consoleCommandTerrainRedo("CONFIRM")
        )

        return
    end

    if id == "tabSelect"
        or id == "tabDesign"
        or id == "tabReview"
        or id == "prepare"
        or id == "approve"
        or id == "run" then

        TerrainWriter.armed = false
    end

    return originalPerform(owner, id)
end

print(
    "[Terraform Plus] TerrainWriter 0.0.14.0 registriert (9-Punkt-Test + Undo/Redo)"
)
