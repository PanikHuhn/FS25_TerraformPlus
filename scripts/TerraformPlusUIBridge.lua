-- Terraform Plus v0.0.13.0 - UI, Entwurf, Undo/Redo und Prueflauf
-- Nach TerraformPlus.lua laden. Der getestete Kern bleibt unveraendert.
assert(TerraformPlus ~= nil and TerrainToolUI ~= nil and TerrainDesign ~= nil
    and TerrainPlan ~= nil, "Terraform Plus: Lade-Reihenfolge falsch")
local coreHasUI = type(TerraformPlus.consoleCommandUI) == "function"
TerraformPlus.VERSION = "0.0.13.0"

local function command(name, description, method)
    for _, entry in ipairs(TerraformPlus.COMMANDS) do
        if entry[1] == name then return end
    end
    table.insert(TerraformPlus.COMMANDS, { name, description, method })
end
local function action(name, callback, label)
    for _, entry in ipairs(TerraformPlus.INPUT_ACTIONS) do
        if entry.name == name then return end
    end
    table.insert(TerraformPlus.INPUT_ACTIONS,
        { name = name, callback = callback, label = label })
end

function TerraformPlus:consoleCommandUI()
    local visible = TerrainToolUI.toggle()
    return "[Terraform Plus] Werkzeugfenster " ..
        (visible and "eingeblendet" or "ausgeblendet")
end

function TerraformPlus:consoleCommandUIMouse()
    local ok, active = TerrainToolUI.toggleMouse()
    if not ok then return "[Terraform Plus] Mausmodus-Fehler: " .. tostring(active) end
    return "[Terraform Plus] UI-Mausmodus " .. (active and "aktiviert" or "deaktiviert")
end

function TerraformPlus:onInputUI() print(self:consoleCommandUI()) end

function TerraformPlus:onInputMouse() print(self:consoleCommandUIMouse()) end

local function design(owner)
    if owner.design == nil then
        owner.design = {
            offset = 0,
            slope = 0,
            feather = 0,
            maxChange = 10,
            mode = "all",
            enabled = true
        }
    end
    if owner.design.maxChange == nil then owner.design.maxChange = 10 end
    return owner.design
end
local function invalidate(owner)
    local d = design(owner)
    d.cacheBase = nil; d.cachePointA = nil; d.cacheKey = nil
    d.cacheArea = nil; d.cacheError = nil
    TerrainPlan.invalidate(owner)
end
local function modified(owner, before)
    invalidate(owner)
    TerrainPlan.record(owner, before)
end
local function number(owner, field, value, low, high, name)
    local d = design(owner)
    if value == nil or value == "" then
        return string.format("[Terraform Plus] %s: %.2f", name, d[field])
    end
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge
        or n < low or n > high then
        return string.format("[Terraform Plus] %s: Bereich %.2f bis %.2f", name, low, high)
    end
    if n ~= d[field] then
        local before = TerrainPlan.snapshot(d)
        d[field] = n
        modified(owner, before)
    end
    return string.format("[Terraform Plus] %s: %.2f", name, d[field])
end

function TerraformPlus:beginDesignEdit()
    TerrainPlan.beginEdit(self)
end

function TerraformPlus:endDesignEdit()
    TerrainPlan.endEdit(self)
end

function TerraformPlus:consoleCommandDesignUndo()
    local ok, message = TerrainPlan.undo(self)
    return "[Terraform Plus] " .. message
end

function TerraformPlus:consoleCommandDesignRedo()
    local ok, message = TerrainPlan.redo(self)
    return "[Terraform Plus] " .. message
end

function TerraformPlus:consoleCommandTargetOffset(value)
    return number(self, "offset", value, -100, 100, "Hoehenversatz (m)")
end

function TerraformPlus:consoleCommandTargetHeight(value)
    if self.pointA == nil then return "[Terraform Plus] Erst Punkt A setzen" end
    if value == nil or value == "" then
        return string.format("[Terraform Plus] Zielhoehe A: %.3f m",
            self.pointA.terrainY + design(self).offset)
    end
    local n = tonumber(value)
    if n == nil or n ~= n or n == math.huge or n == -math.huge then
        return "[Terraform Plus] Bitte endliche Zielhoehe eingeben"
    end
    return self:consoleCommandTargetOffset(tostring(n - self.pointA.terrainY))
end

function TerraformPlus:consoleCommandTargetSlope(v)
    return number(self, "slope", v, -100, 100, "Zielsteigung (%)")
end

function TerraformPlus:consoleCommandEdgeBlend(v)
    return number(self, "feather", v, 0, 20, "Weicher Rand (m)")
end

function TerraformPlus:consoleCommandChangeLimit(v)
    return number(self, "maxChange", v, 0.5, 50, "Max. Hoehenaenderung (m)")
end

function TerraformPlus:consoleCommandWorkMode(v)
    local d = design(self)
    if v == nil or v == "" then return "[Terraform Plus] Modus: " .. d.mode end
    local mode = string.lower(tostring(v))
    if mode ~= "all" and mode ~= "cut" and mode ~= "fill" then
        return "[Terraform Plus] Modus: all / cut / fill"
    end
    if d.mode ~= mode then
        local before = TerrainPlan.snapshot(d)
        d.mode = mode; modified(self, before)
    end
    return "[Terraform Plus] Bearbeitungsmodus: " .. mode
end

function TerraformPlus:consoleCommandDesignVisual()
    local d = design(self)
    local before = TerrainPlan.snapshot(d)
    d.enabled = not d.enabled
    modified(self, before)
    return "[Terraform Plus] Soll-Vorschau " .. (d.enabled and "aktiviert" or "deaktiviert")
end

function TerraformPlus:consoleCommandDesignReset()
    local d = design(self)
    local before = TerrainPlan.snapshot(d)
    d.offset = 0; d.slope = 0; d.feather = 0; d.maxChange = 10; d.mode = "all"
    modified(self, before)
    return "[Terraform Plus] Soll-Gelaendeparameter zurueckgesetzt"
end

function TerraformPlus:getDesignArea()
    local base
    if self.selection ~= nil and self.selection.active then
        base = self.selection.preview and self.selection.preview.area or nil
    else
        base = self.area
    end
    if base == nil or self.pointA == nil then
        return nil, "Erst Start- und Endpunkt festlegen"
    end
    local d = design(self)
    local key = string.format("%.7f/%.7f/%.7f/%.7f/%s/%.7f",
        d.offset, d.slope, d.feather, d.maxChange, d.mode, self.pointA.terrainY)
    if d.cacheBase == base and d.cachePointA == self.pointA and d.cacheKey == key then
        return d.cacheArea, d.cacheError
    end
    local ok, a, err = pcall(TerrainDesign.build, base, self.pointA, d)
    if not ok then
        err = tostring(a); a = nil
    end
    d.cacheBase = base; d.cachePointA = self.pointA; d.cacheKey = key
    d.cacheArea = a; d.cacheError = err
    return a, err
end

function TerraformPlus:consoleCommandDesign()
    local a, err = self:getDesignArea()
    if a == nil then return "[Terraform Plus] SOLL nicht bereit: " .. tostring(err) end
    return string.format(
        "[Terraform Plus] SOLL | A=%.3f m | Steigung=%+.2f%% | Rand=%.2f m | Limit=%.2f m | Modus=%s | Abtrag=%.2f m3 | Auftrag=%.2f m3 | BegrenzteZellen=%d/%d",
        a.startY, a.slope, a.feather, a.maxChange, a.mode, a.cutVolume, a.fillVolume,
        a.limitedCells, #a.samples)
end

function TerraformPlus:consoleCommandDesignCheck()
    local a, err = self:getDesignArea()
    if a == nil then return "[Terraform Plus] Pruefung fehlgeschlagen: " .. tostring(err) end
    return string.format(
        "[Terraform Plus] VORSCHAU | %d Zellen | Max. Bedarf=%.2f m | Hoehenlimit=%.2f m | Begrenzt=%d | KEINE TERRAINAENDERUNG",
        #a.samples, a.maxRequested, a.maxChange, a.limitedCells)
end

function TerraformPlus:consoleCommandPlanPrepare()
    local plan, err = TerrainPlan.prepare(self)
    if plan == nil then return "[Terraform Plus] PLAN-FEHLER: " .. tostring(err) end
    return string.format(
        "[Terraform Plus] PLAN BEREIT | Heightmap-Schritt=%.3f m | Rasterpunkte=%d | Betroffen=%d | Limitaktiv=%d | Abtrag ca. %.2f m3 | Auftrag ca. %.2f m3 | KEINE AENDERUNG",
        plan.unit, plan.checked, #plan.points, plan.limited,
        plan.cutVolume, plan.fillVolume)
end

function TerraformPlus:consoleCommandPlanApprove(token)
    if token ~= "CONFIRM" then
        return "[Terraform Plus] Bestaetigung erforderlich: tpPlanApprove CONFIRM"
    end
    local ok, message = TerrainPlan.approve(self)
    return "[Terraform Plus] " .. message
end

function TerraformPlus:consoleCommandPlanRun(token)
    if token ~= "RUN" then
        return "[Terraform Plus] Probelauf: tpPlanRun RUN"
    end
    local ok, message = TerrainPlan.dryRun(self)
    return "[Terraform Plus] " .. message
end

for _, s in ipairs({
    { "tpUI",           "Fenster anzeigen",                "consoleCommandUI" },
    { "tpUIMouse",      "UI-Maus umschalten",              "consoleCommandUIMouse" },
    { "tpDesign",       "Sollwerte anzeigen",              "consoleCommandDesign" },
    { "tpDesignCheck",  "Soll-Raster pruefen",             "consoleCommandDesignCheck" },
    { "tpTargetOffset", "Hoehenversatz",                   "consoleCommandTargetOffset" },
    { "tpTargetHeight", "Absolute Zielhoehe",              "consoleCommandTargetHeight" },
    { "tpTargetSlope",  "Zielsteigung",                    "consoleCommandTargetSlope" },
    { "tpEdgeBlend",    "Weicher Rand",                    "consoleCommandEdgeBlend" },
    { "tpChangeLimit",  "Max. Hoehenaenderung",            "consoleCommandChangeLimit" },
    { "tpWorkMode",     "Abtrag oder Auftrag",             "consoleCommandWorkMode" },
    { "tpDesignVisual", "Soll-Vorschau umschalten",        "consoleCommandDesignVisual" },
    { "tpDesignReset",  "Gestaltung zuruecksetzen",        "consoleCommandDesignReset" },
    { "tpDesignUndo",   "Gestaltung rueckgaengig",         "consoleCommandDesignUndo" },
    { "tpDesignRedo",   "Gestaltung wiederherstellen",     "consoleCommandDesignRedo" },
    { "tpPlanPrepare",  "Heightmap-Pruefraster erstellen", "consoleCommandPlanPrepare" },
    { "tpPlanApprove",  "Pruefplan bestaetigen",           "consoleCommandPlanApprove" },
    { "tpPlanRun",      "Sicheren Probelauf ausfuehren",   "consoleCommandPlanRun" }
}) do command(s[1], s[2], s[3]) end

action("TP_TOOL_UI", "onInputUI", "Terraform Plus: Werkzeugfenster")
action("TP_TOOL_MOUSE", "onInputMouse", "Terraform Plus: Mausmodus")

local oldLoad = TerraformPlus.loadMap
function TerraformPlus:loadMap(...)
    local result = oldLoad(self, ...)
    self.design = { offset = 0, slope = 0, feather = 0, maxChange = 10, mode = "all", enabled = true }
    self.designUndo = {}; self.designRedo = {}; self.designEditBefore = nil
    self.terrainPlan = nil
    if not TerrainToolUI.initialized then TerrainToolUI.initialize(self) end
    print("[Terraform Plus] UI, Entwurfsverlauf und Pruefplan bereit - " .. self.VERSION)
    return result
end

local oldDraw = TerraformPlus.draw
function TerraformPlus:draw(...)
    local designPage = TerrainToolUI.page == "design" or TerrainToolUI.page == "review"
    local oldArea, oldProfile = self.areaEnabled, self.previewEnabled
    if designPage then
        self.areaEnabled = false; self.previewEnabled = false
    end
    local ok, err = pcall(oldDraw, self, ...)
    self.areaEnabled, self.previewEnabled = oldArea, oldProfile
    if not ok then print("[Terraform Plus] Basis-Zeichenfehler: " .. tostring(err)) end
    if designPage and self.visualEnabled and design(self).enabled then
        local area = self:getDesignArea()
        local b = self.pointB
        if self.selection ~= nil and self.selection.active and self.selection.preview ~= nil then
            b = self.selection.preview.pointB
        end
        if area ~= nil and b ~= nil then
            local drawn, msg = pcall(TerrainDesign.draw, area, self.pointA, b)
            if not drawn then print("[Terraform Plus] Soll-Zeichenfehler: " .. tostring(msg)) end
        end
    end
    if not coreHasUI and TerrainToolUI.visible then
        local drawn, msg = pcall(TerrainToolUI.draw, self)
        if not drawn then
            TerrainToolUI.visible = false; TerrainToolUI.disableMouse()
            print("[Terraform Plus] UI-Zeichenfehler: " .. tostring(msg))
        end
    end
end

if not coreHasUI then
    local oldMouse = TerraformPlus.mouseEvent
    function TerraformPlus:mouseEvent(x, y, down, up, button, used)
        if oldMouse ~= nil then used = oldMouse(self, x, y, down, up, button, used) or used end
        if TerrainToolUI.mouseActive then
            local ok, result = pcall(TerrainToolUI.mouseEvent, self, x, y, down, up, button, used)
            if ok then
                used = result or used
            else
                print("[Terraform Plus] UI-Mausfehler: " .. tostring(result))
            end
        end
        return used
    end
end

local oldSample = TerraformPlus.getSelectionSample
function TerraformPlus:getSelectionSample(...)
    if TerrainToolUI.mouseActive then
        if TerrainToolUI.frozenSample == nil then
            return nil, "Kein Kameraziel fixiert. Mit Rechtsklick erneut anvisieren"
        end
        return self:createPoint(TerrainToolUI.frozenSample), nil
    end
    return oldSample(self, ...)
end

-- tpClear verwirft auch alle vorbereiteten Probelaufdaten.
local oldClear = TerraformPlus.consoleCommandClear
function TerraformPlus:consoleCommandClear(...)
    local message = oldClear(self, ...)
    TerrainPlan.invalidate(self)
    return message
end

local oldUpdate = TerraformPlus.update
function TerraformPlus:update(dt, ...)
    if oldUpdate ~= nil then oldUpdate(self, dt, ...) end
    if TerrainToolUI.initialized then
        local ok, err = pcall(TerrainToolUI.update, self, dt)
        if not ok then print("[Terraform Plus] UI-Updatefehler: " .. tostring(err)) end
    end
end

local oldDelete = TerraformPlus.deleteMap
function TerraformPlus:deleteMap(...)
    if TerrainToolUI.initialized then TerrainToolUI.delete() end
    self.terrainPlan = nil; self.designEditBefore = nil
    self.designUndo = nil; self.designRedo = nil; self.design = nil
    return oldDelete(self, ...)
end

print("[Terraform Plus] 0.0.13.0 Methoden registriert (Undo/Redo + Pruefplan)")
