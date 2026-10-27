--
-- LimeDropHelpDialog
-- Heap Delivery "How it works": every part of the mod explained, one topic at a time. Opened from the bottom
-- left of the zone list. Numbers (capacities, fee, delivery time, limits) come from the live values.
--

LimeDropHelpDialog = {}
local LimeDropHelpDialog_mt = Class(LimeDropHelpDialog, ScreenElement)

LimeDropHelpDialog.NAME = "LimeDropHelpDialog"
LimeDropHelpDialog.INSTANCE = nil

-- title key and paragraph keys per topic; a paragraph can be a function returning text
LimeDropHelpDialog.TOPICS = {
    {
        title = "limeDrop_help_start_title",
        paragraphs = { "limeDrop_help_start_1", "limeDrop_help_start_2", "limeDrop_help_start_3" }
    },
    {
        title = "limeDrop_help_place_title",
        paragraphs = {
            "limeDrop_help_place_1",
            function(mod)
                return string.format(mod.getText("limeDrop_help_place_2"), LimeDropZone.MAX_ZONES_PER_FARM)
            end,
            "limeDrop_help_place_3",
            "limeDrop_help_place_4"
        }
    },
    {
        title = "limeDrop_help_sizes_title",
        paragraphs = {
            "limeDrop_help_sizes_1",
            function(mod)
                local lines = { mod.getText("limeDrop_help_sizes_2") }
                for _, product in ipairs(mod:getProducts()) do
                    local parts = {}
                    for _, preset in ipairs(LimeDropZone.ZONE_SIZES) do
                        table.insert(parts, string.format("%d m %s", preset.size,
                            mod.formatLiters(mod:getCapacityForSize(preset.size, preset.size, product.name))))
                    end
                    table.insert(lines, string.format("  %s: %s", product.title, table.concat(parts, ", ")))
                end
                return table.concat(lines, "\n")
            end,
            "limeDrop_help_sizes_3"
        }
    },
    {
        title = "limeDrop_help_order_title",
        paragraphs = {
            "limeDrop_help_order_1",
            "limeDrop_help_order_2",
            function(mod)
                return string.format(mod.getText("limeDrop_help_order_3"),
                    mod.formatDuration(mod:getDeliveryDelayMs()), mod.formatPercent(mod:getSetting("deliveryFee")))
            end,
            "limeDrop_help_order_4"
        }
    },
    {
        title = "limeDrop_help_slopes_title",
        paragraphs = { "limeDrop_help_slopes_1", "limeDrop_help_slopes_2", "limeDrop_help_slopes_3", "limeDrop_help_slopes_4" }
    },
    {
        title = "limeDrop_help_products_title",
        paragraphs = {
            function(mod)
                local titles = {}
                for _, product in ipairs(mod:getProducts()) do
                    table.insert(titles, product.title)
                end
                return string.format(mod.getText("limeDrop_help_products_1"), table.concat(titles, ", "))
            end,
            "limeDrop_help_products_2",
            "limeDrop_help_products_3"
        }
    },
    {
        title = "limeDrop_help_history_title",
        paragraphs = {
            function(mod)
                return string.format(mod.getText("limeDrop_help_history_1"), LimeDropZone.MAX_HISTORY_PER_ZONE)
            end,
            "limeDrop_help_history_2",
            "limeDrop_help_history_3"
        }
    },
    {
        title = "limeDrop_help_settings_title",
        paragraphs = { "limeDrop_help_settings_1", "limeDrop_help_settings_2", "limeDrop_help_settings_3" }
    }
}

function LimeDropHelpDialog.register()
    local dialog = LimeDropHelpDialog.new()
    g_gui:loadGui(LimeDropZone.MOD_DIR .. "gui/LimeDropHelpDialog.xml", LimeDropHelpDialog.NAME, dialog)
    LimeDropHelpDialog.INSTANCE = dialog
    return dialog
end

function LimeDropHelpDialog.show()
    if LimeDropHelpDialog.INSTANCE == nil then
        LimeDropHelpDialog.register()
    end
    g_gui:showDialog(LimeDropHelpDialog.NAME)
end

function LimeDropHelpDialog.new(target, customMt)
    local self = ScreenElement.new(target, customMt or LimeDropHelpDialog_mt)
    self.isCloseAllowed = true
    self.topicIndex = 1
    return self
end

-- one click handler per topic button
for i = 1, #LimeDropHelpDialog.TOPICS do
    LimeDropHelpDialog["onClickTopic" .. i] = function(self)
        self:showTopic(i)
    end
end

function LimeDropHelpDialog:onOpen()
    if LimeDropHelpDialog:superClass().onOpen ~= nil then
        LimeDropHelpDialog:superClass().onOpen(self)
    end
    local mod = LimeDropZone
    mod.subDialogOpen = true
    self.headerTextElement:setText(mod.getText("limeDrop_help_header"))
    for i, topic in ipairs(LimeDropHelpDialog.TOPICS) do
        local button = self["topicButton" .. i]
        if button ~= nil then
            button:setText(mod.getText(topic.title))
        end
    end
    self:showTopic(self.topicIndex or 1)
end

function LimeDropHelpDialog:onClose()
    LimeDropZone.subDialogOpen = false
    LimeDropZone:requestMenuRefresh()
    if LimeDropHelpDialog:superClass().onClose ~= nil then
        LimeDropHelpDialog:superClass().onClose(self)
    end
end

---Shows a topic's title and text; its button stays selected
function LimeDropHelpDialog:showTopic(index)
    local mod = LimeDropZone
    local topic = LimeDropHelpDialog.TOPICS[index]
    if topic == nil then
        return
    end
    self.topicIndex = index
    local paragraphs = {}
    for _, paragraph in ipairs(topic.paragraphs) do
        if type(paragraph) == "function" then
            table.insert(paragraphs, paragraph(mod))
        else
            table.insert(paragraphs, mod.getText(paragraph))
        end
    end
    self.topicTitleElement:setText(mod.getText(topic.title))
    self.topicBodyElement:setText(table.concat(paragraphs, "\n\n"))
    local button = self["topicButton" .. index]
    if button ~= nil then
        FocusManager:setFocus(button)
    end
end

function LimeDropHelpDialog:onClickBack(forceBack, usedMenuButton)
    self:close()
    return false
end

function LimeDropHelpDialog:close()
    g_gui:closeDialogByName(LimeDropHelpDialog.NAME)
end

function LimeDropHelpDialog:getBlurArea()
    if self.dialogElement ~= nil then
        return self.dialogElement.absPosition[1], self.dialogElement.absPosition[2],
            self.dialogElement.absSize[1], self.dialogElement.absSize[2]
    end
end
