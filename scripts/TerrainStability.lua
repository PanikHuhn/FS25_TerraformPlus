
-- Terraform Plus 0.0.16.0 - UI / Nachbarpruefung / Saveguard
-- Muss NACH TerrainBatch.lua geladen werden.
-- EXPERIMENTELL: nur mit einer Kopie des Einzelspieler-Spielstands.
assert(TerraformPlus and TerrainToolUI and TerrainPlan and TerrainBatch and TerrainWriter,
    '[Terraform Plus] 0.0.16.0: Module fehlen oder Ladereihenfolge falsch')

TerrainStability = TerrainStability or {}
TerrainStability.TOLERANCE = 0.04
TerrainStability.MAX_NEIGHBORS = 1400
TerrainStability.saveHookReady = false
TerrainStability.lastCheck = 'Noch keine Nachbarpruefung'
TerraformPlus.VERSION = '0.0.16.0'

local function finite(v)
    return type(v)=='number' and v==v and v~=math.huge and v~=-math.huge
end
local function read(x,z)
    if not g_terrainNode or type(getTerrainHeightAtWorldPos)~='function' then
        return nil, 'Terrain nicht geladen'
    end
    local ok,y=pcall(getTerrainHeightAtWorldPos,g_terrainNode,x,0,z)
    if not ok or not finite(y) then return nil,tostring(y) end
    return y
end
local function write(x,z,y)
    if not g_terrainNode or type(setTerrainHeightAtWorldPos)~='function' then
        return false,'Terrain-Schreibfunktion nicht verfuegbar'
    end
    local ok,err=pcall(setTerrainHeightAtWorldPos,g_terrainNode,x,0,z,y)
    if not ok then return false,tostring(err) end
    local actual,readErr=read(x,z)
    if actual==nil or math.abs(actual-y)>TerrainStability.TOLERANCE then
        return false, 'Ruecklesetest: '..tostring(readErr or actual)
    end
    return true
end
local function key(x,z)
    return string.format('%.4f:%.4f',x,z)
end

-- Snapshot ausschliesslich der nicht bearbeiteten direkten Nachbarpunkte.
-- Damit erkennen wir versehentliche Effekte ueber die eigentliche Auswahl hinaus.
local function neighborsFor(tx,unit)
    if not finite(unit) or unit < 0.05 or unit > 32 then
        return nil,'Ungueltige Heightmap-Einheit'
    end
    local selected={}
    for _,p in ipairs(tx.points) do selected[key(p.x,p.z)]=true end
    local seen={}
    local neighbors={}
    local offsets={{unit,0},{-unit,0},{0,unit},{0,-unit}}
    for _,p in ipairs(tx.points) do
        for _,off in ipairs(offsets) do
            local x,z=p.x+off[1],p.z+off[2]
            local k=key(x,z)
            if not selected[k] and not seen[k] then
                seen[k]=true
                if #neighbors >= TerrainStability.MAX_NEIGHBORS then
                    return nil,'Zu viele Nachbarpunkte'
                end
                local y,err=read(x,z)
                if y==nil then return nil,'Nachbar-Snapshot: '..tostring(err) end
                neighbors[#neighbors+1]={x=x,z=z,before=y}
            end
        end
    end
    return neighbors
end

function TerrainStability.checkNeighbors(tx)
    if tx==nil or tx.neighbors==nil then
        return false,'Kein Nachbar-Snapshot vorhanden'
    end
    local changed=0
    local maxDiff=0
    local first=nil
    for _,p in ipairs(tx.neighbors) do
        local y,err=read(p.x,p.z)
        if y==nil then return false,'Nachbar-Lesefehler: '..tostring(err) end
        local delta=math.abs(y-p.before)
        maxDiff=math.max(maxDiff,delta)
        if delta>TerrainStability.TOLERANCE then
            changed=changed+1
            if first==nil then first=string.format('X=%.2f Z=%.2f (%.3f m)',p.x,p.z,delta) end
        end
    end
    TerrainStability.lastCheck=string.format('%d Nachbarpunkte | %d veraendert | max. %.4f m',
        #tx.neighbors,changed,maxDiff)
    if changed>0 then
        return false, TerrainStability.lastCheck..' | erster: '..tostring(first)
    end
    return true,TerrainStability.lastCheck
end

-- Bestehende Batch-Vorbereitung um eine Nachbarschaftssicherung ergaenzen.
local oldPrepare=TerrainBatch.prepare
function TerrainBatch.prepare(owner)
    local tx,err=oldPrepare(owner)
    if tx==nil then return nil,err end
    local plan=owner.terrainPlan
    local unit=plan and plan.unit or nil
    local nearby,msg=neighborsFor(tx,unit)
    if nearby==nil then return nil,msg end
    tx.neighbors=nearby
    tx.neighborsChecked=false
    TerrainStability.lastCheck='Snapshot: '..#nearby..' Nachbarpunkte'
    return tx
end

-- Nach fertigen Schreib- und Undo-Phasen pruefen, nicht nur die Zielpunkte.
local oldBatchUpdate=TerrainBatch.update
function TerrainBatch.update(owner)
    local tx=TerrainBatch.transaction
    local before=tx and tx.state or nil
    oldBatchUpdate(owner)
    tx=TerrainBatch.transaction
    if tx==nil or tx.state==before then return end
    if tx.state=='applied' then
        local ok,msg=TerrainStability.checkNeighbors(tx)
        tx.neighborsChecked=ok
        if not ok then
            print('[Terraform Plus] WARNUNG Nachbarschaft nach Schreiben: '..tostring(msg))
            local started,reason=TerrainBatch.undo('CONFIRM')
            if not started then
                tx.state='uncertain'
                print('[Terraform Plus] KRITISCH: Rollback nicht gestartet: '..tostring(reason))
            else
                print('[Terraform Plus] Nachbarabweichung: automatischer Batch-Rollback gestartet')
            end
        else
            print('[Terraform Plus] Nachbarpruefung OK: '..tostring(msg))
        end
    elseif tx.state=='undone' then
        local ok,msg=TerrainStability.checkNeighbors(tx)
        tx.neighborsChecked=ok
        if not ok then
            tx.state='uncertain'
            tx.replayAllowed=false
            print('[Terraform Plus] KRITISCH: Nachbarpruefung nach Undo: '..tostring(msg))
        else
            print('[Terraform Plus] Undo-Nachbarpruefung OK: '..tostring(msg))
        end
    end
end

-- Volle Wiederherstellung VOR einem Save-Vorgang.
-- Niemals nach dem Start des echten Save-Writers reparieren.
local function restoreBatchBeforeSave()
    local tx=TerrainBatch.transaction
    if tx==nil or tx.state=='undone' then return true end

    -- Sofort verhindern, dass der Update-Loop waehrend des Speicherns weiterschreibt.
    local previous=tx.state
    tx.state='saveRestoring'
    local count=(previous=='uncertain') and #tx.points
        or math.max(tx.lastAttempted or 0, tx.done or 0)
    if previous=='applied' then count=#tx.points end

    local failures=0
    for i=count,1,-1 do
        local p=tx.points[i]
        local ok=write(p.x,p.z,p.before)
        if not ok then failures=failures+1 end
    end

    -- Alle gesicherten Positionen verifizieren, auch wenn sie nicht geschrieben wurden.
    for _,p in ipairs(tx.points) do
        local y=read(p.x,p.z)
        if y==nil or math.abs(y-p.before)>TerrainStability.TOLERANCE then
            failures=failures+1
        end
    end
    if failures==0 then
        local neighborsOk=TerrainStability.checkNeighbors(tx)
        if not neighborsOk then failures=failures+1 end
    end

    if failures>0 then
        tx.state='uncertain'
        tx.replayAllowed=false
        print('[Terraform Plus] KRITISCH: Saveguard konnte Batch nicht sicher zuruecksetzen ('..failures..' Fehler)')
        return false
    end

    tx.state='undone'
    tx.replayAllowed=false
    tx.rollbackIndex=0
    tx.rollbackFailures=0
    tx.neighborsChecked=true
    print('[Terraform Plus] SAVEGUARD: Batch vor dem Speichern sicher zurueckgesetzt ('..count..' Schreibpositionen)')
    return true
end

local function restoreWriterBeforeSave(owner)
    local tx=TerrainWriter.transaction
    if tx==nil or tx.state=='undone' then return true end
    if tx.state~='applied' and tx.state~='uncertain' then return true end
    local ok,msg=TerrainWriter.undo(owner,'CONFIRM')
    if not ok then
        print('[Terraform Plus] KRITISCH: Saveguard 9-Punkte-Undo: '..tostring(msg))
        return false
    end
    return true
end

function TerrainStability.beforeSave(mission)
    local owner=TerraformPlus
    if not restoreBatchBeforeSave() then return false end
    if not restoreWriterBeforeSave(owner) then return false end
    return true
end

-- Nur dokumentierte Mission-Speicher-Einstiegspunkte hooken.
-- Ist die Version inkompatibel, sperren wir neue Terrain-Schreibtests.
local saveClass=FSBaseMission
if type(saveClass)=='table'
    and type(saveClass.startSaveCurrentGame)=='function'
    and type(saveClass.saveSavegame)=='function' then

    local originalStart=saveClass.startSaveCurrentGame
    local originalSave=saveClass.saveSavegame

    saveClass.startSaveCurrentGame=function(mission,...)
        if not TerrainStability.beforeSave(mission) then
            print('[Terraform Plus] SAVEGUARD: Speichern wegen unsicherer Terrainhoehen blockiert')
            return false
        end
        return originalStart(mission,...)
    end

    saveClass.saveSavegame=function(mission,...)
        if not TerrainStability.beforeSave(mission) then
            print('[Terraform Plus] SAVEGUARD: Speichern wegen unsicherer Terrainhoehen blockiert')
            return false
        end
        return originalSave(mission,...)
    end

    TerrainStability.saveHookReady=true
    print('[Terraform Plus] Saveguard aktiv: startSaveCurrentGame + saveSavegame')
else
    print('[Terraform Plus] SAVEGUARD NICHT VERFUEGBAR: Schreibtests bleiben gesperrt')
end

local oldApply=TerraformPlus.consoleCommandBatchApply
function TerraformPlus:consoleCommandBatchApply(...)
    if not TerrainStability.saveHookReady then
        return '[Terraform Plus] Schreibtest blockiert: Saveguard nicht geladen'
    end
    return oldApply(self,...)
end

local oldTest=TerraformPlus.consoleCommandTerrainTest
function TerraformPlus:consoleCommandTerrainTest(...)
    if not TerrainStability.saveHookReady then
        return '[Terraform Plus] 9-Punkte-Test blockiert: Saveguard nicht geladen'
    end
    return oldTest(self,...)
end

function TerraformPlus:consoleCommandNeighborCheck()
    local tx=TerrainBatch.transaction
    if tx==nil or tx.neighbors==nil then
        return '[Terraform Plus] Noch kein Batch mit Nachbarschaftssicherung vorhanden'
    end
    local ok,msg=TerrainStability.checkNeighbors(tx)
    return '[Terraform Plus] Nachbarpruefung '..(ok and 'OK: ' or 'FEHLER: ')..tostring(msg)
end

function TerraformPlus:consoleCommandSaveGuardStatus()
    return '[Terraform Plus] Saveguard='..(TerrainStability.saveHookReady and 'AKTIV' or 'NICHT VERFUEGBAR')
        ..' | '..tostring(TerrainStability.lastCheck)
end

for _,spec in ipairs({
    {'tpNeighborCheck','Unveraenderte Nachbarhoehen pruefen','consoleCommandNeighborCheck'},
    {'tpSaveGuardStatus','Speicherschutz-Status','consoleCommandSaveGuardStatus'}
}) do
    local exists=false
    for _,c in ipairs(TerraformPlus.COMMANDS or {}) do
        if c[1]==spec[1] then exists=true break end
    end
    if not exists then table.insert(TerraformPlus.COMMANDS,spec) end
end

local oldLoad=TerraformPlus.loadMap
function TerraformPlus:loadMap(...)
    TerrainStability.lastCheck='Noch keine Nachbarpruefung'
    return oldLoad(self,...)
end

-- Eine einzige Zeichenroutine; die gestapelten alten Draw-Wrapper
-- werden nicht mehr aufgerufen. Bestehende Eingabe-/Haltefunktionen bleiben.
function TerrainToolUI.draw(owner)
    if not TerrainToolUI.visible or RenderText==nil or type(renderText)~='function'
        or (g_gui and type(g_gui.getIsGuiVisible)=='function'
            and g_gui:getIsGuiVisible()) then return end

    local c=TerrainToolUI.COLORS
    TerrainToolUI.buttons={}

    TerrainToolUI.rect(0.675,0.120,0.305,0.670,c.panel)
    TerrainToolUI.rect(0.675,0.746,0.305,0.044,c.header)
    TerrainToolUI.text(0.690,0.757,'TERRAFORM PLUS 0.0.16.0',0.016,c.text)
    TerrainToolUI.button('close','X',0.939,0.752,0.026,0.031,true,'warning')

    for i,t in ipairs({
        {'select','BEREICH'},
        {'design','GESTALTUNG'},
        {'review','PRUEFUNG'}
    }) do
        local x=0.690+(i-1)*0.093
        local id='tab'..(i==1 and 'Select' or i==2 and 'Design' or 'Review')
        TerrainToolUI.button(id,t[2],x,0.700,0.088,0.036,true,
            TerrainToolUI.page==t[1] and 'active')
    end

    local page=TerrainToolUI.page

    if page=='select' then
        local s=owner.selection
        local active=s~=nil and s.active
        local area=active and s.preview and s.preview.area or owner.area
        local state=not active and 'Kein Bereich aktiv' or
            (s.stage=='A' and 'Startpunkt anvisieren' or 'Endpunkt anvisieren')

        TerrainToolUI.text(0.690,0.658,state,0.014,c.text)
        TerrainToolUI.text(0.690,0.628,TerrainToolUI.mouseActive
            and 'Maus aktiv - Kameraziel fixiert'
            or 'Rechtsklick: Maus einschalten',0.012,c.muted)

        if area then
            TerrainToolUI.text(0.690,0.591,string.format(
                'Flaeche %.1f m2 | %d Zellen',
                area.area,#area.samples),0.012,c.text)
            TerrainToolUI.text(0.690,0.563,string.format(
                'Abtrag %.1f / Auftrag %.1f m3',
                area.cutVolume,area.fillVolume),0.012,c.muted)
        else
            TerrainToolUI.text(0.690,0.580,'Noch keine Analyse',0.012,c.muted)
        end

        TerrainToolUI.button('start','NEUER BEREICH',
            0.690,0.508,0.132,0.040,not active)
        TerrainToolUI.button('refresh','NEU BERECHNEN',
            0.833,0.508,0.132,0.040,
            not active and owner.pointA~=nil and owner.pointB~=nil)

        local aim=not TerrainToolUI.mouseActive
            or TerrainToolUI.frozenSample~=nil

        TerrainToolUI.button('anchor','STARTPUNKT SETZEN',
            0.690,0.459,0.132,0.040,
            active and s.stage=='A' and aim)
        TerrainToolUI.button('confirm','ENDPUNKT SETZEN',
            0.833,0.459,0.132,0.040,
            active and s.stage=='B' and aim)
        TerrainToolUI.button('clear','BEREICH LOESCHEN',
            0.690,0.409,0.275,0.040,
            active or owner.pointA~=nil or owner.pointB~=nil,'warning')

        TerrainToolUI.setting('width','BREITE (0,5-m-Schritte)',
            owner.areaWidth,0.337,
            TerrainArea.MIN_WIDTH,TerrainArea.MAX_WIDTH,'m')
        TerrainToolUI.setting('step','RASTERABSTAND',
            owner.areaStep,0.268,
            TerrainArea.MIN_STEP,TerrainArea.MAX_STEP,'m')

        TerrainToolUI.text(0.690,0.240,
            'Halten: schneller, Schrittweite bleibt fest',0.011,c.muted)

        TerrainToolUI.button('preview',
            owner.previewEnabled and 'HOEHENPROFIL AN' or 'HOEHENPROFIL AUS',
            0.690,0.157,0.132,0.042,true,
            owner.previewEnabled and 'active')
        TerrainToolUI.button('areaVisual',
            owner.areaEnabled and '3D-VORSCHAU AN' or '3D-VORSCHAU AUS',
            0.833,0.157,0.132,0.042,true,
            owner.areaEnabled and 'active')

    elseif page=='design' then
        local d=owner.design or {
            offset=0,slope=0,feather=0,
            maxChange=10,mode='all',enabled=true
        }
        local target=owner.pointA and owner.pointA.terrainY+d.offset or nil

        TerrainToolUI.text(0.690,0.655,
            target and string.format('Sollhoehe bei A: %.2f m',target)
            or 'Bitte Bereich festlegen',0.013,c.text)

        TerrainToolUI.setting('height','HOEHENVERSATZ',
            d.offset,0.581,-100,100,'m')
        TerrainToolUI.setting('slope','ZIELSTEIGUNG',
            d.slope,0.515,-100,100,'%')
        TerrainToolUI.setting('feather','WEICHER RAND',
            d.feather,0.449,0,20,'m')
        TerrainToolUI.setting('limit','MAX. HOEHENAENDERUNG',
            d.maxChange,0.383,0.5,50,'m')

        TerrainToolUI.button('modeAll','BEIDES',
            0.690,0.338,0.088,0.034,true,d.mode=='all' and 'active')
        TerrainToolUI.button('modeCut','NUR ABTRAG',
            0.782,0.338,0.088,0.034,true,d.mode=='cut' and 'active')
        TerrainToolUI.button('modeFill','NUR AUFTRAG',
            0.874,0.338,0.091,0.034,true,d.mode=='fill' and 'active')

        local a,err=owner:getDesignArea()
        if a then
            TerrainToolUI.text(0.690,0.305,string.format(
                'Abtrag %.1f | Auftrag %.1f m3',
                a.cutVolume,a.fillVolume),0.012,c.text)
            TerrainToolUI.text(0.690,0.278,string.format(
                'Hoehenlimit bei %d Zellen aktiv',
                a.limitedCells),0.012,c.muted)
        else
            TerrainToolUI.text(0.690,0.290,
                tostring(err or 'Keine Vorschau'),0.012,c.muted)
        end

        TerrainToolUI.button('undo','RUECKGAENGIG',
            0.690,0.237,0.132,0.039,
            #(owner.designUndo or {})>0)
        TerrainToolUI.button('redo','WIEDERHOLEN',
            0.833,0.237,0.132,0.039,
            #(owner.designRedo or {})>0)
        TerrainToolUI.button('designVisual',
            d.enabled and 'SOLL-VORSCHAU AN' or 'SOLL-VORSCHAU AUS',
            0.690,0.157,0.169,0.043,true,d.enabled and 'active')
        TerrainToolUI.button('resetDesign','RESET',
            0.867,0.157,0.098,0.043,true)

    else
        local tx=TerrainBatch.transaction
        local tstate=tx and tx.state or 'idle'
        local busy=TerrainBatch.busy()
        local plan=TerrainPlan.isFresh(owner) and owner.terrainPlan or nil
        local old=TerrainWriter.transaction
        local oldBusy=old and (
            old.state=='applied' or old.state=='uncertain'
        )
        local canWrite=TerrainStability.saveHookReady
            and plan and plan.approved
            and not TerrainBatch.blocksLegacy() and not oldBusy

        local percentage=tx and #tx.points>0
            and math.floor(100*(tx.done or 0)/#tx.points) or 0

        TerrainToolUI.text(0.690,0.660,
            'TESTBETRIEB - nur Savegame-Kopie',0.013,c.text)
        TerrainToolUI.text(0.690,0.627,
            plan and string.format(
                'Pruefplan: %d Punkte | %.3f m Raster',
                #plan.points,plan.unit)
            or 'Kein aktueller Pruefplan',0.012,c.muted)
        TerrainToolUI.text(0.690,0.600,
            TerrainStability.saveHookReady
                and 'Speicherschutz aktiv (automatisches Undo)'
                or 'ACHTUNG: SPEICHERSCHUTZ FEHLT',
            0.012,
            TerrainStability.saveHookReady and c.fill or c.cut)

        TerrainToolUI.text(0.690,0.569,
            string.format('Batch: %s | %d/%d (%d%%)',
                tstate,tx and tx.done or 0,
                tx and #tx.points or 0,percentage),
            0.012,c.text)

        TerrainToolUI.rect(0.690,0.543,0.275,0.012,c.disabled)
        TerrainToolUI.rect(0.690,0.543,
            0.275*percentage/100,0.012,c.active)

        TerrainToolUI.text(0.690,0.512,
            TerrainStability.lastCheck,0.0108,c.muted)

        TerrainToolUI.button('prepare','PRUEFRASTER',
            0.690,0.454,0.132,0.040,
            not busy and owner.selection==nil
                and owner.pointA~=nil and owner.pointB~=nil)
        TerrainToolUI.button('approve','PLAN FREIGEBEN',
            0.833,0.454,0.132,0.040,
            not busy and plan~=nil and not plan.approved)
        TerrainToolUI.button('run','PROBELAUF (OHNE AENDERUNG)',
            0.690,0.402,0.275,0.040,
            not busy and plan~=nil and plan.approved)

        TerrainToolUI.button('batchApply',
            TerrainBatch.armed
                and 'ECHTEN EINGRIFF BESTAETIGEN'
                or 'BATCH TESTWEISE AUSFUEHREN',
            0.690,0.350,0.275,0.042,canWrite,'warning')

        TerrainToolUI.button('batchCancel','ABBRECHEN + ROLLBACK',
            0.690,0.301,0.275,0.039,
            tx~=nil and tx.state=='applying','warning')
        TerrainToolUI.button('batchUndo','BATCH ZURUECKSETZEN',
            0.690,0.253,0.132,0.039,
            tx~=nil and tx.state=='applied','active')
        TerrainToolUI.button('batchRedo','REDO',
            0.833,0.253,0.132,0.039,
            tx~=nil and tx.state=='undone' and tx.replayAllowed)
        TerrainToolUI.button('batchRecover','WIEDERHERSTELLEN',
            0.690,0.204,0.275,0.039,
            tx~=nil and tx.state=='uncertain','warning')

        TerrainToolUI.text(0.690,0.154,
            'Vor Speichern: Batch wird automatisch zurueckgesetzt',
            0.0105,c.cut)
    end

    setTextAlignment(RenderText.ALIGN_LEFT)
    setTextColor(1,1,1,1)
end

-- Alle UI-Klicks zentral verarbeiten,
-- ohne die alten perform-Wrapper aufzurufen.
function TerrainToolUI.perform(owner,id)
    if id=='tabSelect' then
        TerrainToolUI.page='select'
    elseif id=='tabDesign' then
        TerrainToolUI.page='design'
    elseif id=='tabReview' then
        TerrainToolUI.page='review'
    elseif id=='modeAll' then
        print(owner:consoleCommandWorkMode('all'))
    elseif id=='modeCut' then
        print(owner:consoleCommandWorkMode('cut'))
    elseif id=='modeFill' then
        print(owner:consoleCommandWorkMode('fill'))
    elseif id=='approve' then
        print(owner:consoleCommandPlanApprove('CONFIRM'))
    elseif id=='run' then
        print(owner:consoleCommandPlanRun('RUN'))
    elseif id=='batchApply' then
        if not TerrainBatch.armed then
            TerrainBatch.armed=true
            print('[Terraform Plus] ECHTE Hoehenaenderung: Button erneut klicken')
            return
        end
        TerrainBatch.armed=false
        print(owner:consoleCommandBatchApply('CONFIRM'))
        return
    elseif id=='batchCancel' then
        print(owner:consoleCommandBatchCancel())
    elseif id=='batchUndo' then
        print(owner:consoleCommandBatchUndo('CONFIRM'))
    elseif id=='batchRedo' then
        print(owner:consoleCommandBatchRedo('CONFIRM'))
    elseif id=='batchRecover' then
        print(owner:consoleCommandBatchRecover('CONFIRM'))
    else
        local methods={
            close='consoleCommandUI',
            start='consoleCommandSelect',
            refresh='consoleCommandRefresh',
            anchor='consoleCommandAnchor',
            confirm='consoleCommandConfirm',
            clear='consoleCommandClear',
            preview='consoleCommandPreview',
            areaVisual='consoleCommandAreaVisual',
            designVisual='consoleCommandDesignVisual',
            resetDesign='consoleCommandDesignReset',
            undo='consoleCommandDesignUndo',
            redo='consoleCommandDesignRedo',
            prepare='consoleCommandPlanPrepare'
        }
        local fn=methods[id]
        if fn and type(owner[fn])=='function' then
            print(owner[fn](owner))
        end
    end

    TerrainBatch.armed=false
    TerrainWriter.armed=false
end

print('[Terraform Plus] 0.0.16.0 Stabilitaet geladen (ein UI-Renderer, Nachbarschaft, Saveguard)')
