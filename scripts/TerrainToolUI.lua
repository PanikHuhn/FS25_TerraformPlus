
-- Terraform Plus v0.0.12.0 - Werkzeugfenster
-- Bereich / Gestaltung, Kamera-Sperre, Rechtsklick und beschleunigtes Halten.
TerrainToolUI = TerrainToolUI or {}
TerrainToolUI.X, TerrainToolUI.Y = 0.675, 0.12
TerrainToolUI.W, TerrainToolUI.H = 0.305, 0.67
TerrainToolUI.RIGHT_BUTTON = 3
TerrainToolUI.HOLD_DELAY_MS = 400
TerrainToolUI.HOLD_RAMP_MS = 3200
TerrainToolUI.COLORS = {
    panel={0.035,0.055,0.075,0.93}, header={0.045,0.22,0.23,0.96},
    button={0.13,0.19,0.24,0.96}, active={0.11,0.48,0.37,0.97},
    warning={0.55,0.24,0.20,0.95}, disabled={0.10,0.12,0.15,0.65},
    text={0.94,0.97,1,1}, muted={0.67,0.74,0.79,1},
    cut={1,0.4,0.4,1}, fill={0.35,1,0.61,1}
}

local function menuOpen()
    return g_gui ~= nil and type(g_gui.getIsGuiVisible)=="function"
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
        return nil,"PlayerInputComponent nicht verfuegbar"
    end
    return input
end

function TerrainToolUI.initialize(owner)
    TerrainToolUI.owner=owner
    TerrainToolUI.visible=false
    TerrainToolUI.mouseActive=false
    TerrainToolUI.frozenSample=nil
    TerrainToolUI.lockedInput=nil
    TerrainToolUI.previousMouseVisible=false
    TerrainToolUI.rightHeld=false
    TerrainToolUI.pressedButton=nil
    TerrainToolUI.hold=nil
    TerrainToolUI.page="select"
    TerrainToolUI.buttons={}
    TerrainToolUI.initialized=true
    if TerrainToolUI.rectangle~=nil then
        TerrainToolUI.rectangle:delete()
        TerrainToolUI.rectangle=nil
    end
    if g_overlayManager~=nil and g_plainColorSliceId~=nil
        and type(g_overlayManager.createOverlay)=="function" then
        local ok,overlay=pcall(g_overlayManager.createOverlay,
            g_overlayManager,g_plainColorSliceId,0,0,0,0)
        if ok then TerrainToolUI.rectangle=overlay end
    end
    print("[Terraform Plus] TerrainToolUI initialisiert (0.0.12.0)")
end

function TerrainToolUI.stopHold()
    TerrainToolUI.hold=nil
    TerrainToolUI.pressedButton=nil
end

function TerrainToolUI.disableMouse()
    if not TerrainToolUI.mouseActive then return end
    TerrainToolUI.mouseActive=false
    TerrainToolUI.stopHold()
    TerrainToolUI.frozenSample=nil
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
        local ok,result,message=pcall(owner.getSelectionSample,owner)
        if ok and result~=nil then
            sample={x=result.x,z=result.z,terrainY=result.terrainY}
        else
            sampleErr=ok and message or result
        end
    end
    local oldCursor=g_inputBinding:getShowMouseCursor()
    local locked,lockErr=pcall(input.lock,input)
    if not locked then return false,"Kamerasperre: "..tostring(lockErr) end
    if type(input.resetState)=="function" then pcall(input.resetState,input) end
    local shown,showErr=pcall(g_inputBinding.setShowMouseCursor,
        g_inputBinding,true)
    if not shown then
        pcall(input.unlock,input)
        return false,"Mauszeiger: "..tostring(showErr)
    end
    TerrainToolUI.previousMouseVisible=oldCursor
    TerrainToolUI.lockedInput=input
    TerrainToolUI.frozenSample=sample
    TerrainToolUI.mouseActive=true
    TerrainToolUI.visible=true
    print("[Terraform Plus] Kamerasteuerung gesperrt (UI-Mausmodus)")
    if sample==nil then
        print("[Terraform Plus] Kein fixiertes Kameraziel: "..tostring(sampleErr))
    end
    return true,true
end

-- Nummerische Bedienelemente: ein Klick = ein Basisschritt.
-- Beim Halten steigt der Schritt kontinuierlich bis zum Faktor 10.
local numeric = {
    width={field="areaWidth",base=2,min=1,max=80,method="consoleCommandWidth"},
    step={field="areaStep",base=0.5,min=0.5,max=5,method="consoleCommandGridStep"},
    height={field="offset",base=0.5,min=-100,max=100,method="consoleCommandTargetOffset",design=true},
    slope={field="slope",base=1,min=-100,max=100,method="consoleCommandTargetSlope",design=true},
    feather={field="feather",base=1,min=0,max=20,method="consoleCommandEdgeBlend",design=true},
    limit={field="maxChange",base=0.5,min=0.5,max=50,method="consoleCommandChangeLimit",design=true}
}
local function numericSpec(id)
    local key,sign=id:match("^(%a+)(Plus)$")
    if sign~=nil then return numeric[key],1 end
    key,sign=id:match("^(%a+)(Minus)$")
    if sign~=nil then return numeric[key],-1 end
    return nil,nil
end
local function updateNumeric(owner,id,factor,log)
    local spec,sign=numericSpec(id)
    if spec==nil then return false end
    local state=spec.design and owner.design or owner
    if state==nil then return false end
    local before=state[spec.field]
    if type(before)~="number" then return false end
    local after=math.max(spec.min,math.min(spec.max,
        before+sign*spec.base*factor))
    after=math.floor(after*1000+0.5)/1000
    if math.abs(after-before)<0.000001 then return false end
    local message=owner[spec.method](owner,tostring(after))
    if log and message~=nil then print(message) end
    return true
end

function TerrainToolUI.update(owner,dt)
    if TerrainToolUI.mouseActive and menuOpen() then
        TerrainToolUI.disableMouse()
    end
    if not TerrainToolUI.visible or menuOpen() then
        TerrainToolUI.rightHeld=false
        TerrainToolUI.stopHold()
        return
    end
    if Input~=nil and type(Input.isMouseButtonPressed)=="function" then
        local right=Input.MOUSE_BUTTON_RIGHT or TerrainToolUI.RIGHT_BUTTON
        local ok,pressed=pcall(Input.isMouseButtonPressed,right)
        if ok then
            if pressed and not TerrainToolUI.rightHeld then
                TerrainToolUI.rightHeld=true
                print(owner:consoleCommandUIMouse())
            elseif not pressed then
                TerrainToolUI.rightHeld=false
            end
        end
    end
    local hold=TerrainToolUI.hold
    if not TerrainToolUI.mouseActive or hold==nil then return end
    local elapsed=type(dt)=="number" and math.max(0,math.min(dt,250)) or 0
    hold.elapsed=hold.elapsed+elapsed
    local count=0
    while hold.elapsed>=hold.nextRepeat and count<6 do
        local t=math.max(0,math.min(1,
            (hold.nextRepeat-TerrainToolUI.HOLD_DELAY_MS)/TerrainToolUI.HOLD_RAMP_MS))
        local multiplier=1+9*t
        if not updateNumeric(owner,hold.id,multiplier,false) then
            TerrainToolUI.stopHold()
            break
        end
        hold.repeats=hold.repeats+1
        hold.multiplier=multiplier
        hold.nextRepeat=hold.nextRepeat+(160-85*t)
        count=count+1
    end
end

function TerrainToolUI.rect(x,y,w,h,c)
    local overlay=TerrainToolUI.rectangle
    if overlay==nil then return end
    overlay:setPosition(x,y)
    overlay:setDimension(w,h)
    overlay:setColor(c[1],c[2],c[3],c[4])
    overlay:render()
end
function TerrainToolUI.text(x,y,value,size,color,center)
    setTextAlignment(center and RenderText.ALIGN_CENTER or RenderText.ALIGN_LEFT)
    setTextColor(color[1],color[2],color[3],color[4])
    renderText(x,y,size or 0.013,tostring(value))
end
function TerrainToolUI.button(id,label,x,y,w,h,enabled,kind)
    local c=TerrainToolUI.COLORS
    local color=not enabled and c.disabled
        or kind=="active" and c.active
        or kind=="warning" and c.warning or c.button
    TerrainToolUI.rect(x,y,w,h,color)
    TerrainToolUI.text(x+w/2,y+h*0.3,label,0.0125,
        enabled and c.text or c.muted,true)
    table.insert(TerrainToolUI.buttons,
        {id=id,x=x,y=y,w=w,h=h,enabled=enabled})
end
function TerrainToolUI.setting(id,label,value,y,min,max,unit)
    local c=TerrainToolUI.COLORS
    TerrainToolUI.text(0.690,y+0.044,label,0.0125,c.muted)
    TerrainToolUI.button(id.."Minus","-",0.690,y,0.050,0.033,value>min)
    TerrainToolUI.text(0.823,y+0.009,
        string.format("%.2f %s",value,unit or "m"),0.013,c.text,true)
    TerrainToolUI.button(id.."Plus","+",0.909,y,0.055,0.033,value<max)
end

function TerrainToolUI.draw(owner)
    if not TerrainToolUI.visible or menuOpen() or RenderText==nil
        or type(renderText)~="function" then return end
    local c=TerrainToolUI.COLORS
    TerrainToolUI.buttons={}
    TerrainToolUI.rect(0.675,0.12,0.305,0.67,c.panel)
    TerrainToolUI.rect(0.675,0.746,0.305,0.044,c.header)
    TerrainToolUI.text(0.690,0.757,"TERRAFORM PLUS  0.0.12.0",0.016,c.text)
    TerrainToolUI.button("close","X",0.939,0.752,0.026,0.031,true,"warning")
    TerrainToolUI.button("tabSelect","BEREICH",0.690,0.697,0.132,0.040,true,
        TerrainToolUI.page=="select" and "active")
    TerrainToolUI.button("tabDesign","GESTALTUNG",0.833,0.697,0.132,0.040,true,
        TerrainToolUI.page=="design" and "active")
    local selection=owner.selection
    local selecting=selection~=nil and selection.active
    local baseArea=selecting and (selection.preview and selection.preview.area)
        or (not selecting and owner.area) or nil

    if TerrainToolUI.page=="select" then
        local stage=not selecting and "Kein Bereich aktiv"
            or selection.stage=="A" and "Startpunkt anvisieren"
            or "Endpunkt anvisieren"
        TerrainToolUI.text(0.690,0.664,stage,0.014,c.text)
        TerrainToolUI.text(0.690,0.634,TerrainToolUI.mouseActive
            and "Maus aktiv - Kameraziel fixiert"
            or "Rechtsklick: UI-Maus aktivieren",0.012,c.muted)
        if baseArea~=nil then
            TerrainToolUI.text(0.690,0.600,string.format(
                "Flaeche %.1f m2 | %d Rasterzellen",baseArea.area,#baseArea.samples),
                0.013,c.text)
            TerrainToolUI.text(0.690,0.571,string.format(
                "Abtrag %.1f m3 / Auftrag %.1f m3",
                baseArea.cutVolume,baseArea.fillVolume),0.012,c.text)
        else
            TerrainToolUI.text(0.690,0.583,"Noch keine Flaechenberechnung",0.013,c.muted)
        end
        TerrainToolUI.button("start","NEUER BEREICH",0.690,0.512,0.132,0.041,
            not selecting,"active")
        TerrainToolUI.button("refresh","NEU BERECHNEN",0.833,0.512,0.132,0.041,
            not selecting and owner.pointA~=nil and owner.pointB~=nil)
        local hasAim=not TerrainToolUI.mouseActive
            or TerrainToolUI.frozenSample~=nil
        TerrainToolUI.button("anchor","STARTPUNKT SETZEN",0.690,0.460,0.132,0.041,
            selecting and selection.stage=="A" and hasAim)
        TerrainToolUI.button("confirm","ENDPUNKT SETZEN",0.833,0.460,0.132,0.041,
            selecting and selection.stage=="B" and hasAim)
        TerrainToolUI.button("clear","BEREICH LOESCHEN",0.690,0.406,0.275,0.041,
            selecting or owner.pointA~=nil or owner.pointB~=nil,
            "warning")
        TerrainToolUI.setting("width","BREITE DES BEREICHS",owner.areaWidth,
            0.336,TerrainArea.MIN_WIDTH,TerrainArea.MAX_WIDTH,"m")
        TerrainToolUI.setting("step","RASTERABSTAND",owner.areaStep,
            0.265,TerrainArea.MIN_STEP,TerrainArea.MAX_STEP,"m")
        TerrainToolUI.text(0.690,0.243,
            "+ / - halten: bis zu 10x schneller",0.0115,c.muted)
        TerrainToolUI.button("preview",
            owner.previewEnabled and "HOEHENPROFIL AN" or "HOEHENPROFIL AUS",
            0.690,0.160,0.132,0.041,true,
            owner.previewEnabled and "active")
        TerrainToolUI.button("areaVisual",
            owner.areaEnabled and "3D-VORSCHAU AN" or "3D-VORSCHAU AUS",
            0.833,0.160,0.132,0.041,true,
            owner.areaEnabled and "active")
    else
        local d=owner.design or {
            offset=0,slope=0,feather=0,maxChange=10,mode="all",enabled=true
        }
        local height=owner.pointA and owner.pointA.terrainY+d.offset or nil
        local design,err=owner:getDesignArea()
        TerrainToolUI.text(0.690,0.664,height~=nil and
            string.format("Zielhoehe bei A: %.2f m",height)
            or "Zuerst Bereich A-B festlegen",0.013,c.text)
        TerrainToolUI.setting("height","HOEHENVERSATZ BEI A",d.offset,
            0.588,TerrainDesign.MIN_OFFSET,TerrainDesign.MAX_OFFSET,"m")
        TerrainToolUI.setting("slope","ZIELSTEIGUNG",d.slope,
            0.520,TerrainDesign.MIN_SLOPE,TerrainDesign.MAX_SLOPE,"%")
        TerrainToolUI.setting("feather","WEICHER RAND",d.feather,
            0.452,TerrainDesign.MIN_FEATHER,TerrainDesign.MAX_FEATHER,"m")
        TerrainToolUI.setting("limit","MAX. HOEHENAENDERUNG",d.maxChange,
            0.384,TerrainDesign.MIN_CHANGE,TerrainDesign.MAX_CHANGE,"m")
        TerrainToolUI.text(0.690,0.363,"GELAENDEAENDERUNG",0.012,c.muted)
        TerrainToolUI.button("modeAll","BEIDES",0.690,0.325,0.088,0.033,true,
            d.mode=="all" and "active")
        TerrainToolUI.button("modeCut","NUR ABTRAG",0.782,0.325,0.088,0.033,true,
            d.mode=="cut" and "active")
        TerrainToolUI.button("modeFill","NUR AUFTRAG",0.874,0.325,0.091,0.033,true,
            d.mode=="fill" and "active")
        if design~=nil then
            TerrainToolUI.text(0.690,0.299,string.format(
                "Abtrag: %.2f m3",design.cutVolume),0.013,c.cut)
            TerrainToolUI.text(0.690,0.275,string.format(
                "Auftrag: %.2f m3",design.fillVolume),0.013,c.fill)
            TerrainToolUI.text(0.690,0.251,string.format(
                "Netto: %+.2f m3",design.netVolume),0.013,c.text)
            TerrainToolUI.text(0.690,0.227,string.format(
                "Begrenzt: %d / %d Zellen",design.limitedCells,#design.samples),
                0.012,design.limitedCells>0 and c.cut or c.muted)
        else
            TerrainToolUI.text(0.690,0.270,err or "Keine Vorschau",0.012,c.muted)
        end
        TerrainToolUI.button("designVisual",
            d.enabled and "SOLL-VORSCHAU AN" or "SOLL-VORSCHAU AUS",
            0.690,0.150,0.170,0.042,true,d.enabled and "active")
        TerrainToolUI.button("resetDesign","ZURUECKSETZEN",
            0.869,0.150,0.096,0.042,true)
    end
    setTextColor(1,1,1,1)
    setTextAlignment(RenderText.ALIGN_LEFT)
end

function TerrainToolUI.findButton(x,y)
    for _,b in ipairs(TerrainToolUI.buttons or {}) do
        if x>=b.x and x<=b.x+b.w and y>=b.y and y<=b.y+b.h then
            return b
        end
    end
    return nil
end

function TerrainToolUI.perform(owner,id)
    if id=="tabSelect" then TerrainToolUI.page="select";return end
    if id=="tabDesign" then TerrainToolUI.page="design";return end
    local methods={
        close="consoleCommandUI",start="consoleCommandSelect",
        anchor="consoleCommandAnchor",confirm="consoleCommandConfirm",
        clear="consoleCommandClear",refresh="consoleCommandRefresh",
        preview="consoleCommandPreview",areaVisual="consoleCommandAreaVisual",
        designVisual="consoleCommandDesignVisual",
        resetDesign="consoleCommandDesignReset"
    }
    local method=methods[id]
    local result
    if method~=nil then
        result=owner[method](owner)
    elseif id=="modeAll" then
        result=owner:consoleCommandWorkMode("all")
    elseif id=="modeCut" then
        result=owner:consoleCommandWorkMode("cut")
    elseif id=="modeFill" then
        result=owner:consoleCommandWorkMode("fill")
    end
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
        if up and (Input==nil
            or type(Input.isMouseButtonPressed)~="function") then
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
    local inside=x>=TerrainToolUI.X and x<=TerrainToolUI.X+TerrainToolUI.W
        and y>=TerrainToolUI.Y and y<=TerrainToolUI.Y+TerrainToolUI.H
    if down then
        TerrainToolUI.stopHold()
        if hit~=nil and hit.enabled then
            TerrainToolUI.pressedButton=hit.id
            if numericSpec(hit.id)~=nil then
                updateNumeric(owner,hit.id,1,true)
                TerrainToolUI.hold={id=hit.id,elapsed=0,
                    nextRepeat=TerrainToolUI.HOLD_DELAY_MS,
                    repeats=0,multiplier=1}
            end
            return true
        end
    elseif up then
        local id=TerrainToolUI.pressedButton
        local hold=TerrainToolUI.hold
        TerrainToolUI.stopHold()
        if id~=nil then
            if hold~=nil and hold.repeats>0 then
                print(string.format(
                    "[Terraform Plus] Schnellverstellung: %d Wiederholungen (bis %.1fx)",
                    hold.repeats,hold.multiplier))
            elseif hold==nil and hit~=nil and hit.enabled and hit.id==id then
                TerrainToolUI.perform(owner,id)
            end
            return true
        end
    elseif TerrainToolUI.hold~=nil and (hit==nil
        or hit.id~=TerrainToolUI.hold.id) then
        -- Cursor vom gehaltenen Feld weggezogen: sofort stoppen.
        TerrainToolUI.stopHold()
    end
    return (down or up) and inside or false
end

function TerrainToolUI.delete()
    TerrainToolUI.disableMouse()
    TerrainToolUI.stopHold()
    if TerrainToolUI.rectangle~=nil then
        TerrainToolUI.rectangle:delete()
        TerrainToolUI.rectangle=nil
    end
    TerrainToolUI.visible=false
    TerrainToolUI.initialized=false
    TerrainToolUI.buttons={}
    TerrainToolUI.owner=nil
end
