-- Terraform Plus - UI Integration Bridge
-- Version: 0.0.10.0 (right-click + camera freeze)
-- Load this AFTER TerraformPlus.lua in modDesc.xml.
-- Compatible with the tested 0.0.9.0 core as well as 0.0.10.0.

if TerraformPlus == nil then
    error("[Terraform Plus] TerraformPlus.lua muss vor TerraformPlusUIBridge.lua geladen werden")
end
if TerrainToolUI == nil then
    error("[Terraform Plus] TerrainToolUI.lua muss vor TerraformPlusUIBridge.lua geladen werden")
end

local hadIntegratedUI = type(TerraformPlus.consoleCommandUI) == "function"
TerraformPlus.VERSION = "0.0.10.0"

-- Both handlers are explicitly defined BEFORE loadMap registers commands.
function TerraformPlus:consoleCommandUI()
    local visible = TerrainToolUI.toggle()
    return "[Terraform Plus] Werkzeugfenster "
        .. (visible and "eingeblendet" or "ausgeblendet")
end

function TerraformPlus:consoleCommandUIMouse()
    local ok, state = TerrainToolUI.toggleMouse()
    if not ok then
        return "[Terraform Plus] Mausmodus-Fehler: " .. tostring(state)
    end
    return "[Terraform Plus] UI-Mausmodus "
        .. (state and "aktiviert" or "deaktiviert")
end

function TerraformPlus:onInputUI()
    print(self:consoleCommandUI())
end

function TerraformPlus:onInputMouse()
    print(self:consoleCommandUIMouse())
end

-- No duplicate command entries, regardless of which core was copied.
local function hasCommand(name)
    for _, entry in ipairs(TerraformPlus.COMMANDS or {}) do
        if entry[1] == name or entry.name == name then
            return true
        end
    end
    return false
end

TerraformPlus.COMMANDS = TerraformPlus.COMMANDS or {}
for _, spec in ipairs({
    {"tpUI", "Werkzeugfenster umschalten", "consoleCommandUI"},
    {"tpUIMouse", "UI-Mausmodus umschalten", "consoleCommandUIMouse"}
}) do
    if not hasCommand(spec[1]) then
        table.insert(TerraformPlus.COMMANDS, spec)
    end
end

local function hasAction(name)
    for _, action in ipairs(TerraformPlus.INPUT_ACTIONS or {}) do
        if action.name == name then
            return true
        end
    end
    return false
end

TerraformPlus.INPUT_ACTIONS = TerraformPlus.INPUT_ACTIONS or {}
for _, spec in ipairs({
    {name="TP_TOOL_UI", callback="onInputUI", label="Terraform Plus: Werkzeugfenster"},
    {name="TP_TOOL_MOUSE", callback="onInputMouse", label="Terraform Plus: Mausmodus"}
}) do
    if not hasAction(spec.name) then
        table.insert(TerraformPlus.INPUT_ACTIONS, spec)
    end
end

local originalLoadMap = TerraformPlus.loadMap
function TerraformPlus:loadMap(...)
    -- Register all commands via existing loadMap, including our appended commands.
    local result = originalLoadMap(self, ...)
    if not TerrainToolUI.initialized then
        TerrainToolUI.initialize(self)
    end

    local required = {
        tpUI = "consoleCommandUI",
        tpUIMouse = "consoleCommandUIMouse"
    }
    for name, method in pairs(required) do
        local ready = hasCommand(name) and type(self[method]) == "function"
        print(string.format("[Terraform Plus] CHECK %s: %s", name,
            ready and "registriert" or "FEHLT"))
    end
    print("[Terraform Plus] UI Bridge geladen - Version " .. self.VERSION)
    return result
end

-- If the core already included a UI draw/mouse hook, do not double-wire it.
if not hadIntegratedUI then
    local originalDraw = TerraformPlus.draw
    function TerraformPlus:draw(...)
        if originalDraw ~= nil then
            originalDraw(self, ...)
        end
        if TerrainToolUI.visible then
            local ok, err = pcall(TerrainToolUI.draw, self)
            if not ok then
                TerrainToolUI.visible = false
                TerrainToolUI.disableMouse()
                print("[Terraform Plus] UI-Zeichenfehler: " .. tostring(err))
            end
        end
    end

    local originalMouseEvent = TerraformPlus.mouseEvent
    function TerraformPlus:mouseEvent(x, y, down, up, button, eventUsed)
        local used = eventUsed or false
        if originalMouseEvent ~= nil then
            used = originalMouseEvent(self, x, y, down, up, button, used) or used
        end
        if TerrainToolUI.mouseActive then
            local ok, result = pcall(
                TerrainToolUI.mouseEvent,
                self, x, y, down, up, button, used
            )
            if not ok then
                print("[Terraform Plus] UI-Mausfehler: " .. tostring(result))
            else
                used = result or used
            end
        end
        return used
    end
end

local originalDeleteMap = TerraformPlus.deleteMap
function TerraformPlus:deleteMap(...)
    if TerrainToolUI.initialized then
        TerrainToolUI.delete()
    end
    return originalDeleteMap(self, ...)
end

-- FIX: Beim Anklicken der UI immer den beim Rechtsklick
-- gesicherten Zielpunkt verwenden (keine verrutschten A/B-Punkte).
local originalSelectionSample = TerraformPlus.getSelectionSample
function TerraformPlus:getSelectionSample(...)
    if TerrainToolUI.mouseActive then
        local sample = TerrainToolUI.frozenSample
        if sample == nil then
            return nil, "Kein Ziel fixiert. Mit Rechtsklick zur Kamera zurueck, "
                .. "Boden anvisieren und erneut Rechtsklick"
        end
        return self:createPoint(sample), nil
    end
    return originalSelectionSample(self, ...)
end

-- Bei Wechsel Kamera/Spieler im UI-Modus muss auch der
-- eingefrorene Zielpunkt zur neuen Zielquelle passen.
local originalCursorMode = TerraformPlus.consoleCommandCursorMode
if type(originalCursorMode) == "function" then
    function TerraformPlus:consoleCommandCursorMode(mode)
        local previous = self.cursorMode
        local message = originalCursorMode(self, mode)
        if TerrainToolUI.mouseActive and previous ~= self.cursorMode then
            local ok, sample = pcall(originalSelectionSample, self)
            if ok and sample ~= nil then
                TerrainToolUI.frozenSample = self:createPoint(sample)
            else
                TerrainToolUI.frozenSample = nil
            end
        end
        return message
    end
end

-- Auch ohne laufende Auswahl Rechtsklicks pruefen.
local originalUpdate = TerraformPlus.update
function TerraformPlus:update(dt, ...)
    if originalUpdate ~= nil then
        originalUpdate(self, dt, ...)
    end
    if TerrainToolUI.initialized then
        local ok, err = pcall(TerrainToolUI.update, self)
        if not ok then
            print("[Terraform Plus] UI-Updatefehler: " .. tostring(err))
        end
    end
end

print("[Terraform Plus] UI-Funktionen definiert: tpUI / tpUIMouse")
