--
-- LimeDropZone network events
--

local function writeRect(streamId, rect)
    streamWriteFloat32(streamId, rect.x or 0)
    streamWriteFloat32(streamId, rect.z or 0)
    streamWriteFloat32(streamId, rect.width or 0)
    streamWriteFloat32(streamId, rect.length or 0)
    streamWriteFloat32(streamId, rect.yaw or 0)
end

---Field label data: field number, farmland number, letter index
local function writeLabel(streamId, zone)
    streamWriteInt32(streamId, zone.fieldId or 0)
    streamWriteInt32(streamId, zone.farmlandId or 0)
    streamWriteUInt8(streamId, zone.suffixIndex or 1)
end

local function readLabel(streamId, zone)
    zone.fieldId = streamReadInt32(streamId)
    zone.farmlandId = streamReadInt32(streamId)
    zone.suffixIndex = streamReadUInt8(streamId)
    return zone
end

local function writeHistoryEntry(streamId, entry)
    streamWriteUInt8(streamId, entry.farmId)
    streamWriteInt32(streamId, entry.day)
    streamWriteInt32(streamId, entry.minute)
    streamWriteInt32(streamId, entry.zoneId)
    streamWriteInt32(streamId, entry.fieldId)
    streamWriteInt32(streamId, entry.farmlandId)
    streamWriteUInt8(streamId, entry.suffixIndex)
    streamWriteString(streamId, entry.name or "")
    streamWriteInt32(streamId, entry.liters)
    streamWriteInt32(streamId, entry.delivered)
    streamWriteInt32(streamId, entry.paid)
    streamWriteInt32(streamId, entry.refund)
    streamWriteBool(streamId, entry.cancelled)
    streamWriteString(streamId, entry.fillTypeName or "LIME")
end

local function readHistoryEntry(streamId)
    local entry = {}
    entry.farmId = streamReadUInt8(streamId)
    entry.day = streamReadInt32(streamId)
    entry.minute = streamReadInt32(streamId)
    entry.zoneId = streamReadInt32(streamId)
    entry.fieldId = streamReadInt32(streamId)
    entry.farmlandId = streamReadInt32(streamId)
    entry.suffixIndex = streamReadUInt8(streamId)
    entry.name = streamReadString(streamId)
    entry.liters = streamReadInt32(streamId)
    entry.delivered = streamReadInt32(streamId)
    entry.paid = streamReadInt32(streamId)
    entry.refund = streamReadInt32(streamId)
    entry.cancelled = streamReadBool(streamId)
    entry.fillTypeName = streamReadString(streamId)
    return entry
end

local function readRect(streamId, rect)
    rect.x = streamReadFloat32(streamId)
    rect.z = streamReadFloat32(streamId)
    rect.width = streamReadFloat32(streamId)
    rect.length = streamReadFloat32(streamId)
    rect.yaw = streamReadFloat32(streamId)
    return rect
end

---------------------------------------------------------------------------
-- LimeDropZoneEvent: client -> server request to add/remove/rename/resize a zone,
-- server -> clients broadcast of the applied change
---------------------------------------------------------------------------

LimeDropZoneEvent = {}
LimeDropZoneEvent.ACTION_ADD = 1
LimeDropZoneEvent.ACTION_REMOVE = 2
LimeDropZoneEvent.ACTION_RENAME = 3
LimeDropZoneEvent.ACTION_RESIZE = 4
local LimeDropZoneEvent_mt = Class(LimeDropZoneEvent, Event)
InitEventClass(LimeDropZoneEvent, "LimeDropZoneEvent")

function LimeDropZoneEvent.emptyNew()
    return Event.new(LimeDropZoneEvent_mt)
end

---zone: { id, farmId, name, x, z, width, length, yaw } (fields not needed by the action may be nil)
function LimeDropZoneEvent.new(action, zone)
    local self = LimeDropZoneEvent.emptyNew()
    self.action = action
    self.zone = zone
    return self
end

function LimeDropZoneEvent:writeStream(streamId, connection)
    local zone = self.zone
    streamWriteUInt8(streamId, self.action)
    streamWriteInt32(streamId, zone.id or 0)
    streamWriteUInt8(streamId, zone.farmId or 0)
    streamWriteString(streamId, zone.name or "")
    writeLabel(streamId, zone)
    writeRect(streamId, zone)
end

function LimeDropZoneEvent:readStream(streamId, connection)
    self.action = streamReadUInt8(streamId)
    local zone = {}
    zone.id = streamReadInt32(streamId)
    zone.farmId = streamReadUInt8(streamId)
    zone.name = streamReadString(streamId)
    readLabel(streamId, zone)
    self.zone = readRect(streamId, zone)
    self:run(connection)
end

function LimeDropZoneEvent:run(connection)
    local zone = self.zone
    if connection:getIsServer() then
        -- we are a client, the server applied a change
        if self.action == LimeDropZoneEvent.ACTION_ADD then
            LimeDropZone:applyAddZone(zone, true)
        elseif self.action == LimeDropZoneEvent.ACTION_REMOVE then
            LimeDropZone:applyRemoveZone(zone.id, true)
            LimeDropZone:removeHistoryForZone(zone.id)
        elseif self.action == LimeDropZoneEvent.ACTION_RENAME then
            LimeDropZone:applyRenameZone(zone.id, zone.name, true)
        elseif self.action == LimeDropZoneEvent.ACTION_RESIZE then
            LimeDropZone:applyResizeZone(zone.id, zone.width, zone.length, true)
        end
    else
        -- we are the server, a client asked for a change
        local farmId = LimeDropZone:getFarmIdForConnection(connection, zone.farmId)
        if self.action == LimeDropZoneEvent.ACTION_ADD then
            LimeDropZone:serverAddZone(farmId, zone.x, zone.z, zone.width, zone.length, zone.yaw)
        elseif self.action == LimeDropZoneEvent.ACTION_REMOVE then
            LimeDropZone:serverRemoveZone(farmId, zone.id)
        elseif self.action == LimeDropZoneEvent.ACTION_RENAME then
            LimeDropZone:serverRenameZone(farmId, zone.id, zone.name)
        elseif self.action == LimeDropZoneEvent.ACTION_RESIZE then
            LimeDropZone:serverResizeZone(farmId, zone.id, zone.width, zone.length)
        end
    end
end

local function sendRequest(action, zone)
    g_client:getServerConnection():sendEvent(LimeDropZoneEvent.new(action, zone))
end

function LimeDropZoneEvent.sendAddRequest(farmId, rect)
    if g_server ~= nil then
        LimeDropZone:serverAddZone(farmId, rect.x, rect.z, rect.width, rect.length, rect.yaw)
    else
        sendRequest(LimeDropZoneEvent.ACTION_ADD, { farmId = farmId, x = rect.x, z = rect.z,
            width = rect.width, length = rect.length, yaw = rect.yaw })
    end
end

function LimeDropZoneEvent.sendRemoveRequest(farmId, zoneId)
    if g_server ~= nil then
        LimeDropZone:serverRemoveZone(farmId, zoneId)
    else
        sendRequest(LimeDropZoneEvent.ACTION_REMOVE, { id = zoneId, farmId = farmId })
    end
end

function LimeDropZoneEvent.sendRenameRequest(farmId, zoneId, name)
    if g_server ~= nil then
        LimeDropZone:serverRenameZone(farmId, zoneId, name)
    else
        sendRequest(LimeDropZoneEvent.ACTION_RENAME, { id = zoneId, farmId = farmId, name = name })
    end
end

function LimeDropZoneEvent.sendResizeRequest(farmId, zoneId, width, length)
    if g_server ~= nil then
        LimeDropZone:serverResizeZone(farmId, zoneId, width, length)
    else
        sendRequest(LimeDropZoneEvent.ACTION_RESIZE, { id = zoneId, farmId = farmId, width = width, length = length })
    end
end

---------------------------------------------------------------------------
-- LimeDropOrderEvent: client -> server order (product, amount, spot)
---------------------------------------------------------------------------

LimeDropOrderEvent = {}
local LimeDropOrderEvent_mt = Class(LimeDropOrderEvent, Event)
InitEventClass(LimeDropOrderEvent, "LimeDropOrderEvent")

function LimeDropOrderEvent.emptyNew()
    return Event.new(LimeDropOrderEvent_mt)
end

function LimeDropOrderEvent.new(farmId, zoneId, liters, fillTypeName)
    local self = LimeDropOrderEvent.emptyNew()
    self.farmId = farmId
    self.zoneId = zoneId
    self.liters = liters
    self.fillTypeName = fillTypeName
    return self
end

function LimeDropOrderEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.farmId)
    streamWriteInt32(streamId, self.zoneId)
    streamWriteInt32(streamId, self.liters)
    streamWriteString(streamId, self.fillTypeName or "LIME")
end

function LimeDropOrderEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt8(streamId)
    self.zoneId = streamReadInt32(streamId)
    self.liters = streamReadInt32(streamId)
    self.fillTypeName = streamReadString(streamId)
    self:run(connection)
end

function LimeDropOrderEvent:run(connection)
    if connection:getIsServer() then
        return
    end
    local farmId = LimeDropZone:getFarmIdForConnection(connection, self.farmId)
    LimeDropZone:serverPlaceOrder(farmId, self.zoneId, self.liters, self.fillTypeName)
end

function LimeDropOrderEvent.sendToServer(farmId, zoneId, liters, fillTypeName)
    if g_server ~= nil then
        LimeDropZone:serverPlaceOrder(farmId, zoneId, liters, fillTypeName)
    else
        g_client:getServerConnection():sendEvent(LimeDropOrderEvent.new(farmId, zoneId, liters, fillTypeName))
    end
end

---------------------------------------------------------------------------
-- LimeDropOrderStateEvent: server -> clients, order placed / delivered
---------------------------------------------------------------------------

LimeDropOrderStateEvent = {}
local LimeDropOrderStateEvent_mt = Class(LimeDropOrderStateEvent, Event)
InitEventClass(LimeDropOrderStateEvent, "LimeDropOrderStateEvent")

function LimeDropOrderStateEvent.emptyNew()
    return Event.new(LimeDropOrderStateEvent_mt)
end

function LimeDropOrderStateEvent.new(order, state, amount, spilled)
    local self = LimeDropOrderStateEvent.emptyNew()
    self.order = order
    self.state = state
    self.amount = amount
    self.spilled = spilled or 0
    return self
end

local function writeOrder(streamId, order)
    streamWriteInt32(streamId, order.id)
    streamWriteUInt8(streamId, order.farmId)
    streamWriteInt32(streamId, order.zoneId)
    streamWriteInt32(streamId, order.liters)
    streamWriteInt32(streamId, math.floor(order.remainingMs))
    writeRect(streamId, order)
    streamWriteFloat32(streamId, order.pricePerLiter or 0)
    streamWriteInt32(streamId, math.floor(order.price or 0))
    streamWriteString(streamId, order.fillTypeName or "LIME")
end

local function readOrder(streamId)
    local order = {}
    order.id = streamReadInt32(streamId)
    order.farmId = streamReadUInt8(streamId)
    order.zoneId = streamReadInt32(streamId)
    order.liters = streamReadInt32(streamId)
    order.remainingMs = streamReadInt32(streamId)
    readRect(streamId, order)
    order.pricePerLiter = streamReadFloat32(streamId)
    order.price = streamReadInt32(streamId)
    order.fillTypeName = streamReadString(streamId)
    return order
end

function LimeDropOrderStateEvent:writeStream(streamId, connection)
    writeOrder(streamId, self.order)
    streamWriteUInt8(streamId, self.state)
    streamWriteFloat32(streamId, self.amount)
    streamWriteFloat32(streamId, self.spilled or 0)
end

function LimeDropOrderStateEvent:readStream(streamId, connection)
    self.order = readOrder(streamId)
    self.state = streamReadUInt8(streamId)
    self.amount = streamReadFloat32(streamId)
    self.spilled = streamReadFloat32(streamId)
    self:run(connection)
end

function LimeDropOrderStateEvent:run(connection)
    if connection:getIsServer() then
        LimeDropZone:onOrderState(self.order, self.state, self.amount, self.spilled)
    end
end

---------------------------------------------------------------------------
-- LimeDropSyncEvent: server -> joining client, full state
---------------------------------------------------------------------------

LimeDropSyncEvent = {}
local LimeDropSyncEvent_mt = Class(LimeDropSyncEvent, Event)
InitEventClass(LimeDropSyncEvent, "LimeDropSyncEvent")

function LimeDropSyncEvent.emptyNew()
    return Event.new(LimeDropSyncEvent_mt)
end

function LimeDropSyncEvent.new()
    return LimeDropSyncEvent.emptyNew()
end

function LimeDropSyncEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, #LimeDropZone.SETTINGS)
    for _, def in ipairs(LimeDropZone.SETTINGS) do
        streamWriteString(streamId, def.key)
        streamWriteFloat32(streamId, LimeDropZone:getSetting(def.key))
    end
    local zones, orders = {}, {}
    for _, zone in pairs(LimeDropZone.zones) do
        table.insert(zones, zone)
    end
    for _, order in pairs(LimeDropZone.orders) do
        table.insert(orders, order)
    end

    streamWriteInt32(streamId, #zones)
    for _, zone in ipairs(zones) do
        streamWriteInt32(streamId, zone.id)
        streamWriteUInt8(streamId, zone.farmId)
        streamWriteString(streamId, zone.name or "")
        writeLabel(streamId, zone)
        writeRect(streamId, zone)
    end

    streamWriteInt32(streamId, #orders)
    for _, order in ipairs(orders) do
        writeOrder(streamId, order)
    end

    streamWriteInt32(streamId, #LimeDropZone.history)
    for _, entry in ipairs(LimeDropZone.history) do
        writeHistoryEntry(streamId, entry)
    end
end

function LimeDropSyncEvent:readStream(streamId, connection)
    self.settings = {}
    local numSettings = streamReadUInt8(streamId)
    for _ = 1, numSettings do
        local key = streamReadString(streamId)
        self.settings[key] = streamReadFloat32(streamId)
    end
    self.zones, self.orders = {}, {}

    local numZones = streamReadInt32(streamId)
    for _ = 1, numZones do
        local zone = {}
        zone.id = streamReadInt32(streamId)
        zone.farmId = streamReadUInt8(streamId)
        zone.name = streamReadString(streamId)
        readLabel(streamId, zone)
        readRect(streamId, zone)
        table.insert(self.zones, zone)
    end

    local numOrders = streamReadInt32(streamId)
    for _ = 1, numOrders do
        table.insert(self.orders, readOrder(streamId))
    end

    self.history = {}
    local numHistory = streamReadInt32(streamId)
    for _ = 1, numHistory do
        table.insert(self.history, readHistoryEntry(streamId))
    end

    self:run(connection)
end

function LimeDropSyncEvent:run(connection)
    if connection:getIsServer() then
        for key, value in pairs(self.settings) do
            LimeDropZone:applySetting(key, value)
        end
        LimeDropZone:applySync(self.zones, self.orders)
        LimeDropZone.history = self.history
    end
end

---------------------------------------------------------------------------
-- LimeDropHistoryEvent: server -> clients, one finished delivery
---------------------------------------------------------------------------

LimeDropHistoryEvent = {}
local LimeDropHistoryEvent_mt = Class(LimeDropHistoryEvent, Event)
InitEventClass(LimeDropHistoryEvent, "LimeDropHistoryEvent")

function LimeDropHistoryEvent.emptyNew()
    return Event.new(LimeDropHistoryEvent_mt)
end

function LimeDropHistoryEvent.new(entry)
    local self = LimeDropHistoryEvent.emptyNew()
    self.entry = entry
    return self
end

function LimeDropHistoryEvent:writeStream(streamId, connection)
    writeHistoryEntry(streamId, self.entry)
end

function LimeDropHistoryEvent:readStream(streamId, connection)
    self.entry = readHistoryEntry(streamId)
    self:run(connection)
end

function LimeDropHistoryEvent:run(connection)
    if connection:getIsServer() then
        LimeDropZone:applyHistoryEntry(self.entry)
    end
end

---------------------------------------------------------------------------
-- LimeDropSettingsEvent: one setting changed (client -> server request, server -> clients)
---------------------------------------------------------------------------

LimeDropSettingsEvent = {}
local LimeDropSettingsEvent_mt = Class(LimeDropSettingsEvent, Event)
InitEventClass(LimeDropSettingsEvent, "LimeDropSettingsEvent")

function LimeDropSettingsEvent.emptyNew()
    return Event.new(LimeDropSettingsEvent_mt)
end

function LimeDropSettingsEvent.new(key, value)
    local self = LimeDropSettingsEvent.emptyNew()
    self.key = key
    self.value = value
    return self
end

function LimeDropSettingsEvent:writeStream(streamId, connection)
    streamWriteString(streamId, self.key)
    streamWriteFloat32(streamId, self.value)
end

function LimeDropSettingsEvent:readStream(streamId, connection)
    self.key = streamReadString(streamId)
    self.value = streamReadFloat32(streamId)
    self:run(connection)
end

function LimeDropSettingsEvent:run(connection)
    if connection:getIsServer() then
        LimeDropZone:applySetting(self.key, self.value)
    else
        LimeDropZone:serverSetSetting(self.key, self.value, connection)
    end
end
