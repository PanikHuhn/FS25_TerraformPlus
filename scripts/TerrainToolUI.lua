
-- Terraform Plus v0.0.13.0 - UI: halbe Meter, Halten, Undo, Pruefung
TerrainToolUI = TerrainToolUI or {}
TerrainToolUI.X,TerrainToolUI.Y,TerrainToolUI.W,TerrainToolUI.H=0.675,0.12,0.305,0.67
TerrainToolUI.RIGHT_BUTTON=3
TerrainToolUI.HOLD_DELAY_MS=400
TerrainToolUI.HOLD_RAMP_MS=3200
TerrainToolUI.COLORS={
    panel={0.035,0.055,0.075,0.93},header={0.045,0.22,0.23,0.96},
    button={0.13,0.19,0.24,0.96},active={0.11,0.48,0.37,0.97},
    warning={0.55,0.24,0.20,0.95},disabled={0.10,0.12,0.15,0.65},
    text={0.94,0.97,1,1},muted={0.67,0.74,0.79,1},
    cut={1,0.4,0.4,1},fill={0.35,1,0.61,1}
}
local function menuOpen()
    return g_gui~=nil and type(g_gui.getIsGuiVisible)=="function"
        and g_gui:getIsGuiVisible()
end
local function getPlayerInput()
    if g_localPlayer==nil then return nil,"Spieler nicht geladen" end
    if type(g_localPlayer.getCurrentVehicle)=="function"
        and g_localPlayer:getCurrentVehicle()~=nil then
        return nil,"UI-Mausmodus nur zu Fuss"
    end
    local input=g_localPlayer.inputComponent
    if input==nil or type(input.lock)~="function"
        or type(input.unlock)~="function" then
        return nil,"PlayerInputComponent fehlt"
    end
    return input
end

function TerrainToolUI.initialize(owner)
    TerrainToolUI.owner=owner
    TerrainToolUI.visible=false;TerrainToolUI.mouseActive=false
    TerrainToolUI.frozenSample=nil;TerrainToolUI.lockedInput=nil
    TerrainToolUI.previousMouseVisible=false
    TerrainToolUI.rightHeld=false;TerrainToolUI.pressedButton=nil
    TerrainToolUI.hold=nil;TerrainToolUI.buttons={};TerrainToolUI.page="select"
    TerrainToolUI.initialized=true
    if TerrainToolUI.rectangle~=nil then
        TerrainToolUI.rectangle:delete();TerrainToolUI.rectangle=nil
    end
    if g_overlayManager~=nil and g_plainColorSliceId~=nil
        and type(g_overlayManager.createOverlay)=="function" then
        local ok,overlay=pcall(g_overlayManager.createOverlay,
            g_overlayManager,g_plainColorSliceId,0,0,0,0)
        if ok then TerrainToolUI.rectangle=overlay end
    end
    print("[Terraform Plus] TerrainToolUI initialisiert (0.0.13.0)")
end

-- Beendet eine Tastenserie und fasst eine Design-Aenderung als Undo zusammen.
function TerrainToolUI.stopHold()
    local hold=TerrainToolUI.hold
    TerrainToolUI.hold=nil
    TerrainToolUI.pressedButton=nil
    if hold~=nil and hold.design and TerrainToolUI.owner~=nil then
        TerrainToolUI.owner:endDesignEdit()
    end
end

function TerrainToolUI.disableMouse()
    if not TerrainToolUI.mouseActive then return end
    TerrainToolUI.mouseActive=false
    TerrainToolUI.stopHold();TerrainToolUI.frozenSample=nil
    local input=TerrainToolUI.lockedInput
    TerrainToolUI.lockedInput=nil
    if input~=nil and not menuOpen() then
        local ok,err=pcall(input.unlock,input)
        if not ok then print("[Terraform Plus] Input-Unlock: "..tostring(err)) end
    end
    if not menuOpen() and g_inputBinding~=nil
        and type(g_inputBinding.setShowMouseCursor)=="function" then
        g_inputBinding:setShowMouseCursor(
            TerrainToolUI.previousMouseVisible or false)
    end
    print("[Terraform Plus] Kamerasteuerung wieder freigegeben")
end

function TerrainToolUI.toggle()
    TerrainToolUI.visible=not TerrainToolUI.visible
    if not TerrainToolUI.visible then
        TerrainToolUI.disableMouse()
        TerrainToolUI.stopHold()
        TerrainToolUI.rightHeld=false
    end
    return TerrainToolUI.visible
end

function TerrainToolUI.toggleMouse()
    if TerrainToolUI.mouseActive then
        TerrainToolUI.disableMouse()
        return true,false
    end
    if menuOpen() then return false,"Zuerst Spielmenue schliessen" end
    if g_inputBinding==nil
        or type(g_inputBinding.getShowMouseCursor)~="function"
        or type(g_inputBinding.setShowMouseCursor)~="function" then
        return false,"Maus-API fehlt"
    end
    local input,err=getPlayerInput()
    if input==nil then return false,err end
    if input.locked then return false,"Spielersteuerung bereits gesperrt" end
    local sample,sampleErr=nil,nil
    local owner=TerrainToolUI.owner
    if owner~=nil then
        local ok,value,message=pcall(owner.getSelectionSample,owner)
        if ok and value~=nil then
            sample={x=value.x,z=value.z,terrainY=value.terrainY}
        else sampleErr=ok and message or value end
    end
    local previous=g_inputBinding:getShowMouseCursor()
    local locked,lockErr=pcall(input.lock,input)
    if not locked then return false,"Kamerasperre: "..tostring(lockErr) end
    if type(input.resetState)=="function" then pcall(input.resetState,input) end
    local shown,showErr=pcall(g_inputBinding.setShowMouseCursor,g_inputBinding,true)
    if not shown then
        pcall(input.unlock,input)
        return false,"Mauszeiger: "..tostring(showErr)
    end
    TerrainToolUI.previousMouseVisible=previous
    TerrainToolUI.lockedInput=input;TerrainToolUI.frozenSample=sample
    TerrainToolUI.mouseActive=true;TerrainToolUI.visible=true
    print("[Terraform Plus] Kamerasteuerung gesperrt (UI-Mausmodus)")
    if sample==nil then print("[Terraform Plus] Kein fixiertes Kameraziel: "..
        tostring(sampleErr)) end
    return true,true
end

-- Keine prozentuale Vergroesserung der Schrittweite!
-- Jeder Breiten-Tick entspricht immer exakt 0,5 m.
-- Beim Halten steigt ausschliesslich die Anzahl Ticks pro Sekunde.
local numeric={
    width={field="areaWidth",step=0.5,min=1,max=80,fn="consoleCommandWidth"},
    step={field="areaStep",step=0.5,min=0.5,max=5,fn="consoleCommandGridStep"},
    height={field="offset",step=0.5,min=-100,max=100,fn="consoleCommandTargetOffset",design=true},
    slope={field="slope",step=1,min=-100,max=100,fn="consoleCommandTargetSlope",design=true},
    feather={field="feather",step=1,min=0,max=20,fn="consoleCommandEdgeBlend",design=true},
    limit={field="maxChange",step=0.5,min=0.5,max=50,fn="consoleCommandChangeLimit",design=true}
}
local function specFor(id)
    local key=id:match("^(%a+)Plus$")
    if key~=nil then return numeric[key],1 end
    key=id:match("^(%a+)Minus$")
    if key~=nil then return numeric[key],-1 end
    return nil,nil
end
local function tick(owner,id,doLog)
    local s,direction=specFor(id)
    if s==nil then return false end
    local source=s.design and owner.design or owner
    if source==nil or type(source[s.field])~="number" then return false end
    local old=source[s.field]
    -- In ganzzahligen Tick-Einheiten rechnen: keine krummen Float-Zwischenwerte.
    local index=math.floor((old-s.min)/s.step+0.5)
    local maximum=math.floor((s.max-s.min)/s.step+0.5)
    local nextIndex=math.max(0,math.min(maximum,index+direction))
    if nextIndex==index then return false end
    local value=s.min+nextIndex*s.step
    local message=owner[s.fn](owner,tostring(value))
    if doLog and message~=nil then print(message) end
    return true
end

function TerrainToolUI.update(owner,dt)
    if TerrainToolUI.mouseActive and menuOpen() then TerrainToolUI.disableMouse() end
    if not TerrainToolUI.visible or menuOpen() then
        TerrainToolUI.rightHeld=false;TerrainToolUI.stopHold();return
    end
    if Input~=nil and type(Input.isMouseButtonPressed)=="function" then
        local right=Input.MOUSE_BUTTON_RIGHT or TerrainToolUI.RIGHT_BUTTON
        local ok,pressed=pcall(Input.isMouseButtonPressed,right)
        if ok then
            if pressed and not TerrainToolUI.rightHeld then
                TerrainToolUI.rightHeld=true
                print(owner:consoleCommandUIMouse())
            elseif not pressed then TerrainToolUI.rightHeld=false end
        end
    end
    local hold=TerrainToolUI.hold
    if not TerrainToolUI.mouseActive or hold==nil then return end
    local delta=type(dt)=="number" and math.max(0,math.min(dt,250)) or 0
    hold.elapsed=hold.elapsed+delta
    local count=0
    while hold.elapsed>=hold.nextRepeat and count<16 do
        if not tick(owner,hold.id,false) then TerrainToolUI.stopHold();break end
        hold.repeats=hold.repeats+1
        local progress=math.min(1,math.max(0,
            (hold.nextRepeat-TerrainToolUI.HOLD_DELAY_MS)/TerrainToolUI.HOLD_RAMP_MS))
        local interval=200-180*progress  -- 5 Hz bis 50 Hz (10x schneller)
        hold.nextRepeat=hold.nextRepeat+interval
        count=count+1
    end
end

function TerrainToolUI.rect(x,y,w,h,color)
    local r=TerrainToolUI.rectangle
    if r==nil then return end
    r:setPosition(x,y);r:setDimension(w,h)
    r:setColor(color[1],color[2],color[3],color[4]);r:render()
end
function TerrainToolUI.text(x,y,value,size,color,center)
    setTextAlignment(center and RenderText.ALIGN_CENTER or RenderText.ALIGN_LEFT)
    setTextColor(color[1],color[2],color[3],color[4])
    renderText(x,y,size or 0.013,tostring(value))
end
function TerrainToolUI.button(id,label,x,y,w,h,enabled,kind)
    local c=TerrainToolUI.COLORS
    local color=not enabled and c.disabled or kind=="active" and c.active
        or kind=="warning" and c.warning or c.button
    TerrainToolUI.rect(x,y,w,h,color)
    TerrainToolUI.text(x+w/2,y+h*0.30,label,0.012,
        enabled and c.text or c.muted,true)
    table.insert(TerrainToolUI.buttons,{id=id,x=x,y=y,w=w,h=h,enabled=enabled})
end
function TerrainToolUI.setting(id,label,value,y,low,high,unit)
    local c=TerrainToolUI.COLORS
    TerrainToolUI.text(0.690,y+0.040,label,0.012,c.muted)
    TerrainToolUI.button(id.."Minus","-",0.690,y,0.050,0.031,value>low)
    TerrainToolUI.text(0.824,y+0.009,
        string.format("%.2f %s",value,unit or "m"),0.013,c.text,true)
    TerrainToolUI.button(id.."Plus","+",0.909,y,0.055,0.031,value<high)
end

function TerrainToolUI.draw(owner)
    if not TerrainToolUI.visible or menuOpen() or RenderText==nil
        or type(renderText)~="function" then return end
    local c=TerrainToolUI.COLORS
    TerrainToolUI.buttons={}
    TerrainToolUI.rect(0.675,0.12,0.305,0.67,c.panel)
    TerrainToolUI.rect(0.675,0.746,0.305,0.044,c.header)
    TerrainToolUI.text(0.690,0.757,"TERRAFORM PLUS  0.0.13.0",0.016,c.text)
    TerrainToolUI.button("close","X",0.939,0.752,0.026,0.031,true,"warning")
    TerrainToolUI.button("tabSelect","BEREICH",0.690,0.700,0.087,0.036,true,
        TerrainToolUI.page=="select" and "active")
    TerrainToolUI.button("tabDesign","GESTALTUNG",0.783,0.700,0.087,0.036,true,
        TerrainToolUI.page=="design" and "active")
    TerrainToolUI.button("tabReview","PRUEFUNG",0.876,0.700,0.089,0.036,true,
        TerrainToolUI.page=="review" and "active")
    local selection=owner.selection
    local selecting=selection~=nil and selection.active
    local area=selecting and (selection.preview and selection.preview.area)
        or (not selecting and owner.area) or nil

    if TerrainToolUI.page=="select" then
        TerrainToolUI.text(0.690,0.660,not selecting and "Kein Bereich aktiv"
            or selection.stage=="A" and "Startpunkt anvisieren"
            or "Endpunkt anvisieren",0.013,c.text)
        TerrainToolUI.text(0.690,0.626,TerrainToolUI.mouseActive
            and "Maus aktiv - Kameraziel fixiert"
            or "Rechtsklick: UI-Maus aktivieren",0.012,c.muted)
        if area~=nil then
            TerrainToolUI.text(0.690,0.592,string.format(
                "Flaeche: %.1f m2 | %d Zellen",area.area,#area.samples),0.013,c.text)
            TerrainToolUI.text(0.690,0.564,string.format(
                "Abtrag %.1f / Auftrag %.1f m3",area.cutVolume,area.fillVolume),0.012,c.text)
        else
            TerrainToolUI.text(0.690,0.586,"Noch keine Bereichsanalyse",0.013,c.muted)
        end
        TerrainToolUI.button("start","NEUER BEREICH",0.690,0.510,0.132,0.041,
            not selecting,"active")
        TerrainToolUI.button("refresh","NEU BERECHNEN",0.833,0.510,0.132,0.041,
            not selecting and owner.pointA~=nil and owner.pointB~=nil)
        local hasAim=not TerrainToolUI.mouseActive or TerrainToolUI.frozenSample~=nil
        TerrainToolUI.button("anchor","STARTPUNKT SETZEN",0.690,0.460,0.132,0.041,
            selecting and selection.stage=="A" and hasAim)
        TerrainToolUI.button("confirm","ENDPUNKT SETZEN",0.833,0.460,0.132,0.041,
            selecting and selection.stage=="B" and hasAim)
        TerrainToolUI.button("clear","BEREICH LOESCHEN",0.690,0.408,0.275,0.041,
            selecting or owner.pointA~=nil or owner.pointB~=nil,"warning")
        TerrainToolUI.setting("width","BREITE (0,5-M-SCHRITTE)",owner.areaWidth,
            0.338,TerrainArea.MIN_WIDTH,TerrainArea.MAX_WIDTH,"m")
        TerrainToolUI.setting("step","RASTERABSTAND",owner.areaStep,
            0.267,TerrainArea.MIN_STEP,TerrainArea.MAX_STEP,"m")
        TerrainToolUI.text(0.690,0.245,"Halten: schnellere Wiederholung, fester Schritt",
            0.011,c.muted)
        TerrainToolUI.button("preview",owner.previewEnabled and "HOEHENPROFIL AN"
            or "HOEHENPROFIL AUS",0.690,0.158,0.132,0.042,true,
            owner.previewEnabled and "active")
        TerrainToolUI.button("areaVisual",owner.areaEnabled and "3D-VORSCHAU AN"
            or "3D-VORSCHAU AUS",0.833,0.158,0.132,0.042,true,
            owner.areaEnabled and "active")
    elseif TerrainToolUI.page=="design" then
        local d=owner.design
        local target=owner.pointA and owner.pointA.terrainY+d.offset or nil
        local proposed,err=owner:getDesignArea()
        TerrainToolUI.text(0.690,0.661,target~=nil and string.format(
            "Zielhoehe bei A: %.2f m",target) or "Erst Bereich A-B festlegen",0.013,c.text)
        TerrainToolUI.setting("height","HOEHENVERSATZ",d.offset,0.585,-100,100,"m")
        TerrainToolUI.setting("slope","ZIELSTEIGUNG",d.slope,0.520,-100,100,"%")
        TerrainToolUI.setting("feather","WEICHER RAND",d.feather,0.455,0,20,"m")
        TerrainToolUI.setting("limit","MAX. HOEHENAENDERUNG",d.maxChange,0.390,0.5,50,"m")
        TerrainToolUI.button("modeAll","BEIDES",0.690,0.344,0.088,0.033,true,
            d.mode=="all" and "active")
        TerrainToolUI.button("modeCut","NUR ABTRAG",0.782,0.344,0.088,0.033,true,
            d.mode=="cut" and "active")
        TerrainToolUI.button("modeFill","NUR AUFTRAG",0.874,0.344,0.091,0.033,true,
            d.mode=="fill" and "active")
        if proposed~=nil then
            TerrainToolUI.text(0.690,0.314,string.format(
                "Abtrag %.1f / Auftrag %.1f m3",proposed.cutVolume,
                proposed.fillVolume),0.013,c.text)
            TerrainToolUI.text(0.690,0.286,string.format(
                "Hoehenlimit: %d Zellen betroffen",proposed.limitedCells),0.012,c.muted)
        else
            TerrainToolUI.text(0.690,0.294,err or "Keine Vorschau",0.012,c.muted)
        end
        TerrainToolUI.button("undo","RUECKGAENGIG",0.690,0.245,0.132,0.037,
            #(owner.designUndo or {})>0)
        TerrainToolUI.button("redo","WIEDERHOLEN",0.833,0.245,0.132,0.037,
            #(owner.designRedo or {})>0)
        TerrainToolUI.button("designVisual",d.enabled and "SOLL-VORSCHAU AN"
            or "SOLL-VORSCHAU AUS",0.690,0.158,0.170,0.042,true,
            d.enabled and "active")
        TerrainToolUI.button("resetDesign","ZURUECKSETZEN",
            0.869,0.158,0.096,0.042,true)
    else
        TerrainToolUI.text(0.690,0.656,"HEIGHTMAP-PRUEFUNG (NUR LESEN)",0.013,c.text)
        TerrainToolUI.text(0.690,0.620,
            "Zuerst Bereich bestaetigen und Entwurf festlegen",0.012,c.muted)
        local fresh=TerrainPlan.isFresh(owner)
        local plan=fresh and owner.terrainPlan or nil
        if plan~=nil then
            TerrainToolUI.text(0.690,0.565,string.format(
                "Heightmap-Raster: %.3f m",plan.unit),0.013,c.text)
            TerrainToolUI.text(0.690,0.532,string.format(
                "Geprueft: %d / Betroffen: %d",plan.checked,#plan.points),0.013,c.text)
            TerrainToolUI.text(0.690,0.499,string.format(
                "Abtrag ca. %.1f m3",plan.cutVolume),0.013,c.cut)
            TerrainToolUI.text(0.690,0.466,string.format(
                "Auftrag ca. %.1f m3",plan.fillVolume),0.013,c.fill)
            TerrainToolUI.text(0.690,0.433,
                plan.approved and "Status: PRUEFPLAN FREIGEGEBEN"
                    or "Status: BITTE FREIGEBEN",0.013,c.text)
        else
            TerrainToolUI.text(0.690,0.536,"Noch kein aktueller Pruefplan",0.013,c.muted)
        end
        TerrainToolUI.button("prepare","PRUEFRASTER ERSTELLEN",
            0.690,0.366,0.275,0.046,
            not selecting and owner.pointA~=nil and owner.pointB~=nil,"active")
        TerrainToolUI.button("approve","PLAN FREIGEBEN",
            0.690,0.298,0.275,0.046,plan~=nil and not plan.approved,"warning")
        TerrainToolUI.button("run","PROBELAUF (KEINE AENDERUNG)",
            0.690,0.230,0.275,0.046,plan~=nil and plan.approved,"active")
        TerrainToolUI.text(0.690,0.165,
            "Keine Hoehenwerte werden geschrieben!",0.012,c.muted)
    end
    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1,1,1,1)
end

function TerrainToolUI.findButton(x,y)
    for _,b in ipairs(TerrainToolUI.buttons or {}) do
        if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then return b end
    end
    return nil
end

function TerrainToolUI.perform(owner,id)
    if id=="tabSelect" then TerrainToolUI.page="select";return end
    if id=="tabDesign" then TerrainToolUI.page="design";return end
    if id=="tabReview" then TerrainToolUI.page="review";return end
    local methods={
        close="consoleCommandUI",start="consoleCommandSelect",
        anchor="consoleCommandAnchor",confirm="consoleCommandConfirm",
        clear="consoleCommandClear",refresh="consoleCommandRefresh",
        preview="consoleCommandPreview",areaVisual="consoleCommandAreaVisual",
        designVisual="consoleCommandDesignVisual",resetDesign="consoleCommandDesignReset",
        undo="consoleCommandDesignUndo",redo="consoleCommandDesignRedo",
        prepare="consoleCommandPlanPrepare"
    }
    local result
    if methods[id]~=nil then result=owner[methods[id]](owner)
    elseif id=="modeAll" then result=owner:consoleCommandWorkMode("all")
    elseif id=="modeCut" then result=owner:consoleCommandWorkMode("cut")
    elseif id=="modeFill" then result=owner:consoleCommandWorkMode("fill")
    elseif id=="approve" then result=owner:consoleCommandPlanApprove("CONFIRM")
    elseif id=="run" then result=owner:consoleCommandPlanRun("RUN") end
    if result~=nil then print(result) end
end

function TerrainToolUI.mouseEvent(owner,x,y,down,up,button,used)
    if TerrainToolUI.visible and not menuOpen()
        and button==(Input~=nil and Input.MOUSE_BUTTON_RIGHT
            or TerrainToolUI.RIGHT_BUTTON) then
        if down and not TerrainToolUI.rightHeld then
            TerrainToolUI.rightHeld=true
            print(owner:consoleCommandUIMouse())
        end
        if up and (Input==nil or type(Input.isMouseButtonPressed)~="function") then
            TerrainToolUI.rightHeld=false
        end
        return true
    end
    if used or not TerrainToolUI.visible or not TerrainToolUI.mouseActive
        or menuOpen() then
        TerrainToolUI.stopHold()
        return used or false
    end
    local left=Input~=nil and Input.MOUSE_BUTTON_LEFT or 1
    if button~=left then return false end
    local hit=TerrainToolUI.findButton(x,y)
    local inPanel=x>=TerrainToolUI.X and x<=TerrainToolUI.X+TerrainToolUI.W
        and y>=TerrainToolUI.Y and y<=TerrainToolUI.Y+TerrainToolUI.H
    if down then
        TerrainToolUI.stopHold()
        if hit~=nil and hit.enabled then
            TerrainToolUI.pressedButton=hit.id
            local spec=specFor(hit.id)
            if spec~=nil then
                if spec.design then owner:beginDesignEdit() end
                tick(owner,hit.id,true)
                TerrainToolUI.hold={id=hit.id,elapsed=0,
                    nextRepeat=TerrainToolUI.HOLD_DELAY_MS,repeats=0,
                    design=spec.design}
            end
            return true
        end
    elseif up then
        local id=TerrainToolUI.pressedButton
        local hold=TerrainToolUI.hold
        TerrainToolUI.stopHold()
        if id~=nil then
            if hold~=nil then
                if hold.repeats>0 then
                    print(string.format("[Terraform Plus] Schnellverstellung: %d Ticks (feste Schrittweite)",hold.repeats))
                end
            elseif hit~=nil and hit.enabled and hit.id==id then
                TerrainToolUI.perform(owner,id)
            end
            return true
        end
    end
    return (down or up) and inPanel or false
end

function TerrainToolUI.delete()
    TerrainToolUI.disableMouse();TerrainToolUI.stopHold()
    if TerrainToolUI.rectangle~=nil then
        TerrainToolUI.rectangle:delete();TerrainToolUI.rectangle=nil
    end
    TerrainToolUI.visible=false;TerrainToolUI.initialized=false
    TerrainToolUI.buttons={};TerrainToolUI.owner=nil
end
