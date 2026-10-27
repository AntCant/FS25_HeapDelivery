--
-- LimeDropMenuDialog
-- Scrollable list of the farm's lime drop zones with Order / History / Edit
-- buttons per row. Order, History and Edit (Size / Rename / Remove) each open a dialog on top of the list.
--

LimeDropMenuDialog = {}
local LimeDropMenuDialog_mt = Class(LimeDropMenuDialog, ScreenElement)

LimeDropMenuDialog.NAME = "LimeDropMenuDialog"
LimeDropMenuDialog.INSTANCE = nil
LimeDropMenuDialog.VIEW_ZONES = 1
LimeDropMenuDialog.NUM_ROW_BUTTONS = 3

LimeDropMenuDialog.ROW_COLOR_ODD = { 1, 1, 1, 0.04 }
LimeDropMenuDialog.ROW_COLOR_EVEN = { 1, 1, 1, 0.08 }
LimeDropMenuDialog.INFO_UPDATE_MS = 500
LimeDropMenuDialog.COLOR_WARNING = { 0.88, 0.2, 0.12, 1 }
LimeDropMenuDialog.INFO_SEPARATOR = "  |  "

function LimeDropMenuDialog.register()
    local dialog = LimeDropMenuDialog.new()
    g_gui:loadGui(LimeDropZone.MOD_DIR .. "gui/LimeDropMenuDialog.xml", LimeDropMenuDialog.NAME, dialog)
    LimeDropMenuDialog.INSTANCE = dialog
    return dialog
end

function LimeDropMenuDialog.show()
    if LimeDropMenuDialog.INSTANCE == nil then
        LimeDropMenuDialog.register()
    end
    local dialog = LimeDropMenuDialog.INSTANCE
    dialog.view = LimeDropMenuDialog.VIEW_ZONES
    dialog.zoneId = nil
    g_gui:showDialog(LimeDropMenuDialog.NAME)
end

---Rebuilds the list if the dialog is open (zones or orders changed)
function LimeDropMenuDialog.refresh()
    local dialog = LimeDropMenuDialog.INSTANCE
    if dialog == nil or not dialog.isShowing then
        return
    end
    dialog:rebuildList()
end

function LimeDropMenuDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or LimeDropMenuDialog_mt)
    self.isCloseAllowed = true
    self.view = LimeDropMenuDialog.VIEW_ZONES
    self.zoneId = nil
    return self
end

function LimeDropMenuDialog:onCreate()
    if LimeDropMenuDialog:superClass().onCreate ~= nil then
        LimeDropMenuDialog:superClass().onCreate(self)
    end
    -- the row in the XML is only a template that gets cloned
    if self.scrollingLayoutItem ~= nil then
        self.scrollingLayoutItem:unlinkElement()
        FocusManager:removeElement(self.scrollingLayoutItem)
    end
end

function LimeDropMenuDialog:delete()
    if self.scrollingLayoutItem ~= nil then
        self.scrollingLayoutItem:delete()
    end
    if LimeDropMenuDialog:superClass().delete ~= nil then
        LimeDropMenuDialog:superClass().delete(self)
    end
end

function LimeDropMenuDialog:onOpen()
    if LimeDropMenuDialog:superClass().onOpen ~= nil then
        LimeDropMenuDialog:superClass().onOpen(self)
    end
    self.isShowing = true
    self:rebuildList()
end

function LimeDropMenuDialog:update(dt)
    LimeDropMenuDialog:superClass().update(self, dt)
    -- the game restores the old focus after opening, so the reset runs again a moment later
    if self.focusResetFrames ~= nil then
        self.focusResetFrames = self.focusResetFrames - 1
        if self.focusResetFrames <= 0 then
            self.focusResetFrames = nil
            LimeDropZone.resetDialogFocus(self.dialogElement, self.backButton)
        end
    end
    -- keeps "arrives in ..." counting down while the list is open
    self.infoTimer = (self.infoTimer or 0) + dt
    if self.infoTimer >= LimeDropMenuDialog.INFO_UPDATE_MS then
        self.infoTimer = 0
        self:updateRowInfo()
    end
end

---Refreshes the info line of each row in place (no rebuild, so scroll and focus stay)
function LimeDropMenuDialog:updateRowInfo()
    if self.rowInfo == nil or next(self.rowInfo) == nil then
        return
    end
    for _, entry in ipairs(LimeDropZone:getMenuEntries()) do
        local row = self.rowInfo[entry.zoneId]
        if row ~= nil then
            self:setRowInfo(row, entry.info, entry.warning)
        end
    end
end

function LimeDropMenuDialog:onClose()
    self.isShowing = false
    self:clearRows()
    if LimeDropMenuDialog:superClass().onClose ~= nil then
        LimeDropMenuDialog:superClass().onClose(self)
    end
end

function LimeDropMenuDialog:clearRows()
    self.rowInfo = {}
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

---Adds a row; buttons is a list of { text, callback, disabled } (unused buttons are hidden)
function LimeDropMenuDialog:addRow(index, title, info, buttons)
    local item = self.scrollingLayoutItem:clone(self.scrollingLayoutElement)
    local color = index % 2 == 0 and LimeDropMenuDialog.ROW_COLOR_EVEN or LimeDropMenuDialog.ROW_COLOR_ODD
    item:setImageColor(nil, color[1], color[2], color[3], color[4])

    local titleElement = item:getDescendantByName("title")
    if titleElement ~= nil then
        titleElement:setText(title)
    end
    local infoElement = item:getDescendantByName("info")
    if infoElement ~= nil then
        infoElement:setText(info or "")
    end

    local firstButton = nil
    for i = 1, LimeDropMenuDialog.NUM_ROW_BUTTONS do
        local button = item:getDescendantByName("button" .. i)
        if button ~= nil then
            local def = buttons[i]
            if def ~= nil then
                button:setText(def.text)
                button.onClickCallback = def.callback
                button:setDisabled(def.disabled == true)
                if firstButton == nil and def.disabled ~= true then
                    firstButton = button
                end
            else
                button:setVisible(false)
                button:setDisabled(true)
            end
        end
    end
    return firstButton, infoElement, item:getDescendantByName("status")
end

---Info line of a row; a warning (zone full, land not owned) follows it in red
function LimeDropMenuDialog:setRowInfo(row, info, warning)
    local key = info .. "\0" .. (warning or "")
    if row.key == key then
        return
    end
    row.key = key
    if warning == nil then
        row.info:setText(info)
        row.status:setText("")
        return
    end
    local lead = info .. LimeDropMenuDialog.INFO_SEPARATOR
    row.info:setText(lead)
    setTextBold(row.info.textBold == true)
    local width = getTextWidth(row.info.textSize, lead)
    setTextBold(false)
    row.status:setPosition(row.info.position[1] + width, row.info.position[2])
    local color = LimeDropMenuDialog.COLOR_WARNING
    row.status:setTextColor(color[1], color[2], color[3], color[4])
    row.status:setText(warning)
end

function LimeDropMenuDialog:rebuildList()
    if self.scrollingLayoutElement == nil or self.scrollingLayoutItem == nil then
        return
    end
    self:clearRows()

    self:buildZoneRows()

    self:updateBottomButtons()
    self.scrollingLayoutElement:invalidateLayout(true)
    self.infoTimer = 0
    LimeDropZone.resetDialogFocus(self.dialogElement, self.backButton)
    self.focusResetFrames = 2
end

function LimeDropMenuDialog:updateBottomButtons()
    local mod = LimeDropZone
    if self.newZoneButton ~= nil then
        self.newZoneButton:setText(mod.getText("limeDrop_button_newZone"))
    end
    if self.helpButton ~= nil then
        self.helpButton:setText(mod.getText("limeDrop_button_help"))
    end
    if self.markersButton ~= nil then
        self.markersButton:setText(mod.getText(mod.showMarkers and "limeDrop_button_hideMarkers" or "limeDrop_button_showMarkers"))
    end
end

function LimeDropMenuDialog:onClickNewZone()
    if LimeDropZone:requestPlacement() then
        self:close()
    end
end

function LimeDropMenuDialog:onClickHelp()
    LimeDropHelpDialog.show()
end

function LimeDropMenuDialog:onClickToggleMarkers()
    LimeDropZone:setShowMarkers(not LimeDropZone.showMarkers)
    self:updateBottomButtons()
end

function LimeDropMenuDialog:buildZoneRows()
    local mod = LimeDropZone
    self.headerTextElement:setText(mod.getText("limeDrop_menu_title"))
    self.subHeaderTextElement:setText(mod.getText("limeDrop_menu_text"))

    local entries = mod:getMenuEntries()
    if #entries == 0 then
        self:addRow(1, mod.getText("limeDrop_menu_empty"), mod.getText("limeDrop_menu_emptyInfo"), {})
        return nil
    end

    local firstButton
    for index, entry in ipairs(entries) do
        local zoneId = entry.zoneId
        local button, infoElement, statusElement = self:addRow(index, entry.name, entry.info, {
            {
                text = mod.getText("limeDrop_button_order"),
                disabled = not entry.canOrder,
                callback = function()
                    mod:openOrderDialog(zoneId)
                end
            },
            {
                text = mod.getText("limeDrop_button_history"),
                callback = function()
                    mod:openHistory(zoneId)
                end
            },
            {
                text = mod.getText("limeDrop_button_edit"),
                callback = function()
                    mod:openEditDialog(zoneId)
                end
            }
        })
        firstButton = firstButton or button
        local row = { info = infoElement, status = statusElement }
        self:setRowInfo(row, entry.info, entry.warning)
        self.rowInfo[zoneId] = row
    end
    return firstButton
end

function LimeDropMenuDialog:showView(view, zoneId)
    self.view = view
    self.zoneId = zoneId
    self:rebuildList()
end

---Back from the sizes goes to the zone list, back from the zone list closes
function LimeDropMenuDialog:onClickBack(forceBack, usedMenuButton)
    if self.view ~= LimeDropMenuDialog.VIEW_ZONES and not forceBack then
        self:showView(LimeDropMenuDialog.VIEW_ZONES)
        return false
    end
    self:close()
    return false
end

function LimeDropMenuDialog:close()
    g_gui:closeDialogByName(LimeDropMenuDialog.NAME)
end

function LimeDropMenuDialog:getBlurArea()
    if self.dialogElement ~= nil then
        return self.dialogElement.absPosition[1], self.dialogElement.absPosition[2],
            self.dialogElement.absSize[1], self.dialogElement.absSize[2]
    end
end
