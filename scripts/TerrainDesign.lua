
-- Terraform Plus 0.0.11.0 - Read-only terrain design
TerrainDesign = TerrainDesign or {}

TerrainDesign.MIN_OFFSET = -100
TerrainDesign.MAX_OFFSET = 100
TerrainDesign.MIN_SLOPE = -100
TerrainDesign.MAX_SLOPE = 100
TerrainDesign.MIN_FEATHER = 0
TerrainDesign.MAX_FEATHER = 20

local function smooth01(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

-- base: measured TerrainArea, containing midpoint samples.
-- No heightmap writes and no additional terrain reads.
function TerrainDesign.build(base, pointA, settings)
    if base == nil or pointA == nil then
        return nil, "Bitte zuerst einen Bereich mit A und B festlegen"
    end
    if type(base.samples) ~= "table" then
        return nil, "Ungueltiges 2D-Raster"
    end
    local offset = settings.offset or 0
    local slope = settings.slope or 0
    local feather = settings.feather or 0
    local mode = settings.mode or "all"
    if mode ~= "all" and mode ~= "cut" and mode ~= "fill" then
        return nil, "Ungueltiger Bearbeitungsmodus"
    end

    local length = base.distance
    local width = base.width
    local startY = pointA.terrainY + offset
    local endY = startY + length * slope / 100
    local samples = {}
    local cut, fill = 0, 0
    local maxCut, maxFill = 0, 0
    local maxCutSample, maxFillSample = nil, nil

    for _, source in ipairs(base.samples) do
        local along = (source.alongIndex - 0.5) * base.cellLength
        local lateral = ((source.acrossIndex - 0.5) / base.widthCells - 0.5) * width
        local desiredY = startY + along * slope / 100
        local delta = desiredY - source.terrainY

        if mode == "cut" then delta = math.min(0, delta) end
        if mode == "fill" then delta = math.max(0, delta) end

        local influence = 1
        if feather > 0 then
            local endDistance = math.min(along, length - along)
            local edgeDistance = width / 2 - math.abs(lateral)
            influence = smooth01(math.min(endDistance, edgeDistance) / feather)
        end
        delta = delta * influence

        local sample = {
            x = source.x, z = source.z,
            terrainY = source.terrainY,
            desiredY = desiredY,
            referenceY = source.terrainY + delta,
            requiredChange = delta,
            influence = influence,
            cellArea = source.cellArea,
            alongIndex = source.alongIndex,
            acrossIndex = source.acrossIndex
        }
        samples[#samples + 1] = sample
        if delta > 0 then
            fill = fill + delta * source.cellArea
            if delta > maxFill then maxFill, maxFillSample = delta, sample end
        elseif delta < 0 then
            cut = cut - delta * source.cellArea
            if -delta > maxCut then maxCut, maxCutSample = -delta, sample end
        end
    end

    return {
        samples = samples,
        area = base.area,
        width = width,
        distance = length,
        requestedStep = base.requestedStep,
        lengthCells = base.lengthCells,
        widthCells = base.widthCells,
        cellLength = base.cellLength,
        cellWidth = base.cellWidth,
        cutVolume = cut,
        fillVolume = fill,
        netVolume = fill - cut,
        maxCutDepth = maxCut,
        maxFillDepth = maxFill,
        maxCutSample = maxCutSample,
        maxFillSample = maxFillSample,
        startY = startY,
        endY = endY,
        mode = mode,
        feather = feather,
        slope = slope
    }, nil
end

-- Separate cyan nominal plane and red/green adjustment guides.
-- We deliberately do not draw the old straight A-B target as the design.
function TerrainDesign.draw(area, pointA, pointB)
    if area == nil or pointA == nil or pointB == nil
        or TerrainVisualizer == nil
        or type(TerrainVisualizer.drawLine) ~= "function" then return end

    local dx, dz = pointB.x - pointA.x, pointB.z - pointA.z
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.01 then return end
    local sx, sz = -dz / length, dx / length
    local half = area.width / 2
    local lift = 0.30

    local function line(x1, y1, z1, x2, y2, z2, r, g, b)
        TerrainVisualizer.drawLine(x1, y1, z1, x2, y2, z2, r, g, b)
    end

    local aLx, aLz = pointA.x + sx * half, pointA.z + sz * half
    local aRx, aRz = pointA.x - sx * half, pointA.z - sz * half
    local bLx, bLz = pointB.x + sx * half, pointB.z + sz * half
    local bRx, bRz = pointB.x - sx * half, pointB.z - sz * half
    local yA, yB = area.startY + lift, area.endY + lift
    line(aLx,yA,aLz, aRx,yA,aRz, 0.1,0.8,1.0)
    line(bLx,yB,bLz, bRx,yB,bRz, 0.1,0.8,1.0)
    line(aLx,yA,aLz, bLx,yB,bLz, 0.1,0.8,1.0)
    line(aRx,yA,aRz, bRx,yB,bRz, 0.1,0.8,1.0)
    line(pointA.x,yA,pointA.z, pointB.x,yB,pointB.z, 0.1,0.8,1.0)

    local stride = math.max(1, math.ceil(#area.samples / 96))
    for i = 1, #area.samples, stride do
        local sample = area.samples[i]
        if math.abs(sample.requiredChange) > 0.02 then
            local r,g,b = 1.0,0.25,0.2
            if sample.requiredChange > 0 then r,g,b=0.2,1.0,0.35 end
            line(sample.x,sample.terrainY+lift,sample.z,
                sample.x,sample.referenceY+lift,sample.z,r,g,b)
        end
    end
end
