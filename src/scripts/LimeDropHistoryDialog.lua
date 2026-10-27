--
-- LimeDropHistoryDialog
-- Deliveries of one spot, newest first. Opened with the History button of a zone row.
--

LimeDropHistoryDialog = {}
local LimeDropHistoryDialog_mt = Class(LimeDropHistoryDialog, ScreenElement)

LimeDropHistoryDialog.NAME = "LimeDropHistoryDialog"
LimeDropHistoryDialog.INSTANCE = nil
LimeDropHistoryDialog.ROW_COLOR_ODD = { 1, 1, 1, 0.04 }
LimeDropHistoryDialog.ROW_COLOR_EVEN = { 1, 1, 1, 0.08 }
LimeDropHistoryDialog.COLOR_PAID = { 0.88, 0.2, 0.12, 1 }
LimeDropHistoryDialog.COLOR_REFUND = { 0.55, 0.85, 0.25, 1 }

function LimeDropHistoryDialog.register()
    local dialog = LimeDropHistoryDialog.new()
    g_gui:loadGui(LimeDropZone.MOD_DIR .. "gui/LimeDropHistoryDialog.xml", LimeDropHistoryDialog.NAME, dialog)
    LimeDropHistoryDialog.INSTANCE = dialog
    return dialog
end

function LimeDropHistoryDialog.show(zoneId)
    if LimeDropHistoryDialog.INSTANCE == nil then
        LimeDropHistoryDialog.register()
    end
    LimeDropHistoryDialog.INSTANCE.zoneId = zoneId
    g_gui:showDialog(LimeDropHistoryDialog.NAME)
end

---Rebuilds the list if it is open (a delivery finished)
function LimeDropHistoryDialog.refresh()
    local dialog = LimeDropHistoryDialog.INSTANCE
    if dialog ~= nil and dialog.isShowing then
        dialog:rebuildList()
    end
end

function LimeDropHistoryDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or LimeDropHistoryDialog_mt)
    self.isCloseAllowed = true
    return self
end

function LimeDropHistoryDialog:onCreate()
    if LimeDropHistoryDialog:superClass().onCreate ~= nil then
        LimeDropHistoryDialog:superClass().onCreate(self)
    end
    -- the row in the XML is only a template that gets cloned
    if self.scrollingLayoutItem ~= nil then
        self.scrollingLayoutItem:unlinkElement()
        FocusManager:removeElement(self.scrollingLayoutItem)
    end
end

function LimeDropHistoryDialog:delete()
    if self.scrollingLayoutItem ~= nil then
        self.scrollingLayoutItem:delete()
    end
    if LimeDropHistoryDialog:superClass().delete ~= nil then
        LimeDropHistoryDialog:superClass().delete(self)
    end
end

function LimeDropHistoryDialog:onOpen()
    if LimeDropHistoryDialog:superClass().onOpen ~= nil then
        LimeDropHistoryDialog:superClass().onOpen(self)
    end
    self.isShowing = true
    LimeDropZone.subDialogOpen = true
    self:rebuildList()
end

function LimeDropHistoryDialog:onClose()
    self.isShowing = false
    LimeDropZone.subDialogOpen = false
    LimeDropZone:requestMenuRefresh()
    self:clearRows()
    if LimeDropHistoryDialog:superClass().onClose ~= nil then
        LimeDropHistoryDialog:superClass().onClose(self)
    end
end

function LimeDropHistoryDialog:clearRows()
    if self.scrollingLayoutElement == nil then
        return
    end
    for i = #self.scrollingLayoutElement.elements, 1, -1 do
        local element = self.scrollingLayoutElement.elements[i]
        if element ~= self.scrollingLayoutItem then
            element:delete()
        end
    end
end

---right / rightSub: { text, color } shown on the right of the row (paid, refund); icon: product image or nil
function LimeDropHistoryDialog:addRow(index, title, info, right, rightSub, icon)
    local item = self.scrollingLayoutItem:clone(self.scrollingLayoutElement)
    local color = index % 2 == 0 and LimeDropHistoryDialog.ROW_COLOR_EVEN or LimeDropHistoryDialog.ROW_COLOR_ODD
    item:setImageColor(nil, color[1], color[2], color[3], color[4])
    item:getDescendantByName("title"):setText(title)
    item:getDescendantByName("info"):setText(info or "")
    local iconElement = item:getDescendantByName("icon")
    if icon ~= nil then
        iconElement:setImageFilename(icon)
        iconElement:setVisible(true)
    else
        iconElement:setVisible(false)
    end
    for name, value in pairs({ right = right or false, rightSub = rightSub or false }) do
        local element = item:getDescendantByName(name)
        if value then
            element:setText(value[1])
            element:setTextColor(value[2][1], value[2][2], value[2][3], value[2][4])
        else
            element:setText("")
        end
    end
end

function LimeDropHistoryDialog:rebuildList()
    if self.scrollingLayoutElement == nil or self.scrollingLayoutItem == nil then
        return
    end
    self:clearRows()

    local mod = LimeDropZone
    local zone = mod.zones[self.zoneId or 0]
    self.headerTextElement:setText(zone ~= nil and mod:getZoneName(zone) or "")
    self.subHeaderTextElement:setText(string.format(mod.getText("limeDrop_history_text"), LimeDropZone.MAX_HISTORY_PER_ZONE))

    local entries = mod:getHistoryForZone(self.zoneId)
    if #entries == 0 then
        self:addRow(1, mod.getText("limeDrop_history_empty"), mod.getText("limeDrop_history_emptyInfo"))
    end
    for index, entry in ipairs(entries) do
        local productTitle, icon = mod:getFillTypeDisplay(entry.fillTypeName)
        local title = string.format("%s  -  %s %s", mod:formatHistoryTime(entry), productTitle, mod.formatLiters(entry.liters))
        local parts = {}
        if entry.cancelled then
            table.insert(parts, mod.getText("limeDrop_history_cancelled"))
        else
            table.insert(parts, string.format(mod.getText("limeDrop_history_delivered"), mod.formatLiters(entry.delivered)))
        end
        local paid = { "-" .. mod.formatMoney(entry.paid), LimeDropHistoryDialog.COLOR_PAID }
        local refund = entry.refund > 0 and { "+" .. mod.formatMoney(entry.refund), LimeDropHistoryDialog.COLOR_REFUND } or nil
        self:addRow(index, title, table.concat(parts, "  |  "), paid, refund, icon)
    end

    self.scrollingLayoutElement:invalidateLayout(true)
    if self.backButton ~= nil then
        FocusManager:setFocus(self.backButton)
    end
end

function LimeDropHistoryDialog:onClickBack(forceBack, usedMenuButton)
    self:close()
    return false
end

function LimeDropHistoryDialog:close()
    g_gui:closeDialogByName(LimeDropHistoryDialog.NAME)
end

function LimeDropHistoryDialog:getBlurArea()
    if self.dialogElement ~= nil then
        return self.dialogElement.absPosition[1], self.dialogElement.absPosition[2],
            self.dialogElement.absSize[1], self.dialogElement.absSize[2]
    end
end
