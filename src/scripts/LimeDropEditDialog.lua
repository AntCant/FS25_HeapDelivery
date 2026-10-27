--
-- LimeDropEditDialog
-- Edit a spot: Size, Rename and Remove in one popup over the zone list.
-- Each button closes this popup and opens its own dialog; Back returns to the list.
--

LimeDropEditDialog = {}
local LimeDropEditDialog_mt = Class(LimeDropEditDialog, ScreenElement)

LimeDropEditDialog.NAME = "LimeDropEditDialog"
LimeDropEditDialog.INSTANCE = nil

function LimeDropEditDialog.register()
    local dialog = LimeDropEditDialog.new()
    g_gui:loadGui(LimeDropZone.MOD_DIR .. "gui/LimeDropEditDialog.xml", LimeDropEditDialog.NAME, dialog)
    LimeDropEditDialog.INSTANCE = dialog
    return dialog
end

function LimeDropEditDialog.show(zoneId)
    if LimeDropEditDialog.INSTANCE == nil then
        LimeDropEditDialog.register()
    end
    LimeDropEditDialog.INSTANCE.zoneId = zoneId
    g_gui:showDialog(LimeDropEditDialog.NAME)
end

function LimeDropEditDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or LimeDropEditDialog_mt)
    self.isCloseAllowed = true
    self.zoneId = nil
    return self
end

function LimeDropEditDialog:onOpen()
    if LimeDropEditDialog:superClass().onOpen ~= nil then
        LimeDropEditDialog:superClass().onOpen(self)
    end
    local mod = LimeDropZone
    local zone = mod.zones[self.zoneId or 0]
    if zone == nil then
        self:close()
        return
    end
    mod.subDialogOpen = true
    self.dialogTitleElement:setText(mod:getZoneName(zone))
    self.dialogTextElement:setText(mod.getText("limeDrop_edit_text"))
    self.sizeButton:setText(mod.getText("limeDrop_button_size"))
    self.renameButton:setText(mod.getText("limeDrop_button_rename"))
    self.removeButton:setText(mod.getText("limeDrop_button_remove"))
    LimeDropZone.resetDialogFocus(self.dialogElement, self.backButton)
    self.focusResetFrames = 2
end

function LimeDropEditDialog:update(dt)
    LimeDropEditDialog:superClass().update(self, dt)
    if self.focusResetFrames ~= nil then
        self.focusResetFrames = self.focusResetFrames - 1
        if self.focusResetFrames <= 0 then
            self.focusResetFrames = nil
            LimeDropZone.resetDialogFocus(self.dialogElement, self.backButton)
        end
    end
end

function LimeDropEditDialog:onClose()
    LimeDropZone.subDialogOpen = false
    LimeDropZone:requestMenuRefresh()
    if LimeDropEditDialog:superClass().onClose ~= nil then
        LimeDropEditDialog:superClass().onClose(self)
    end
end

---Closes this popup, then opens the next dialog for the same spot
function LimeDropEditDialog:switchTo(openFunc)
    local zoneId = self.zoneId
    self:close()
    if zoneId ~= nil and LimeDropZone.zones[zoneId] ~= nil then
        openFunc(zoneId)
    end
end

function LimeDropEditDialog:onClickSize()
    self:switchTo(function(zoneId)
        LimeDropZone:openSizeDialog(zoneId)
    end)
end

function LimeDropEditDialog:onClickRename()
    self:switchTo(function(zoneId)
        LimeDropZone:openRenameDialog(zoneId)
    end)
end

function LimeDropEditDialog:onClickRemove()
    self:switchTo(function(zoneId)
        LimeDropZone:openRemoveDialog(zoneId)
    end)
end

function LimeDropEditDialog:onClickBack(forceBack, usedMenuButton)
    self:close()
    return false
end

function LimeDropEditDialog:close()
    g_gui:closeDialogByName(LimeDropEditDialog.NAME)
end

function LimeDropEditDialog:getBlurArea()
    if self.dialogElement ~= nil then
        return self.dialogElement.absPosition[1], self.dialogElement.absPosition[2],
            self.dialogElement.absSize[1], self.dialogElement.absSize[2]
    end
end
