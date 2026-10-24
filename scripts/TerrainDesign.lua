
-- Terraform Plus v0.0.12.0 - Sichere Soll-Gelaendevorschau
-- Nur Berechnung/Visualisierung: keine Terrain-Schreibzugriffe.
TerrainDesign = TerrainDesign or {}

TerrainDesign.MIN_OFFSET, TerrainDesign.MAX_OFFSET = -100, 100
TerrainDesign.MIN_SLOPE, TerrainDesign.MAX_SLOPE = -100, 100
TerrainDesign.MIN_FEATHER, TerrainDesign.MAX_FEATHER = 0, 20
TerrainDesign.MIN_CHANGE, TerrainDesign.MAX_CHANGE = 0.5, 50
TerrainDesign.DEFAULT_CHANGE = 10

local function clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function smoothstep(value)
    local t = clamp(value, 0, 1)
    return t * t * (3 - 2 * t)
end

local function finite(value)
    return type(value) == "number" and value == value
        and value ~= math.huge and value ~= -math.huge
end

function TerrainDesign.build(base, pointA, options)
    if base == nil or pointA == nil or type(base.samples) ~= "table" then
        return nil, "Zuerst einen Bereich auswaehlen"
    end
    options = options or {}
    local offset = options.offset or 0
    local slope = options.slope or 0
    local feather = options.feather or 0
    local limit = options.maxChange or TerrainDesign.DEFAULT_CHANGE
    local mode = options.mode or "all"
    if not (finite(offset) and finite(slope) and finite(feather)
        and finite(limit)) then
        return nil, "Ungueltige Soll-Gelaendeparameter"
    end
    if offset < TerrainDesign.MIN_OFFSET or offset > TerrainDesign.MAX_OFFSET
        or slope < TerrainDesign.MIN_SLOPE or slope > TerrainDesign.MAX_SLOPE
        or feather < TerrainDesign.MIN_FEATHER or feather > TerrainDesign.MAX_FEATHER
        or limit < TerrainDesign.MIN_CHANGE or limit > TerrainDesign.MAX_CHANGE then
        return nil, "Soll-Gelaendeparameter ausserhalb der Grenzen"
    end
    if mode ~= "all" and mode ~= "cut" and mode ~= "fill" then
        return nil, "Modus muss all, cut oder fill sein"
    end
    local length, width = base.distance, base.width
    if not finite(length) or length <= 0 or not finite(width) or width <= 0
        or not finite(base.cellLength) or not finite(base.cellArea) then
        return nil, "Ungueltiges Raster"
    end
    local widthCells = base.widthCells
    if type(widthCells) ~= "number" or widthCells < 1 then
        return nil, "Ungueltige Rasterbreite"
    end
    local startY = pointA.terrainY + offset
    local endY = startY + length * slope / 100
    local samples = {}
    local cut, fill = 0, 0
    local maxCut, maxFill = 0, 0
    local maxCutSample, maxFillSample = nil, nil
    local limitedCells, limitedVolume = 0, 0
    local maxRequested = 0

    for _, source in ipairs(base.samples) do
        local along = (source.alongIndex - 0.5) * base.cellLength
        local lateral = ((source.acrossIndex - 0.5) / widthCells - 0.5) * width
        local desired = startY + along * slope / 100
        local requested = desired - source.terrainY
        if mode == "cut" then requested = math.min(0, requested) end
        if mode == "fill" then requested = math.max(0, requested) end

        local influence = 1
        if feather > 0 then
            local distanceToEdge = math.min(along, length - along,
                width / 2 - math.abs(lateral))
            influence = smoothstep(distanceToEdge / feather)
        end
        requested = requested * influence
        local actual = clamp(requested, -limit, limit)
        maxRequested = math.max(maxRequested, math.abs(requested))
        if math.abs(actual - requested) > 0.000001 then
            limitedCells = limitedCells + 1
            limitedVolume = limitedVolume +
                math.abs(requested - actual) * source.cellArea
        end
        local sample = {
            x = source.x, z = source.z,
            terrainY = source.terrainY, desiredY = desired,
            referenceY = source.terrainY + actual,
            requestedChange = requested, requiredChange = actual,
            influence = influence, cellArea = source.cellArea,
            alongIndex = source.alongIndex,
            acrossIndex = source.acrossIndex
        }
        samples[#samples + 1] = sample
        if actual > 0 then
            fill = fill + actual * source.cellArea
            if actual > maxFill then
                maxFill, maxFillSample = actual, sample
            end
        elseif actual < 0 then
            local depth = -actual
            cut = cut + depth * source.cellArea
            if depth > maxCut then
                maxCut, maxCutSample = depth, sample
            end
        end
    end

    return {
        samples = samples, area = base.area, width = width,
        distance = length, cellArea = base.cellArea,
        lengthCells = base.lengthCells, widthCells = widthCells,
        cellLength = base.cellLength, cellWidth = base.cellWidth,
        cutVolume = cut, fillVolume = fill, netVolume = fill - cut,
        maxCutDepth = maxCut, maxFillDepth = maxFill,
        maxCutSample = maxCutSample, maxFillSample = maxFillSample,
        limitedCells = limitedCells, limitedVolume = limitedVolume,
        maxRequested = maxRequested, maxChange = limit,
        startY = startY, endY = endY,
        mode = mode, feather = feather, slope = slope
    }, nil
end

function TerrainDesign.draw(area, pointA, pointB)
    if area == nil or pointA == nil or pointB == nil
        or TerrainVisualizer == nil
        or type(TerrainVisualizer.drawLine) ~= "function" then return end
    local dx, dz = pointB.x - pointA.x, pointB.z - pointA.z
    local length = math.sqrt(dx * dx + dz * dz)
    if length < 0.01 then return end
    local sx, sz = -dz / length, dx / length
    local half, lift = area.width / 2, 0.30
    local function line(x1,y1,z1,x2,y2,z2,r,g,b)
        TerrainVisualizer.drawLine(x1,y1,z1,x2,y2,z2,r,g,b)
    end
    local ax1,az1 = pointA.x + sx*half,pointA.z + sz*half
    local ax2,az2 = pointA.x - sx*half,pointA.z - sz*half
    local bx1,bz1 = pointB.x + sx*half,pointB.z + sz*half
    local bx2,bz2 = pointB.x - sx*half,pointB.z - sz*half
    local ya,yb = area.startY + lift,area.endY + lift
    line(ax1,ya,az1,ax2,ya,az2,0.1,0.8,1)
    line(bx1,yb,bz1,bx2,yb,bz2,0.1,0.8,1)
    line(ax1,ya,az1,bx1,yb,bz1,0.1,0.8,1)
    line(ax2,ya,az2,bx2,yb,bz2,0.1,0.8,1)
    line(pointA.x,ya,pointA.z,pointB.x,yb,pointB.z,0.1,0.8,1)
    local stride = math.max(1, math.ceil(#area.samples / 120))
    for i = 1, #area.samples, stride do
        local s = area.samples[i]
        if math.abs(s.requiredChange) > 0.02 then
            local r,g,b = 1,0.25,0.2
            if s.requiredChange > 0 then r,g,b = 0.2,1,0.35 end
            line(s.x,s.terrainY+lift,s.z,
                 s.x,s.referenceY+lift,s.z,r,g,b)
        end
    end
end
