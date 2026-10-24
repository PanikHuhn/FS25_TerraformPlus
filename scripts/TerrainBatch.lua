
-- Terraform Plus v0.0.15.0
-- Paketausfuehrung mit gesicherten Originalhoehen, Abbruch und Rollback.
-- EXPERIMENTELL: nur auf Kopien von Einzelspieler-Testspielstaenden.
-- Speichern waehrend eines aktiven Eingriffs unbedingt vermeiden.

TerrainBatch = TerrainBatch or {}

TerrainBatch.MAX_POINTS = 256
TerrainBatch.POINTS_PER_FRAME = 8
TerrainBatch.MAX_DELTA = 0.25
TerrainBatch.MIN_DELTA = 0.03
TerrainBatch.TOLERANCE = 0.04

TerrainBatch.transaction = nil
TerrainBatch.armed = false


local function finite(v)
    return type(v) == "number"
        and v == v
        and v ~= math.huge
        and v ~= -math.huge
end


local function singleplayer()
    local m = g_currentMission

    if m == nil
        or type(m.getIsServer) ~= "function"
        or not m:getIsServer() then

        return false
    end

    return not (
        (m.missionInfo and m.missionInfo.isMultiplayer)
        or (m.missionDynamicInfo and m.missionDynamicInfo.isMultiplayer)
    )
end


local function read(p)
    if not g_terrainNode
        or type(getTerrainHeightAtWorldPos) ~= "function" then

        return nil, "Terrain-Lese-API fehlt"
    end

    local ok, h = pcall(
        getTerrainHeightAtWorldPos,
        g_terrainNode, p.x, 0, p.z
    )

    if not ok or not finite(h) then
        return nil, "Terrain-Leseproblem: " .. tostring(h)
    end

    return h
end


local function writeAndCheck(p, target)
    if type(setTerrainHeightAtWorldPos) ~= "function" then
        return false, "Terrain-Schreib-API fehlt"
    end

    local ok, err = pcall(
        setTerrainHeightAtWorldPos,
        g_terrainNode, p.x, 0, p.z, target
    )

    if not ok then
        return false, "Schreibproblem: " .. tostring(err)
    end

    local actual, readErr = read(p)

    if actual == nil
        or math.abs(actual - target) > TerrainBatch.TOLERANCE then

        return false, string.format(
            "Ruecklesetest X=%.2f Z=%.2f: %s",
            p.x, p.z, tostring(readErr or actual)
        )
    end

    return true
end


local function checkAll(points, field)
    for i, p in ipairs(points) do
        local current, err = read(p)

        if current == nil then
            return false, err
        end

        if math.abs(current - p[field])
            > TerrainBatch.TOLERANCE then

            return false, string.format(
                "Punkt %d veraendert: %.3f statt %.3f",
                i, current, p[field]
            )
        end
    end

    return true
end


local function refresh(owner)
    if type(owner.consoleCommandRefresh) == "function" then
        local ok, result = pcall(
            owner.consoleCommandRefresh, owner
        )

        print(
            "[Terraform Plus] Batch-Analyse: "
            .. tostring(result)
        )

        if not ok then
            print(
                "[Terraform Plus] WARNUNG: "
                .. "Analyse-Aktualisierung fehlgeschlagen"
            )
        end
    end
end


local function beginRollback(tx, reason)
    tx.state = "rollingBack"
    tx.reason = reason

    -- Nur ein vollstaendig abgeschlossener Batch,
    -- der regulär per Undo entfernt wurde,
    -- darf spaeter erneut ausgefuehrt werden.
    tx.replayAllowed = (reason == "Terrain-Undo")

    tx.rollbackIndex = tx.lastAttempted
    tx.rollbackFailures = 0

    TerrainBatch.armed = false

    print(
        "[Terraform Plus] Batch-Rollback gestartet: "
        .. tostring(reason)
    )
end


local function allowed(owner)
    if not singleplayer() then
        return nil, "Nur lokaler Einzelspieler"
    end

    if type(setTerrainHeightAtWorldPos) ~= "function" then
        return nil, "Terrain-Schreibfunktion fehlt"
    end

    local old = TerrainWriter and TerrainWriter.transaction

    if old ~= nil
        and (old.state == "applied"
            or old.state == "uncertain") then

        return nil,
            "Zuerst alten 9-Punkte-Test rueckgaengig machen"
    end

    local tx = TerrainBatch.transaction

    if tx ~= nil and tx.state ~= "undone" then
        return nil,
            "Vorhandene Batch-Transaktion: "
            .. tostring(tx.state)
    end

    if TerrainPlan == nil
        or not TerrainPlan.isFresh(owner)
        or owner.terrainPlan == nil
        or not owner.terrainPlan.approved then

        return nil,
            "Erst tpPlanPrepare und tpPlanApprove CONFIRM"
    end

    local plan = owner.terrainPlan
    local base = owner.area

    -- Verhindert Schreibtests mit geaenderter Breite
    -- oder Rasteraufloesung ohne neue Bereichsanalyse.
    if base == nil
        or type(base.width) ~= "number"
        or type(base.requestedStep) ~= "number"
        or math.abs(base.width - owner.areaWidth) > 0.00001
        or math.abs(base.requestedStep - owner.areaStep) > 0.00001 then

        return nil,
            "Breite/Raster nach Analyse geaendert: "
            .. "tpRefresh und tpPlanPrepare"
    end

    if math.abs(plan.unit - 1) > 0.01 then
        return nil,
            "Nur getestetes 1.000-m-Heightmap-Raster erlaubt"
    end

    if #plan.points == 0 then
        return nil, "Pruefplan ohne betroffene Punkte"
    end

    return plan
end


-- Alle Originalhoehen werden vor dem ersten
-- Schreibzugriff gelesen und gesichert.
-- Bei grossen Flaechen werden die mittleren
-- 256 Rasterpunkte bevorzugt.
function TerrainBatch.prepare(owner)
    local plan, err = allowed(owner)

    if plan == nil then
        return nil, err
    end

    local a, b = owner.pointA, owner.pointB
    local mx = (a.x + b.x) / 2
    local mz = (a.z + b.z) / 2

    local ranking = {}

    for _, p in ipairs(plan.points) do
        local dx = p.x - mx
        local dz = p.z - mz

        ranking[#ranking + 1] = {
            p = p,
            d = dx * dx + dz * dz
        }
    end

    table.sort(ranking, function(l, r)
        if l.d ~= r.d then
            return l.d < r.d
        end

        if l.p.x ~= r.p.x then
            return l.p.x < r.p.x
        end

        return l.p.z < r.p.z
    end)

    local selected = {}
    local seen = {}
    local capped = 0

    for _, item in ipairs(ranking) do
        if #selected >= TerrainBatch.MAX_POINTS then
            break
        end

        local p = item.p

        local key = string.format(
            "%.4f:%.4f", p.x, p.z
        )

        if seen[key] then
            return nil, "Doppelte Rasterposition: " .. key
        end

        seen[key] = true

        local current, readErr = read(p)

        if current == nil then
            return nil, readErr
        end

        if math.abs(current - p.before)
            > TerrainBatch.TOLERANCE then

            return nil,
                "Terrain seit dem Pruefplan veraendert; "
                .. "bitte neu pruefen"
        end

        local requested = p.after - p.before

        local delta = math.max(
            -TerrainBatch.MAX_DELTA,
            math.min(
                TerrainBatch.MAX_DELTA,
                requested
            )
        )

        if math.abs(delta) >= TerrainBatch.MIN_DELTA then
            if math.abs(delta - requested) > 0.000001 then
                capped = capped + 1
            end

            selected[#selected + 1] = {
                x = p.x,
                z = p.z,
                before = current,
                after = current + delta
            }
        end
    end

    if #selected == 0 then
        return nil, "Kein messbarer Hoeheneingriff"
    end

    return {
        points = selected,
        totalAvailable = #plan.points,
        capped = capped,

        state = "applying",
        done = 0,
        lastAttempted = 0,
        replayAllowed = false,

        rollbackIndex = 0,
        rollbackFailures = 0,

        reason = "",
        lastLogged = -1
    }
end


function TerrainBatch.apply(owner, token)
    if token ~= "CONFIRM" then
        return nil,
            "Bestaetigung: tpBatchApply CONFIRM"
    end

    local tx, err = TerrainBatch.prepare(owner)

    if tx == nil then
        return nil, err
    end

    -- Die gesicherten Originalwerte existieren,
    -- bevor das erste Frame etwas schreibt.
    TerrainBatch.transaction = tx
    TerrainBatch.armed = false

    if TerrainWriter ~= nil then
        TerrainWriter.armed = false
    end

    TerrainPlan.invalidate(owner)

    return true, string.format(
        "Batch START: %d von %d Punkten (max %.2f m), "
        .. "%d Hoehen begrenzt; %d Punkte/Frame",
        #tx.points,
        tx.totalAvailable,
        TerrainBatch.MAX_DELTA,
        tx.capped,
        TerrainBatch.POINTS_PER_FRAME
    )
end


function TerrainBatch.cancel()
    local tx = TerrainBatch.transaction

    if tx == nil or tx.state ~= "applying" then
        return nil, "Keine laufende Batch-Ausfuehrung"
    end

    beginRollback(tx, "Benutzerabbruch")

    return true,
        "Abbruch angefordert; "
        .. "Originalhoehen werden wiederhergestellt"
end


function TerrainBatch.undo(token)
    if token ~= "CONFIRM" then
        return nil, "tpBatchUndo CONFIRM"
    end

    local tx = TerrainBatch.transaction

    if tx == nil or tx.state ~= "applied" then
        return nil, "Kein fertig angewendeter Batch"
    end

    if not singleplayer() then
        return nil, "Nur lokaler Einzelspieler"
    end

    local valid, err = checkAll(
        tx.points, "after"
    )

    if not valid then
        return nil,
            "Undo gesperrt: " .. tostring(err)
    end

    tx.lastAttempted = #tx.points

    beginRollback(tx, "Terrain-Undo")

    return true, "Terrain-Undo laeuft in Paketen"
end


function TerrainBatch.redo(token)
    if token ~= "CONFIRM" then
        return nil, "tpBatchRedo CONFIRM"
    end

    local tx = TerrainBatch.transaction

    if tx == nil
        or tx.state ~= "undone"
        or not tx.replayAllowed then

        return nil,
            "Kein wiederholbarer Terrain-Undo vorhanden"
    end

    if not singleplayer() then
        return nil, "Nur lokaler Einzelspieler"
    end

    local old = TerrainWriter and TerrainWriter.transaction

    if old ~= nil
        and (old.state == "applied"
            or old.state == "uncertain") then

        return nil, "9-Punkte-Transaktion blockiert Redo"
    end

    local valid, err = checkAll(
        tx.points, "before"
    )

    if not valid then
        return nil,
            "Redo gesperrt: " .. tostring(err)
    end

    tx.done = 0
    tx.lastAttempted = 0
    tx.lastLogged = -1

    tx.state = "applying"
    tx.reason = "Redo"
    tx.replayAllowed = false

    return true, "Terrain-Redo laeuft in Paketen"
end


function TerrainBatch.recover(token)
    if token ~= "CONFIRM" then
        return nil, "tpBatchRecover CONFIRM"
    end

    local tx = TerrainBatch.transaction

    if tx == nil or tx.state ~= "uncertain" then
        return nil,
            "Keine unsichere Transaktion vorhanden"
    end

    if not singleplayer() then
        return nil, "Nur lokaler Einzelspieler"
    end

    tx.lastAttempted = #tx.points

    beginRollback(
        tx, "Wiederherstellungsversuch"
    )

    return true,
        "Erneute Wiederherstellung gestartet"
end


-- Wird einmal pro Frame aus TerraformPlus:update aufgerufen.
function TerrainBatch.update(owner)
    local tx = TerrainBatch.transaction

    if tx == nil then
        return
    end

    if tx.state == "applying" then

        for _ = 1, TerrainBatch.POINTS_PER_FRAME do
            local i = tx.done + 1

            if i > #tx.points then
                break
            end

            -- Auch der fehlgeschlagene Schreibversuch
            -- wird beim Rollback beruecksichtigt.
            tx.lastAttempted = i

            local p = tx.points[i]

            local ok, err = writeAndCheck(
                p, p.after
            )

            if not ok then
                beginRollback(
                    tx,
                    "Punkt " .. i .. ": " .. tostring(err)
                )

                break
            end

            tx.done = i
        end

        if tx.state == "applying" then
            local percentage = math.floor(
                tx.done / #tx.points * 100
            )

            local quarter = math.floor(
                percentage / 25
            )

            if quarter > tx.lastLogged then
                tx.lastLogged = quarter

                print(string.format(
                    "[Terraform Plus] Batch-Fortschritt: %d/%d (%d%%)",
                    tx.done,
                    #tx.points,
                    percentage
                ))
            end

            if tx.done == #tx.points then
                tx.state = "applied"

                print(
                    "[Terraform Plus] Batch ERFOLGREICH: "
                    .. #tx.points
                    .. " Terrainpunkte geschrieben und rueckgelesen"
                )

                refresh(owner)
            end
        end

    elseif tx.state == "rollingBack" then

        for _ = 1, TerrainBatch.POINTS_PER_FRAME do
            if tx.rollbackIndex < 1 then
                break
            end

            local p = tx.points[
                tx.rollbackIndex
            ]

            local ok, err = writeAndCheck(
                p, p.before
            )

            if not ok then
                tx.rollbackFailures =
                    tx.rollbackFailures + 1

                print(
                    "[Terraform Plus] ROLLBACK-PROBLEM: "
                    .. tostring(err)
                )
            end

            tx.rollbackIndex =
                tx.rollbackIndex - 1
        end

        if tx.rollbackIndex < 1 then

            if tx.rollbackFailures == 0 then
                tx.state = "undone"

                print(
                    "[Terraform Plus] Batch-Rollback ERFOLGREICH: "
                    .. #tx.points
                    .. " Originalhoehen gesichert/wiederhergestellt"
                )

                refresh(owner)

            else
                tx.state = "uncertain"

                print(
                    "[Terraform Plus] KRITISCH: "
                    .. tx.rollbackFailures
                    .. " Wiederherstellungsfehler; NICHT SPEICHERN"
                )
            end
        end
    end
end


-- Ruecknahme beim Entladen der Karte.
-- Dies ist nur ein letzter Rettungsversuch;
-- kein Ersatz fuer eine Savegame-Sicherung.
function TerrainBatch.restoreOnExit()
    local tx = TerrainBatch.transaction

    if tx == nil or tx.state == "undone" then
        return true
    end

    if not singleplayer() then
        return false
    end

    local failed = 0
    local last = tx.lastAttempted

    if tx.state == "uncertain" then
        last = #tx.points
    end

    for i = last, 1, -1 do
        local p = tx.points[i]

        local ok = writeAndCheck(
            p, p.before
        )

        if not ok then
            failed = failed + 1
        end
    end

    if failed == 0 then
        tx.state = "undone"

        print(
            "[Terraform Plus] Batch bei Kartenende wiederhergestellt"
        )

        return true
    end

    tx.state = "uncertain"

    print(
        "[Terraform Plus] KRITISCH: "
        .. failed
        .. " Fehler beim Kartenende; "
        .. "Backup des Spielstands verwenden"
    )

    return false
end


function TerrainBatch.busy()
    local tx = TerrainBatch.transaction

    return tx ~= nil
        and (tx.state == "applying"
            or tx.state == "rollingBack")
end


function TerrainBatch.blocksLegacy()
    local tx = TerrainBatch.transaction

    return tx ~= nil
        and tx.state ~= "undone"
end


function TerrainBatch.status()
    local tx = TerrainBatch.transaction

    if tx == nil then
        return "Kein Batch vorhanden"
    end

    return string.format(
        "Batch=%s | %d/%d geschrieben | Rollback=%d | Fehler=%d | max. %.2f m",
        tx.state,
        tx.done,
        #tx.points,
        tx.rollbackIndex,
        tx.rollbackFailures,
        TerrainBatch.MAX_DELTA
    )
end


-- ===========================================
-- Konsole und Integration
-- ===========================================

local function addCommand(name, description, method)
    TerraformPlus.COMMANDS =
        TerraformPlus.COMMANDS or {}

    for _, c in ipairs(TerraformPlus.COMMANDS) do
        if c[1] == name then
            return
        end
    end

    table.insert(
        TerraformPlus.COMMANDS,
        {name, description, method}
    )
end


TerraformPlus.VERSION = "0.0.15.0"


function TerraformPlus:consoleCommandBatchApply(token)
    local ok, msg = TerrainBatch.apply(self, token)
    return "[Terraform Plus] " .. tostring(msg)
end


function TerraformPlus:consoleCommandBatchCancel()
    local ok, msg = TerrainBatch.cancel()
    return "[Terraform Plus] " .. tostring(msg)
end


function TerraformPlus:consoleCommandBatchUndo(token)
    local ok, msg = TerrainBatch.undo(token)
    return "[Terraform Plus] " .. tostring(msg)
end


function TerraformPlus:consoleCommandBatchRedo(token)
    local ok, msg = TerrainBatch.redo(token)
    return "[Terraform Plus] " .. tostring(msg)
end


function TerraformPlus:consoleCommandBatchRecover(token)
    local ok, msg = TerrainBatch.recover(token)
    return "[Terraform Plus] " .. tostring(msg)
end


function TerraformPlus:consoleCommandBatchStatus()
    return "[Terraform Plus] " .. TerrainBatch.status()
end


for _, spec in ipairs({
    {
        "tpBatchApply",
        "Begrenzte Flaeche in Paketen bearbeiten",
        "consoleCommandBatchApply"
    },
    {
        "tpBatchCancel",
        "Batch abbrechen und ruecknehmen",
        "consoleCommandBatchCancel"
    },
    {
        "tpBatchUndo",
        "Batch-Hoehen rueckgaengig",
        "consoleCommandBatchUndo"
    },
    {
        "tpBatchRedo",
        "Batch-Hoehen wiederholen",
        "consoleCommandBatchRedo"
    },
    {
        "tpBatchRecover",
        "Unsicheren Batch wiederherstellen",
        "consoleCommandBatchRecover"
    },
    {
        "tpBatchStatus",
        "Fortschritt der Batch-Verarbeitung",
        "consoleCommandBatchStatus"
    }
}) do
    addCommand(
        spec[1], spec[2], spec[3]
    )
end


-- Kein gleichzeitiger Zugriff durch den alten
-- 9-Punkte-Writer und den neuen Batch-Writer.
for _, name in ipairs({
    "consoleCommandTerrainTest",
    "consoleCommandTerrainUndo",
    "consoleCommandTerrainRedo"
}) do
    local previous = TerraformPlus[name]

    if type(previous) == "function" then
        TerraformPlus[name] = function(self, ...)
            if TerrainBatch.blocksLegacy() then
                return "[Terraform Plus] Zuerst Batch zuruecksetzen: "
                    .. TerrainBatch.status()
            end

            return previous(self, ...)
        end
    end
end


-- Solange ein Batch schreibt oder zuruecksetzt,
-- sind Aenderungen an Auswahl und Sollwerten gesperrt.
for _, name in ipairs({
    "consoleCommandSelect",
    "consoleCommandClear",
    "consoleCommandAnchor",
    "consoleCommandConfirm",
    "consoleCommandCancel",
    "consoleCommandRefresh",
    "consoleCommandWidth",
    "consoleCommandGridStep",
    "consoleCommandTargetOffset",
    "consoleCommandTargetHeight",
    "consoleCommandTargetSlope",
    "consoleCommandEdgeBlend",
    "consoleCommandChangeLimit",
    "consoleCommandWorkMode",
    "consoleCommandDesignReset",
    "consoleCommandDesignUndo",
    "consoleCommandDesignRedo",
    "consoleCommandPlanPrepare",
    "consoleCommandPlanApprove",
    "consoleCommandPlanRun"
}) do
    local previous = TerraformPlus[name]

    if type(previous) == "function" then
        TerraformPlus[name] = function(self, ...)
            if TerrainBatch.busy() then
                return "[Terraform Plus] Batch laeuft: "
                    .. TerrainBatch.status()
            end

            return previous(self, ...)
        end
    end
end


local oldLoad = TerraformPlus.loadMap

function TerraformPlus:loadMap(...)
    TerrainBatch.transaction = nil
    TerrainBatch.armed = false

    return oldLoad(self, ...)
end


local oldUpdate = TerraformPlus.update

function TerraformPlus:update(dt, ...)
    if oldUpdate ~= nil then
        oldUpdate(self, dt, ...)
    end

    local ok, err = pcall(
        TerrainBatch.update, self
    )

    if not ok then
        if TerrainBatch.transaction then
            TerrainBatch.transaction.state = "uncertain"
        end

        print(
            "[Terraform Plus] KRITISCH: Batch-Laufzeitfehler "
            .. tostring(err)
        )
    end
end


local oldDelete = TerraformPlus.deleteMap

function TerraformPlus:deleteMap(...)
    TerrainBatch.restoreOnExit()

    local result = oldDelete(self, ...)

    TerrainBatch.transaction = nil
    TerrainBatch.armed = false

    return result
end


-- ===========================================
-- UI Erweiterung
-- ===========================================

local oldUIDraw = TerrainToolUI.draw

function TerrainToolUI.draw(owner)
    oldUIDraw(owner)

    if not TerrainToolUI.visible then
        return
    end

    if g_gui ~= nil
        and type(g_gui.getIsGuiVisible) == "function"
        and g_gui:getIsGuiVisible() then

        return
    end

    local c = TerrainToolUI.COLORS

    TerrainToolUI.rect(
        0.679, 0.747,
        0.246, 0.040, c.header
    )

    TerrainToolUI.text(
        0.690, 0.757,
        "TERRAFORM PLUS  0.0.15.0",
        0.016, c.text
    )

    if TerrainToolUI.page ~= "review" then
        return
    end

    -- Bestehenden Pruefungsreiter ersetzen.
    -- Bereich und Gestaltung bleiben erhalten.
    TerrainToolUI.rect(
        0.676, 0.121,
        0.302, 0.567, c.panel
    )

    TerrainToolUI.buttons = {}

    TerrainToolUI.button(
        "close", "X",
        0.939, 0.752,
        0.026, 0.031,
        true, "warning"
    )

    TerrainToolUI.button(
        "tabSelect", "BEREICH",
        0.690, 0.700,
        0.087, 0.036,
        true
    )

    TerrainToolUI.button(
        "tabDesign", "GESTALTUNG",
        0.783, 0.700,
        0.087, 0.036,
        true
    )

    TerrainToolUI.button(
        "tabReview", "PRUEFUNG",
        0.876, 0.700,
        0.089, 0.036,
        true, "active"
    )

    local tx = TerrainBatch.transaction
    local existing = TerrainWriter.transaction

    local fresh = TerrainPlan.isFresh(owner)

    local plan =
        fresh and owner.terrainPlan or nil

    local locked =
        tx ~= nil and tx.state ~= "undone"

    local progress =
        tx and tx.done / #tx.points or 0

    TerrainToolUI.text(
        0.690, 0.658,
        "PAKETBEARBEITUNG / TESTSPIELSTAND",
        0.012, c.text
    )

    TerrainToolUI.text(
        0.690, 0.628,

        plan and string.format(
            "Plan: %d Punkte | %.3f m Raster",
            #plan.points,
            plan.unit
        ) or "Kein freigegebener Pruefplan",

        0.012, c.muted
    )

    TerrainToolUI.text(
        0.690, 0.597,
        "Limit: 256 Punkte, je max. 0,25 m",
        0.012, c.muted
    )

    TerrainToolUI.text(
        0.690, 0.565,

        tx and string.format(
            "%s: %d/%d Punkte | Fehler: %d",
            tx.state,
            tx.done,
            #tx.points,
            tx.rollbackFailures
        ) or "Noch kein Batch",

        0.012, c.text
    )

    -- Fortschrittsbalken.
    TerrainToolUI.rect(
        0.690, 0.534,
        0.275, 0.013, c.disabled
    )

    TerrainToolUI.rect(
        0.690, 0.534,
        0.275 * progress, 0.013, c.active
    )

    TerrainToolUI.button(
        "prepare", "PRUEFRASTER",
        0.690, 0.474,
        0.132, 0.040,

        not TerrainBatch.busy()
            and owner.selection == nil
            and owner.pointA ~= nil
            and owner.pointB ~= nil
    )

    TerrainToolUI.button(
        "approve", "PLAN FREIGEBEN",
        0.833, 0.474,
        0.132, 0.040,

        not TerrainBatch.busy()
            and plan ~= nil
            and not plan.approved
    )

    TerrainToolUI.button(
        "batchApply",

        TerrainBatch.armed
            and "ECHT SCHREIBEN? ERNEUT KLICKEN"
            or "FLAECHE TESTWEISE BEARBEITEN",

        0.690, 0.413,
        0.275, 0.043,

        plan ~= nil
            and plan.approved
            and not locked
            and not (
                existing
                and (
                    existing.state == "applied"
                    or existing.state == "uncertain"
                )
            ),

        "warning"
    )

    TerrainToolUI.button(
        "batchCancel",
        "LAUF ABBRECHEN + RUECKNAHME",

        0.690, 0.360,
        0.275, 0.039,

        tx ~= nil and tx.state == "applying"
    )

    TerrainToolUI.button(
        "batchUndo",
        "GESAMTEN BATCH ZURUECKSETZEN",

        0.690, 0.311,
        0.275, 0.039,

        tx ~= nil and tx.state == "applied",
        "active"
    )

    TerrainToolUI.button(
        "batchRedo",
        "BATCH WIEDERHOLEN",

        0.690, 0.263,
        0.275, 0.039,

        tx ~= nil
            and tx.state == "undone"
            and tx.replayAllowed
    )

    TerrainToolUI.button(
        "batchRecover",
        "WIEDERHERSTELLUNG ERNEUT VERSUCHEN",

        0.690, 0.214,
        0.275, 0.039,

        tx ~= nil and tx.state == "uncertain",
        "warning"
    )

    TerrainToolUI.text(
        0.690, 0.156,
        "NICHT SPEICHERN! Erst Undo / Backup pruefen.",
        0.011, c.cut
    )
end


local oldPerform = TerrainToolUI.perform

function TerrainToolUI.perform(owner, id)
    if id == "batchApply" then

        if not TerrainBatch.armed then
            TerrainBatch.armed = true

            print(
                "[Terraform Plus] WARNUNG: Echter Eingriff. "
                .. "Erneut klicken zum Bestaetigen"
            )
        else
            TerrainBatch.armed = false

            print(
                owner:consoleCommandBatchApply("CONFIRM")
            )
        end

        return

    elseif id == "batchCancel" then
        print(owner:consoleCommandBatchCancel())
        return

    elseif id == "batchUndo" then
        print(owner:consoleCommandBatchUndo("CONFIRM"))
        return

    elseif id == "batchRedo" then
        print(owner:consoleCommandBatchRedo("CONFIRM"))
        return

    elseif id == "batchRecover" then
        print(owner:consoleCommandBatchRecover("CONFIRM"))
        return
    end

    TerrainBatch.armed = false

    return oldPerform(owner, id)
end


print(
    "[Terraform Plus] TerrainBatch 0.0.15.0 bereit: "
    .. "256 Punkte, 8/Frame, Undo/Redo"
)
