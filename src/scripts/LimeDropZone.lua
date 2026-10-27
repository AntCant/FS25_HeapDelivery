--
-- LimeDropZone
-- Mark rectangular drop zones on the map and order lime that is delivered there as a heap.
--
-- Server-authoritative: zones and pending orders live on the server, are saved
-- in the savegame and synced to clients. Clients only send requests.
--

LimeDropZone = {}
LimeDropZone.MOD_NAME = g_currentModName
LimeDropZone.MOD_DIR = g_currentModDirectory
LimeDropZone.SAVE_FILENAME = "heapDelivery.xml"
LimeDropZone.LEGACY_SAVE_FILENAME = "limeDropZone.xml"   -- test saves from before the rename
LimeDropZone.SETTINGS_FILENAME = "FS25_HeapDelivery.xml"

-- Tweakables ---------------------------------------------------------------
-- Zone sizes (circle diameters) offered in the Size menu, with the most lime a heap of that size holds (liters).
-- Measured in game on flat ground with grid-aligned heaps (4x4: 11,111 L,
-- 6x6: 35,778 L, 8x8: 82,667 L, identical on every spot), set about 10% lower for leeway.
LimeDropZone.ZONE_SIZES = {
    { size = 4, capacity = 10000 },
    { size = 6, capacity = 32000 },
    { size = 8, capacity = 74000 }
}
-- Same for other products (they pile differently). Manure measured in game on flat ground:
-- 4x4: 7,937 L, 6x6: 25,556 L, 8x8: 59,048 L, set about 10% lower like lime.
-- A product missing here is estimated from the lime numbers and its heap angle.
LimeDropZone.PRODUCT_CAPACITIES = {
    MANURE = { [4] = 7000, [6] = 23000, [8] = 53000 }
}
LimeDropZone.DEFAULT_SIZE = 8                   -- m, size of new zones until the player picks another
LimeDropZone.ZONE_GAP = 1                       -- m, minimum space between two zones
LimeDropZone.MAX_ZONES_PER_FARM = 50
LimeDropZone.MAX_NAME_LENGTH = 30
LimeDropZone.MAX_DESCRIPTION_LENGTH = 24        -- characters after "Field 3 - "
LimeDropZone.DELIVERY_DELAY_OPTIONS = { 10, 30, 60, 120, 300, 600, 900, 1800, 3600 }  -- seconds, the Settings choices
LimeDropZone.DEFAULT_DELIVERY_DELAY = 60        -- seconds of real time, paused with the game
LimeDropZone.DELIVERY_FEE_OPTIONS = { 0, 2.5, 5, 7.5, 10, 15, 20, 25 }            -- percent of the lime price
LimeDropZone.DEFAULT_DELIVERY_FEE = 5
LimeDropZone.FALLBACK_HEAP_PIECE = 20           -- L, used if the game doesn't report its smallest heap piece
LimeDropZone.MAX_HISTORY_PER_ZONE = 50          -- deliveries kept in the history of each spot
LimeDropZone.PRICE_MULTIPLIER = 1.0             -- on top of the game's lime price (difficulty included)
LimeDropZone.FALLBACK_PRICE_PER_LITER = 0.2     -- only used if the fill type has no price
LimeDropZone.AMOUNT_STEP = 500                  -- L, one step of the order slider
LimeDropZone.MIN_ORDER_LITERS = 500
-- products that can be ordered (fill type names); each must be a heap type the map allows on the ground
LimeDropZone.PRODUCTS = { "LIME", "MANURE", "STRAW", "DRYGRASS_WINDROW", "GRASS_WINDROW" }
-- capacities in ZONE_SIZES were measured with lime; other products are estimated from their heap angle and bulk
LimeDropZone.MEASURED_PRODUCT = "LIME"
LimeDropZone.HEAP_EDGE_MARGIN = 0.5             -- m, keep the heap this far inside the zone edge
LimeDropZone.SLOPE_CHECK_STEP = 1               -- m, spacing of the ground height samples for the slope readout
LimeDropZone.TIP_CHUNK = 2000                   -- L per tipping call
LimeDropZone.TIP_EMPTY_CALLS_TO_STOP = 5        -- this many calls in a row placing nothing = heap is full
LimeDropZone.TIP_MAX_CALLS = 5000               -- hard safety limit (10,000,000 L)
-- On ground too steep for a heap the game keeps almost nothing in the zone. The rest of the order is then
-- tipped on the nearest ground around the zone that holds it (owned land only, clear of other zones).
-- Rings of spots hugging the circle: each value is how far the overflow heap's center sits outside the
-- zone edge, in heap radii (0 = centered on the edge, half inside the zone). SPILL_DIRECTIONS spots per
-- ring, lowest ground first, so overflow piles against the downhill side of the zone.
LimeDropZone.SPILL_RINGS = { 0, 0.5, 1, 1.5, 2, 3, 4.5 }
LimeDropZone.SPILL_DIRECTIONS = 16
LimeDropZone.SPILL_EMPTY_CALLS_TO_STOP = 2      -- an overflow spot that takes nothing twice is skipped
LimeDropZone.STEEP_SLOPE = 12                   -- deg, from here the placement preview warns that heaps may spread
LimeDropZone.DRAW_DISTANCE = 150                -- m, outline/label render distance
LimeDropZone.SHOW_MAP_HOTSPOTS = true
LimeDropZone.OUTLINE_STEP = 0.5                 -- m, outline segment length (follows the terrain)
LimeDropZone.OUTLINE_COLOR = { 0.6, 1.0, 0.2 }
LimeDropZone.PLACE_MAX_DISTANCE = 60            -- m, how far away a new zone can be placed
LimeDropZone.PLACE_FALLBACK_DISTANCE = 15       -- m, preview distance when looking above the horizon
LimeDropZone.PLACE_COLOR_OK = { 0.2, 1.0, 0.2 }
LimeDropZone.PLACE_COLOR_BAD = { 1.0, 0.25, 0.1 }
LimeDropZone.LAND_CHECK_STEP = 2                -- m, spacing of the owned-land check across a zone
LimeDropZone.MAX_EVENT_IDS_PER_KEY = 4           -- key event ids kept per action (one per input context)
-----------------------------------------------------------------------------

LimeDropZone.ORDER_STATE_PLACED = 1
LimeDropZone.ORDER_STATE_DELIVERED = 2
LimeDropZone.ORDER_STATE_CANCELLED = 3

-- [zoneId] = { id, farmId, name, x, z, width, length, yaw, outlinePoints, centerY, hotspot }
LimeDropZone.zones = {}
-- [orderId] = { id, farmId, zoneId, liters, remainingMs, x, z, width, length, yaw, pricePerLiter }
LimeDropZone.orders = {}
-- delivery history, all farms (server keeps it in the savegame, clients get a copy)
-- { farmId, day, minute, zoneId, fieldId, farmlandId, suffixIndex, name, liters, delivered, paid, refund, cancelled }
LimeDropZone.history = {}
LimeDropZone.nextZoneId = 1
LimeDropZone.nextOrderId = 1
LimeDropZone.actionEventIds = {}
LimeDropZone.currentZone = nil
LimeDropZone.placement = nil      -- { startTime, rect, isValid, reason } while placing a new zone
-- savegame settings (Settings > Game Settings > Lime Drop Zones), synced to clients
LimeDropZone.settingValues = {
    deliveryDelay = LimeDropZone.DEFAULT_DELIVERY_DELAY,
    deliveryFee = LimeDropZone.DEFAULT_DELIVERY_FEE
}
-- per player, saved in modSettings
LimeDropZone.showMarkers = true
LimeDropZone.newZoneWidth = LimeDropZone.DEFAULT_SIZE
LimeDropZone.newZoneLength = LimeDropZone.DEFAULT_SIZE

local function log(fmt, ...)
    print(string.format("[LimeDropZone] " .. fmt, ...))
end

local function getText(key)
    return (g_i18n:getText(key):gsub("\\n", "\n"))
end

local function formatNumber(value)
    local s = tostring(math.floor(value + 0.5))
    local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    if formatted:sub(1, 1) == "," then
        formatted = formatted:sub(2)
    end
    return formatted
end

local function formatLiters(liters)
    return formatNumber(liters) .. " L"
end

---Money with the currency symbol in front ("$2,750")
local function formatMoney(amount)
    local text = g_i18n:formatMoney(amount, 0, true, true)
    return (text:gsub("^(%D-)%s+(%d)", "%1%2"))
end

---Readable duration: "1 minute", "30 seconds", "2 minutes 15 seconds"
local function formatDuration(ms)
    local total = math.max(0, math.ceil(ms / 1000))
    local minutes, seconds = math.floor(total / 60), total % 60
    local parts = {}
    if minutes > 0 then
        table.insert(parts, string.format(getText(minutes == 1 and "limeDrop_time_minute" or "limeDrop_time_minutes"), minutes))
    end
    if seconds > 0 or minutes == 0 then
        table.insert(parts, string.format(getText(seconds == 1 and "limeDrop_time_second" or "limeDrop_time_seconds"), seconds))
    end
    return table.concat(parts, " ")
end

local function formatMeters(value)
    if math.abs(value - math.floor(value)) < 0.05 then
        return tostring(math.floor(value))
    end
    return string.format("%.1f", value)
end

local function formatSize(width, length)
    return string.format(getText("limeDrop_size_label"), formatMeters(width), formatMeters(length))
end

---Name order for the zone list: case-insensitive, numbers compared as numbers
-- ("Field 2" < "Field 10", "Field 1" < "Field 1 - Front Gate" < "Field 1a")
local function naturalLess(a, b)
    local function chunks(text)
        local list = {}
        for number, rest in tostring(text):lower():gmatch("(%d*)(%D*)") do
            if number ~= "" then
                table.insert(list, tonumber(number))
            end
            if rest ~= "" then
                table.insert(list, rest)
            end
        end
        return list
    end
    local ca, cb = chunks(a), chunks(b)
    for i = 1, math.min(#ca, #cb) do
        local x, y = ca[i], cb[i]
        if x ~= y then
            if type(x) == type(y) then
                return x < y
            end
            return type(x) == "number"
        end
    end
    return #ca < #cb
end

local function getTerrainHeight(x, z)
    local terrainNode = g_currentMission ~= nil and g_currentMission.terrainRootNode or g_terrainNode
    if terrainNode == nil then
        return 0
    end
    return getTerrainHeightAtWorldPos(terrainNode, x, 0, z)
end

local function sanitizeName(name)
    name = tostring(name or "")
    name = name:gsub("[%c]", ""):gsub("^%s+", ""):gsub("%s+$", "")
    -- byte limit as a safety net, the input dialog already limits characters
    if #name > LimeDropZone.MAX_NAME_LENGTH * 4 then
        name = name:sub(1, LimeDropZone.MAX_NAME_LENGTH * 4)
    end
    return name
end

---Nearest preset size (zones are squares of one of the ZONE_SIZES)
local function clampSize(value)
    value = value or LimeDropZone.DEFAULT_SIZE
    local best, bestDiff = LimeDropZone.DEFAULT_SIZE, nil
    for _, preset in ipairs(LimeDropZone.ZONE_SIZES) do
        local diff = math.abs(preset.size - value)
        if bestDiff == nil or diff < bestDiff then
            best, bestDiff = preset.size, diff
        end
    end
    return best
end

---Zones are square: both sides become the preset nearest the longer side
local function squareSize(width, length)
    local size = clampSize(math.max(width or 0, length or 0))
    return size, size
end

---------------------------------------------------------------------------
-- Rectangle geometry. A zone is centered on (x, z); its length runs along
-- the yaw direction ("forward"), its width across it ("right").
---------------------------------------------------------------------------

local function getAxes(yaw)
    local fx, fz = math.sin(yaw), math.cos(yaw)
    return fx, fz, fz, -fx
end

---World point to zone-local (across, along)
local function toLocal(zone, x, z)
    local fx, fz, rx, rz = getAxes(zone.yaw)
    local dx, dz = x - zone.x, z - zone.z
    return dx * rx + dz * rz, dx * fx + dz * fz
end

---Zone-local (across, along) to world point
local function toWorld(zone, u, v)
    local fx, fz, rx, rz = getAxes(zone.yaw)
    return zone.x + rx * u + fx * v, zone.z + rz * u + fz * v
end

---Zones are circles: the diameter is the zone size (stored as width/length)
local function getRadius(rect)
    return math.max(rect.width or 0, rect.length or 0) * 0.5
end

---Ground points covering a circular zone: a grid about every `step` meters inside it plus a ring
-- on its edge (pulled in by `inset`), so checks catch anything that crosses the edge
local function getCirclePoints(rect, step, inset)
    local radius = math.max(0.1, getRadius(rect) - (inset or 0))
    local points = { { rect.x, rect.z } }
    local steps = math.min(20, math.max(1, math.ceil(radius * 2 / step)))
    for i = 0, steps do
        for j = 0, steps do
            local u, v = -radius + 2 * radius * i / steps, -radius + 2 * radius * j / steps
            if u * u + v * v <= radius * radius then
                table.insert(points, { rect.x + u, rect.z + v })
            end
        end
    end
    local ringSteps = math.max(12, math.ceil(2 * math.pi * radius / step))
    for k = 0, ringSteps - 1 do
        local a = 2 * math.pi * k / ringSteps
        table.insert(points, { rect.x + math.cos(a) * radius, rect.z + math.sin(a) * radius })
    end
    return points
end

---Two circular zones closer than `gap` at their edges
local function getCirclesOverlap(a, b, gap)
    local dx, dz = b.x - a.x, b.z - a.z
    local limit = getRadius(a) + getRadius(b) + gap
    return dx * dx + dz * dz < limit * limit
end

LimeDropZone.getText = getText
LimeDropZone.formatLiters = formatLiters
LimeDropZone.formatMoney = formatMoney
LimeDropZone.formatDuration = formatDuration

---Clears hover/focus looks left over from the last time a dialog was open, then selects focusElement
function LimeDropZone.resetDialogFocus(root, focusElement)
    local focusData = FocusManager.currentFocusData
    if focusData ~= nil then
        if focusData.highlightElement ~= nil and focusData.highlightElement.parent ~= nil then
            FocusManager:unsetHighlight(focusData.highlightElement)
        end
    end
    local normal = GuiOverlay ~= nil and GuiOverlay.STATE_NORMAL or nil
    local function reset(element)
        if element.disabled then
            return
        end
        if normal ~= nil and element.overlayState ~= nil and element.setOverlayState ~= nil then
            element:setOverlayState(normal)
        end
        for _, child in ipairs(element.elements or {}) do
            reset(child)
        end
    end
    if root ~= nil then
        reset(root)
    end
    if focusElement ~= nil then
        FocusManager:setFocus(focusElement)
    end
end
LimeDropZone.formatSize = formatSize

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------

---Title and icon of a product by fill type name (history rows, order screen)
function LimeDropZone:getFillTypeDisplay(fillTypeName)
    local fillType = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeByName(fillTypeName or "LIME") or nil
    if fillType == nil then
        return fillTypeName or "", nil
    end
    local icon = fillType.hudOverlayFilename or fillType.hudOverlayFilenameSmall
    if icon == "" then
        icon = nil
    end
    return fillType.title or fillTypeName, icon
end

function LimeDropZone:getLimeFillTypeIndex()
    if self.limeFillTypeIndex == nil and g_fillTypeManager ~= nil then
        self.limeFillTypeIndex = g_fillTypeManager:getFillTypeIndexByName("LIME")
    end
    return self.limeFillTypeIndex
end

---Products the order screen offers: PRODUCTS that exist and can lie as a heap on this map
function LimeDropZone:getProducts()
    local products = {}
    for _, name in ipairs(LimeDropZone.PRODUCTS) do
        local index = g_fillTypeManager ~= nil and g_fillTypeManager:getFillTypeIndexByName(name) or nil
        if index ~= nil and DensityMapHeightUtil.getCanTipToGround(index) then
            local title, icon = self:getFillTypeDisplay(name)
            table.insert(products, { name = name, index = index, title = title, icon = icon })
        end
    end
    return products
end

function LimeDropZone:getIsProductAllowed(fillTypeName)
    for _, product in ipairs(self:getProducts()) do
        if product.name == fillTypeName then
            return true
        end
    end
    return false
end

function LimeDropZone:getFillTypeIndex(fillTypeName)
    if g_fillTypeManager == nil then
        return nil
    end
    return g_fillTypeManager:getFillTypeIndexByName(fillTypeName or "LIME")
end

---Steepest angle a heap of this product keeps (radians)
function LimeDropZone:getHeapAngle(fillTypeName)
    local index = self:getFillTypeIndex(fillTypeName)
    local angle
    if index ~= nil then
        local heightType = self:getHeightType(index)
        angle = heightType ~= nil and heightType.maxSurfaceAngle or nil
        if angle == nil then
            local fillType = g_fillTypeManager:getFillTypeByIndex(index)
            angle = fillType ~= nil and fillType.maxPhysicalSurfaceAngle or nil
        end
    end
    if type(angle) ~= "number" or angle <= 0 then
        return math.rad(15)
    end
    if angle > 1.6 then
        angle = math.rad(angle)
    end
    return angle
end

---The game's heap settings for a fill type (angle, bulk), nil if it can't form heaps
function LimeDropZone:getHeightType(fillTypeIndex)
    if g_densityMapHeightManager == nil or g_densityMapHeightManager.getDensityMapHeightTypeByFillTypeIndex == nil then
        return nil
    end
    return g_densityMapHeightManager:getDensityMapHeightTypeByFillTypeIndex(fillTypeIndex)
end

---How much ground volume one liter of the product takes in a heap (straw, hay and grass are fluffy: 6-7)
function LimeDropZone:getHeapBulk(fillTypeName)
    local index = self:getFillTypeIndex(fillTypeName)
    local bulk
    if index ~= nil then
        local heightType = self:getHeightType(index)
        bulk = heightType ~= nil and heightType.fillToGroundScale or nil
    end
    if type(bulk) ~= "number" or bulk <= 0 then
        return 1
    end
    return bulk
end

---Same difficulty factor the game's pallet buying stations apply to purchases
function LimeDropZone:getDifficultyPriceMultiplier(fillTypeName)
    if EconomyManager ~= nil and EconomyManager.getPriceMultiplier ~= nil then
        local multiplier = EconomyManager.getPriceMultiplier(self:getFillTypeIndex(fillTypeName))
        if type(multiplier) == "number" and multiplier > 0 then
            return multiplier
        end
    end
    return 1
end

function LimeDropZone:getPricePerLiter(fillTypeName)
    local pricePerLiter
    local fillTypeIndex = self:getFillTypeIndex(fillTypeName)
    if fillTypeIndex ~= nil then
        local fillType = g_fillTypeManager:getFillTypeByIndex(fillTypeIndex)
        pricePerLiter = fillType ~= nil and fillType.pricePerLiter or nil
    end
    if pricePerLiter == nil or pricePerLiter <= 0 then
        pricePerLiter = LimeDropZone.FALLBACK_PRICE_PER_LITER
    end
    return pricePerLiter * self:getDifficultyPriceMultiplier(fillTypeName) * LimeDropZone.PRICE_MULTIPLIER
end

---Product price per liter plus the delivery fee percentage
function LimeDropZone:getDeliveredPricePerLiter(fillTypeName)
    return self:getPricePerLiter(fillTypeName) * (1 + self:getSetting("deliveryFee") / 100)
end

function LimeDropZone:getOrderPrice(liters, fillTypeName)
    return math.ceil(liters * self:getDeliveredPricePerLiter(fillTypeName))
end

---Heap footprint for a zone: ridge along the longer side, rounded ends.
-- Returns the heap radius, half length of the ridge line and whether the ridge runs along the zone length.
function LimeDropZone:getHeapShape(width, length)
    local short, long = math.min(width, length), math.max(width, length)
    local radius = math.max(1, short * 0.5 - LimeDropZone.HEAP_EDGE_MARGIN)
    local lineHalf = math.max(0, long * 0.5 - LimeDropZone.HEAP_EDGE_MARGIN - radius)
    return radius, lineHalf, length >= width
end

---Most of a product a zone of this size holds: measured values (ZONE_SIZES for lime, PRODUCT_CAPACITIES
-- for others). An unmeasured product is estimated from the lime value: a steeper heap angle holds more,
-- a bulkier product (more ground volume per liter) holds fewer liters. Rounded down to 500 L.
function LimeDropZone:getCapacityForSize(width, length, fillTypeName)
    local size = squareSize(width, length)
    local capacity = 0
    for _, preset in ipairs(LimeDropZone.ZONE_SIZES) do
        if preset.size == size then
            capacity = preset.capacity
        end
    end
    fillTypeName = fillTypeName or LimeDropZone.MEASURED_PRODUCT
    local measured = LimeDropZone.PRODUCT_CAPACITIES[fillTypeName]
    if measured ~= nil and measured[size] ~= nil then
        return measured[size]
    end
    if fillTypeName ~= LimeDropZone.MEASURED_PRODUCT and capacity > 0 then
        local measured = LimeDropZone.MEASURED_PRODUCT
        local ratio = math.tan(self:getHeapAngle(fillTypeName)) / math.tan(self:getHeapAngle(measured))
            * self:getHeapBulk(measured) / self:getHeapBulk(fillTypeName)
        capacity = math.floor(capacity * ratio / 500) * 500
    end
    return capacity
end

function LimeDropZone:getZoneCapacity(zone, fillTypeName)
    return self:getCapacityForSize(zone.width, zone.length, fillTypeName)
end

---Product lying in the zone (the one with the most liters) and its amount, nil when empty
function LimeDropZone:getZoneContents(zone)
    local bestName, bestLevel = nil, 0
    for _, product in ipairs(self:getProducts()) do
        local level = self:getZoneFillLevel(zone, product.name)
        if level >= 1 and level > bestLevel then
            bestName, bestLevel = product.name, level
        end
    end
    return bestName, bestLevel
end

---Amount of a product already lying inside the zone
function LimeDropZone:getZoneFillLevel(zone, fillTypeName)
    local fillTypeIndex = self:getFillTypeIndex(fillTypeName)
    if fillTypeIndex == nil then
        return 0
    end
    local sx, sz = toWorld(zone, -zone.width * 0.5, -zone.length * 0.5)
    local wx, wz = toWorld(zone, zone.width * 0.5, -zone.length * 0.5)
    local hx, hz = toWorld(zone, -zone.width * 0.5, zone.length * 0.5)
    local fillLevel = DensityMapHeightUtil.getFillLevelAtArea(fillTypeIndex, sx, sz, wx, wz, hx, hz)
    if type(fillLevel) == "number" then
        return math.max(0, fillLevel)
    end
    return 0
end

---Room left for a product in the zone, rounded down to 500 L: the size's capacity minus what is there.
-- Heaps can't mix, so a zone holding another product has no room (that product's name is returned too).
-- On steep ground less may fit; whatever doesn't is refunded at delivery.
function LimeDropZone:getZoneFreeCapacity(zone, fillTypeName)
    fillTypeName = fillTypeName or "LIME"
    local contentName = self:getZoneContents(zone)
    if contentName ~= nil and contentName ~= fillTypeName then
        return 0, contentName
    end
    local level = self:getZoneFillLevel(zone, fillTypeName)
    return math.max(0, math.floor((self:getZoneCapacity(zone, fillTypeName) - level) / 500) * 500), nil
end

---Label the mod gives a spot: "Field 3", a second spot on that field "Field 3a", then "Field 3b", and so on.
-- Owned land without a field uses the farmland number instead. The letter is left out on request
-- (named spots), but stays stored so clearing the description brings it back.
function LimeDropZone:getZoneLabel(zone, withoutLetter)
    local index = zone.suffixIndex or 1
    local letter = (not withoutLetter and index > 1 and index <= 27) and string.char(95 + index) or ""
    if (zone.fieldId or 0) > 0 then
        return string.format(getText("limeDrop_fieldLabel"), zone.fieldId, letter)
    elseif (zone.farmlandId or 0) > 0 then
        return string.format(getText("limeDrop_farmlandLabel"), zone.farmlandId, letter)
    end
    return string.format(getText("limeDrop_zoneDefaultName"), zone.id or 0)
end

---Display name: "Field 3a" while unnamed, "Field 3 - front entrance" once the player adds a description
function LimeDropZone:getZoneName(zone)
    if zone.name ~= nil and zone.name ~= "" then
        return string.format(getText("limeDrop_nameWithDescription"), self:getZoneLabel(zone, true), zone.name)
    end
    return self:getZoneLabel(zone)
end

---Name for messages about an order whose zone may already be gone
function LimeDropZone:getZoneNameById(zoneId)
    local zone = self.zones[zoneId]
    if zone ~= nil then
        return self:getZoneName(zone)
    end
    return string.format(getText("limeDrop_zoneDefaultName"), zoneId)
end

function LimeDropZone:getLocalFarmId()
    if g_localPlayer ~= nil and g_localPlayer.getFarmId ~= nil then
        return g_localPlayer:getFarmId()
    end
    if g_currentMission ~= nil and g_currentMission.getFarmId ~= nil then
        return g_currentMission:getFarmId()
    end
    return 0
end

function LimeDropZone:getIsValidFarmId(farmId)
    local spectatorId = FarmManager ~= nil and FarmManager.SPECTATOR_FARM_ID or 0
    return farmId ~= nil and farmId ~= spectatorId and g_farmManager:getFarmById(farmId) ~= nil
end

---Returns the farm id of the player behind a network connection, or the fallback
function LimeDropZone:getFarmIdForConnection(connection, fallback)
    local mission = g_currentMission
    if connection ~= nil and mission ~= nil and mission.connectionsToPlayer ~= nil then
        local player = mission.connectionsToPlayer[connection]
        if player ~= nil then
            if player.farmId ~= nil then
                return player.farmId
            elseif player.getFarmId ~= nil then
                return player:getFarmId()
            end
        end
    end
    return fallback
end

---World position of the local player, or of the vehicle they are driving
function LimeDropZone:getLocalPlayerPosition()
    local player = g_localPlayer
    if player == nil then
        return nil
    end
    local vehicle = player.getCurrentVehicle ~= nil and player:getCurrentVehicle() or nil
    if vehicle ~= nil and vehicle.rootNode ~= nil then
        return getWorldTranslation(vehicle.rootNode)
    end
    return player:getPosition()
end

---Ground point the active camera is looking at, and the camera's heading.
-- Walks along the view ray until it drops below the terrain; looking above the
-- horizon falls back to a point a little way ahead.
function LimeDropZone:getLookAtGroundPoint()
    local camera = getCamera()
    if camera == nil or camera == 0 then
        return nil
    end
    local cx, cy, cz = getWorldTranslation(camera)
    local dx, dy, dz = localDirectionToWorld(camera, 0, 0, -1)
    local horizontal = math.sqrt(dx * dx + dz * dz)
    if horizontal < 0.01 then
        return nil
    end

    local step = 0.5
    local maxDistance = LimeDropZone.PLACE_MAX_DISTANCE + 20
    for distance = step, maxDistance, step do
        local x, y, z = cx + dx * distance, cy + dy * distance, cz + dz * distance
        if y <= getTerrainHeight(x, z) then
            return x, z, math.atan2(dx, dz)
        end
    end
    local fallback = LimeDropZone.PLACE_FALLBACK_DISTANCE
    return cx + dx / horizontal * fallback, cz + dz / horizontal * fallback, math.atan2(dx, dz)
end

function LimeDropZone:getIsPointInZone(zone, x, z)
    local u, v = toLocal(zone, x, z)
    return math.abs(u) <= zone.width * 0.5 and math.abs(v) <= zone.length * 0.5
end

function LimeDropZone:getZoneAt(x, z, farmId)
    local best, bestDist = nil, nil
    for _, zone in pairs(self.zones) do
        if zone.farmId == farmId and self:getIsPointInZone(zone, x, z) then
            local dx, dz = x - zone.x, z - zone.z
            local dist = dx * dx + dz * dz
            if bestDist == nil or dist < bestDist then
                best, bestDist = zone, dist
            end
        end
    end
    return best
end

---True if a zone circle would overlap (or come within ZONE_GAP of) another zone of the farm
function LimeDropZone:getIsTooCloseToZone(rect, farmId, ignoreZoneId)
    for _, zone in pairs(self.zones) do
        if zone.farmId == farmId and zone.id ~= ignoreZoneId and getCirclesOverlap(rect, zone, LimeDropZone.ZONE_GAP) then
            return true
        end
    end
    return false
end

---True if every part of the zone circle lies on farmland owned by the farm.
-- Checks points about every 2 m inside it plus its edge, so a zone can't hang over a boundary.
function LimeDropZone:getIsRectOnOwnedLand(rect, farmId)
    if g_farmlandManager == nil then
        return true
    end
    for _, point in ipairs(getCirclePoints(rect, LimeDropZone.LAND_CHECK_STEP, 0.1)) do
        local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(point[1], point[2])
        if farmlandId == nil or farmlandId == 0 or g_farmlandManager:getFarmlandOwner(farmlandId) ~= farmId then
            return false
        end
    end
    return true
end

---Field a rectangle belongs to: the one covering most of it (same grid as the ownership check).
-- A tie goes to the field under the center. Returns fieldId (0 if none) and farmlandId.
function LimeDropZone:getFieldForRect(rect)
    if g_farmlandManager == nil then
        return 0, 0
    end
    local fieldByFarmland = {}
    local function lookup(x, z)
        local farmlandId = g_farmlandManager:getFarmlandIdAtWorldPosition(x, z) or 0
        if farmlandId <= 0 then
            return 0, 0
        end
        if fieldByFarmland[farmlandId] == nil then
            local fieldId = 0
            local farmland = g_farmlandManager:getFarmlandById(farmlandId)
            local field = farmland ~= nil and farmland.getField ~= nil and farmland:getField() or nil
            if field ~= nil and field.getId ~= nil then
                fieldId = field:getId() or 0
            end
            fieldByFarmland[farmlandId] = fieldId
        end
        return fieldByFarmland[farmlandId], farmlandId
    end

    local counts, info = {}, {}
    for _, point in ipairs(getCirclePoints(rect, LimeDropZone.LAND_CHECK_STEP, 0.1)) do
        local fieldId, farmlandId = lookup(point[1], point[2])
        if farmlandId > 0 then
            local key = fieldId > 0 and ("f" .. fieldId) or ("l" .. farmlandId)
            counts[key] = (counts[key] or 0) + 1
            info[key] = { fieldId, farmlandId }
        end
    end

    local centerFieldId, centerFarmlandId = lookup(rect.x, rect.z)
    local centerKey = centerFieldId > 0 and ("f" .. centerFieldId) or ("l" .. centerFarmlandId)
    local bestKey, bestCount = nil, -1
    for key, count in pairs(counts) do
        if count > bestCount or (count == bestCount and key == centerKey) then
            bestKey, bestCount = key, count
        end
    end
    if bestKey == nil then
        return centerFieldId, centerFarmlandId
    end
    return info[bestKey][1], info[bestKey][2]
end

---Lowest free letter for a field: 1 = no letter, 2 = "b", 3 = "c" ...
function LimeDropZone:getFreeSuffixIndex(farmId, fieldId, farmlandId, ignoreZoneId)
    local used = {}
    for _, zone in pairs(self.zones) do
        if zone.farmId == farmId and zone.id ~= ignoreZoneId and (zone.fieldId or 0) == fieldId
            and (fieldId > 0 or (zone.farmlandId or 0) == farmlandId) then
            used[zone.suffixIndex or 1] = true
        end
    end
    local index = 1
    while used[index] do
        index = index + 1
    end
    return index
end

---Fills in fieldId, farmlandId and the letter for a spot (server side, and for the placement preview)
function LimeDropZone:assignFieldLabel(zone, farmId)
    zone.fieldId, zone.farmlandId = self:getFieldForRect(zone)
    zone.suffixIndex = self:getFreeSuffixIndex(farmId, zone.fieldId, zone.farmlandId, zone.id)
end

---Steepest slope across a zone in degrees: height difference over the distance between
-- ground samples (about every SLOPE_CHECK_STEP meters inside the circle and on its edge).
function LimeDropZone:getRectSlope(rect)
    local samples = {}
    for _, point in ipairs(getCirclePoints(rect, LimeDropZone.SLOPE_CHECK_STEP, 0)) do
        table.insert(samples, { point[1], getTerrainHeight(point[1], point[2]), point[2] })
    end
    local maxAngle = 0
    for a = 1, #samples do
        local pa = samples[a]
        for b = a + 1, #samples do
            local pb = samples[b]
            local dx, dz = pa[1] - pb[1], pa[3] - pb[3]
            local distance = math.sqrt(dx * dx + dz * dz)
            if distance > 0.01 then
                local angle = math.deg(math.atan(math.abs(pa[2] - pb[2]) / distance))
                if angle > maxAngle then
                    maxAngle = angle
                end
            end
        end
    end
    return maxAngle
end

---Size of one cell of the game's heap height grid, in meters (0 if unknown)
function LimeDropZone:getHeightGridCellSize()
    if self.heightCellSize == nil then
        local cellSize = 0
        local heightId = g_currentMission ~= nil and g_currentMission.terrainDetailHeightId or nil
        local terrainSize = g_currentMission ~= nil and g_currentMission.terrainSize or nil
        if heightId ~= nil and heightId ~= 0 and terrainSize ~= nil and terrainSize > 0 then
            local mapSize = getDensityMapSize(heightId)
            if mapSize ~= nil and mapSize > 0 then
                cellSize = terrainSize / mapSize
            end
        end
        self.heightCellSize = cellSize
        log("Heap height grid: %.3f m per cell", cellSize)
    end
    return self.heightCellSize
end

---Moves a world position to the center of its heap grid cell, so every heap of a size covers the same cells
function LimeDropZone:snapToHeightGrid(x, z)
    local cellSize = self:getHeightGridCellSize()
    local terrainSize = g_currentMission ~= nil and g_currentMission.terrainSize or nil
    if cellSize <= 0 or terrainSize == nil then
        return x, z
    end
    local half = terrainSize * 0.5
    local function snap(value)
        return (math.floor((value + half) / cellSize) + 0.5) * cellSize - half
    end
    return snap(x), snap(z)
end

---Whether the zone can change to this size; returns false plus a text key with the reason
function LimeDropZone:getCanResizeZone(zone, width, length)
    local rect = { x = zone.x, z = zone.z, yaw = zone.yaw, width = width, length = length }
    if self:getIsTooCloseToZone(rect, zone.farmId, zone.id) then
        return false, "limeDrop_size_blocked"
    end
    if not self:getIsRectOnOwnedLand(rect, zone.farmId) then
        return false, "limeDrop_size_notOwned"
    end
    return true
end

---True if the local player is walking (not in a vehicle)
function LimeDropZone:getIsLocalPlayerOnFoot()
    local player = g_localPlayer
    if player == nil then
        return false
    end
    return player.getIsInVehicle == nil or not player:getIsInVehicle()
end

---True if the player's hands are busy (hand tool or carried object), since left click would also use them
function LimeDropZone:getAreLocalPlayerHandsBusy()
    local player = g_localPlayer
    if player == nil then
        return false
    end
    if player.getIsHoldingHandTool ~= nil and player:getIsHoldingHandTool() then
        return true
    end
    if player.getAreHandsHoldingObject ~= nil and player:getAreHandsHoldingObject() then
        return true
    end
    return false
end

function LimeDropZone:getNumZonesForFarm(farmId)
    local count = 0
    for _, zone in pairs(self.zones) do
        if zone.farmId == farmId then
            count = count + 1
        end
    end
    return count
end

---Zones of a farm sorted by distance to the given position
function LimeDropZone:getSortedZonesForFarm(farmId, x, z)
    local entries = {}
    for _, zone in pairs(self.zones) do
        if zone.farmId == farmId then
            local dist = 0
            if x ~= nil then
                local dx, dz = x - zone.x, z - zone.z
                dist = math.sqrt(dx * dx + dz * dz)
            end
            table.insert(entries, { zone = zone, distance = dist })
        end
    end
    table.sort(entries, function(a, b)
        if a.distance == b.distance then
            return a.zone.id < b.zone.id
        end
        return a.distance < b.distance
    end)
    return entries
end

function LimeDropZone:getPendingForZone(zoneId)
    local liters, minRemaining = 0, nil
    for _, order in pairs(self.orders) do
        if order.zoneId == zoneId then
            liters = liters + order.liters
            if minRemaining == nil or order.remainingMs < minRemaining then
                minRemaining = order.remainingMs
            end
        end
    end
    return liters, minRemaining
end

function LimeDropZone:getHasPendingOrder(zoneId)
    for _, order in pairs(self.orders) do
        if order.zoneId == zoneId then
            return true
        end
    end
    return false
end

---Rows for the zone list dialog, nearest zone first
function LimeDropZone:getMenuEntries()
    local farmId = self:getLocalFarmId()
    local entries = {}
    for _, entry in ipairs(self:getSortedZonesForFarm(farmId)) do
        local zone = entry.zone
        local parts = { formatSize(zone.width, zone.length) }

        local pendingLiters, remainingMs = self:getPendingForZone(zone.id)
        local canOrder = false
        local warning = nil
        if pendingLiters > 0 then
            table.insert(parts, string.format(getText("limeDrop_menu_incoming"),
                formatLiters(pendingLiters), formatDuration(remainingMs or 0)))
        elseif not self:getIsRectOnOwnedLand(zone, zone.farmId) then
            warning = getText("limeDrop_menu_notOwned")
        else
            local contentName, contentLevel = self:getZoneContents(zone)
            if contentName == nil then
                table.insert(parts, getText("limeDrop_menu_zoneEmpty"))
                canOrder = true
            else
                table.insert(parts, string.format(getText("limeDrop_menu_contents"),
                    (self:getFillTypeDisplay(contentName)), formatLiters(contentLevel)))
                local free = self:getZoneFreeCapacity(zone, contentName)
                if free < LimeDropZone.MIN_ORDER_LITERS then
                    warning = getText("limeDrop_menu_full")
                else
                    canOrder = true
                end
            end
        end

        table.insert(entries, {
            zoneId = zone.id,
            name = self:getZoneName(zone),
            info = table.concat(parts, "  |  "),
            warning = warning,
            canOrder = canOrder
        })
    end
    table.sort(entries, function(a, b)
        return naturalLess(a.name, b.name)
    end)
    return entries
end

---Amounts the selector offers for a zone and product: AMOUNT_STEP up to the room left in it.
-- Also returns the other product blocking the zone, if any.
function LimeDropZone:getAmountSteps(zone, fillTypeName)
    local free, blockingName = self:getZoneFreeCapacity(zone, fillTypeName)
    local steps = {}
    local liters = LimeDropZone.AMOUNT_STEP
    while liters <= free do
        table.insert(steps, liters)
        liters = liters + LimeDropZone.AMOUNT_STEP
    end
    return steps, free, blockingName
end

---Rows for the size dialog: the preset sizes
function LimeDropZone:getSizeOptions(zone)
    local options = {}
    for _, preset in ipairs(LimeDropZone.ZONE_SIZES) do
        local isCurrent = preset.size == zone.width and preset.size == zone.length
        local blockedKey
        if not isCurrent then
            local canResize, reasonKey = self:getCanResizeZone(zone, preset.size, preset.size)
            blockedKey = not canResize and reasonKey or nil
        end
        table.insert(options, {
            width = preset.size,
            length = preset.size,
            isCurrent = isCurrent,
            isBlocked = blockedKey ~= nil,
            blockedText = blockedKey ~= nil and getText(blockedKey) or nil,
            capacity = preset.capacity
        })
    end
    return options
end

function LimeDropZone:notify(text)
    if g_currentMission ~= nil then
        g_currentMission:addIngameNotification(FSBaseMission.INGAME_NOTIFICATION_OK, text)
    end
end

function LimeDropZone:warn(text)
    if g_currentMission ~= nil then
        g_currentMission:showBlinkingWarning(text, 3000)
    end
end

---------------------------------------------------------------------------
-- Zone state (runs on server and clients)
---------------------------------------------------------------------------

function LimeDropZone:applyAddZone(zone, showNotification)
    self:applyRemoveZone(zone.id, false)
    zone.name = sanitizeName(zone.name)
    zone.fieldId = zone.fieldId or 0
    zone.farmlandId = zone.farmlandId or 0
    zone.suffixIndex = math.max(1, zone.suffixIndex or 1)
    zone.width, zone.length = squareSize(zone.width, zone.length)
    zone.yaw = zone.yaw or 0
    self.zones[zone.id] = zone
    if zone.id >= self.nextZoneId then
        self.nextZoneId = zone.id + 1
    end

    if g_client ~= nil then
        self:requestMenuRefresh()
        self:buildOutline(zone)
        self:createHotspot(zone)
        if showNotification and zone.farmId == self:getLocalFarmId() then
            self:notify(string.format(getText("limeDrop_notify_zoneAdded"), self:getZoneName(zone)))
        end
    end
end

function LimeDropZone:applyRemoveZone(zoneId, showNotification)
    local zone = self.zones[zoneId]
    if zone == nil then
        return
    end
    self:deleteHotspot(zone)
    self.zones[zoneId] = nil
    if self.currentZone == zone then
        self.currentZone = nil
    end
    self:requestMenuRefresh()

    if g_client ~= nil and showNotification and zone.farmId == self:getLocalFarmId() then
        self:notify(string.format(getText("limeDrop_notify_zoneRemoved"), self:getZoneName(zone)))
    end
end

function LimeDropZone:applyRenameZone(zoneId, name, showNotification)
    local zone = self.zones[zoneId]
    if zone == nil then
        return
    end
    zone.name = sanitizeName(name)

    if g_client ~= nil then
        self:requestMenuRefresh()
        self:deleteHotspot(zone)
        self:createHotspot(zone)
        if showNotification and zone.farmId == self:getLocalFarmId() then
            self:notify(string.format(getText("limeDrop_notify_zoneRenamed"), self:getZoneName(zone)))
        end
    end
end

function LimeDropZone:applyResizeZone(zoneId, width, length, showNotification)
    local zone = self.zones[zoneId]
    if zone == nil then
        return
    end
    zone.width, zone.length = squareSize(width, length)

    if g_client ~= nil then
        self:requestMenuRefresh()
        self:buildOutline(zone)
        if showNotification and zone.farmId == self:getLocalFarmId() then
            self:notify(string.format(getText("limeDrop_notify_zoneResized"), self:getZoneName(zone), formatSize(zone.width, zone.length)))
        end
    end
end

---Replaces all zones/orders with the data the server sent on join
function LimeDropZone:applySync(zones, orders)
    for zoneId, _ in pairs(self.zones) do
        self:applyRemoveZone(zoneId, false)
    end
    self.orders = {}
    for _, zone in ipairs(zones) do
        self:applyAddZone(zone, false)
    end
    for _, order in ipairs(orders) do
        self.orders[order.id] = order
    end
end

---------------------------------------------------------------------------
-- Server logic
---------------------------------------------------------------------------

function LimeDropZone:serverAddZone(farmId, x, z, width, length, yaw)
    if g_server == nil or not self:getIsValidFarmId(farmId) then
        return
    end
    local zone = { id = self.nextZoneId, farmId = farmId, name = "", x = x, z = z,
        width = squareSize(width, length), length = squareSize(width, length), yaw = yaw or 0 }
    if self:getNumZonesForFarm(farmId) >= LimeDropZone.MAX_ZONES_PER_FARM then
        log("Farm %d reached the zone limit, request ignored", farmId)
        return
    end
    if self:getIsTooCloseToZone(zone, farmId) then
        log("Zone request for farm %d overlaps an existing zone, ignored", farmId)
        return
    end
    if not self:getIsRectOnOwnedLand(zone, farmId) then
        log("Zone request for farm %d is not on land the farm owns, ignored", farmId)
        return
    end

    self:assignFieldLabel(zone, farmId)
    self.nextZoneId = self.nextZoneId + 1
    self:applyAddZone(zone, true)
    g_server:broadcastEvent(LimeDropZoneEvent.new(LimeDropZoneEvent.ACTION_ADD, zone), false)
end

function LimeDropZone:serverRemoveZone(farmId, zoneId)
    if g_server == nil then
        return
    end
    local zone = self.zones[zoneId]
    if zone == nil or zone.farmId ~= farmId then
        return
    end
    self:applyRemoveZone(zoneId, true)
    self:removeHistoryForZone(zoneId)
    g_server:broadcastEvent(LimeDropZoneEvent.new(LimeDropZoneEvent.ACTION_REMOVE, zone), false)
end

function LimeDropZone:serverRenameZone(farmId, zoneId, name)
    if g_server == nil then
        return
    end
    local zone = self.zones[zoneId]
    if zone == nil or zone.farmId ~= farmId then
        return
    end
    -- The player's text box already filters on their machine; filter again here so a name
    -- sent by a modified client can't reach other players unfiltered.
    name = sanitizeName(name)
    if filterText ~= nil and name ~= "" then
        local filtered = filterText(name, true, true)
        if type(filtered) == "string" then
            name = sanitizeName(filtered)
        end
    end
    self:applyRenameZone(zoneId, name, true)
    g_server:broadcastEvent(LimeDropZoneEvent.new(LimeDropZoneEvent.ACTION_RENAME, zone), false)
end

function LimeDropZone:serverResizeZone(farmId, zoneId, width, length)
    if g_server == nil then
        return
    end
    local zone = self.zones[zoneId]
    if zone == nil or zone.farmId ~= farmId then
        return
    end
    width, length = squareSize(width, length)
    local canResize, reasonKey = self:getCanResizeZone(zone, width, length)
    if not canResize then
        log("Resize of zone %d refused (%s)", zoneId, reasonKey)
        return
    end
    self:applyResizeZone(zoneId, width, length, true)
    g_server:broadcastEvent(LimeDropZoneEvent.new(LimeDropZoneEvent.ACTION_RESIZE, zone), false)
end

function LimeDropZone:serverPlaceOrder(farmId, zoneId, liters, fillTypeName)
    if g_server == nil then
        return
    end
    fillTypeName = fillTypeName or "LIME"
    if not self:getIsProductAllowed(fillTypeName) then
        log("Order of unknown product '%s' ignored", tostring(fillTypeName))
        return
    end
    local zone = self.zones[zoneId]
    if zone == nil or zone.farmId ~= farmId then
        log("Order for unknown zone %d (farm %d) ignored", zoneId, farmId)
        return
    end
    liters = math.floor(liters)
    if liters < LimeDropZone.MIN_ORDER_LITERS or liters > self:getZoneCapacity(zone, fillTypeName) then
        log("Order of %d L %s does not fit zone %d, ignored", liters, fillTypeName, zoneId)
        return
    end
    local _, blockingName = self:getZoneFreeCapacity(zone, fillTypeName)
    if blockingName ~= nil then
        log("Zone %d holds %s, order of %s ignored (heaps can't mix)", zoneId, blockingName, fillTypeName)
        return
    end
    if self:getHasPendingOrder(zoneId) then
        log("Zone %d already has a delivery on the way, order ignored", zoneId)
        return
    end
    if not self:getIsRectOnOwnedLand(zone, farmId) then
        log("Zone %d is no longer on land farm %d owns, order ignored", zoneId, farmId)
        return
    end

    local price = self:getOrderPrice(liters, fillTypeName)
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farm:getBalance() < price then
        log("Farm %d cannot afford %s order (%d)", farmId, fillTypeName, price)
        return
    end

    local moneyType = MoneyType.PURCHASE_FERTILIZER or MoneyType.OTHER
    g_currentMission:addMoney(-price, farmId, moneyType, true, true)

    local order = {
        id = self.nextOrderId,
        farmId = farmId,
        zoneId = zoneId,
        liters = liters,
        remainingMs = self:getDeliveryDelayMs(),
        x = zone.x,
        z = zone.z,
        width = zone.width,
        length = zone.length,
        yaw = zone.yaw,
        pricePerLiter = self:getDeliveredPricePerLiter(fillTypeName),
        price = price,
        fillTypeName = fillTypeName
    }
    self.nextOrderId = self.nextOrderId + 1
    self.orders[order.id] = order

    self:broadcastOrderState(order, LimeDropZone.ORDER_STATE_PLACED, 0)
end

---Drops the heap, refunds whatever did not fit and tells everyone
function LimeDropZone:serverDeliverOrder(order)
    self.orders[order.id] = nil

    -- land sold since ordering: no heap, full refund including the delivery fee
    if not self:getIsRectOnOwnedLand(order, order.farmId) then
        local refund = math.floor(order.liters * (order.pricePerLiter or self:getDeliveredPricePerLiter(order.fillTypeName)))
        g_currentMission:addMoney(refund, order.farmId, MoneyType.OTHER, true, true)
        self:serverAddHistory(order, 0, refund, true)
        self:broadcastOrderState(order, LimeDropZone.ORDER_STATE_CANCELLED, refund)
        return
    end

    local before = self:getZoneFillLevel(order, order.fillTypeName)
    local dropped, calls, toppedUp, spilled = self:tipHeap(order, order.liters, order.fillTypeName)
    log("Delivery to zone %d (%s): ordered %d L %s, placed %d L in %d steps%s, in zone %d L before / %d L after",
        order.zoneId, formatSize(order.width, order.length), order.liters, tostring(order.fillTypeName), math.floor(dropped), calls or 0,
        (toppedUp or 0) > 0 and string.format(" (last liters topped up with a %.1f L heap piece)", toppedUp) or "",
        math.floor(before), math.floor(self:getZoneFillLevel(order, order.fillTypeName)))
    local leftover = order.liters - dropped
    local refund = 0
    if leftover >= 1 then
        refund = math.floor(leftover * (order.pricePerLiter or self:getPricePerLiter(order.fillTypeName)))
        if refund > 0 then
            g_currentMission:addMoney(refund, order.farmId, MoneyType.OTHER, true, true)
        end
    end

    self:serverAddHistory(order, dropped, refund, false)
    self:broadcastOrderState(order, LimeDropZone.ORDER_STATE_DELIVERED, dropped, spilled)
end

---Tips lime as a heap around a short line through the rectangle (x, z, width, length, yaw).
-- The game only places a limited amount per call, so lime is fed in TIP_CHUNK pieces (like a
-- tipping trailer does) until it is all down or several chunks in a row place nothing (heap full).
-- Returns the amount actually placed and the number of calls used.
---Where the heap for a spot is tipped. Same heap for every spot of a size: centered on a heap
-- grid cell and always along world X, so it covers the same grid cells wherever the spot is and
-- however it is turned (zones are square, so the heap is round).
function LimeDropZone:getTipLine(rect)
    local radius = self:getHeapShape(rect.width, rect.length)
    local cx, cz = self:snapToHeightGrid(rect.x, rect.z)
    local lineHalf = math.max(0.25, self:getHeightGridCellSize() * 0.5)
    local sx, sz, ex, ez = cx - lineHalf, cz, cx + lineHalf, cz
    return sx, getTerrainHeight(sx, sz), sz, ex, getTerrainHeight(ex, ez), ez, radius
end

---Feeds `amount` to one heap spot in TIP_CHUNK calls until it is all down or the spot takes no more.
-- Returns liters placed, calls used and the line offset (for a top-up at the same spot).
function LimeDropZone:tipAtLine(fillTypeIndex, amount, sx, sy, sz, ex, ey, ez, radius, maxEmptyCalls)
    maxEmptyCalls = maxEmptyCalls or LimeDropZone.TIP_EMPTY_CALLS_TO_STOP
    local remaining = amount
    local lineOffset = 0
    local calls, emptyCalls = 0, 0
    while remaining >= 1 and calls < LimeDropZone.TIP_MAX_CALLS do
        calls = calls + 1
        local chunk = math.min(remaining, LimeDropZone.TIP_CHUNK)
        local dropped, newLineOffset = DensityMapHeightUtil.tipToGroundAroundLine(
            nil, chunk, fillTypeIndex, sx, sy, sz, ex, ey, ez, 0.5, radius, lineOffset, false, nil, false)
        dropped = math.max(0, dropped or 0)
        lineOffset = newLineOffset or lineOffset
        remaining = remaining - dropped
        if dropped < 1 then
            emptyCalls = emptyCalls + 1
            if emptyCalls >= maxEmptyCalls then
                break
            end
        else
            emptyCalls = 0
        end
    end
    return amount - remaining, calls, lineOffset
end

---Spots around a zone for what didn't fit in it: rings outward, lowest ground first within a ring.
-- Only on land the farm owns, and with the heap clear of the farm's other zones.
function LimeDropZone:getSpillSpots(rect)
    local zoneRadius = math.max(rect.width, rect.length) * 0.5
    local heapRadius = self:getHeapShape(rect.width, rect.length)
    local ownZoneId = rect.zoneId or rect.id
    local farmId = rect.farmId
    local spots = {}
    for _, factor in ipairs(LimeDropZone.SPILL_RINGS) do
        local ring = {}
        local distance = zoneRadius + heapRadius * factor
        for k = 0, LimeDropZone.SPILL_DIRECTIONS - 1 do
            local angle = 2 * math.pi * k / LimeDropZone.SPILL_DIRECTIONS
            local x, z = rect.x + math.cos(angle) * distance, rect.z + math.sin(angle) * distance
            local spot = { x = x, z = z, width = heapRadius * 2 + 1, length = heapRadius * 2 + 1, yaw = 0 }
            local usable = farmId == nil or self:getIsRectOnOwnedLand(spot, farmId)
            if usable then
                for _, zone in pairs(self.zones) do
                    if zone.id ~= ownZoneId and zone.farmId == farmId then
                        local dx, dz = zone.x - x, zone.z - z
                        local limit = math.max(zone.width, zone.length) * 0.5 + heapRadius + LimeDropZone.ZONE_GAP
                        if dx * dx + dz * dz < limit * limit then
                            usable = false
                            break
                        end
                    end
                end
            end
            if usable then
                spot.height = getTerrainHeight(x, z)
                table.insert(ring, spot)
            end
        end
        table.sort(ring, function(p, q)
            return p.height < q.height
        end)
        for _, spot in ipairs(ring) do
            table.insert(spots, spot)
        end
    end
    return spots
end

---Tips a product as a round heap in the zone. Anything the zone's ground can't hold (too steep)
-- goes on the nearest suitable ground around it unless noSpill is set.
-- Returns the amount placed, the calls used, the liters of a top-up piece and the liters placed outside the zone.
function LimeDropZone:tipHeap(rect, liters, fillTypeName, noSpill)
    local fillTypeIndex = self:getFillTypeIndex(fillTypeName)
    if fillTypeIndex == nil or not DensityMapHeightUtil.getCanTipToGround(fillTypeIndex) then
        log("%s cannot be tipped to the ground on this map", tostring(fillTypeName))
        return 0
    end

    local sx, sy, sz, ex, ey, ez, radius = self:getTipLine(rect)
    local placed, calls, lineOffset = self:tipAtLine(fillTypeIndex, liters, sx, sy, sz, ex, ey, ez, radius)
    local remaining = liters - placed
    local last = { sx, sy, sz, ex, ey, ez, radius, lineOffset }
    local piece = self:getHeapPieceLiters(fillTypeIndex)
    local spilled = 0

    -- less than one heap piece left can't be tipped anywhere; the top-up below takes care of it
    if remaining >= piece and not noSpill then
        local inZone = placed
        local spotsUsed = 0
        for _, spot in ipairs(self:getSpillSpots(rect)) do
            local ssx, ssy, ssz, sex, sey, sez, sradius = self:getTipLine(spot)
            local spotPlaced, spotCalls, spotOffset = self:tipAtLine(fillTypeIndex, remaining, ssx, ssy, ssz, sex, sey, sez, sradius,
                LimeDropZone.SPILL_EMPTY_CALLS_TO_STOP)
            calls = calls + spotCalls
            if spotPlaced >= 1 then
                spotsUsed = spotsUsed + 1
                remaining = remaining - spotPlaced
                last = { ssx, ssy, ssz, sex, sey, sez, sradius, spotOffset }
            end
            if remaining < 1 then
                break
            end
        end
        spilled = liters - remaining - inZone
        log("Zone ground held %d L; %d L more placed on %d spot(s) around it%s", math.floor(inZone),
            math.floor(liters - remaining - inZone), spotsUsed,
            remaining >= piece and string.format(", %d L found no ground", math.floor(remaining))
            or remaining >= 1 and string.format(", last %.1f L below one heap piece", remaining) or "")
    end

    -- The game places heaps in whole pieces, so the last few liters of an order can be smaller than
    -- one piece and can't be placed on their own. Top up with one smallest piece (a few liters
    -- extra, free) instead of refunding them; a real shortfall stays as it is.
    local toppedUp = 0
    if remaining >= 1 and remaining < piece then
        local dropped = DensityMapHeightUtil.tipToGroundAroundLine(
            nil, piece, fillTypeIndex, last[1], last[2], last[3], last[4], last[5], last[6], 0.5, last[7], last[8], false, nil, false)
        if (dropped or 0) >= remaining then
            toppedUp = dropped
            remaining = 0
        end
    end

    return math.max(0, liters - math.max(remaining, 0)), calls, toppedUp, spilled
end

---Smallest amount the game can place as a heap piece of a product
function LimeDropZone:getHeapPieceLiters(fillTypeIndex)
    self.heapPieceLiters = self.heapPieceLiters or {}
    fillTypeIndex = fillTypeIndex or self:getLimeFillTypeIndex()
    if self.heapPieceLiters[fillTypeIndex] == nil then
        local piece
        if g_densityMapHeightManager ~= nil and g_densityMapHeightManager.getMinValidLiterValue ~= nil then
            piece = g_densityMapHeightManager:getMinValidLiterValue(fillTypeIndex)
        end
        if type(piece) ~= "number" or piece <= 0 then
            piece = LimeDropZone.FALLBACK_HEAP_PIECE
        end
        self.heapPieceLiters[fillTypeIndex] = piece
        log("Smallest heap piece of fill type %s: %.1f L", tostring(fillTypeIndex), piece)
    end
    return self.heapPieceLiters[fillTypeIndex]
end

---amount: liters delivered (or refund when cancelled); spilled: liters tipped next to the zone
function LimeDropZone:broadcastOrderState(order, state, amount, spilled)
    if g_server ~= nil then
        g_server:broadcastEvent(LimeDropOrderStateEvent.new(order, state, amount, spilled), false)
    end
    if g_client ~= nil then
        self:onOrderState(order, state, amount, spilled)
    end
end

---------------------------------------------------------------------------
-- Client side reaction to order updates
---------------------------------------------------------------------------

function LimeDropZone:onOrderState(order, state, amount, spilled)
    local isOwnFarm = order.farmId == self:getLocalFarmId()
    local zoneName = self:getZoneNameById(order.zoneId)
    self:requestMenuRefresh()

    if state == LimeDropZone.ORDER_STATE_PLACED then
        if g_server == nil then
            self.orders[order.id] = order
        end
        if isOwnFarm then
            self:notify(string.format(getText("limeDrop_notify_ordered"), (self:getFillTypeDisplay(order.fillTypeName)),
                formatLiters(order.liters), zoneName, formatDuration(order.remainingMs)))
        end

    elseif state == LimeDropZone.ORDER_STATE_DELIVERED then
        if g_server == nil then
            self.orders[order.id] = nil
        end
        if isOwnFarm then
            if (spilled or 0) >= 1 then
                self:notify(string.format(getText("limeDrop_notify_deliveredSpill"), (self:getFillTypeDisplay(order.fillTypeName)),
                    formatLiters(amount), zoneName, formatLiters(spilled)))
            else
                self:notify(string.format(getText("limeDrop_notify_delivered"), (self:getFillTypeDisplay(order.fillTypeName)),
                    formatLiters(amount), zoneName))
            end
            local leftover = order.liters - amount
            if leftover >= 1 then
                local refund = math.floor(leftover * (order.pricePerLiter or self:getPricePerLiter(order.fillTypeName)))
                self:notify(string.format(getText("limeDrop_notify_refund"), formatLiters(amount), formatMoney(refund)))
            end
        end

    elseif state == LimeDropZone.ORDER_STATE_CANCELLED then
        if g_server == nil then
            self.orders[order.id] = nil
        end
        if isOwnFarm then
            self:notify(string.format(getText("limeDrop_notify_cancelledNotOwned"), zoneName, formatMoney(amount)))
        end
    end
end

---------------------------------------------------------------------------
-- Input
---------------------------------------------------------------------------

---Registers our keys in whatever input context the game is building (on foot or a vehicle).
-- The game rebuilds contexts when entering/leaving vehicles, so the same key ends up with
-- several event ids over time. All of them are kept and updated together.
function LimeDropZone.registerActionEvents(playerInputComponent, controlling)
    local self = LimeDropZone

    -- shown in the key help box (top left) while on foot.
    -- The placement keys are not registered here, see registerPlacementEvents.
    local definitions = {
        { key = "menu", action = InputAction.LIMEDROP_MENU, callback = self.onActionMenu, text = "input_LIMEDROP_MENU" }
    }

    for _, def in ipairs(definitions) do
        if def.action ~= nil then
            local _, eventId = g_inputBinding:registerActionEvent(def.action, self, def.callback, false, true, false, true)
            if eventId ~= nil then
                g_inputBinding:setActionEventText(eventId, g_i18n:getText(def.text))
                g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_NORMAL)
                g_inputBinding:setActionEventTextVisibility(eventId, false)
                local ids = self.actionEventIds[def.key] or {}
                table.insert(ids, eventId)
                -- only the newest few can still exist (one per context)
                while #ids > LimeDropZone.MAX_EVENT_IDS_PER_KEY do
                    table.remove(ids, 1)
                end
                self.actionEventIds[def.key] = ids
            end
        end
    end

    log("Keys registered for input context '%s'", tostring(controlling or g_inputBinding.currentContextName))

    -- force the next update to apply visibility to the new events
    self.lastOnFoot = nil
end

---Applies a setter to every event id we hold for a key (the input binding ignores ids it no longer knows)
function LimeDropZone:forEachActionEvent(key, func)
    for _, eventId in ipairs(self.actionEventIds[key] or {}) do
        func(eventId)
    end
end

---The menu hint only shows on foot
function LimeDropZone:updateActionEventVisibility()
    local onFoot = self:getIsLocalPlayerOnFoot()
    if onFoot ~= self.lastOnFoot then
        self.lastOnFoot = onFoot
        self:forEachActionEvent("menu", function(eventId)
            g_inputBinding:setActionEventTextVisibility(eventId, onFoot)
        end)
    end
end

---Opens the zone list dialog. Works anywhere on the map, but only on foot.
function LimeDropZone:onActionMenu()
    self:openMenu()
end

function LimeDropZone:openMenu()
    if LimeDropMenuDialog.INSTANCE ~= nil and LimeDropMenuDialog.INSTANCE.isShowing then
        return
    end
    if not self:getIsLocalPlayerOnFoot() then
        self:warn(getText("limeDrop_warning_onFootOnly"))
        return
    end
    local farmId = self:getLocalFarmId()
    if not self:getIsValidFarmId(farmId) then
        self:warn(getText("limeDrop_warning_noFarm"))
        return
    end
    self:cancelPlacement()
    LimeDropMenuDialog.show()
end

---------------------------------------------------------------------------
-- Placing a new zone: a preview follows the point the camera looks at until
-- the player places it (or cancels). Started from the menu's "New zone" button.
---------------------------------------------------------------------------

---Reason a new zone can't be created at all, or nil
function LimeDropZone:getNewZoneBlocker()
    if not self:getIsLocalPlayerOnFoot() then
        return getText("limeDrop_warning_onFootOnly")
    end
    if self:getAreLocalPlayerHandsBusy() then
        return getText("limeDrop_warning_handsBusy")
    end
    local farmId = self:getLocalFarmId()
    if not self:getIsValidFarmId(farmId) then
        return getText("limeDrop_warning_noFarm")
    end
    local fillTypeIndex = self:getLimeFillTypeIndex()
    if fillTypeIndex == nil or not DensityMapHeightUtil.getCanTipToGround(fillTypeIndex) then
        return getText("limeDrop_warning_noHeaps")
    end
    if self:getNumZonesForFarm(farmId) >= LimeDropZone.MAX_ZONES_PER_FARM then
        return string.format(getText("limeDrop_warning_maxZones"), LimeDropZone.MAX_ZONES_PER_FARM)
    end
    return nil
end

-- Target object for the placement key events, kept separate so they can be removed on their own
LimeDropZone.placementInput = {
    onPlace = function() LimeDropZone:onActionPlace() end,
    onCancel = function() LimeDropZone:onActionPlaceCancel() end
}

---Adds place/rotate/cancel to the on-foot input context. They exist only while placing,
-- so getting in and out of vehicles can never leave them in a stale state.
function LimeDropZone:registerPlacementEvents()
    self:removePlacementEvents()
    local target = LimeDropZone.placementInput
    local definitions = {
        { action = InputAction.LIMEDROP_PLACE, callback = target.onPlace, text = "input_LIMEDROP_PLACE" },
        { action = InputAction.LIMEDROP_PLACE_CANCEL, callback = target.onCancel, text = "input_LIMEDROP_PLACE_CANCEL" }
    }
    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    for _, def in ipairs(definitions) do
        if def.action ~= nil then
            local _, eventId = g_inputBinding:registerActionEvent(def.action, target, def.callback, false, true, false, true)
            if eventId ~= nil then
                g_inputBinding:setActionEventText(eventId, g_i18n:getText(def.text))
                g_inputBinding:setActionEventTextPriority(eventId, GS_PRIO_VERY_HIGH)
                g_inputBinding:setActionEventTextVisibility(eventId, true)
            end
        end
    end
    g_inputBinding:endActionEventsModification()
    self.placementEventsRegistered = true
end

function LimeDropZone:removePlacementEvents()
    if not self.placementEventsRegistered then
        return
    end
    self.placementEventsRegistered = false
    g_inputBinding:beginActionEventsModification(PlayerInputComponent.INPUT_CONTEXT_NAME)
    g_inputBinding:removeActionEventsByTarget(LimeDropZone.placementInput)
    g_inputBinding:endActionEventsModification()
end

---True when the game is currently using the on-foot controls (not a vehicle, menu or text box)
function LimeDropZone:getIsOnFootInputActive()
    return g_inputBinding.getContextName ~= nil and g_inputBinding:getContextName() == PlayerInputComponent.INPUT_CONTEXT_NAME
end

function LimeDropZone:startPlacement()
    local blocker = self:getNewZoneBlocker()
    if blocker ~= nil then
        self:warn(blocker)
        return
    end
    self.placement = { startTime = g_time }
    self:registerPlacementEvents()
    self:updatePlacement()
end

---Stops placing; with a text key the player is told why
function LimeDropZone:cancelPlacement(reasonKey)
    if self.placement ~= nil and reasonKey ~= nil then
        self:notify(getText(reasonKey))
    end
    self.placement = nil
    self.placementStartFrames = nil
    self:removePlacementEvents()
end

---Moves the preview to where the player looks and checks whether it can go there
function LimeDropZone:updatePlacement()
    local placement = self.placement
    local x, z = self:getLookAtGroundPoint()
    if x == nil then
        placement.rect = nil
        return
    end
    local size = squareSize(self.newZoneWidth, self.newZoneLength)
    local rect = { x = x, z = z, yaw = 0, width = size, length = size }
    -- live slope under the preview, recalculated once it moved a bit (the check samples the whole circle)
    local last = placement.slopeAt
    if last == nil or last.size ~= size or (last.x - x) ^ 2 + (last.z - z) ^ 2 > 0.04 then
        placement.slope = self:getRectSlope(rect)
        placement.slopeAt = { x = x, z = z, size = size }
    end
    self:assignFieldLabel(rect, self:getLocalFarmId())
    placement.rect = rect

    local px, _, pz = self:getLocalPlayerPosition()
    local reason = self:getNewZoneBlocker()
    if reason == nil and px ~= nil then
        local dx, dz = x - px, z - pz
        if dx * dx + dz * dz > LimeDropZone.PLACE_MAX_DISTANCE * LimeDropZone.PLACE_MAX_DISTANCE then
            reason = getText("limeDrop_place_tooFar")
        end
    end
    if reason == nil and self:getIsTooCloseToZone(rect, self:getLocalFarmId()) then
        reason = getText("limeDrop_warning_tooClose")
    end
    if reason == nil and not self:getIsRectOnOwnedLand(rect, self:getLocalFarmId()) then
        reason = getText("limeDrop_place_notOwned")
    end
    placement.isValid = reason == nil
    placement.reason = reason
end

function LimeDropZone:onActionPlace()
    local placement = self.placement
    -- ignore the click that pressed the menu button
    if placement == nil or g_time - placement.startTime < 300 then
        return
    end
    self:updatePlacement()
    if not placement.isValid or placement.rect == nil then
        self:warn(placement.reason or getText("limeDrop_warning_tooClose"))
        return
    end
    self:cancelPlacement()
    LimeDropZoneEvent.sendAddRequest(self:getLocalFarmId(), placement.rect)
end

function LimeDropZone:onActionPlaceCancel()
    self:cancelPlacement("limeDrop_place_cancelled")
end

function LimeDropZone:drawPlacement()
    local placement = self.placement
    local rect = placement.rect
    if rect == nil then
        return
    end
    local color = placement.isValid and LimeDropZone.PLACE_COLOR_OK or LimeDropZone.PLACE_COLOR_BAD
    local points, centerY = self:getOutlinePoints(rect)
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        drawDebugLine(p1[1], p1[2], p1[3], color[1], color[2], color[3], p2[1], p2[2], p2[3], color[1], color[2], color[3])
    end
    -- center post, like placed zones
    drawDebugLine(rect.x, centerY, rect.z, color[1], color[2], color[3], rect.x, centerY + 1.5, rect.z, color[1], color[2], color[3])

    Utils.renderTextAtWorldPosition(rect.x, centerY + 2.2, rect.z, string.format(getText("limeDrop_place_label"),
        self:getZoneLabel(rect), formatSize(rect.width, rect.length)), 0.016, 0)
    Utils.renderTextAtWorldPosition(rect.x, centerY + 1.8, rect.z,
        placement.reason or getText("limeDrop_place_hint"), 0.014, 0)
    if placement.slope ~= nil then
        local slopeText = string.format(getText("limeDrop_place_slope"), placement.slope)
        if placement.slope >= LimeDropZone.STEEP_SLOPE then
            slopeText = slopeText .. " - " .. getText("limeDrop_place_steep")
        end
        Utils.renderTextAtWorldPosition(rect.x, centerY + 1.4, rect.z, slopeText, 0.014, 0)
    end
end

---Edit button in the zone list: Size / Rename / Remove
function LimeDropZone:openEditDialog(zoneId)
    if self.zones[zoneId] ~= nil then
        LimeDropEditDialog.show(zoneId)
    end
end

---Size option of the edit dialog
function LimeDropZone:openSizeDialog(zoneId)
    if self.zones[zoneId] ~= nil then
        LimeDropSizeDialog.show(zoneId)
    end
end

---Order button in the zone list: the slider dialog, unless a delivery is already on its way
function LimeDropZone:openOrderDialog(zoneId)
    if self:getHasPendingOrder(zoneId) then
        self:warn(string.format(getText("limeDrop_warning_orderPending"), self:getZoneNameById(zoneId)))
        return
    end
    LimeDropOrderDialog.show(zoneId)
end

function LimeDropZone:placeOrder(zoneId, liters, fillTypeName)
    local zone = self.zones[zoneId]
    if liters == nil or zone == nil then
        return
    end
    if self:getHasPendingOrder(zoneId) then
        self:warn(string.format(getText("limeDrop_warning_orderPending"), self:getZoneName(zone)))
        return
    end

    local farm = g_farmManager:getFarmById(zone.farmId)
    if farm == nil or farm:getBalance() < self:getOrderPrice(liters, fillTypeName) then
        self:warn(getText("limeDrop_warning_noMoney"))
        return
    end

    LimeDropOrderEvent.sendToServer(zone.farmId, zoneId, liters, fillTypeName or "LIME")
end

---Picking a size also makes it the default for the next new zone
function LimeDropZone:resizeZone(zoneId, width, length)
    local zone = self.zones[zoneId]
    if zone == nil then
        return
    end
    width, length = squareSize(width, length)
    local canResize, reasonKey = self:getCanResizeZone(zone, width, length)
    if not canResize then
        self:warn(getText(reasonKey))
        return
    end
    self.newZoneWidth, self.newZoneLength = width, length
    self:saveSettings()
    LimeDropZoneEvent.sendResizeRequest(zone.farmId, zoneId, width, length)
end

---Shows the game's text input dialog on top of the zone list
function LimeDropZone:showTextInput(defaultText, prompt, maxCharacters, confirmText, callback)
    self.subDialogOpen = true
    self.textInputCallback = callback
    TextInputDialog.show(self.onTextInputResult, self, defaultText, prompt, nil, maxCharacters, confirmText, nil, nil, false)
end

function LimeDropZone:onTextInputResult(text, success)
    self.subDialogOpen = false
    self:requestMenuRefresh()
    local callback = self.textInputCallback
    self.textInputCallback = nil
    if success and callback ~= nil then
        callback(text)
    end
end

---Rename/size/remove dialogs open on top of the zone list; the list refreshes once they close
function LimeDropZone:openRenameDialog(zoneId)
    local zone = self.zones[zoneId]
    if zone == nil then
        return
    end
    local prompt = string.format(getText("limeDrop_rename_prompt"), self:getZoneLabel(zone, true))
    self:showTextInput(zone.name or "", prompt, LimeDropZone.MAX_DESCRIPTION_LENGTH,
        getText("limeDrop_rename_confirm"), function(text)
            local name = sanitizeName(text)
            -- the label is added by the mod; drop it if the player typed it anyway
            -- (also when the game's text filter turned "Field" into "Fiel&"), and a leading dash
            name = name:gsub("^[Ff][Ii][Ee][Ll][Dd&]%s*%d+%a?$", "")
            name = name:gsub("^[Ff][Ii][Ee][Ll][Dd&]%s*%d+%a?%s+", "")
            name = name:gsub("^%-+%s*", "")
            LimeDropZoneEvent.sendRenameRequest(zone.farmId, zone.id, name)
        end)
end

function LimeDropZone:openRemoveDialog(zoneId)
    local zone = self.zones[zoneId]
    if zone == nil then
        return
    end
    self.subDialogOpen = true
    self.removeZoneId = zoneId
    YesNoDialog.show(self.onRemoveDialogResult, self,
        string.format(getText("limeDrop_remove_text"), self:getZoneName(zone)), getText("limeDrop_remove_title"))
end

function LimeDropZone:onRemoveDialogResult(yes)
    local zone = self.zones[self.removeZoneId or 0]
    self.removeZoneId = nil
    self.subDialogOpen = false
    self:requestMenuRefresh()
    if yes and zone ~= nil then
        LimeDropZoneEvent.sendRemoveRequest(zone.farmId, zone.id)
    end
end

---Rebuilds the zone list (if open) a couple of frames later, after any dialog on top has closed
function LimeDropZone:requestMenuRefresh()
    if g_client ~= nil then
        self.menuRefreshFrames = 2
    end
end

---------------------------------------------------------------------------
-- Player settings (modSettings, per player)
---------------------------------------------------------------------------

function LimeDropZone:setShowMarkers(show)
    self.showMarkers = show
    self:saveSettings()
    self:notify(getText(show and "limeDrop_notify_markersShown" or "limeDrop_notify_markersHidden"))
end

function LimeDropZone:getSettingsPath()
    return getUserProfileAppPath() .. "modSettings/" .. LimeDropZone.SETTINGS_FILENAME
end

function LimeDropZone:loadSettings()
    local path = self:getSettingsPath()
    if not fileExists(path) then
        return
    end
    local xmlFile = XMLFile.load("limeDropZoneSettings", path)
    if xmlFile ~= nil then
        self.showMarkers = xmlFile:getBool("limeDropZoneSettings#showMarkers", true)
        self.newZoneWidth, self.newZoneLength = squareSize(
            xmlFile:getFloat("limeDropZoneSettings#zoneWidth", LimeDropZone.DEFAULT_SIZE),
            xmlFile:getFloat("limeDropZoneSettings#zoneLength", LimeDropZone.DEFAULT_SIZE))
        xmlFile:delete()
    end
end

function LimeDropZone:saveSettings()
    createFolder(getUserProfileAppPath() .. "modSettings/")
    local xmlFile = XMLFile.create("limeDropZoneSettings", self:getSettingsPath(), "limeDropZoneSettings")
    if xmlFile ~= nil then
        xmlFile:setBool("limeDropZoneSettings#showMarkers", self.showMarkers)
        xmlFile:setFloat("limeDropZoneSettings#zoneWidth", self.newZoneWidth)
        xmlFile:setFloat("limeDropZoneSettings#zoneLength", self.newZoneLength)
        xmlFile:save()
        xmlFile:delete()
    end
end

---------------------------------------------------------------------------
-- Order history
---------------------------------------------------------------------------

---In-game day and time of day in minutes, for history entries
function LimeDropZone:getGameDayAndMinute()
    local day, minute = 0, 0
    local environment = g_currentMission ~= nil and g_currentMission.environment or nil
    if environment ~= nil then
        day = environment.currentDay or 0
        minute = math.floor((environment.dayTime or 0) / 60000)
    end
    return day, minute
end

function LimeDropZone:formatHistoryTime(entry)
    return string.format(getText("limeDrop_history_time"), entry.day, math.floor(entry.minute / 60), entry.minute % 60)
end

---Server: remembers a finished delivery and sends it to all players
function LimeDropZone:serverAddHistory(order, delivered, refund, cancelled)
    local zone = self.zones[order.zoneId]
    local day, minute = self:getGameDayAndMinute()
    local entry = {
        farmId = order.farmId,
        day = day,
        minute = minute,
        zoneId = order.zoneId,
        fieldId = zone ~= nil and zone.fieldId or 0,
        farmlandId = zone ~= nil and zone.farmlandId or 0,
        suffixIndex = zone ~= nil and zone.suffixIndex or 1,
        name = zone ~= nil and zone.name or "",
        liters = math.floor(order.liters),
        delivered = math.floor(delivered),
        paid = math.floor(order.price or (order.liters * (order.pricePerLiter or 0))),
        refund = math.floor(refund),
        cancelled = cancelled == true,
        fillTypeName = order.fillTypeName or "LIME"
    }
    self:applyHistoryEntry(entry)
    if g_server ~= nil then
        g_server:broadcastEvent(LimeDropHistoryEvent.new(entry), false)
    end
end

---Adds an entry, keeping at most MAX_HISTORY_PER_ZONE per spot (oldest dropped)
function LimeDropZone:applyHistoryEntry(entry)
    table.insert(self.history, entry)
    local count = 0
    for i = #self.history, 1, -1 do
        if self.history[i].zoneId == entry.zoneId then
            count = count + 1
            if count > LimeDropZone.MAX_HISTORY_PER_ZONE then
                table.remove(self.history, i)
            end
        end
    end
    if LimeDropHistoryDialog ~= nil then
        LimeDropHistoryDialog.refresh()
    end
end

---Entries of one spot, newest first
function LimeDropZone:getHistoryForZone(zoneId)
    local entries = {}
    for i = #self.history, 1, -1 do
        if self.history[i].zoneId == zoneId then
            table.insert(entries, self.history[i])
        end
    end
    return entries
end

---A removed spot takes its history with it
function LimeDropZone:removeHistoryForZone(zoneId)
    for i = #self.history, 1, -1 do
        if self.history[i].zoneId == zoneId then
            table.remove(self.history, i)
        end
    end
end

---History button of a zone row
function LimeDropZone:openHistory(zoneId)
    if self.zones[zoneId] ~= nil then
        LimeDropHistoryDialog.show(zoneId)
    end
end

---------------------------------------------------------------------------
-- Savegame settings shown under Settings > Game Settings > Lime Drop Zones
---------------------------------------------------------------------------

local function formatPercent(value)
    if math.abs(value - math.floor(value)) < 0.01 then
        return string.format("%d%%", value)
    end
    return string.format("%.1f%%", value)
end
LimeDropZone.formatPercent = formatPercent

LimeDropZone.SETTINGS = {
    {
        key = "deliveryDelay", options = LimeDropZone.DELIVERY_DELAY_OPTIONS, default = LimeDropZone.DEFAULT_DELIVERY_DELAY,
        title = "limeDrop_setting_delay_title", tooltip = "limeDrop_setting_delay_tooltip",
        format = function(value) return formatDuration(value * 1000) end
    },
    {
        key = "deliveryFee", options = LimeDropZone.DELIVERY_FEE_OPTIONS, default = LimeDropZone.DEFAULT_DELIVERY_FEE,
        title = "limeDrop_setting_fee_title", tooltip = "limeDrop_setting_fee_tooltip",
        format = formatPercent
    }
}
LimeDropZone.settingsOptions = {}

local function getSettingDef(key)
    for _, def in ipairs(LimeDropZone.SETTINGS) do
        if def.key == key then
            return def
        end
    end
    return nil
end

function LimeDropZone:getSetting(key)
    return self.settingValues[key]
end

function LimeDropZone:getDeliveryDelayMs()
    return self:getSetting("deliveryDelay") * 1000
end

---Index of the choice closest to the current value
function LimeDropZone:getSettingIndex(key)
    local def = getSettingDef(key)
    local value = self.settingValues[key]
    local best, bestDiff = 1, nil
    for i, option in ipairs(def.options) do
        local diff = math.abs(option - value)
        if bestDiff == nil or diff < bestDiff then
            best, bestDiff = i, diff
        end
    end
    return best
end

---Applies a value (snapped to the nearest choice) and updates the Settings page
function LimeDropZone:applySetting(key, value)
    local def = getSettingDef(key)
    if def == nil then
        return
    end
    self.settingValues[key] = tonumber(value) or def.default
    self.settingValues[key] = def.options[self:getSettingIndex(key)]
    self:updateSettingsOptions()
    self:requestMenuRefresh()
end

---Only the host or an admin may change these in multiplayer
function LimeDropZone:getCanChangeSettings()
    if g_currentMission == nil then
        return false
    end
    if g_currentMission:getIsServer() then
        return true
    end
    return g_currentMission.isMasterUser == true
end

function LimeDropZone:requestSetting(key, value)
    if g_server ~= nil then
        self:serverSetSetting(key, value, nil)
    elseif self:getCanChangeSettings() then
        g_client:getServerConnection():sendEvent(LimeDropSettingsEvent.new(key, value))
    else
        self:updateSettingsOptions()
    end
end

function LimeDropZone:serverSetSetting(key, value, connection)
    if g_server == nil or getSettingDef(key) == nil then
        return
    end
    if connection ~= nil then
        local userManager = g_currentMission ~= nil and g_currentMission.userManager or nil
        local user = userManager ~= nil and userManager:getUserByConnection(connection) or nil
        local isAdmin = user ~= nil and user:getIsMasterUser()
        if not isAdmin then
            log("Setting change from a non-admin player ignored (%s)", key)
            return
        end
    end
    self:applySetting(key, value)
    g_server:broadcastEvent(LimeDropSettingsEvent.new(key, self:getSetting(key)), false)
end

---Adds a "Lime Drop Zones" section to the game settings page by copying the game's own
-- section header and option row (the same way other settings mods do it)
function LimeDropZone:addSettingsOptions()
    if next(self.settingsOptions) ~= nil or g_inGameMenu == nil then
        return
    end
    self:buildSettingsOptions()
    self:updateSettingsOptions()
end

---Clones the game's section header and option row into the game settings list
function LimeDropZone:buildSettingsOptions()
    local settingsPage = g_inGameMenu.pageSettings
    local layout = settingsPage ~= nil and settingsPage.gameSettingsLayout or nil
    if layout == nil then
        log("Settings page layout not found, settings not added")
        return
    end
    local headerTemplate, rowTemplate
    for _, element in pairs(layout.elements) do
        if headerTemplate == nil and element.name == "sectionHeader" then
            headerTemplate = element
        end
        if rowTemplate == nil and element.typeName == "Bitmap" and element.elements[1] ~= nil
            and element.elements[1].typeName == "MultiTextOption" then
            rowTemplate = element
        end
    end
    if headerTemplate == nil or rowTemplate == nil then
        log("Settings page templates not found, settings not added")
        return
    end

    local header = headerTemplate:clone(layout)
    header:setText(getText("limeDrop_settings_title"))

    for _, def in ipairs(LimeDropZone.SETTINGS) do
        local row = rowTemplate:clone(layout)
        row.id = nil
        local option = row.elements[1]
        option.id = "limeDrop_" .. def.key
        row.elements[2]:setText(getText(def.title))
        if option.elements[1] ~= nil and option.elements[1].setText ~= nil then
            option.elements[1]:setText(getText(def.tooltip))
        end
        local texts = {}
        for i, value in ipairs(def.options) do
            texts[i] = def.format(value)
        end
        option:setTexts(texts)
        local key = def.key
        option.onClickCallback = function(_, state)
            LimeDropZone:requestSetting(key, getSettingDef(key).options[state])
        end
        row:setVisible(true)
        row:setDisabled(false)
        self.settingsOptions[key] = option
    end
    layout:invalidateLayout()
end

function LimeDropZone:updateSettingsOptions()
    local canChange = self:getCanChangeSettings()
    for key, option in pairs(self.settingsOptions or {}) do
        option:setState(self:getSettingIndex(key), false)
        option:setDisabled(not canChange)
    end
end

---------------------------------------------------------------------------
-- Visuals
---------------------------------------------------------------------------

---Circle outline split into short segments so it follows the terrain
function LimeDropZone:getOutlinePoints(rect)
    local radius = getRadius(rect)
    local steps = math.max(24, math.ceil(2 * math.pi * radius / LimeDropZone.OUTLINE_STEP))
    local points = {}
    for i = 0, steps - 1 do
        local a = 2 * math.pi * i / steps
        local px, pz = rect.x + math.cos(a) * radius, rect.z + math.sin(a) * radius
        table.insert(points, { px, getTerrainHeight(px, pz) + 0.15, pz })
    end
    table.insert(points, points[1])
    return points, getTerrainHeight(rect.x, rect.z)
end

function LimeDropZone:buildOutline(zone)
    zone.outlinePoints, zone.centerY = self:getOutlinePoints(zone)
end

function LimeDropZone:createHotspot(zone)
    if not LimeDropZone.SHOW_MAP_HOTSPOTS or PlaceableHotspot == nil or zone.farmId ~= self:getLocalFarmId() then
        return
    end
    local hotspot = PlaceableHotspot.new()
    local name = self:getZoneName(zone)
    hotspot:setName(name)
    hotspot:createIcon()
    -- PlaceableHotspot expects a placeable behind it; give it a minimal stand-in
    local imageFilename = LimeDropZone.MOD_DIR .. "icon_heapDelivery.dds"
    hotspot.placeable = {
        getHotspot = function() return hotspot end,
        getImageFilename = function() return imageFilename end,
        getName = function() return name end,
        getOwnerFarmId = function() return zone.farmId end,
        getIsBeingDeleted = function() return false end,
        specializations = {},
        canBeSold = function() return false end
    }
    local hotspotType = PlaceableHotspot.TYPE.UNLOADING or PlaceableHotspot.TYPE.SHOP
    if hotspotType ~= nil then
        hotspot:setPlaceableType(hotspotType)
    end
    hotspot:setWorldPosition(zone.x, zone.z)
    if hotspot.setTeleportWorldPosition ~= nil then
        hotspot:setTeleportWorldPosition(zone.x, getTerrainHeight(zone.x, zone.z), zone.z)
    end
    g_currentMission:addMapHotspot(hotspot)
    zone.hotspot = hotspot
end

---Map markers are only shown for the local player's farm, so rebuild them when it changes
function LimeDropZone:refreshHotspots()
    for _, zone in pairs(self.zones) do
        self:deleteHotspot(zone)
        self:createHotspot(zone)
    end
end

function LimeDropZone:deleteHotspot(zone)
    if zone.hotspot ~= nil then
        if g_currentMission ~= nil then
            g_currentMission:removeMapHotspot(zone.hotspot)
        end
        zone.hotspot:delete()
        zone.hotspot = nil
    end
end

function LimeDropZone:drawZone(zone)
    local points = zone.outlinePoints
    if points == nil then
        return
    end
    local r, g, b = LimeDropZone.OUTLINE_COLOR[1], LimeDropZone.OUTLINE_COLOR[2], LimeDropZone.OUTLINE_COLOR[3]
    for i = 1, #points - 1 do
        local p1, p2 = points[i], points[i + 1]
        drawDebugLine(p1[1], p1[2], p1[3], r, g, b, p2[1], p2[2], p2[3], r, g, b)
    end
    drawDebugLine(zone.x, zone.centerY, zone.z, r, g, b, zone.x, zone.centerY + 2.5, zone.z, r, g, b)

    Utils.renderTextAtWorldPosition(zone.x, zone.centerY + 3.2, zone.z, self:getZoneName(zone), 0.016, 0)

    local pendingLiters, remainingMs = self:getPendingForZone(zone.id)
    if pendingLiters > 0 then
        Utils.renderTextAtWorldPosition(zone.x, zone.centerY + 2.8, zone.z,
            string.format(getText("limeDrop_zonePending"), formatLiters(pendingLiters), formatDuration(remainingMs or 0)), 0.014, 0)
    end
end

---------------------------------------------------------------------------
-- Save / load (server only)
---------------------------------------------------------------------------

function LimeDropZone:getSavegameFilePath()
    local missionInfo = g_currentMission ~= nil and g_currentMission.missionInfo or nil
    if missionInfo == nil then
        return nil
    end
    local dir = missionInfo.savegameDirectory
    if dir == nil and missionInfo.savegameIndex ~= nil then
        dir = string.format("%ssavegame%d", getUserProfileAppPath(), missionInfo.savegameIndex)
    end
    if dir == nil then
        return nil
    end
    return dir .. "/" .. LimeDropZone.SAVE_FILENAME
end

local function saveRect(xmlFile, key, rect)
    xmlFile:setFloat(key .. "#x", rect.x)
    xmlFile:setFloat(key .. "#z", rect.z)
    xmlFile:setFloat(key .. "#width", rect.width)
    xmlFile:setFloat(key .. "#length", rect.length)
    xmlFile:setFloat(key .. "#yaw", rect.yaw)
end

---Reads a rectangle; zones saved by 1.x (circles with a radius) become squares
local function loadRect(xmlFile, key, rect)
    rect.x = xmlFile:getFloat(key .. "#x")
    rect.z = xmlFile:getFloat(key .. "#z")
    local radius = xmlFile:getFloat(key .. "#radius")
    local fallback = radius ~= nil and radius * 2 or nil
    rect.width = xmlFile:getFloat(key .. "#width", fallback or LimeDropZone.DEFAULT_SIZE)
    rect.length = xmlFile:getFloat(key .. "#length", fallback or LimeDropZone.DEFAULT_SIZE)
    rect.yaw = xmlFile:getFloat(key .. "#yaw", 0)
    return rect
end

function LimeDropZone:saveToSavegame()
    if g_server == nil then
        return
    end
    local path = self:getSavegameFilePath()
    if path == nil then
        return
    end

    local xmlFile = XMLFile.create("limeDropZoneXML", path, "limeDropZone")
    if xmlFile == nil then
        log("Could not create %s", path)
        return
    end

    xmlFile:setInt("limeDropZone#nextZoneId", self.nextZoneId)
    xmlFile:setInt("limeDropZone#nextOrderId", self.nextOrderId)
    for _, def in ipairs(LimeDropZone.SETTINGS) do
        xmlFile:setFloat("limeDropZone.settings#" .. def.key, self:getSetting(def.key))
    end

    local i = 0
    for _, zone in pairs(self.zones) do
        local key = string.format("limeDropZone.zones.zone(%d)", i)
        xmlFile:setInt(key .. "#id", zone.id)
        xmlFile:setInt(key .. "#farmId", zone.farmId)
        xmlFile:setString(key .. "#name", zone.name or "")
        xmlFile:setInt(key .. "#fieldId", zone.fieldId or 0)
        xmlFile:setInt(key .. "#farmlandId", zone.farmlandId or 0)
        xmlFile:setInt(key .. "#suffixIndex", zone.suffixIndex or 1)
        saveRect(xmlFile, key, zone)
        i = i + 1
    end

    i = 0
    for _, order in pairs(self.orders) do
        local key = string.format("limeDropZone.orders.order(%d)", i)
        xmlFile:setInt(key .. "#id", order.id)
        xmlFile:setInt(key .. "#farmId", order.farmId)
        xmlFile:setInt(key .. "#zoneId", order.zoneId)
        xmlFile:setInt(key .. "#liters", order.liters)
        xmlFile:setInt(key .. "#remainingMs", math.floor(order.remainingMs))
        saveRect(xmlFile, key, order)
        xmlFile:setFloat(key .. "#pricePerLiter", order.pricePerLiter or self:getPricePerLiter())
        xmlFile:setInt(key .. "#price", order.price or 0)
        xmlFile:setString(key .. "#fillType", order.fillTypeName or "LIME")
        i = i + 1
    end

    for index, entry in ipairs(self.history) do
        local key = string.format("limeDropZone.history.entry(%d)", index - 1)
        xmlFile:setInt(key .. "#farmId", entry.farmId)
        xmlFile:setInt(key .. "#day", entry.day)
        xmlFile:setInt(key .. "#minute", entry.minute)
        xmlFile:setInt(key .. "#zoneId", entry.zoneId)
        xmlFile:setInt(key .. "#fieldId", entry.fieldId)
        xmlFile:setInt(key .. "#farmlandId", entry.farmlandId)
        xmlFile:setInt(key .. "#suffixIndex", entry.suffixIndex)
        xmlFile:setString(key .. "#name", entry.name)
        xmlFile:setInt(key .. "#liters", entry.liters)
        xmlFile:setInt(key .. "#delivered", entry.delivered)
        xmlFile:setInt(key .. "#paid", entry.paid)
        xmlFile:setInt(key .. "#refund", entry.refund)
        xmlFile:setBool(key .. "#cancelled", entry.cancelled)
        xmlFile:setString(key .. "#fillType", entry.fillTypeName or "LIME")
    end

    xmlFile:save()
    xmlFile:delete()
end

function LimeDropZone:loadFromSavegame()
    if g_server == nil then
        return
    end
    local path = self:getSavegameFilePath()
    if path ~= nil and not fileExists(path) then
        local legacyPath = path:sub(1, #path - #LimeDropZone.SAVE_FILENAME) .. LimeDropZone.LEGACY_SAVE_FILENAME
        if fileExists(legacyPath) then
            log("Loading zones from %s (saved before the rename)", LimeDropZone.LEGACY_SAVE_FILENAME)
            path = legacyPath
        end
    end
    if path == nil or not fileExists(path) then
        return
    end

    local xmlFile = XMLFile.load("limeDropZoneXML", path)
    if xmlFile == nil then
        return
    end

    self.nextZoneId = xmlFile:getInt("limeDropZone#nextZoneId", 1)
    self.nextOrderId = xmlFile:getInt("limeDropZone#nextOrderId", 1)
    for _, def in ipairs(LimeDropZone.SETTINGS) do
        -- 1.17 saved the delivery time as limeDropZone#deliveryDelay
        local legacy = def.key == "deliveryDelay" and xmlFile:getInt("limeDropZone#deliveryDelay") or nil
        self:applySetting(def.key, xmlFile:getFloat("limeDropZone.settings#" .. def.key, legacy or def.default))
    end

    xmlFile:iterate("limeDropZone.zones.zone", function(_, key)
        local zone = loadRect(xmlFile, key, {
            id = xmlFile:getInt(key .. "#id"),
            farmId = xmlFile:getInt(key .. "#farmId"),
            name = xmlFile:getString(key .. "#name", ""),
            fieldId = xmlFile:getInt(key .. "#fieldId"),
            farmlandId = xmlFile:getInt(key .. "#farmlandId"),
            suffixIndex = xmlFile:getInt(key .. "#suffixIndex")
        })
        if zone.id ~= nil and zone.farmId ~= nil and zone.x ~= nil and zone.z ~= nil then
            -- spots saved before field names existed: name them now; their old free text was a full name, so drop it
            if zone.fieldId == nil then
                zone.width, zone.length = squareSize(zone.width, zone.length)
                self:assignFieldLabel(zone, zone.farmId)
                zone.name = ""
            end
            self:applyAddZone(zone, false)
        end
    end)

    xmlFile:iterate("limeDropZone.orders.order", function(_, key)
        local order = loadRect(xmlFile, key, {
            id = xmlFile:getInt(key .. "#id"),
            farmId = xmlFile:getInt(key .. "#farmId"),
            zoneId = xmlFile:getInt(key .. "#zoneId", 0),
            liters = xmlFile:getInt(key .. "#liters", 0),
            remainingMs = xmlFile:getInt(key .. "#remainingMs", 0),
            pricePerLiter = xmlFile:getFloat(key .. "#pricePerLiter"),
            price = xmlFile:getInt(key .. "#price"),
            fillTypeName = xmlFile:getString(key .. "#fillType", "LIME")
        })
        if order.id ~= nil and order.farmId ~= nil and order.x ~= nil and order.z ~= nil and order.liters > 0 then
            self.orders[order.id] = order
            if order.id >= self.nextOrderId then
                self.nextOrderId = order.id + 1
            end
        end
    end)

    self.history = {}
    xmlFile:iterate("limeDropZone.history.entry", function(_, key)
        table.insert(self.history, {
            farmId = xmlFile:getInt(key .. "#farmId", 0),
            day = xmlFile:getInt(key .. "#day", 0),
            minute = xmlFile:getInt(key .. "#minute", 0),
            zoneId = xmlFile:getInt(key .. "#zoneId", 0),
            fieldId = xmlFile:getInt(key .. "#fieldId", 0),
            farmlandId = xmlFile:getInt(key .. "#farmlandId", 0),
            suffixIndex = xmlFile:getInt(key .. "#suffixIndex", 1),
            name = xmlFile:getString(key .. "#name", ""),
            liters = xmlFile:getInt(key .. "#liters", 0),
            delivered = xmlFile:getInt(key .. "#delivered", 0),
            paid = xmlFile:getInt(key .. "#paid", 0),
            refund = xmlFile:getInt(key .. "#refund", 0),
            cancelled = xmlFile:getBool(key .. "#cancelled", false),
            fillTypeName = xmlFile:getString(key .. "#fillType", "LIME")
        })
    end)

    xmlFile:delete()

    local numZones = 0
    for _ in pairs(self.zones) do
        numZones = numZones + 1
    end
    log("Loaded %d zone(s)", numZones)
end

---------------------------------------------------------------------------
-- Mod event listener
---------------------------------------------------------------------------

function LimeDropZone:loadMap(filename)
    if g_client ~= nil then
        self:loadSettings()
        self:addSettingsOptions()
    end
end

function LimeDropZone:deleteMap()
    for _, zone in pairs(self.zones) do
        self:deleteHotspot(zone)
    end
    self.zones = {}
    self.orders = {}
    self.nextZoneId = 1
    self.nextOrderId = 1
    self.actionEventIds = {}
    self.currentZone = nil
    self.lastLocalFarmId = nil
    self.menuRefreshFrames = nil
    self.subDialogOpen = false
    self.textInputCallback = nil
    self.placement = nil
    self.placementStartFrames = nil
    self.placementEventsRegistered = false
    self.lastOnFoot = nil
    self.settingsOptions = {}
    self.history = {}
    for _, def in ipairs(LimeDropZone.SETTINGS) do
        self.settingValues[def.key] = def.default
    end
end

---Called by the menu's "New zone" button; placement starts once the menu has closed
function LimeDropZone:requestPlacement()
    local blocker = self:getNewZoneBlocker()
    if blocker ~= nil then
        self:warn(blocker)
        return false
    end
    self.placementStartFrames = 2
    return true
end

function LimeDropZone:update(dt)
    for _, order in pairs(self.orders) do
        order.remainingMs = math.max(0, order.remainingMs - dt)
        if g_server ~= nil and order.remainingMs <= 0 then
            self:serverDeliverOrder(order)
        end
    end

    if self.menuRefreshFrames ~= nil and not self.subDialogOpen then
        self.menuRefreshFrames = self.menuRefreshFrames - 1
        if self.menuRefreshFrames <= 0 then
            self.menuRefreshFrames = nil
            LimeDropMenuDialog.refresh()
        end
    end

    if g_client ~= nil and g_localPlayer ~= nil then
        local farmId = self:getLocalFarmId()
        if farmId ~= self.lastLocalFarmId then
            self.lastLocalFarmId = farmId
            self:refreshHotspots()
        end

        local x, _, z = self:getLocalPlayerPosition()
        if x ~= nil and self:getIsLocalPlayerOnFoot() then
            self.currentZone = self:getZoneAt(x, z, farmId)
        else
            self.currentZone = nil
        end

        if self.placementStartFrames ~= nil then
            self.placementStartFrames = self.placementStartFrames - 1
            if self.placementStartFrames <= 0 then
                if self:getIsOnFootInputActive() then
                    self.placementStartFrames = nil
                    self:startPlacement()
                elseif self.placementStartFrames < -120 then
                    -- the on-foot controls never came back (another menu opened); give up quietly
                    self.placementStartFrames = nil
                end
            end
        end
        if self.placement ~= nil then
            if not self:getIsLocalPlayerOnFoot() then
                self:cancelPlacement("limeDrop_place_cancelledVehicle")
            elseif self:getAreLocalPlayerHandsBusy() then
                self:cancelPlacement("limeDrop_place_cancelledHands")
            elseif not self:getIsValidFarmId(farmId) then
                self:cancelPlacement("limeDrop_place_cancelled")
            else
                self:updatePlacement()
            end
        end

        self:updateActionEventVisibility()
    end
end

function LimeDropZone:draw()
    if g_localPlayer == nil then
        return
    end
    if self.placement ~= nil then
        self:drawPlacement()
    end
    if not self.showMarkers then
        return
    end
    local px, _, pz = self:getLocalPlayerPosition()
    if px == nil then
        return
    end
    local farmId = self:getLocalFarmId()
    local maxDist = LimeDropZone.DRAW_DISTANCE
    for _, zone in pairs(self.zones) do
        if zone.farmId == farmId then
            local dx, dz = px - zone.x, pz - zone.z
            if dx * dx + dz * dz < maxDist * maxDist then
                self:drawZone(zone)
            end
        end
    end
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------

Mission00.loadMission00Finished = Utils.appendedFunction(Mission00.loadMission00Finished, function()
    LimeDropZone:loadFromSavegame()
end)

if InGameMenuSettingsFrame ~= nil and InGameMenuSettingsFrame.updateGameSettings ~= nil then
    InGameMenuSettingsFrame.updateGameSettings = Utils.appendedFunction(InGameMenuSettingsFrame.updateGameSettings, function()
        LimeDropZone:updateSettingsOptions()
    end)
end

FSBaseMission.saveSavegame = Utils.appendedFunction(FSBaseMission.saveSavegame, function()
    LimeDropZone:saveToSavegame()
end)

FSBaseMission.sendInitialClientState = Utils.appendedFunction(FSBaseMission.sendInitialClientState, function(mission, connection)
    if connection ~= nil then
        connection:sendEvent(LimeDropSyncEvent.new())
    end
end)

if PlayerInputComponent ~= nil and PlayerInputComponent.registerGlobalPlayerActionEvents ~= nil then
    PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
        PlayerInputComponent.registerGlobalPlayerActionEvents, LimeDropZone.registerActionEvents)
else
    Logging.error("[LimeDropZone] PlayerInputComponent.registerGlobalPlayerActionEvents not found, keybinds unavailable")
end

addModEventListener(LimeDropZone)
