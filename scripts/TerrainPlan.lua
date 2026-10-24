
-- Terraform Plus 0.0.13.0 - Entwurfsverlauf und sicherer Probelauf
-- Ausschliesslich lesende Terrain-Abfragen; keine Heightmap-Schreibzugriffe.
TerrainPlan = TerrainPlan or {}
TerrainPlan.MAX_HISTORY = 40
TerrainPlan.MAX_CANDIDATES = 30000
TerrainPlan.MAX_CHANGED_POINTS = 12000

local fields = {"offset", "slope", "feather", "maxChange", "mode", "enabled"}

function TerrainPlan.snapshot(d)
    local result = {}
    for _, key in ipairs(fields) do result[key] = d[key] end
    return result
end

function TerrainPlan.different(a, b)
    for _, key in ipairs(fields) do
        if a[key] ~= b[key] then return true end
    end
    return false
end

function TerrainPlan.invalidate(owner)
    owner.terrainPlan = nil
end

function TerrainPlan.record(owner, before)
    TerrainPlan.invalidate(owner)
    if owner.designEditBefore ~= nil then return end
    if not TerrainPlan.different(before, owner.design) then return end
    local undo = owner.designUndo
    undo[#undo + 1] = before
    if #undo > TerrainPlan.MAX_HISTORY then table.remove(undo, 1) end
    owner.designRedo = {}
end

function TerrainPlan.beginEdit(owner)
    if owner.designEditBefore == nil then
        owner.designEditBefore = TerrainPlan.snapshot(owner.design)
    end
end

function TerrainPlan.endEdit(owner)
    local before = owner.designEditBefore
    owner.designEditBefore = nil
    if before ~= nil then TerrainPlan.record(owner, before) end
end

local function applySnapshot(owner, saved)
    for _, key in ipairs(fields) do owner.design[key] = saved[key] end
    owner.design.cacheBase = nil
    owner.design.cacheKey = nil
    owner.design.cacheArea = nil
    owner.design.cacheError = nil
    TerrainPlan.invalidate(owner)
end

function TerrainPlan.undo(owner)
    TerrainPlan.endEdit(owner)
    local undo = owner.designUndo
    if #undo == 0 then return nil, "Keine Gestaltungsaktion rueckgaengig zu machen" end
    local previous = table.remove(undo)
    owner.designRedo[#owner.designRedo + 1] = TerrainPlan.snapshot(owner.design)
    applySnapshot(owner, previous)
    return true, "Letzte Gestaltungsaktion rueckgaengig gemacht"
end

function TerrainPlan.redo(owner)
    TerrainPlan.endEdit(owner)
    local redo = owner.designRedo
    if #redo == 0 then return nil, "Keine Gestaltungsaktion wiederherzustellen" end
    local nextValue = table.remove(redo)
    owner.designUndo[#owner.designUndo + 1] = TerrainPlan.snapshot(owner.design)
    applySnapshot(owner, nextValue)
    return true, "Gestaltungsaktion wiederhergestellt"
end

local function fingerprint(d)
    return string.format("%.5f/%.5f/%.5f/%.5f/%s",
        d.offset, d.slope, d.feather, d.maxChange, d.mode)
end

function TerrainPlan.isFresh(owner)
    local plan = owner.terrainPlan
    return plan ~= nil and owner.selection == nil
        and owner.pointA == plan.pointA and owner.pointB == plan.pointB
        and owner.area == plan.baseArea
        and fingerprint(owner.design) == plan.fingerprint
end

local function clamp(value, a, b)
    return math.max(a, math.min(b, value))
end

local function smooth(t)
    t = clamp(t, 0, 1)
    return t*t*(3-2*t)
end

-- Liest ein pruefbares Raster im Abstand der Engine-Heightmap-Einheit.
-- Das Raster wird am Terrain-Node-Ursprung ausgerichtet. Die exakte
-- Vertexzuordnung muss vor spaeteren Schreibzugriffen gesondert verifiziert werden.
function TerrainPlan.prepare(owner)
    if owner.selection ~= nil or owner.pointA == nil or owner.pointB == nil
        or owner.area == nil then
        return nil, "Zuerst einen Bereich vollstaendig bestaetigen"
    end
    if g_terrainNode == nil or type(getTerrainHeightmapUnitSize) ~= "function" then
        return nil, "Heightmap-Einheit der Engine nicht verfuegbar"
    end
    local ok, unit = pcall(getTerrainHeightmapUnitSize, g_terrainNode)
    if not ok or type(unit) ~= "number" or unit ~= unit or unit < 0.05 or unit > 32 then
        return nil, "Ungueltige Heightmap-Einheit: " .. tostring(unit)
    end
    local a, b, area, d = owner.pointA, owner.pointB, owner.area, owner.design
    local dx, dz = b.x-a.x, b.z-a.z
    local length = math.sqrt(dx*dx+dz*dz)
    if length < 0.01 then return nil, "Auswahl zu klein" end
    local ux, uz = dx/length, dz/length
    local sx, sz = -uz, ux
    local halfWidth = owner.areaWidth / 2
    local xs, zs = {}, {}
    for _, along in ipairs({0, length}) do
        for _, lateral in ipairs({-halfWidth, halfWidth}) do
            xs[#xs+1] = a.x+ux*along+sx*lateral
            zs[#zs+1] = a.z+uz*along+sz*lateral
        end
    end
    local minX,maxX,minZ,maxZ = xs[1],xs[1],zs[1],zs[1]
    for i=2,#xs do
        minX=math.min(minX,xs[i]); maxX=math.max(maxX,xs[i])
        minZ=math.min(minZ,zs[i]); maxZ=math.max(maxZ,zs[i])
    end
    local ox,oz = 0,0
    if type(getWorldTranslation)=="function" then
        local success,x,_,z = pcall(getWorldTranslation,g_terrainNode)
        if success and type(x)=="number" and type(z)=="number" then ox,oz=x,z end
    end
    local ix0,ix1 = math.ceil((minX-ox)/unit),math.floor((maxX-ox)/unit)
    local iz0,iz1 = math.ceil((minZ-oz)/unit),math.floor((maxZ-oz)/unit)
    local candidates = math.max(0,ix1-ix0+1)*math.max(0,iz1-iz0+1)
    if candidates > TerrainPlan.MAX_CANDIDATES then
        return nil, string.format("Pruefraster zu gross: %d Kandidaten (max. %d). Breite/Laenge reduzieren",
            candidates, TerrainPlan.MAX_CANDIDATES)
    end
    local points, checked, cut, fill = {},0,0,0
    local limited = 0
    for iz=iz0,iz1 do
        for ix=ix0,ix1 do
            local x,z = ox+ix*unit,oz+iz*unit
            local rx,rz=x-a.x,z-a.z
            local along=rx*ux+rz*uz
            local across=rx*sx+rz*sz
            if along >= 0 and along <= length and math.abs(across) <= halfWidth then
                checked=checked+1
                local readOk, height, err=pcall(TerrainAdapter.getHeightAt,x,z)
                if not readOk or type(height)~="number" then
                    return nil,"Terrainabfrage fehlgeschlagen: "..tostring(err or height)
                end
                local wanted=(a.terrainY+d.offset+along*d.slope/100)-height
                if d.mode=="cut" then wanted=math.min(0,wanted) end
                if d.mode=="fill" then wanted=math.max(0,wanted) end
                if d.feather>0 then
                    local border=math.min(along,length-along,halfWidth-math.abs(across))
                    wanted=wanted*smooth(border/d.feather)
                end
                local delta=clamp(wanted,-d.maxChange,d.maxChange)
                if math.abs(wanted-delta)>0.000001 then limited=limited+1 end
                if math.abs(delta)>0.02 then
                    if #points >= TerrainPlan.MAX_CHANGED_POINTS then
                        return nil,"Zu viele betroffene Rasterpunkte; Bereich verkleinern"
                    end
                    points[#points+1]={x=x,z=z,before=height,after=height+delta,change=delta}
                    if delta>0 then fill=fill+delta*unit*unit
                    else cut=cut-delta*unit*unit end
                end
            end
        end
    end
    local plan={points=points,checked=checked,candidates=candidates,
        cutVolume=cut,fillVolume=fill,limited=limited,unit=unit,
        pointA=a,pointB=b,baseArea=area,fingerprint=fingerprint(d),
        approved=false}
    owner.terrainPlan=plan
    return plan,nil
end

function TerrainPlan.approve(owner)
    if not TerrainPlan.isFresh(owner) then
        return nil,"Pruefung fehlt oder Entwurf geaendert. Erst tpPlanPrepare"
    end
    owner.terrainPlan.approved=true
    return true,"Pruefplan freigegeben (weiterhin KEINE Gelaendeaenderung)"
end

function TerrainPlan.dryRun(owner)
    if not TerrainPlan.isFresh(owner) or not owner.terrainPlan.approved then
        return nil,"Erst tpPlanPrepare und tpPlanApprove CONFIRM"
    end
    local plan=owner.terrainPlan
    plan.approved=false
    return true,string.format(
        "PROBELAUF OK | %d betroffene Pruefpunkte | Abtrag ca. %.2f m3 | Auftrag ca. %.2f m3 | KEINE HEIGHTMAP-AENDERUNG",
        #plan.points,plan.cutVolume,plan.fillVolume)
end
