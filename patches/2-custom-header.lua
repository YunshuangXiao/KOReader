-- ###########################################################################
-- Copyright (C) 2026 Yunshuang XIAO
-- Project: https://github.com/YunshuangXiao/KOReader_patches
--
-- This file is a custom extension(patch) for KOReader.
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program. If not, see <https://www.gnu.org/licenses/>.
-- ###########################################################################


local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local NetworkMgr = require("ui/network/manager")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local UIManager = require("ui/uimanager")
local util = require("util")
local datetime = require("datetime")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template

local ReaderView = require("apps/reader/modules/readerview")
local ReaderMenu = require("apps/reader/modules/readermenu")


-- ###########################################################################
--                         CUSTOM TRANSLATIONS
-- ###########################################################################

local CUSTOM_TRANSLATIONS = {

    zh = {
        ["Dynamic filler"] = "自适应填充",
        ["Double space"] = "双空格",
        ["Show custom header"] = "显示自定义顶部状态栏",
        ["Custom header"] = "自定义顶部状态栏",
        ["Header items (%1)"] = "状态栏项目（%1）",
        ["Arrange items"] = "状态栏项目排序",
        ["Arrange header items"] = "顶部状态栏项目排序",
        ["Separator style"] = "分隔符样式",
        ["Header font size"] = "顶部状态栏字体大小",
        ["Bold text"] = "文本加粗",
    },

    zh_CN = {
        ["Dynamic filler"] = "自适应填充",
        ["Double space"] = "双空格",
        ["Show custom header"] = "显示自定义顶部状态栏",
        ["Custom header"] = "自定义顶部状态栏",
        ["Header items (%1)"] = "状态栏项目（%1）",
        ["Arrange items"] = "状态栏项目排序",
        ["Arrange header items"] = "顶部状态栏项目排序",
        ["Separator style"] = "分隔符样式",
        ["Header font size"] = "顶部状态栏字体大小",
        ["Bold text"] = "文本加粗",
    },
}


-- ###########################################################################
--                              TRANSLATOR
-- ###########################################################################

local function getCurrentLanguage()
    -- Prefer the language gettext itself is actually using right now.
    --
    -- G_reader_settings:readSetting("language") is NOT reliable on its
    -- own: if the user never manually opened Settings -> Language and
    -- picked Chinese (e.g. it was auto-detected from the OS locale at
    -- first run instead), KOReader may never persist that value to
    -- G_reader_settings, even though the UI is genuinely running in
    -- Chinese right now. gettext's own current_lang field reflects the
    -- real, currently active language regardless of how it was set.
    local lang = _.current_lang

    if not lang or lang == "" or lang == "C" then
        lang = G_reader_settings:readSetting("language")
    end

    if not lang or lang == "" then
        return nil
    end

    lang = tostring(lang)

    -- Normalize:
    --
    -- zh_CN
    -- zh-CN
    -- zh_CN.UTF-8
    -- zh-CN.UTF-8
    --
    -- all become zh_CN.
    lang = lang:gsub("%.UTF%-8$", ""):gsub("%.utf%-8$", ""):gsub("-", "_")

    return lang
end


local function getCustomTranslation(msgid)
    local lang = getCurrentLanguage()

    if not lang then
        return nil
    end

    -- Exact language.
    local lang_table = CUSTOM_TRANSLATIONS[lang]

    if lang_table and lang_table[msgid] then
        return lang_table[msgid]
    end

    -- Base language.
    --
    -- zh_CN -> zh
    -- zh_TW -> zh
    -- en_US -> en
    local base_lang = lang:match("^([^_]+)")

    if base_lang then
        lang_table = CUSTOM_TRANSLATIONS[base_lang]

        if lang_table and lang_table[msgid] then
            return lang_table[msgid]
        end
    end

    return nil
end


local function tr(msgid, ...)
    local result

    -- IMPORTANT:
    --
    -- For our custom strings, prefer the local translation.
    --
    -- This avoids the situation where gettext returns the original
    -- English msgid while our fallback translation is available.
    local custom = getCustomTranslation(msgid)

    if custom then
        result = custom
    else
        result = _(msgid)
    end

    -- Replace %1, %2, ...
    --
    -- Use a function replacement so that replacement strings containing
    -- '%' are handled safely.
    local args = {...}

    for i, value in ipairs(args) do
        result = result:gsub("%%" .. i, function()
            return tostring(value)
        end)
    end

    return result
end


local function getItemName(item)
    if not item or not item.msgid then
        return ""
    end

    if item.icon then
        return tr(item.msgid, item.icon)
    end

    return tr(item.msgid)
end


-- ###########################################################################
--                         CUSTOM HEADER ITEMS
-- ###########################################################################

local HEADER_ITEMS = {

    time = {
        msgid = "Current time",
        generator = nil,
        is_spacer = false,
    },

    battery = {
        msgid = "Battery percentage (%1)",
        icon = "",
        generator = nil,
        is_spacer = false,
    },

    wifi = {
        msgid = "Wi-Fi status (%1)",
        icon = "",
        generator = nil,
        is_spacer = false,
    },

    percentage = {
        msgid = "Progress percentage (%1)",
        icon = "%",
        generator = nil,
        is_spacer = false,
    },

    page_progress = {
        msgid = "Current page (%1)",
        icon = "/",
        generator = nil,
        is_spacer = false,
    },

    pages_left_book = {
        msgid = "Pages left in book (%1)",
        icon = "→",
        generator = nil,
        is_spacer = false,
    },

    pages_left = {
        msgid = "Pages left in chapter (%1)",
        icon = "⇒",
        generator = nil,
        is_spacer = false,
    },

    chapter_progress = {
        msgid = "Current page in chapter (%1)",
        icon = "//",
        generator = nil,
        is_spacer = false,
    },

    title = {
        msgid = "Book title",
        generator = nil,
        is_spacer = false,
    },

    author = {
        msgid = "Book author",
        generator = nil,
        is_spacer = false,
    },

    chapter = {
        msgid = "Chapter title",
        generator = nil,
        is_spacer = false,
    },

    frontlight = {
        msgid = "Brightness level (%1)",
        icon = "☼",
        generator = nil,
        is_spacer = false,
    },

    frontlight_warmth = {
        msgid = "Warmth level (%1)",
        icon = "⊛",
        generator = nil,
        is_spacer = false,
    },

    mem_usage = {
        msgid = "KOReader memory usage (%1)",
        icon = "",
        generator = nil,
        is_spacer = false,
    },

    bookmark_count = {
        msgid = "Bookmark count (%1)",
        icon = "\u{F097}",
        generator = nil,
        is_spacer = false,
    },

    spacer = {
        msgid = "Dynamic filler",
        generator = nil,
        is_spacer = true,
    },
}


-- ###########################################################################
--                              MENU ORDER
-- ###########################################################################

local ITEMS_ORDER = {
    "time",
    "battery",
    "wifi",
    "percentage",
    "page_progress",
    "chapter_progress",
    "pages_left_book",
    "pages_left",
    "title",
    "author",
    "chapter",
    "frontlight",
    "frontlight_warmth",
    "mem_usage",
    "bookmark_count",
    "spacer",
}


-- ###########################################################################
--                           SEPARATOR STYLES
-- ###########################################################################

local SEPARATOR_STYLES = {
    "  ",
    " • ",
    " - ",
    " ○ ",
}


-- ###########################################################################
--                       CUSTOM HEADER SETTINGS
-- ###########################################################################

local header_defaults = {
    enabled = true,

    items = {
        "time",
        "battery",
        "spacer",
        "percentage",
    },

    separator_style = 1,
    item_separator = "  ",

    text_font_size = 16,
    text_font_bold = false,
}


local function getHeaderSettings()
    local settings = G_reader_settings:readSetting("custom_header")

    if not settings then
        settings = util.tableDeepCopy(header_defaults)
        G_reader_settings:saveSetting("custom_header", settings)
    end

    if settings.enabled == nil then
        settings.enabled = true
    end

    if settings.items == nil then
        settings.items = util.tableDeepCopy(header_defaults.items)
    end

    if settings.separator_style == nil then
        settings.separator_style = 1
    end

    if not SEPARATOR_STYLES[settings.separator_style] then
        settings.separator_style = 1
    end

    settings.item_separator = SEPARATOR_STYLES[settings.separator_style]

    if settings.text_font_size == nil then
        settings.text_font_size = 16
    end

    if settings.text_font_bold == nil then
        settings.text_font_bold = false
    end

    return settings
end


local function saveHeaderSettings(settings)
    G_reader_settings:saveSetting("custom_header", settings)
end


local function isHeaderEnabled()
    return getHeaderSettings().enabled
end


local function hasItem(items_list, item_key)
    for _, key in ipairs(items_list) do
        if key == item_key then
            return true
        end
    end

    return false
end


local function toggleItem(items_list, item_key)
    for i, key in ipairs(items_list) do
        if key == item_key then
            table.remove(items_list, i)
            return
        end
    end

    table.insert(items_list, item_key)
end


local function setSeparatorStyle(style_index)
    local settings = getHeaderSettings()

    settings.separator_style = style_index
    settings.item_separator = SEPARATOR_STYLES[style_index]

    saveHeaderSettings(settings)
end


-- ###########################################################################
--                              GENERATORS
-- ###########################################################################

HEADER_ITEMS.time.generator = function(self)
    return datetime.secondsToHour(
        os.time(),
        G_reader_settings:isTrue("twelve_hour_clock")
    ) or ""
end


HEADER_ITEMS.battery.generator = function(self)
    if not Device:hasBattery() then
        return ""
    end

    local power_dev = Device:getPowerDevice()
    local batt_lvl = power_dev:getCapacity() or 0
    local is_charging = power_dev:isCharging() or false

    local batt_prefix = power_dev:getBatterySymbol(
        power_dev:isCharged(),
        is_charging,
        batt_lvl
    ) or ""

    return batt_prefix .. batt_lvl .. "%"
end


HEADER_ITEMS.wifi.generator = function(self)
    if NetworkMgr:isWifiOn() then
        return ""
    end

    return ""
end


HEADER_ITEMS.percentage.generator = function(self)
    local pageno = self.state.page or 1
    local pages = self.ui.doc_settings.data.doc_pages or 1

    if pages <= 0 then
        return ""
    end

    local percentage = (pageno / pages) * 100

    return string.format("%.0f", percentage) .. "%"
end


HEADER_ITEMS.page_progress.generator = function(self)
    local pageno = self.state.page or 1
    local pages = self.ui.doc_settings.data.doc_pages or 1

    return ("%d / %d"):format(pageno, pages)
end


HEADER_ITEMS.pages_left_book.generator = function(self)
    local pageno = self.state.page or 1
    local pages = self.ui.doc_settings.data.doc_pages or 1
    local remaining = pages - pageno

    return ("→ %d / %d"):format(remaining, pages)
end


HEADER_ITEMS.pages_left.generator = function(self)
    local pageno = self.state.page or 1

    if self.ui.toc then
        local left = self.ui.toc:getChapterPagesLeft(pageno) or 0
        return ("⇒ %d"):format(left)
    end

    return ""
end


HEADER_ITEMS.chapter_progress.generator = function(self)
    local pageno = self.state.page or 1

    if not self.ui.toc then
        return ""
    end

    local pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
    pages_done = pages_done + 1

    local pages_chapter = self.ui.toc:getChapterPageCount(pageno) or 0

    if pages_chapter > 0 then
        return ("%d // %d"):format(pages_done, pages_chapter)
    end

    return ""
end


HEADER_ITEMS.title.generator = function(self)
    if self.ui.doc_props then
        return self.ui.doc_props.display_title or ""
    end

    return ""
end


HEADER_ITEMS.author.generator = function(self)
    if not self.ui.doc_props then
        return ""
    end

    local author = self.ui.doc_props.authors or ""

    if author:find("\n") then
        author = tr("%1 et al.", util.splitToArray(author, "\n")[1])
    end

    return author
end


HEADER_ITEMS.chapter.generator = function(self)
    local pageno = self.state.page or 1

    if self.ui.toc then
        return self.ui.toc:getTocTitleByPage(pageno) or ""
    end

    return ""
end


HEADER_ITEMS.frontlight.generator = function(self)
    if not Device:hasFrontlight() then
        return ""
    end

    local powerd = Device:getPowerDevice()

    if powerd:isFrontlightOn() then
        local level = powerd:frontlightIntensity()

        if Device:isCervantes() or Device:isKobo() then
            return "☼" .. ("%d%%"):format(level)
        else
            return "☼" .. ("%d"):format(level)
        end
    end

    return "☼" .. tr("Off")
end


HEADER_ITEMS.frontlight_warmth.generator = function(self)
    if not Device:hasNaturalLight() then
        return ""
    end

    local powerd = Device:getPowerDevice()

    if powerd:isFrontlightOn() then
        local warmth = powerd:frontlightWarmth()

        if warmth then
            return "⊛" .. ("%d%%"):format(warmth)
        end
    else
        return "⊛" .. tr("Off")
    end

    return ""
end


HEADER_ITEMS.mem_usage.generator = function(self)
    local statm = io.open("/proc/self/statm", "r")

    if not statm then
        return ""
    end

    local dummy, rss = statm:read("*number", "*number")
    statm:close()

    if not rss then
        return ""
    end

    rss = math.floor(rss * (4096 / 1024 / 1024))

    return "" .. ("%d MiB"):format(rss)
end


HEADER_ITEMS.bookmark_count.generator = function(self)
    if not self.ui.annotation then
        return ""
    end

    local count = self.ui.annotation:getNumberOfAnnotations()

    return "\u{F097}" .. ("%d"):format(count)
end


-- ###########################################################################
--                         BUILD HEADER CONTENT
-- ###########################################################################

local function buildHeaderWidgets(self, settings)
    local groups = {}
    local current_group = {}

    for _, item_key in ipairs(settings.items) do
        local item = HEADER_ITEMS[item_key]

        if item then
            if item.is_spacer then
                if #current_group > 0 then
                    table.insert(groups, current_group)
                    current_group = {}
                end

                table.insert(groups, "spacer")
            elseif item.generator then
                local text = item.generator(self)

                if text and text ~= "" then
                    table.insert(current_group, text)
                end
            end
        end
    end

    if #current_group > 0 then
        table.insert(groups, current_group)
    end

    local text_groups = {}

    for _, group in ipairs(groups) do
        if type(group) == "table" then
            table.insert(text_groups, table.concat(group, settings.item_separator))
        else
            table.insert(text_groups, group)
        end
    end

    return text_groups
end


-- ###########################################################################
--                         CUSTOM HEADER TOUCH ZONE
-- ###########################################################################

local function setupHeaderTouchZone(reader_ui)
    if not Device:isTouchDevice() then
        return
    end

    local header_height = Size.item.height_default

    local header_zone = {
        ratio_x = 0,
        ratio_y = 0,
        ratio_w = 1,
        ratio_h = header_height / Screen:getHeight(),
    }

    reader_ui:registerTouchZones({
        {
            id = "reader_custom_header_tap",
            ges = "tap",
            screen_zone = header_zone,

            handler = function()
                local settings = getHeaderSettings()

                settings.enabled = not settings.enabled

                saveHeaderSettings(settings)
                UIManager:setDirty(reader_ui.dialog, "ui")

                return true
            end,

            overrides = {
                "readerconfigmenu_ext_tap",
                "readerconfigmenu_tap",
            },
        },
    })
end


-- ###########################################################################
--                         CUSTOM HEADER PAINT
-- ###########################################################################

local _ReaderView_paintTo_orig = ReaderView.paintTo


ReaderView.paintTo = function(self, bb, x, y)
    -- ---------------------------------------------------------------
    -- ALWAYS let the original ReaderView paint first.
    --
    -- This is important:
    -- Native Header and Native Footer remain untouched.
    -- ---------------------------------------------------------------
    _ReaderView_paintTo_orig(self, bb, x, y)

    -- Keep the existing EPUB-like document limitation.
    if self.render_mode ~= nil then
        return
    end

    -- Custom Header switch only.
    if not isHeaderEnabled() then
        return
    end

    local settings = getHeaderSettings()


    -- ===============================================================
    -- Appearance
    -- ===============================================================

    local header_font_face = "ffont"
    local header_font_size = settings.text_font_size or 16
    local header_font_bold = settings.text_font_bold or false
    local header_font_color = Blitbuffer.COLOR_BLACK
    local header_top_padding = Size.padding.small
    local header_use_book_margins = true
    local header_margin = Size.padding.large


    -- ===============================================================
    -- Generate content
    -- ===============================================================

    local text_groups = buildHeaderWidgets(self, settings)

    if #text_groups == 0 then
        return
    end


    -- ===============================================================
    -- Calculate available width
    -- ===============================================================

    local screen_width = Screen:getWidth()
    local left_margin = header_margin
    local right_margin = header_margin

    if header_use_book_margins then
        local page_margins = self.document:getPageMargins()

        if page_margins then
            left_margin = page_margins.left or header_margin
            right_margin = page_margins.right or header_margin
        end
    end

    local avail_width = math.max(1, screen_width - left_margin - right_margin)


    -- ===============================================================
    -- Fit text
    -- ===============================================================

    local function getFittedText(text)
        if not text or text == "" then
            return ""
        end

        local text_widget = TextWidget:new{
            text = text:gsub(" ", "\u{00A0}"),
            max_width = avail_width,
            face = Font:getFace(header_font_face, header_font_size),
            bold = header_font_bold,
            padding = 0,
        }

        local fitted_text, add_ellipsis = text_widget:getFittedText()

        text_widget:free()

        if add_ellipsis then
            fitted_text = fitted_text .. "…"
        end

        return BD.auto(fitted_text)
    end


    -- ===============================================================
    -- Create text widgets
    -- ===============================================================

    local header_widgets = {}
    local total_text_width = 0
    local spacer_count = 0

    for _, group in ipairs(text_groups) do
        if group == "spacer" then
            spacer_count = spacer_count + 1
            table.insert(header_widgets, "spacer")
        else
            local fitted = getFittedText(group)

            if fitted ~= "" then
                local text_widget = TextWidget:new{
                    text = fitted,
                    face = Font:getFace(header_font_face, header_font_size),
                    bold = header_font_bold,
                    fgcolor = header_font_color,
                    padding = 0,
                }

                total_text_width = total_text_width + text_widget:getSize().w

                table.insert(header_widgets, text_widget)
            end
        end
    end


    -- ===============================================================
    -- Dynamic filler
    -- ===============================================================

    local spacer_width = 0

    if spacer_count > 0 then
        spacer_width = math.max(0, (avail_width - total_text_width) / spacer_count)
    end


    local horizontal_items = {}

    for _, widget in ipairs(header_widgets) do
        if widget == "spacer" then
            table.insert(horizontal_items, HorizontalSpan:new{ width = spacer_width })
        else
            table.insert(horizontal_items, widget)
        end
    end


    -- No dynamic filler:
    -- content remains left aligned.
    if spacer_count == 0 then
        local remaining_space = avail_width - total_text_width

        if remaining_space > 0 then
            table.insert(horizontal_items, HorizontalSpan:new{ width = remaining_space })
        end
    end


    -- ===============================================================
    -- Calculate height
    -- ===============================================================

    local max_height = 0

    for _, widget in ipairs(header_widgets) do
        if widget ~= "spacer" then
            max_height = math.max(max_height, widget:getSize().h)
        end
    end

    if max_height <= 0 then
        return
    end


    -- ===============================================================
    -- Header container
    -- ===============================================================

    local header = CenterContainer:new{
        dimen = Geom:new{
            w = screen_width,
            h = max_height + header_top_padding,
        },

        VerticalGroup:new{
            VerticalSpan:new{ width = header_top_padding },
            HorizontalGroup:new(horizontal_items),
        },
    }

    header:paintTo(bb, x, y)
end


-- ###########################################################################
--                              READER UI
-- ###########################################################################

local ReaderUI = require("apps/reader/readerui")
local orig_ReaderUI_init = ReaderUI.init


function ReaderUI:init(...)
    orig_ReaderUI_init(self, ...)
    setupHeaderTouchZone(self)
end


-- ###########################################################################
--                         CUSTOM HEADER MENU
-- ###########################################################################

local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable


function ReaderMenu:setUpdateItemTable()
    local menu_order = require("ui/elements/reader_menu_order")
    local SortWidget = require("ui/widget/sortwidget")


    -- ===============================================================
    -- Item selector
    -- ===============================================================

    local function createItemsSelector()
        return {
            text_func = function()
                local settings = getHeaderSettings()
                return tr("Header items (%1)", #settings.items)
            end,

            sub_item_table = (function()
                local items = {}

                for _, key in ipairs(ITEMS_ORDER) do
                    local item = HEADER_ITEMS[key]

                    if item then
                        table.insert(items, {
                            text = getItemName(item),

                            checked_func = function()
                                local settings = getHeaderSettings()
                                return hasItem(settings.items, key)
                            end,

                            callback = function(touchmenu_instance)
                                local settings = getHeaderSettings()

                                toggleItem(settings.items, key)
                                saveHeaderSettings(settings)
                                touchmenu_instance:updateItems()

                                if self.ui and self.ui.document then
                                    UIManager:setDirty(self.ui.dialog, "ui")
                                end
                            end,
                        })
                    end
                end

                return items
            end)(),
        }
    end


    -- ===============================================================
    -- Reorder
    -- ===============================================================

    local function createReorderMenu()
        return {
            text = tr("Arrange items"),
            keep_menu_open = true,

            enabled_func = function()
                local settings = getHeaderSettings()
                return #settings.items > 1
            end,

            callback = function()
                local settings = getHeaderSettings()
                local item_table = {}

                for _, key in ipairs(settings.items) do
                    local item = HEADER_ITEMS[key]

                    if item then
                        table.insert(item_table, {
                            text = getItemName(item),
                            label = key,
                        })
                    end
                end

                UIManager:show(SortWidget:new{
                    title = tr("Arrange header items"),
                    item_table = item_table,

                    callback = function()
                        local new_items = {}

                        for _, item in ipairs(item_table) do
                            table.insert(new_items, item.label)
                        end

                        settings.items = new_items
                        saveHeaderSettings(settings)

                        if self.ui and self.ui.document then
                            UIManager:setDirty(self.ui.dialog, "ui")
                        end
                    end,
                })
            end,
        }
    end


    -- ===============================================================
    -- Separator style
    -- ===============================================================

    local function createSeparatorStyleSelector()
        return {
            text = tr("Separator style"),

            sub_item_table = (function()
                local items = {}

                for i, style in ipairs(SEPARATOR_STYLES) do
                    local style_name = style

                    if style == "  " then
                        style_name = tr("Double space")
                    end

                    table.insert(items, {
                        text = style_name,

                        checked_func = function()
                            local settings = getHeaderSettings()
                            return settings.separator_style == i
                        end,

                        callback = function(touchmenu_instance)
                            setSeparatorStyle(i)
                            touchmenu_instance:updateItems()

                            if self.ui and self.ui.document then
                                UIManager:setDirty(self.ui.dialog, "ui")
                            end
                        end,
                    })
                end

                return items
            end)(),
        }
    end


    -- ===============================================================
    -- Font size
    -- ===============================================================

    local function createFontSizeMenu()
        return {
            text_func = function()
                local settings = getHeaderSettings()
                return tr("Font size: %1", settings.text_font_size)
            end,

            callback = function()
                local SpinWidget = require("ui/widget/spinwidget")
                local settings = getHeaderSettings()

                UIManager:show(SpinWidget:new{
                    value = settings.text_font_size,
                    value_min = 8,
                    value_max = 40,
                    default_value = 16,
                    title_text = tr("Header font size"),
                    ok_text = tr("Set size"),
                    keep_shown_on_apply = true,

                    callback = function(spin)
                        settings.text_font_size = spin.value
                        saveHeaderSettings(settings)

                        if self.ui and self.ui.document then
                            UIManager:setDirty(self.ui.dialog, "ui")
                        end
                    end,
                })
            end,
        }
    end


    -- ===============================================================
    -- Bold
    -- ===============================================================

    local function createFontBoldMenu()
        return {
            text = tr("Bold text"),

            checked_func = function()
                local settings = getHeaderSettings()
                return settings.text_font_bold
            end,

            callback = function(touchmenu_instance)
                local settings = getHeaderSettings()

                settings.text_font_bold = not settings.text_font_bold
                saveHeaderSettings(settings)
                touchmenu_instance:updateItems()

                if self.ui and self.ui.document then
                    UIManager:setDirty(self.ui.dialog, "ui")
                end
            end,
        }
    end


    -- ===============================================================
    -- Add Custom Header to native ReaderMenu
    --
    -- IMPORTANT:
    --
    -- We only ADD these two menu entries.
    --
    -- We do NOT modify:
    --   native Header settings
    --   native Footer settings
    --   ReaderFooter
    --   reader_footer_mode
    -- ===============================================================

    table.insert(menu_order.setting, "----------------------------")
    table.insert(menu_order.setting, "custom_header_toggle")
    table.insert(menu_order.setting, "custom_header_settings")


    -- ===============================================================
    -- Custom Header switch
    -- ===============================================================

    self.menu_items.custom_header_toggle = {
        text = tr("Show custom header"),
        checked_func = isHeaderEnabled,

        callback = function(touchmenu_instance)
            local settings = getHeaderSettings()

            settings.enabled = not settings.enabled
            saveHeaderSettings(settings)
            touchmenu_instance:updateItems()

            if self.ui and self.ui.document then
                UIManager:setDirty(self.ui.dialog, "ui")
            end
        end,
    }


    -- ===============================================================
    -- Custom Header settings
    -- ===============================================================

    self.menu_items.custom_header_settings = {
        text = tr("Custom header"),

        sub_item_table = {
            createItemsSelector(),
            createReorderMenu(),
            createSeparatorStyleSelector(),
            createFontSizeMenu(),
            createFontBoldMenu(),
        },
    }


    -- ===============================================================
    -- Continue with KOReader's native ReaderMenu.
    --
    -- This is critical:
    --
    -- Native Header:
    --     untouched
    --
    -- Native Footer:
    --     untouched
    --
    -- Custom Header:
    --     independent
    -- ===============================================================

    orig_ReaderMenu_setUpdateItemTable(self)
end


-- ###########################################################################
--                              END OF PATCH
-- ###########################################################################
--
-- There is intentionally NO ReaderFooter modification in this file.
--
-- In particular, this patch does NOT override:
--
--     ReaderFooter.init
--     ReaderFooter.genAllFooterText
--     ReaderFooter.applyFooterMode
--     ReaderFooter.updateFooterTextGenerator
--     ReaderFooter.set_mode_index
--     ReaderFooter.set_has_no_mode
--     ReaderFooter.resetLayout
--
-- It also does NOT modify:
--
--     reader_footer_mode
--     footer settings
--
--
-- Therefore the three components are independent:
--
--     Native Header
--          |
--          +---- controlled only by KOReader
--
--     Custom Header
--          |
--          +---- custom_header.enabled
--          +---- custom_header.items
--          +---- custom_header separator
--          +---- custom_header font size
--          +---- custom_header bold
--
--     Native Footer
--          |
--          +---- controlled only by KOReader
--          +---- "状态栏 -> 配置项目 -> 显示所有选定项目"
--
-- The Custom Header switch can never disable or enable
-- the Native Footer.
--
-- ###########################################################################
