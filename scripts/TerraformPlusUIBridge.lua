
-- Terraform Plus v0.0.12.0 - UI/Planung Integration
-- Muss NACH TerraformPlus.lua in modDesc.xml geladen werden.
if TerraformPlus==nil then error("TerraformPlus.lua fehlt") end
if TerrainToolUI==nil then error("TerrainToolUI.lua fehlt") end
if TerrainDesign==nil then error("TerrainDesign.lua fehlt") end

local coreHasUI=type(TerraformPlus.consoleCommandUI)=="function"
TerraformPlus.VERSION="0.0.12.0"
local function ensureCommand(name,description,method)
    TerraformPlus.COMMANDS=TerraformPlus.COMMANDS or {}
    for _,c in ipairs(TerraformPlus.COMMANDS) do
        if c[1]==name then return end
    end
    table.insert(TerraformPlus.COMMANDS,{name,description,method})
end
local function ensureAction(name,callback,label)
    TerraformPlus.INPUT_ACTIONS=TerraformPlus.INPUT_ACTIONS or {}
    for _,a in ipairs(TerraformPlus.INPUT_ACTIONS) do
        if a.name==name then return end
    end
    table.insert(TerraformPlus.INPUT_ACTIONS,
        {name=name,callback=callback,label=label})
end

function TerraformPlus:consoleCommandUI()
    local shown=TerrainToolUI.toggle()
    return "[Terraform Plus] Werkzeugfenster "
        ..(shown and "eingeblendet" or "ausgeblendet")
end
function TerraformPlus:consoleCommandUIMouse()
    local ok,active=TerrainToolUI.toggleMouse()
    if not ok then return "[Terraform Plus] Mausmodus-Fehler: "..tostring(active) end
    return "[Terraform Plus] UI-Mausmodus "
        ..(active and "aktiviert" or "deaktiviert")
end
function TerraformPlus:onInputUI() print(self:consoleCommandUI()) end
function TerraformPlus:onInputMouse() print(self:consoleCommandUIMouse()) end

local function design(owner)
    if owner.design==nil then
        owner.design={offset=0,slope=0,feather=0,
            maxChange=TerrainDesign.DEFAULT_CHANGE,mode="all",enabled=true}
    end
    if owner.design.maxChange==nil then
        owner.design.maxChange=TerrainDesign.DEFAULT_CHANGE
    end
    return owner.design
end
local function invalidate(owner)
    local d=design(owner)
    d.cacheBase=nil
    d.cachePointA=nil
    d.cacheKey=nil
    d.cacheArea=nil
    d.cacheError=nil
end
local function setNumber(owner,field,value,min,max,label)
    local d=design(owner)
    if value==nil or value=="" then
        return string.format("[Terraform Plus] %s: %.2f",label,d[field])
    end
    local n=tonumber(value)
    if n==nil or n~=n or n==math.huge or n==-math.huge
        or n<min or n>max then
        return string.format("[Terraform Plus] %s: erlaubt %.2f bis %.2f",
            label,min,max)
    end
    d[field]=n
    invalidate(owner)
    return string.format("[Terraform Plus] %s: %.2f",label,n)
end

function TerraformPlus:consoleCommandTargetOffset(value)
    return setNumber(self,"offset",value,TerrainDesign.MIN_OFFSET,
        TerrainDesign.MAX_OFFSET,"Hoehenversatz (m)")
end
function TerraformPlus:consoleCommandTargetHeight(value)
    if self.pointA==nil then return "[Terraform Plus] Erst Punkt A setzen" end
    if value==nil or value=="" then
        return string.format("[Terraform Plus] Zielhoehe A: %.3f m",
            self.pointA.terrainY+design(self).offset)
    end
    local n=tonumber(value)
    if n==nil or n~=n or n==math.huge or n==-math.huge then
        return "[Terraform Plus] Zielhoehe muss eine endliche Zahl sein"
    end
    return self:consoleCommandTargetOffset(tostring(n-self.pointA.terrainY))
end
function TerraformPlus:consoleCommandTargetSlope(value)
    return setNumber(self,"slope",value,TerrainDesign.MIN_SLOPE,
        TerrainDesign.MAX_SLOPE,"Zielsteigung (%)")
end
function TerraformPlus:consoleCommandEdgeBlend(value)
    return setNumber(self,"feather",value,TerrainDesign.MIN_FEATHER,
        TerrainDesign.MAX_FEATHER,"Weicher Rand (m)")
end
function TerraformPlus:consoleCommandChangeLimit(value)
    return setNumber(self,"maxChange",value,TerrainDesign.MIN_CHANGE,
        TerrainDesign.MAX_CHANGE,"Max. Hoehenaenderung (m)")
end
function TerraformPlus:consoleCommandWorkMode(value)
    local d=design(self)
    if value==nil or value=="" then
        return "[Terraform Plus] Bearbeitungsmodus: "..d.mode
    end
    local mode=string.lower(tostring(value))
    if mode~="all" and mode~="cut" and mode~="fill" then
        return "[Terraform Plus] Modus: all / cut / fill"
    end
    d.mode=mode
    invalidate(self)
    return "[Terraform Plus] Bearbeitungsmodus: "..mode
end
function TerraformPlus:consoleCommandDesignVisual()
    local d=design(self)
    d.enabled=not d.enabled
    return "[Terraform Plus] Soll-Vorschau "
        ..(d.enabled and "aktiviert" or "deaktiviert")
end
function TerraformPlus:consoleCommandDesignReset()
    local d=design(self)
    d.offset=0
    d.slope=0
    d.feather=0
    d.maxChange=TerrainDesign.DEFAULT_CHANGE
    d.mode="all"
    invalidate(self)
    return "[Terraform Plus] Soll-Gelaendeparameter zurueckgesetzt"
end

-- Rechnet ausschliesslich mit dem bereits abgetasteten Raster.
function TerraformPlus:getDesignArea()
    local base
    if self.selection~=nil and self.selection.active then
        base=self.selection.preview and self.selection.preview.area or nil
    else
        base=self.area
    end
    if base==nil or self.pointA==nil then
        return nil,"Zuerst Start- und Endpunkt setzen"
    end
    local d=design(self)
    local key=string.format("%.6f;%.6f;%.6f;%.6f;%s;%.6f",
        d.offset,d.slope,d.feather,d.maxChange,d.mode,self.pointA.terrainY)
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
    local a,err=self:getDesignArea()
    if a==nil then
        return "[Terraform Plus] Soll-Vorschau nicht bereit: "..tostring(err)
    end
    return string.format(
        "[Terraform Plus] SOLL | HoeheA=%.3f m | Steigung=%+.2f%% | Rand=%.2f m | Modus=%s | Limit=%.2f m | Abtrag=%.3f m3 | Auftrag=%.3f m3 | Netto=%+.3f m3 | BegrenzteZellen=%d/%d | NichtGeplantesVolumen=%.3f m3",
        a.startY,a.slope,a.feather,a.mode,a.maxChange,
        a.cutVolume,a.fillVolume,a.netVolume,a.limitedCells,#a.samples,
        a.limitedVolume)
end
function TerraformPlus:consoleCommandDesignCheck()
    local a,err=self:getDesignArea()
    if a==nil then
        return "[Terraform Plus] PRUEFUNG NICHT MOEGLICH: "..tostring(err)
    end
    local state=a.limitedCells>0 and "BEGRENZT" or "INNERHALB LIMIT"
    return string.format(
        "[Terraform Plus] VORSCHAU-PRUEFUNG: %s | Max. Sollbedarf=%.2f m | Grenzwert=%.2f m | Limit aktiv in %d/%d Rasterzellen | Abtrag=%.2f m3 | Auftrag=%.2f m3 | KEINE GELAENDEAENDERUNG",
        state,a.maxRequested,a.maxChange,a.limitedCells,#a.samples,
        a.cutVolume,a.fillVolume)
end

for _,c in ipairs({
    {"tpUI","Werkzeugfenster ein/aus","consoleCommandUI"},
    {"tpUIMouse","Mausmodus ein/aus","consoleCommandUIMouse"},
    {"tpDesign","Soll-Gelaende anzeigen","consoleCommandDesign"},
    {"tpDesignCheck","Soll-Plan pruefen","consoleCommandDesignCheck"},
    {"tpTargetOffset","Hoehenversatz","consoleCommandTargetOffset"},
    {"tpTargetHeight","Absolute Zielhoehe","consoleCommandTargetHeight"},
    {"tpTargetSlope","Zielsteigung","consoleCommandTargetSlope"},
    {"tpEdgeBlend","Weicher Rand","consoleCommandEdgeBlend"},
    {"tpChangeLimit","Maximale Hoehenaenderung","consoleCommandChangeLimit"},
    {"tpWorkMode","Bearbeitungsmodus","consoleCommandWorkMode"},
    {"tpDesignVisual","Soll-Vorschau umschalten","consoleCommandDesignVisual"},
    {"tpDesignReset","Soll-Plan zuruecksetzen","consoleCommandDesignReset"}
}) do ensureCommand(c[1],c[2],c[3]) end
ensureAction("TP_TOOL_UI","onInputUI","Terraform Plus: Werkzeugfenster")
ensureAction("TP_TOOL_MOUSE","onInputMouse","Terraform Plus: Mausmodus")

local oldLoadMap=TerraformPlus.loadMap
function TerraformPlus:loadMap(...)
    local result=oldLoadMap(self,...)
    self.design={offset=0,slope=0,feather=0,
        maxChange=TerrainDesign.DEFAULT_CHANGE,mode="all",enabled=true}
    if not TerrainToolUI.initialized then TerrainToolUI.initialize(self) end
    print("[Terraform Plus] Soll-Gelaende und UI bereit - Version "..self.VERSION)
    return result
end

local oldDraw=TerraformPlus.draw
function TerraformPlus:draw(...)
    local designing=TerrainToolUI.page=="design"
    local wasArea,wasProfile=self.areaEnabled,self.previewEnabled
    if designing then
        self.areaEnabled=false
        self.previewEnabled=false
    end
    local ok,err=pcall(oldDraw,self,...)
    self.areaEnabled,self.previewEnabled=wasArea,wasProfile
    if not ok then print("[Terraform Plus] Basis-Zeichnung: "..tostring(err)) end
    if designing and self.visualEnabled and design(self).enabled then
        local area=self:getDesignArea()
        local targetB=self.pointB
        if self.selection~=nil and self.selection.active
            and self.selection.preview~=nil then
            targetB=self.selection.preview.pointB
        end
        if area~=nil and targetB~=nil then
            local drawn,drawErr=pcall(TerrainDesign.draw,area,self.pointA,targetB)
            if not drawn then
                print("[Terraform Plus] Soll-Vorschau-Zeichnung: "..tostring(drawErr))
            end
        end
    end
    if not coreHasUI and TerrainToolUI.visible then
        local drawn,drawErr=pcall(TerrainToolUI.draw,self)
        if not drawn then
            TerrainToolUI.visible=false
            TerrainToolUI.disableMouse()
            print("[Terraform Plus] UI-Zeichenfehler: "..tostring(drawErr))
        end
    end
end

if not coreHasUI then
    local oldMouse=TerraformPlus.mouseEvent
    function TerraformPlus:mouseEvent(x,y,down,up,button,eventUsed)
        local used=eventUsed or false
        if oldMouse~=nil then
            used=oldMouse(self,x,y,down,up,button,used) or used
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

-- Im UI-Mausmodus wird der zuletzt anvisierte Terrainpunkt festgehalten.
local oldSample=TerraformPlus.getSelectionSample
function TerraformPlus:getSelectionSample(...)
    if TerrainToolUI.mouseActive then
        if TerrainToolUI.frozenSample==nil then
            return nil,"Kein Terrainziel fixiert: Rechtsklick, Boden anvisieren, Rechtsklick"
        end
        return self:createPoint(TerrainToolUI.frozenSample),nil
    end
    return oldSample(self,...)
end

local oldUpdate=TerraformPlus.update
function TerraformPlus:update(dt,...)
    if oldUpdate~=nil then oldUpdate(self,dt,...) end
    if TerrainToolUI.initialized then
        local ok,err=pcall(TerrainToolUI.update,self,dt)
        if not ok then print("[Terraform Plus] UI-Updatefehler: "..tostring(err)) end
    end
end
local oldDeleteMap=TerraformPlus.deleteMap
function TerraformPlus:deleteMap(...)
    if TerrainToolUI.initialized then TerrainToolUI.delete() end
    self.design=nil
    return oldDeleteMap(self,...)
end

print("[Terraform Plus] 0.0.12.0 Methoden registriert (UI + Hoehenlimit)")
