--
-- LimeDropSizeDialog
-- Size picker for one spot, opened on top of the zone list (Back returns to the list).
--

LimeDropSizeDialog = {}
local LimeDropSizeDialog_mt = Class(LimeDropSizeDialog, ScreenElement)

LimeDropSizeDialog.NAME = "LimeDropSizeDialog"
LimeDropSizeDialog.INSTANCE = nil

function LimeDropSizeDialog.register()
    local dialog = LimeDropSizeDialog.new()
    g_gui:loadGui(LimeDropZone.MOD_DIR .. "gui/LimeDropSizeDialog.xml", LimeDropSizeDialog.NAME, dialog)
    LimeDropSizeDialog.INSTANCE = dialog
    return dialog
end

function LimeDropSizeDialog.show(zoneId)
    if LimeDropSizeDialog.INSTANCE == nil then
        LimeDropSizeDialog.register()
    end
    LimeDropSizeDialog.INSTANCE.zoneId = zoneId
    g_gui:showDialog(LimeDropSizeDialog.NAME)
end

function LimeDropSizeDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or LimeDropSizeDialog_mt)
    self.isCloseAllowed = true
    self.zoneId = nil
    self.options = {}
    self.shownState = nil
    return self
end

function LimeDropSizeDialog:onOpen()
    if LimeDropSizeDialog:superClass().onOpen ~= nil then
        LimeDropSizeDialog:superClass().onOpen(self)
    end
    LimeDropZone.subDialogOpen = true
    self:rebuild()
end

function LimeDropSizeDialog:onClose()
    LimeDropZone.subDialogOpen = false
    LimeDropZone:requestMenuRefresh()
    if LimeDropSizeDialog:superClass().onClose ~= nil then
        LimeDropSizeDialog:superClass().onClose(self)
    end
end

function LimeDropSizeDialog:rebuild()
    local mod = LimeDropZone
    local zone = mod.zones[self.zoneId or 0]
    if zone == nil then
        self:close()
        return
    end

    self.dialogTitleElement:setText(mod:getZoneName(zone))
    self.dialogTextElement:setText(mod.getText("limeDrop_sizes_text"))
    self.yesButton:setText(mod.getText("limeDrop_button_select"))

    self.options = mod:getSizeOptions(zone)
    local texts, current = {}, 1
    for i, option in ipairs(self.options) do
        texts[i] = mod.formatSize(option.width, option.length)
        if option.isCurrent then
            current = i
        end
    end
    self.sizesElement:setTexts(texts)
    self.sizesElement:setState(current, false)
    self.sizesElement.onClickCallback = function(_, state)
        self:updateSelection(state)
    end
    self:updateSelection(current)
    FocusManager:setFocus(self.sizesElement)
end

---Info line and Select button for the chosen size
function LimeDropSizeDialog:updateSelection(index)
    local mod = LimeDropZone
    local option = self.options[index]
    self.shownState = index
    if option == nil then
        return
    end
    if option.isCurrent then
        self.infoElement:setText(mod.getText("limeDrop_size_currentInfo"))
        self.yesButton:setDisabled(true)
    elseif option.isBlocked then
        self.infoElement:setText(string.format(mod.getText("limeDrop_size_blockedInfo"), option.blockedText or ""))
        self.yesButton:setDisabled(true)
    else
        self.infoElement:setText("")
        self.yesButton:setDisabled(false)
    end
end

---Keeps the info line in step with the selector however it was changed
function LimeDropSizeDialog:update(dt)
    LimeDropSizeDialog:superClass().update(self, dt)
    if self.sizesElement ~= nil and #self.options > 0 then
        local state = self.sizesElement:getState()
        if state ~= self.shownState then
            self:updateSelection(state)
        end
    end
end

function LimeDropSizeDialog:onClickOk()
    local option = self.options[self.sizesElement:getState()]
    local zoneId = self.zoneId
    if option == nil or option.isCurrent or option.isBlocked or zoneId == nil then
        return false
    end
    self:close()
    LimeDropZone:resizeZone(zoneId, option.width, option.length)
    return false
end

function LimeDropSizeDialog:onClickBack(forceBack, usedMenuButton)
    self:close()
    return false
end

function LimeDropSizeDialog:close()
    g_gui:closeDialogByName(LimeDropSizeDialog.NAME)
end

function LimeDropSizeDialog:getBlurArea()
    if self.dialogElement ~= nil then
        return self.dialogElement.absPosition[1], self.dialogElement.absPosition[2],
            self.dialogElement.absSize[1], self.dialogElement.absSize[2]
    end
end
