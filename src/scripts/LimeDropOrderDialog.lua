--
-- LimeDropOrderDialog
-- Order dialog for one spot: product selector and amount slider, laid out like the
-- base game's refill (buy) dialog. Opens on top of the zone list.
--

LimeDropOrderDialog = {}
local LimeDropOrderDialog_mt = Class(LimeDropOrderDialog, ScreenElement)

LimeDropOrderDialog.NAME = "LimeDropOrderDialog"
LimeDropOrderDialog.INSTANCE = nil

function LimeDropOrderDialog.register()
    local dialog = LimeDropOrderDialog.new()
    g_gui:loadGui(LimeDropZone.MOD_DIR .. "gui/LimeDropOrderDialog.xml", LimeDropOrderDialog.NAME, dialog)
    LimeDropOrderDialog.INSTANCE = dialog
    return dialog
end

function LimeDropOrderDialog.show(zoneId)
    if LimeDropOrderDialog.INSTANCE == nil then
        LimeDropOrderDialog.register()
    end
    local dialog = LimeDropOrderDialog.INSTANCE
    dialog.zoneId = zoneId
    g_gui:showDialog(LimeDropOrderDialog.NAME)
end

function LimeDropOrderDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or LimeDropOrderDialog_mt)
    self.isCloseAllowed = true
    self.zoneId = nil
    self.fillTypes = {}
    self.amounts = {}
    self.shownState = nil
    return self
end

function LimeDropOrderDialog:onOpen()
    if LimeDropOrderDialog:superClass().onOpen ~= nil then
        LimeDropOrderDialog:superClass().onOpen(self)
    end
    -- keep the zone list underneath from rebuilding (and taking focus) while this is open
    LimeDropZone.subDialogOpen = true
    self:rebuild()
end

function LimeDropOrderDialog:onClose()
    LimeDropZone.subDialogOpen = false
    LimeDropZone:requestMenuRefresh()
    if LimeDropOrderDialog:superClass().onClose ~= nil then
        LimeDropOrderDialog:superClass().onClose(self)
    end
end

---Fills the product list and the amount slider for the spot
function LimeDropOrderDialog:rebuild()
    local mod = LimeDropZone
    local zone = mod.zones[self.zoneId or 0]
    if zone == nil then
        self:close()
        return
    end

    self.dialogTitleElement:setText(mod:getZoneName(zone))
    self.dialogTextElement:setText(string.format(mod.getText("limeDrop_order_text"),
        mod.formatDuration(mod:getDeliveryDelayMs()), mod.formatPercent(mod:getSetting("deliveryFee"))))

    -- products: every heap type in LimeDropZone.PRODUCTS; starts on the one already lying in the spot
    self.products = mod:getProducts()
    self.fillTypes = {}
    local texts = {}
    local startIndex = 1
    local contentName = mod:getZoneContents(zone)
    for i, product in ipairs(self.products) do
        table.insert(self.fillTypes, product.name)
        table.insert(texts, product.title)
        if product.name == contentName then
            startIndex = i
        end
    end
    if #texts == 0 then
        texts = { "-" }
    end
    self.fillTypesElement:setTexts(texts)
    self.fillTypesElement:setState(startIndex, false)
    self.fillTypesElement:setDisabled(#self.products <= 1)
    self:selectProduct(startIndex)
end

---Product picked in the selector: icon, slider amounts and receipt follow it
function LimeDropOrderDialog:selectProduct(index)
    self.shownFillTypeIndex = index
    self.shownState = nil
    local product = self.products ~= nil and self.products[index] or nil
    self.fillTypeName = product ~= nil and product.name or nil
    if product ~= nil and product.icon ~= nil then
        self.fillTypeIconElement:setImageFilename(product.icon)
        self.fillTypeIconElement:setVisible(true)
    else
        self.fillTypeIconElement:setVisible(false)
    end
    local zone = LimeDropZone.zones[self.zoneId or 0]
    if zone ~= nil then
        self:updateAmounts(zone)
    end
end

---Slider steps: AMOUNT_STEP up to the room left, each labelled with the liters and the total price
function LimeDropOrderDialog:updateAmounts(zone)
    local mod = LimeDropZone
    local fillTypeName = self.fillTypeName
    local steps, _, blockingName = {}, 0, nil
    if fillTypeName ~= nil then
        steps, _, blockingName = mod:getAmountSteps(zone, fillTypeName)
    end
    self.amounts = steps

    local isEmpty = #steps == 0
    self.fillAmountsElement:setDisabled(isEmpty)
    self.stepDownButton:setDisabled(isEmpty)
    self.stepUpButton:setDisabled(isEmpty)
    self.yesButton:setDisabled(isEmpty)
    self.warningElement:setVisible(isEmpty)
    self.breakdownElement:setVisible(not isEmpty)
    self.yesButton:setText(mod.getText("limeDrop_button_order"))

    if isEmpty then
        self.fillAmountsElement:setTexts({ "-" })
        self.fillAmountsElement:setState(1, false)
        if blockingName ~= nil then
            self.warningElement:setText(string.format(mod.getText("limeDrop_order_otherProduct"), (mod:getFillTypeDisplay(blockingName))))
        else
            self.warningElement:setText(mod.getText("limeDrop_order_full"))
        end
        -- with several products the player can still switch to one that fits
        FocusManager:setFocus(#self.fillTypes > 1 and self.fillTypesElement or self.noButton)
        return
    end

    local texts = {}
    for i, liters in ipairs(steps) do
        texts[i] = string.format(mod.getText("limeDrop_order_amount"), mod.formatLiters(liters), mod.formatMoney(mod:getOrderPrice(liters, fillTypeName)))
    end
    self.fillAmountsElement:setTexts(texts)
    self.fillAmountsElement.onClickCallback = function(_, state)
        self:updateBreakdown(state)
    end
    -- start at the most the spot can take
    self.fillAmountsElement:setState(#steps, false)
    self:updateBreakdown(#steps)
    FocusManager:setFocus(self.fillAmountsElement)
end

---Receipt under the slider for the selected amount (first line is the product):
--   Lime            $21,600
--   Delivery (5%)    $1,080
--   ----------------------
--   Total           $22,680
function LimeDropOrderDialog:updateBreakdown(index)
    local mod = LimeDropZone
    local liters = self.amounts[index]
    self.shownState = index
    if liters == nil then
        return
    end
    local fillTypeName = self.fillTypeName
    local total = mod:getOrderPrice(liters, fillTypeName)
    local productCost = math.min(total, math.ceil(liters * mod:getPricePerLiter(fillTypeName)))
    self.bdLimeLabel:setText((mod:getFillTypeDisplay(fillTypeName)))
    self.bdLimeValue:setText(mod.formatMoney(productCost))
    self.bdFeeLabel:setText(string.format(mod.getText("limeDrop_order_fee"), mod.formatPercent(mod:getSetting("deliveryFee"))))
    self.bdFeeValue:setText(mod.formatMoney(total - productCost))
    self.bdTotalLabel:setText(mod.getText("limeDrop_order_total"))
    self.bdTotalValue:setText(mod.formatMoney(total))

    self.stepDownButton:setDisabled(index <= 1)
    self.stepUpButton:setDisabled(index >= #self.amounts)
end

---One slider step down/up (always reaches the smallest amount, whatever the mouse does)
function LimeDropOrderDialog:stepAmount(delta)
    if #self.amounts == 0 then
        return
    end
    local index = math.max(1, math.min(#self.amounts, self.fillAmountsElement:getState() + delta))
    self.fillAmountsElement:setState(index, false)
    self:updateBreakdown(index)
end

function LimeDropOrderDialog:onClickStepDown()
    self:stepAmount(-1)
end

function LimeDropOrderDialog:onClickStepUp()
    self:stepAmount(1)
end

---Keeps the fee line in step with the slider however it was moved (drag, arrows, keys)
function LimeDropOrderDialog:update(dt)
    LimeDropOrderDialog:superClass().update(self, dt)
    if self.fillAmountsElement ~= nil and #self.amounts > 0 then
        local state = self.fillAmountsElement:getState()
        if state ~= self.shownState then
            self:updateBreakdown(state)
        end
    end
    if self.fillTypesElement ~= nil and #self.fillTypes > 0 then
        local fillTypeState = self.fillTypesElement:getState()
        if fillTypeState ~= self.shownFillTypeIndex then
            self:selectProduct(fillTypeState)
        end
    end
end

function LimeDropOrderDialog:onClickOk()
    local liters = self.amounts[self.fillAmountsElement:getState()]
    local zoneId = self.zoneId
    local fillTypeName = self.fillTypeName
    if liters == nil or zoneId == nil or fillTypeName == nil then
        return false
    end
    self:close()
    if LimeDropMenuDialog.INSTANCE ~= nil and LimeDropMenuDialog.INSTANCE.isShowing then
        LimeDropMenuDialog.INSTANCE:close()
    end
    LimeDropZone:placeOrder(zoneId, liters, fillTypeName)
    return false
end

function LimeDropOrderDialog:onClickBack(forceBack, usedMenuButton)
    self:close()
    return false
end

function LimeDropOrderDialog:close()
    g_gui:closeDialogByName(LimeDropOrderDialog.NAME)
end

function LimeDropOrderDialog:getBlurArea()
    if self.dialogElement ~= nil then
        return self.dialogElement.absPosition[1], self.dialogElement.absPosition[2],
            self.dialogElement.absSize[1], self.dialogElement.absSize[2]
    end
end
