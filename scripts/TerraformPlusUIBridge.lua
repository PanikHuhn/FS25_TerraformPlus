
-- Terraform Plus 0.0.11.0 - UI and design integration
-- Loaded AFTER TerraformPlus.lua; tested 0.0.9 core remains unchanged.
if TerraformPlus==nil then error("TerraformPlus.lua muss zuerst geladen werden") end
if TerrainToolUI==nil then error("TerrainToolUI.lua muss zuerst geladen werden") end
if TerrainDesign==nil then error("TerrainDesign.lua muss zuerst geladen werden") end

local coreAlreadyHasUI = type(TerraformPlus.consoleCommandUI)=="function"
TerraformPlus.VERSION="0.0.11.0"

local function ensureCommand(name,desc,method)
    TerraformPlus.COMMANDS=TerraformPlus.COMMANDS or {}
    for _,v in ipairs(TerraformPlus.COMMANDS) do
        if v[1]==name then return end
    end
    table.insert(TerraformPlus.COMMANDS,{name,desc,method})
end
local function ensureAction(name,callback,label)
    TerraformPlus.INPUT_ACTIONS=TerraformPlus.INPUT_ACTIONS or {}
    for _,v in ipairs(TerraformPlus.INPUT_ACTIONS) do
        if v.name==name then return end
    end
    table.insert(TerraformPlus.INPUT_ACTIONS,
        {name=name,callback=callback,label=label})
end

function TerraformPlus:consoleCommandUI()
    local visible=TerrainToolUI.toggle()
    return "[Terraform Plus] Werkzeugfenster "
        ..(visible and "eingeblendet" or "ausgeblendet")
end
function TerraformPlus:consoleCommandUIMouse()
    local ok,state=TerrainToolUI.toggleMouse()
    if not ok then return "[Terraform Plus] Mausmodus-Fehler: "..tostring(state) end
    return "[Terraform Plus] UI-Mausmodus "
        ..(state and "aktiviert" or "deaktiviert")
end
function TerraformPlus:onInputUI() print(self:consoleCommandUI()) end
function TerraformPlus:onInputMouse() print(self:consoleCommandUIMouse()) end

local function settings(owner)
    if owner.design==nil then
        owner.design={offset=0,slope=0,feather=0,mode="all",enabled=true}
    end
    return owner.design
end
local function invalidate(owner)
    local d=settings(owner)
    d.cacheBase=nil
    d.cacheArea=nil
    d.cacheKey=nil
end
local function settingNumber(owner,key,value,minimum,maximum,label)
    local d=settings(owner)
    if value==nil or value=="" then
        return string.format("[Terraform Plus] %s: %.2f",label,d[key])
    end
    local n=tonumber(value)
    if n==nil or n~=n or n==math.huge or n==-math.huge
        or n<minimum or n>maximum then
        return string.format("[Terraform Plus] %s: erlaubt %.2f bis %.2f",
            label,minimum,maximum)
    end
    d[key]=n
    invalidate(owner)
    return string.format("[Terraform Plus] %s: %.2f",label,n)
end
function TerraformPlus:consoleCommandTargetOffset(value)
    return settingNumber(self,"offset",value,
        TerrainDesign.MIN_OFFSET,TerrainDesign.MAX_OFFSET,"Hoehenversatz (m)")
end
function TerraformPlus:consoleCommandTargetHeight(value)
    if self.pointA==nil then
        return "[Terraform Plus] Erst Startpunkt A setzen"
    end
    if value==nil or value=="" then
        return string.format("[Terraform Plus] Zielhoehe bei A: %.3f m",
            self.pointA.terrainY+settings(self).offset)
    end
    local height=tonumber(value)
    if height==nil or height~=height then
        return "[Terraform Plus] Gueltige Zielhoehe angeben"
    end
    return self:consoleCommandTargetOffset(
        tostring(height-self.pointA.terrainY))
end
function TerraformPlus:consoleCommandTargetSlope(value)
    return settingNumber(self,"slope",value,
        TerrainDesign.MIN_SLOPE,TerrainDesign.MAX_SLOPE,"Zielsteigung (%)")
end
function TerraformPlus:consoleCommandEdgeBlend(value)
    return settingNumber(self,"feather",value,
        TerrainDesign.MIN_FEATHER,TerrainDesign.MAX_FEATHER,"Weicher Rand (m)")
end
function TerraformPlus:consoleCommandWorkMode(mode)
    local d=settings(self)
    if mode==nil or mode=="" then
        return "[Terraform Plus] Modus: "..d.mode
    end
    mode=string.lower(tostring(mode))
    if mode~="all" and mode~="cut" and mode~="fill" then
        return "[Terraform Plus] Modus: all / cut / fill"
    end
    d.mode=mode
    invalidate(self)
    return "[Terraform Plus] Bearbeitungsmodus: "..mode
end
function TerraformPlus:consoleCommandDesignVisual()
    local d=settings(self)
    d.enabled=not d.enabled
    return "[Terraform Plus] Soll-Vorschau "
        ..(d.enabled and "aktiviert" or "deaktiviert")
end
function TerraformPlus:consoleCommandDesignReset()
    local d=settings(self)
    d.offset=0; d.slope=0; d.feather=0; d.mode="all"
    invalidate(self)
    return "[Terraform Plus] Soll-Gelaendeparameter zurueckgesetzt"
end

-- Work on the already measured raster: do not re-query terrain each frame.
function TerraformPlus:getDesignArea()
    local base
    if self.selection~=nil and self.selection.active then
        base=self.selection.preview and self.selection.preview.area or nil
    else
        base=self.area
    end
    if base==nil or self.pointA==nil then
        return nil,"Erst Start- und Endpunkt festlegen"
    end
    local d=settings(self)
    local key=string.format("%.5f:%.5f:%.5f:%s:%.5f",
        d.offset,d.slope,d.feather,d.mode,self.pointA.terrainY)
    if d.cacheBase==base and d.cachePointA==self.pointA
        and d.cacheKey==key then
        return d.cacheArea,d.cacheError
    end
    local ok,area,err=pcall(TerrainDesign.build,base,self.pointA,d)
    if not ok then err=tostring(area);area=nil end
    d.cacheBase=base
    d.cachePointA=self.pointA
    d.cacheKey=key
    d.cacheArea=area
    d.cacheError=err
    return area,err
end
function TerraformPlus:consoleCommandDesign()
    local d=settings(self)
    local area,err=self:getDesignArea()
    if area==nil then
        return "[Terraform Plus] Soll-Vorschau nicht bereit: "..tostring(err)
    end
    return string.format(
        "[Terraform Plus] SOLL | HoeheA=%.3f m | Steigung=%+.2f%% | Rand=%.2f m | Modus=%s | Abtrag=%.3f m3 | Auftrag=%.3f m3 | Netto=%+.3f m3 | Zellen=%d",
        area.startY,d.slope,d.feather,d.mode,
        area.cutVolume,area.fillVolume,area.netVolume,#area.samples)
end

for _,entry in ipairs({
    {"tpUI","Werkzeugfenster umschalten","consoleCommandUI"},
    {"tpUIMouse","UI-Mausmodus umschalten","consoleCommandUIMouse"},
    {"tpDesign","Soll-Gelaendevolumen anzeigen","consoleCommandDesign"},
    {"tpTargetOffset","Zielhoehe relativ zu A","consoleCommandTargetOffset"},
    {"tpTargetHeight","Absolute Sollhoehe bei A","consoleCommandTargetHeight"},
    {"tpTargetSlope","Sollsteigung in Prozent","consoleCommandTargetSlope"},
    {"tpEdgeBlend","Weichen Rand einstellen","consoleCommandEdgeBlend"},
    {"tpWorkMode","All/Cut/Fill festlegen","consoleCommandWorkMode"},
    {"tpDesignVisual","Soll-Vorschau ein/aus","consoleCommandDesignVisual"},
    {"tpDesignReset","Soll-Parameter zuruecksetzen","consoleCommandDesignReset"}
}) do ensureCommand(entry[1],entry[2],entry[3]) end
ensureAction("TP_TOOL_UI","onInputUI","Terraform Plus: Werkzeugfenster")
ensureAction("TP_TOOL_MOUSE","onInputMouse","Terraform Plus: Mausmodus")

local oldLoadMap=TerraformPlus.loadMap
function TerraformPlus:loadMap(...)
    local result=oldLoadMap(self,...)
    self.design={offset=0,slope=0,feather=0,mode="all",enabled=true}
    if not TerrainToolUI.initialized then TerrainToolUI.initialize(self) end
    print("[Terraform Plus] Soll-Gelaende und UI bereit - Version "..self.VERSION)
    return result
end

-- Do not double-hook an older all-in-one 0.0.10 core.
local oldDraw=TerraformPlus.draw
function TerraformPlus:draw(...)
    local designing=TerrainToolUI.page=="design"
    local previousAreaFlag=self.areaEnabled
    local previousProfileFlag=self.previewEnabled
    if designing then
        self.areaEnabled=false
        self.previewEnabled=false
    end
    local ok,err=pcall(oldDraw,self,...)
    self.areaEnabled=previousAreaFlag
    self.previewEnabled=previousProfileFlag
    if not ok then print("[Terraform Plus] Basiszeichnung: "..tostring(err)) end
    if designing and self.visualEnabled and settings(self).enabled then
        local area=self:getDesignArea()
        local targetB=self.pointB
        if self.selection~=nil and self.selection.active
            and self.selection.preview~=nil then
            targetB=self.selection.preview.pointB
        end
        if area~=nil and targetB~=nil then
            local drawn,drawErr=pcall(TerrainDesign.draw,area,self.pointA,targetB)
            if not drawn then print("[Terraform Plus] Soll-Zeichnung: "..tostring(drawErr)) end
        end
    end
    if not coreAlreadyHasUI and TerrainToolUI.visible then
        local drawn,drawErr=pcall(TerrainToolUI.draw,self)
        if not drawn then
            TerrainToolUI.visible=false
            TerrainToolUI.disableMouse()
            print("[Terraform Plus] UI-Zeichnung: "..tostring(drawErr))
        end
    end
end

if not coreAlreadyHasUI then
    local oldMouseEvent=TerraformPlus.mouseEvent
    function TerraformPlus:mouseEvent(x,y,down,up,button,eventUsed)
        local used=eventUsed or false
        if oldMouseEvent~=nil then
            used=oldMouseEvent(self,x,y,down,up,button,used) or used
        end
        if TerrainToolUI.mouseActive then
            local ok,result=pcall(TerrainToolUI.mouseEvent,
                self,x,y,down,up,button,used)
            if not ok then
                print("[Terraform Plus] UI-Mausfehler: "..tostring(result))
            else
                used=result or used
            end
        end
        return used
    end
end

local oldSample=TerraformPlus.getSelectionSample
function TerraformPlus:getSelectionSample(...)
    if TerrainToolUI.mouseActive then
        if TerrainToolUI.frozenSample==nil then
            return nil,"Kein Ziel fixiert: Rechtsklick, Boden anvisieren, Rechtsklick"
        end
        return self:createPoint(TerrainToolUI.frozenSample),nil
    end
    return oldSample(self,...)
end

local oldUpdate=TerraformPlus.update
function TerraformPlus:update(dt,...)
    if oldUpdate~=nil then oldUpdate(self,dt,...) end
    if TerrainToolUI.initialized then
        local ok,err=pcall(TerrainToolUI.update,self)
        if not ok then print("[Terraform Plus] UI-Update: "..tostring(err)) end
    end
end
local oldDeleteMap=TerraformPlus.deleteMap
function TerraformPlus:deleteMap(...)
    if TerrainToolUI.initialized then TerrainToolUI.delete() end
    self.design=nil
    return oldDeleteMap(self,...)
end
print("[Terraform Plus] 0.0.11.0 Methoden registriert (UI + Soll-Gelaende)")
