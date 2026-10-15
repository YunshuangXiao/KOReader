-- ###########################################################################
-- Copyright (C) 2026 Yunshuang XIAO
-- Project: https://github.com/YunshuangXiao/KOReader/tree/main/patches
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
--
-- AI-assisted programming
--
-- patch: 2-simple-launcher.lua
-- Version: v1.2.0
-- This file is to provide a simple launcher for koreader.
-- All modules and functions are from koreader, no complex functions.
-- No refresh in the background, could be suitable for colorsoft.
--
-- ###########################################################################
--[[
    2-simple-launcher.lua  ——  简易桌面 (Simple Launcher): KOReader 桌面补丁 (参考 SimpleUI 的思路)

    安装:  放进  koreader/patches/  ,重启 KOReader。
    入口:  文件浏览器 → 顶部菜单 → 工具(More tools) → "简易桌面"
           或在 手势 / Profiles 里绑定动作 "显示简易桌面"。

    1.2.0 变化
      * 在线更新后是否备份原文件(.bak)由用户决定: 在线更新菜单中可开关 (默认备份)
      * 代码优化: 合并重复代码 (书籍行、列表编辑菜单、提示消息), 书籍信息缓存, 移除无用依赖与函数
      * 检查更新时附带时间戳以绕过 GitHub raw 的 CDN 缓存; 线上版本号优先读取 VERSION 常量

    1.1.2 变化
      * 中文名定为 "简易桌面" (界面中的名称、菜单、手势动作均使用中文名)
      * 文件头 Version 与代码中的 VERSION 统一为 x.x.x 格式

    1.1.1 变化
      * 更新地址写在代码里 (UPDATE_URL), 菜单中不再提供输入框

    1.1.0 变化
      * 项目更名为 Simple Launcher (文件名 2-simple-launcher.lua; 旧配置自动迁移)

    1.0.0 变化 (此前为 v7)
      * 最近阅读轮播: 每次进入默认聚焦当前阅读的书 (居中);
        圆点页码的 "●" 固定在正中, 两侧为前后几本 (环形), 圆点数量可调

    v6 变化
      * 在线更新改为仅手动 (已移除启动时自动检查)
      * 最近阅读轮播改版: 左右小封面 + 居中大封面 + 书名 / 阅读进度 + 圆点页码

    v4 变化
      * 新增模块: 最近阅读轮播 (左右箭头 / 左右滑动翻页, 可定时自动轮播, 来源可选 "最近阅读" 或 "收藏")、
        收藏书籍、问候语
      * 翻页时只重画模块, 壁纸不再重复处理

    v3 变化
      * 所有模块背景透明 (已移除 "白色底衬" 选项)
      * 全部界面文字改为中文
      * 新增 "将启动器设为文件浏览器的初始界面" (启动 / 读完书后直接进入, 不再先闪出文件列表)
        以及可选的 "文件浏览器 Home 键进入启动器"

    v2 变化
      * 所有模块无边框, 直接画在壁纸上
      * 每个模块都可单独设置:  大小(%) / 宽度(%) / 对齐 / 上方留白 / 底衬,
        以及各自的内容选项 (文字、格式、数量、封面高度、显示哪些元素...)
      * 模块由用户自己挑选: "Modules → Add module..." 添加, 可重复添加同类模块 (如两组快捷按钮),
        可开关 / 排序 / 删除
      * 快捷指令按钮现在属于各个 "Quick actions" 模块实例, 每组按钮、列数、尺寸互相独立
        (旧版配置会自动迁移)

    数据位置
      配置:       koreader/settings/simple_launcher.lua  (旧版 launcher_homescreen.lua 会自动迁移)
      壁纸:       koreader/launcher/wallpapers/
      自定义模块: koreader/launcher/modules/*.lua   (每个文件 return 一张模块表)

    自定义模块示例 (koreader/launcher/modules/hello.lua):

        local TextWidget = require("ui/widget/textwidget")
        return {
            id = "hello", title = "Hello",
            defaults = { text = "Hello KOReader", size = 24 },
            options = {
                { key = "text", label = "Text", type = "string" },
                { key = "size", label = "Font size", type = "number", min = 10, max = 80 },
            },
            build = function(ctx)
                -- ctx.width  可用宽度      ctx.opts  合并后的选项
                -- ctx.font(face, size) / ctx.px(n)  已按该模块 "大小(%)" 缩放
                -- ctx.center(widget)  按该模块 "对齐" 放置
                -- ctx.tappable(widget, fn)  ctx.openBook(file)  ctx.runAction(entry)
                return ctx.center(TextWidget:new{
                    text = ctx.opts.text, face = ctx.font("cfont", ctx.opts.size),
                })
            end,
        }
    options.type 可选: bool / number(min,max,step) / string / choice(choices={{text=,value=}...})
]]

if package.loaded["simple_launcher"] then
    return
end

local SELF_SOURCE = debug.getinfo(1, "S").source or "" -- 本补丁自身路径 (在线更新时覆盖用)

local Blitbuffer = require("ffi/blitbuffer")
local CenterContainer = require("ui/widget/container/centercontainer")
local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local Dispatcher = require("dispatcher")
local DocSettings = require("docsettings")
local FileManager = require("apps/filemanager/filemanager")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local Geom = require("ui/geometry")
local GestureRange = require("ui/gesturerange")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local IconWidget = require("ui/widget/iconwidget")
local ImageWidget = require("ui/widget/imagewidget")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local LeftContainer = require("ui/widget/container/leftcontainer")
local LuaSettings = require("luasettings")
local OverlapGroup = require("ui/widget/overlapgroup")
local PathChooser = require("ui/widget/pathchooser")
local ProgressWidget = require("ui/widget/progresswidget")
local ReadHistory = require("readhistory")
local ReaderUI = require("apps/reader/readerui")
local RenderImage = require("ui/renderimage")
local RightContainer = require("ui/widget/container/rightcontainer")
local SpinWidget = require("ui/widget/spinwidget")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local util = require("util")
local Screen = Device.screen

-- ---------------------------------------------------------------------------
-- 基础
-- ---------------------------------------------------------------------------

local ROOT_DIR = DataStorage:getDataDir() .. "/launcher"
local WALLPAPER_DIR = ROOT_DIR .. "/wallpapers"
local MODULE_DIR = ROOT_DIR .. "/modules"
local SETTINGS_FILE = DataStorage:getSettingsDir() .. "/simple_launcher.lua"
do -- 从旧版配置文件迁移
    local old_file = DataStorage:getSettingsDir() .. "/launcher_homescreen.lua"
    if lfs.attributes(old_file, "mode") == "file" and lfs.attributes(SETTINGS_FILE, "mode") ~= "file" then
        local fi = io.open(old_file, "rb")
        if fi then
            local data = fi:read("*a")
            fi:close()
            local fo = io.open(SETTINGS_FILE, "wb")
            if fo then
                fo:write(data)
                fo:close()
            end
        end
    end
end
local MENU_ZONE_H = 0.15 -- 屏幕顶部多大比例视为 "菜单手势区"

lfs.mkdir(ROOT_DIR)
lfs.mkdir(WALLPAPER_DIR)
lfs.mkdir(MODULE_DIR)
math.randomseed(os.time())

local L = { modules = {}, module_ids = {}, instance = nil, dispatching = false }
package.loaded["simple_launcher"] = L
package.loaded["launcher_homescreen"] = L -- 旧名称别名, 兼容已有的自定义模块

local VERSION = "1.2.0" -- LAUNCHER_VERSION: 1.2.0   (在线更新用它比较新旧; 发布新版时,此处与文件头 "Version: vx.x.x" 保持一致, 格式 x.x.x)
L.VERSION = VERSION

-- 更新地址: 写死在代码里, 用户界面不提供修改 (如需更换仓库, 直接改这一行)
local UPDATE_URL = "https://raw.githubusercontent.com/YunshuangXiao/KOReader/refs/heads/main/patches/2-simple-launcher.lua"

local function scale(n)
    return Screen:scaleBySize(n)
end

local function toast(text, timeout)
    UIManager:show(InfoMessage:new{ text = text, timeout = timeout or 3 })
end

local IMAGE_EXT = { png = true, jpg = true, jpeg = true, webp = true, bmp = true, gif = true, tif = true, tiff = true }
local function isImage(path)
    local ext = path:match("%.(%w+)$")
    return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

local function mode(path)
    return lfs.attributes(path, "mode")
end

--- 可点击包装
local function tappable(widget, callback)
    local size = widget:getSize()
    local c
    c = InputContainer:new{
        dimen = Geom:new{ w = size.w, h = size.h },
        ges_events = {
            Tap = { GestureRange:new{ ges = "tap", range = function() return c.dimen end } },
        },
        widget,
    }
    function c:onTap()
        callback()
        return true
    end
    return c
end

--- 可左右滑动的包装: 向左滑 → on_west, 向右滑 → on_east
local function swipeable(widget, on_west, on_east)
    local size = widget:getSize()
    local c
    c = InputContainer:new{
        dimen = Geom:new{ w = size.w, h = size.h },
        ges_events = {
            Swipe = { GestureRange:new{ ges = "swipe", range = function() return c.dimen end } },
        },
        widget,
    }
    function c:onSwipe(arg, ges)
        if ges.direction == "west" then
            on_west()
            return true
        elseif ges.direction == "east" then
            on_east()
            return true
        end
    end
    return c
end

--- 按对齐方式放进指定宽高的容器
local function alignBox(align, w, h, widget)
    local C = (align == "left" and LeftContainer) or (align == "right" and RightContainer) or CenterContainer
    return C:new{ dimen = Geom:new{ w = w, h = h }, widget }
end

-- 所有模块共有的 "大小与位置" 选项
local COMMON_DEFAULTS = { scale = 100, width_pct = 100, align = "center", space_above = 0 }
local COMMON_OPTIONS = {
    { key = "scale", label = "大小(%)", type = "number", min = 40, max = 250, step = 5 },
    { key = "width_pct", label = "宽度(%)", type = "number", min = 20, max = 100, step = 5 },
    {
        key = "align", label = "对齐方式", type = "choice",
        choices = {
            { text = "靠左", value = "left" },
            { text = "居中", value = "center" },
            { text = "靠右", value = "right" },
        },
    },
    { key = "space_above", label = "上方额外留白", type = "number", min = 0, max = 200, step = 2 },
}

-- ---------------------------------------------------------------------------
-- 配置
-- ---------------------------------------------------------------------------

local settings = LuaSettings:open(SETTINGS_FILE)

local function defaultActions()
    return {
        { label = "书库", builtin = "files" },
        { label = "历史", settings = { history = true } },
        { label = "收藏", settings = { favorites = true } },
        { label = "搜索", settings = { file_search = true } },
        { label = "上次阅读", settings = { open_last_document = true } },
        { label = "菜单", builtin = "menu" },
    }
end

local function defaultConfig()
    return {
        enabled = true,
        auto_show = true,          -- 作为文件浏览器的初始界面: 启动 / 退出阅读后直接进入启动器
        home_to_launcher = true,   -- 在文件浏览器点 Home 时进入启动器
        backup_on_update = true,   -- 在线更新时是否把原文件备份为 .bak (用户可在 "在线更新" 菜单中切换)
        wallpaper = "",            -- 文件 或 文件夹(随机)
        wallpaper_mode = "cover",  -- cover | fit | stretch
        wallpaper_tone = 0,        -- 壁纸深浅: -100(最暗) ~ 100(最浅), 0=原图
        margin = 14,
        spacing = 14,
        valign = "top",            -- top | center | bottom
        refresh_minutes = 0,       -- >0 时定时重绘 (时钟用), 0=关闭
        modules = {
            { id = "clock", enabled = true, opts = {} },
            { id = "current_book", enabled = true, opts = {} },
            { id = "quick_actions", enabled = true, opts = {}, actions = defaultActions() },
            { id = "recent_books", enabled = true, opts = {} },
        },
    }
end

function L:load()
    local cfg = defaultConfig()
    local saved = settings:readSetting("config")
    if type(saved) == "table" then
        for k, v in pairs(saved) do cfg[k] = v end
    end
    if type(cfg.modules) ~= "table" then cfg.modules = defaultConfig().modules end
    if cfg.version ~= 4 then -- v4: Home 键进入启动器改为默认开启
        cfg.version = 4
        cfg.home_to_launcher = true
    end
    for ii, e in ipairs(cfg.modules) do
        e.opts = e.opts or {}
        -- 迁移 v1: 全局 actions / action_cols → 每个快捷指令模块自带
        if e.id == "quick_actions" and type(e.actions) ~= "table" then
            local old = type(saved) == "table" and saved.actions or nil
            e.actions = old and util.tableDeepCopy(old) or defaultActions()
            if type(saved) == "table" and saved.action_cols and e.opts.columns == nil then
                e.opts.columns = saved.action_cols
            end
        end
    end
    self.cfg = cfg
end

function L:save()
    settings:saveSetting("config", self.cfg)
    settings:flush()
end

local function defaultFor(spec, key)
    if spec.defaults and spec.defaults[key] ~= nil then return spec.defaults[key] end
    return COMMON_DEFAULTS[key]
end

local function mergedOpts(entry, spec)
    local o = {}
    for k, v in pairs(COMMON_DEFAULTS) do o[k] = v end
    for k, v in pairs(spec.defaults or {}) do o[k] = v end
    for k, v in pairs(entry.opts or {}) do o[k] = v end
    return o
end

function L:entryTitle(entry)
    local spec = self.modules[entry.id]
    if not spec then return entry.id .. " (缺失)" end
    local total, idx = 0, 0
    for ii, e in ipairs(self.cfg.modules) do
        if e.id == entry.id then
            total = total + 1
            if e == entry then idx = total end
        end
    end
    return total > 1 and string.format("%s #%d", spec.title, idx) or spec.title
end

-- ---------------------------------------------------------------------------
-- 壁纸
-- ---------------------------------------------------------------------------

function L:resolveWallpaper()
    local p = self.cfg.wallpaper
    if not p or p == "" then return nil end
    local m = mode(p)
    if m == "file" then return p end
    if m == "directory" then
        local files = {}
        for name in lfs.dir(p) do
            local full = p .. "/" .. name
            if name:sub(1, 1) ~= "." and isImage(name) and mode(full) == "file" then
                files[#files + 1] = full
            end
        end
        if #files > 0 then return files[math.random(#files)] end
    end
    return nil
end

function L:buildWallpaper(w, h)
    local path = self:resolveWallpaper()
    if not path then return nil end
    local ok, widget = pcall(function()
        local m = self.cfg.wallpaper_mode
        local bb = RenderImage:renderImageFile(path, false)
        if not bb then return nil end
        local iw, ih = bb:getWidth(), bb:getHeight()
        local out
        if m == "stretch" then
            out = RenderImage:scaleBlitBuffer(bb, w, h, true)
        elseif m == "fit" then
            local s = math.min(w / iw, h / ih)
            local sw, sh = math.max(1, math.floor(iw * s)), math.max(1, math.floor(ih * s))
            local scaled = RenderImage:scaleBlitBuffer(bb, sw, sh, true)
            out = Blitbuffer.new(w, h, scaled:getType())
            out:fill(Blitbuffer.COLOR_WHITE)
            out:blitFrom(scaled, math.floor((w - sw) / 2), math.floor((h - sh) / 2), 0, 0, sw, sh)
            scaled:free()
        else -- cover
            local s = math.max(w / iw, h / ih)
            local sw, sh = math.ceil(iw * s), math.ceil(ih * s)
            local scaled = RenderImage:scaleBlitBuffer(bb, sw, sh, true)
            out = Blitbuffer.new(w, h, scaled:getType())
            out:blitFrom(scaled, 0, 0, math.floor((sw - w) / 2), math.floor((sh - h) / 2), w, h)
            scaled:free()
        end
        -- 深浅调整: 负数 → 向黑色压暗, 正数 → 向白色淡化
        local tone = tonumber(self.cfg.wallpaper_tone) or 0
        if tone ~= 0 then
            local f = math.min(0.95, math.abs(tone) / 100)
            local fn = (tone < 0) and out.darkenRect or out.lightenRect
            local okt, errt = pcall(fn, out, 0, 0, w, h, f)
            if not okt then logger.warn("launcher: tone adjust failed", errt) end
        end
        return ImageWidget:new{ image = out, image_disposable = true, width = w, height = h }
    end)
    if ok then return widget end
    logger.warn("launcher: wallpaper failed", path, widget)
    return nil
end

-- ---------------------------------------------------------------------------
-- 书籍信息 / 封面
-- ---------------------------------------------------------------------------

local cover_cache, cover_order = {}, {}
local MAX_COVERS = 12

function L:getCover(file)
    local cached = cover_cache[file]
    if cached ~= nil then return cached or nil end
    local bb
    local BIM
    for ii, name in ipairs{ "bookinfomanager", "plugins/coverbrowser.koplugin/bookinfomanager" } do
        local ok, m = pcall(require, name)
        if ok and type(m) == "table" then BIM = m break end
    end
    if BIM then
        local ok, info = pcall(BIM.getBookInfo, BIM, file, true)
        if ok and info and info.has_cover and info.cover_bb then bb = info.cover_bb end
    end
    if not bb then
        local ok, DocumentRegistry = pcall(require, "document/documentregistry")
        if ok and DocumentRegistry:hasProvider(file) then
            local ok2, doc = pcall(DocumentRegistry.openDocument, DocumentRegistry, file)
            if ok2 and doc then
                local ok3, img = pcall(doc.getCoverPageImage, doc)
                if ok3 then bb = img end
                pcall(doc.close, doc)
            end
        end
    end
    cover_cache[file] = bb or false
    table.insert(cover_order, file)
    if #cover_order > MAX_COVERS then
        local old = table.remove(cover_order, 1)
        local obb = cover_cache[old]
        cover_cache[old] = nil
        if obb and obb.free then pcall(obb.free, obb) end
    end
    return bb
end

--- 书名 / 作者 / 阅读进度 (每次进入启动器期间缓存, 翻页重绘时不再重复读取 sidecar)
function L:getBookMeta(file)
    self._meta = self._meta or {}
    local cached = self._meta[file]
    if cached then return cached end
    local _dir, name = util.splitFilePathName(file)
    local meta = { title = util.splitFileNameSuffix(name), author = "", percent = 0 }
    local ok, ds = pcall(function() return DocSettings:open(file) end)
    if ok and ds then
        local props = ds:readSetting("doc_props")
        if type(props) == "table" then
            if props.title and props.title ~= "" then meta.title = props.title end
            if props.authors and props.authors ~= "" then meta.author = (props.authors:gsub("\n", ", ")) end
        end
        meta.percent = ds:readSetting("percent_finished") or 0
        pcall(ds.close, ds)
    end
    self._meta[file] = meta
    return meta
end

function L:getRecent(n, skip)
    local out = {}
    local hist = ReadHistory.hist or {}
    for ii = 1 + (skip or 0), #hist do
        local item = hist[ii]
        if item and item.file and not item.dim then
            out[#out + 1] = item.file
            if #out >= n then break end
        end
    end
    return out
end

function L:getFavorites(n)
    local out = {}
    local ok, RC = pcall(require, "readcollection")
    if not ok or type(RC) ~= "table" or type(RC.coll) ~= "table" then return out end
    local coll = RC.coll["favorites"]
    if type(coll) ~= "table" then return out end
    local items = {}
    for k, v in pairs(coll) do
        local file, order
        if type(v) == "table" and v.file then
            file, order = v.file, v.order
        elseif type(k) == "string" then
            file = k
        end
        if file and mode(file) == "file" then
            items[#items + 1] = { file = file, order = tonumber(order) or 1e9 }
        end
    end
    table.sort(items, function(a, b) return a.order < b.order end)
    for ii = 1, math.min(n, #items) do out[#out + 1] = items[ii].file end
    return out
end

--- 封面 widget (无边框); 没有封面时只显示书名首字占位
function L:makeCover(file, height, max_w, font_fn)
    local bb = self:getCover(file)
    local w, h
    if bb then
        local bw, bh = bb:getWidth(), bb:getHeight()
        h = height
        w = math.floor(bw * h / bh)
        if max_w and w > max_w then
            w = max_w
            h = math.floor(bh * w / bw)
        end
        return ImageWidget:new{ image = bb, image_disposable = false, width = w, height = h }, w, h
    end
    w = math.min(math.floor(height * 0.7), max_w or 9999)
    h = height
    local _dir, name = util.splitFilePathName(file)
    local initial = (util.splitFileNameSuffix(name) or "?"):sub(1, 1):upper()
    local frame = CenterContainer:new{
        dimen = Geom:new{ w = w, h = h },
        TextWidget:new{ text = initial, face = font_fn("infofont", 28) },
    }
    return frame, w, h
end

--- 封面 + 书名 的可点击单元
function L:bookCell(ctx, file, cell_w, o)
    local cover = self:makeCover(file, ctx.px(o.cover_height), cell_w, ctx.font)
    local col = VerticalGroup:new{ align = "center", cover }
    if o.show_title then
        local meta = self:getBookMeta(file)
        col[#col + 1] = VerticalSpan:new{ width = ctx.px(5) }
        col[#col + 1] = TextWidget:new{ text = meta.title, face = ctx.font("cfont", o.title_size), max_width = cell_w }
    end
    local cell = CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = col:getSize().h }, col }
    return tappable(cell, function() self:openBook(file) end)
end

--- 一行书籍 (slots = 一行最多几本, 保证大小一致); 整行按模块的 "对齐" 放置
function L:bookRow(ctx, files, o, total_w, slots)
    local gap = ctx.px(12)
    local cell_w = math.floor((total_w - (slots - 1) * gap) / slots)
    local row = HorizontalGroup:new{ align = "top" }
    for ii, file in ipairs(files) do
        row[#row + 1] = self:bookCell(ctx, file, cell_w, o)
        if ii < #files then row[#row + 1] = HorizontalSpan:new{ width = gap } end
    end
    return alignBox(ctx.opts.align, total_w, row:getSize().h, row)
end

function L:state(entry)
    self._state = self._state or setmetatable({}, { __mode = "k" })
    self._state[entry] = self._state[entry] or {}
    return self._state[entry]
end

--- 重建启动器内容 (只重画模块, 壁纸不重新处理)
function L:refreshInstance()
    local w = self.instance
    if w then
        w:rebuild()
        UIManager:setDirty(w, "ui")
    end
end

function L:openBook(file)
    self:close()
    ReaderUI:showReader(file)
end

-- ---------------------------------------------------------------------------
-- 快捷指令
-- ---------------------------------------------------------------------------

function L:actionSummary(entry)
    if entry.builtin then return "[" .. entry.builtin .. "]" end
    local ok, list = pcall(Dispatcher.getDisplayList, Dispatcher, entry.settings or {})
    if ok and type(list) == "table" then
        local parts = {}
        for ii, v in ipairs(list) do
            parts[#parts + 1] = type(v) == "table" and (v.text or "") or tostring(v)
        end
        return table.concat(parts, ", ")
    end
    return ""
end

function L:actionLabel(entry)
    if entry.label and entry.label ~= "" then return entry.label end
    local s = self:actionSummary(entry)
    return s ~= "" and s or "动作"
end

function L:runAction(entry)
    if entry.builtin == "files" then
        self:close()
        return
    elseif entry.builtin == "menu" then
        local fm = FileManager.instance
        if fm and fm.menu then pcall(fm.menu.onShowMenu, fm.menu) end
        return
    end
    if not entry.settings or next(entry.settings) == nil then
        toast("这个快捷指令还没有设置动作。")
        return
    end
    self.dispatching = true
    local ok, err = pcall(Dispatcher.execute, Dispatcher, entry.settings)
    self.dispatching = false
    if not ok then
        logger.warn("launcher: action failed", err)
        toast("动作执行失败:" .. tostring(err), 4)
    end
end

-- ---------------------------------------------------------------------------
-- 模块注册
-- ---------------------------------------------------------------------------

function L:registerModule(spec)
    if type(spec) ~= "table" or not spec.id or type(spec.build) ~= "function" then
        logger.warn("launcher: invalid module spec")
        return
    end
    spec.title = spec.title or spec.id
    spec.defaults = spec.defaults or {}
    if not self.modules[spec.id] then
        table.insert(self.module_ids, spec.id)
    end
    self.modules[spec.id] = spec
end

function L:makeCtx(width, opts, entry, win)
    local pct = math.max(20, opts.scale or 100)
    local ctx = {
        width = width, opts = opts, entry = entry, launcher = self, tappable = tappable,
        runAction = function(e) self:runAction(e) end,
        openBook = function(f) self:openBook(f) end,
    }
    function ctx.px(n) return math.max(1, math.floor(scale(n) * pct / 100)) end
    function ctx.font(face, size) return Font:getFace(face, math.max(6, math.floor(size * pct / 100))) end
    function ctx.center(widget)
        return alignBox(opts.align, width, widget:getSize().h, widget)
    end
    --- 模块定时器: sec 秒后执行 fn (每次重建后需重新注册; 启动器不在最上层时顺延)
    function ctx.schedule(sec, fn)
        if not win or not sec or sec <= 0 then return end
        local f
        f = function()
            local top = UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget()
            if top and top ~= win then
                UIManager:scheduleIn(sec, f)
                return
            end
            fn()
        end
        win._mod_timers = win._mod_timers or {}
        table.insert(win._mod_timers, f)
        UIManager:scheduleIn(sec, f)
    end
    return ctx
end

local WEEK_ZH = { "星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六" }
local function safeDate(fmt)
    local wd = WEEK_ZH[tonumber(os.date("%w")) + 1]
    fmt = fmt:gsub("%%A", wd):gsub("%%a", (wd:gsub("星期", "周")))
    local ok, s = pcall(os.date, fmt)
    return ok and s or fmt
end

-- 时钟 ---------------------------------------------------------------------
L:registerModule{
    id = "clock", title = "时钟",
    defaults = { size = 56, show_date = true, bold = true, time_format = "%H:%M", date_format = "%Y年%m月%d日  %A" },
    options = {
        { key = "size", label = "时间字号", type = "number", min = 20, max = 140 },
        { key = "bold", label = "时间加粗", type = "bool" },
        { key = "time_format", label = "时间格式(strftime)", type = "string" },
        { key = "show_date", label = "显示日期", type = "bool" },
        { key = "date_format", label = "日期格式(strftime)", type = "string" },
    },
    build = function(ctx)
        local o = ctx.opts
        local vg = VerticalGroup:new{ align = o.align }
        vg[#vg + 1] = TextWidget:new{
            text = safeDate(o.time_format), bold = o.bold,
            face = ctx.font("infofont", o.size), max_width = ctx.width,
        }
        if o.show_date then
            vg[#vg + 1] = TextWidget:new{
                text = safeDate(o.date_format),
                face = ctx.font("cfont", math.max(12, math.floor(o.size * 0.35))), max_width = ctx.width,
            }
        end
        return ctx.center(vg)
    end,
}

-- 当前阅读 -----------------------------------------------------------------
L:registerModule{
    id = "current_book", title = "当前阅读",
    defaults = {
        cover_height = 170, show_cover = true, show_label = true, label = "继续阅读",
        show_author = true, show_progress = true, title_size = 22,
    },
    options = {
        { key = "show_cover", label = "显示封面", type = "bool" },
        { key = "cover_height", label = "封面高度", type = "number", min = 60, max = 500, step = 5 },
        { key = "show_label", label = "显示标题文字", type = "bool" },
        { key = "label", label = "标题文字", type = "string" },
        { key = "title_size", label = "书名字号", type = "number", min = 10, max = 48 },
        { key = "show_author", label = "显示作者", type = "bool" },
        { key = "show_progress", label = "显示进度", type = "bool" },
    },
    build = function(ctx)
        local o = ctx.opts
        local file = L:getRecent(1)[1]
        if not file then
            return ctx.center(TextWidget:new{ text = "暂无最近阅读", face = ctx.font("cfont", 20), max_width = ctx.width })
        end
        local meta = L:getBookMeta(file)
        local gap = ctx.px(16)
        local cover, cw, ch = nil, 0, 0
        if o.show_cover then
            cover, cw, ch = L:makeCover(file, ctx.px(o.cover_height), math.floor(ctx.width * 0.45), ctx.font)
        end
        local info_w = ctx.width - (cover and (cw + gap) or 0)
        local info = VerticalGroup:new{ align = "left" }
        if o.show_label and o.label ~= "" then
            info[#info + 1] = TextWidget:new{ text = o.label, face = ctx.font("cfont", 14), max_width = info_w }
            info[#info + 1] = VerticalSpan:new{ width = ctx.px(4) }
        end
        info[#info + 1] = TextWidget:new{
            text = meta.title,
            face = ctx.font("cfont", o.title_size),
            bold = true,
            max_width = info_w,
        }
        if o.show_author and meta.author ~= "" then
            info[#info + 1] = TextWidget:new{ text = meta.author, face = ctx.font("cfont", 16), max_width = info_w }
        end
        if o.show_progress then
            info[#info + 1] = VerticalSpan:new{ width = ctx.px(10) }
            local bar_h = ctx.px(6)
            info[#info + 1] = ProgressWidget:new{
                width = info_w, height = bar_h, percentage = meta.percent,
                bordersize = 0, margin_h = 0, margin_v = 0, radius = math.floor(bar_h / 2),
                bgcolor = Blitbuffer.COLOR_GRAY_E, fillcolor = Blitbuffer.COLOR_BLACK,
            }
            info[#info + 1] = VerticalSpan:new{ width = ctx.px(3) }
            info[#info + 1] = TextWidget:new{
                text = string.format("%d%%", math.floor(meta.percent * 100 + 0.5)),
                face = ctx.font("cfont", 14), max_width = info_w,
            }
        end
        local row
        if cover then
            row = HorizontalGroup:new{
                align = "center", cover, HorizontalSpan:new{ width = gap },
                CenterContainer:new{ dimen = Geom:new{ w = info_w, h = math.max(ch, info:getSize().h) }, info },
            }
        else
            row = info
        end
        return tappable(row, function() L:openBook(file) end)
    end,
}

-- 最近阅读 -----------------------------------------------------------------
L:registerModule{
    id = "recent_books", title = "最近阅读",
    defaults = { count = 4, skip_current = true, cover_height = 120, show_title = true, title_size = 14 },
    options = {
        { key = "count", label = "书籍数量", type = "number", min = 1, max = 8 },
        { key = "skip_current", label = "跳过当前阅读的书", type = "bool" },
        { key = "cover_height", label = "封面高度", type = "number", min = 50, max = 400, step = 5 },
        { key = "show_title", label = "显示书名", type = "bool" },
        { key = "title_size", label = "书名字号", type = "number", min = 8, max = 30 },
    },
    build = function(ctx)
        local o = ctx.opts
        local files = L:getRecent(math.min(o.count, 8), o.skip_current and 1 or 0)
        if #files == 0 then return nil end
        return L:bookRow(ctx, files, o, ctx.width, #files)
    end,
}

-- 最近阅读轮播: 左右小封面 + 居中大封面 + 书名/进度 + 圆点页码 ------------------
-- 点左右小封面 / 左右滑动 = 切换; 点中间封面 = 打开这本书; 可定时自动轮播
L:registerModule{
    id = "recent_carousel", title = "最近阅读轮播",
    defaults = {
        source = "recent", count = 6, skip_current = false,
        center_height = 200, side_percent = 70,
        show_label = false, label = "最近阅读",
        show_title = true, title_size = 20, show_progress = true,
        show_indicator = true, indicator_dots = 5, auto_seconds = 0,
    },
    options = {
        {
            key = "source", label = "书籍来源", type = "choice",
            choices = { { text = "最近阅读", value = "recent" }, { text = "收藏", value = "favorites" } },
        },
        { key = "count", label = "轮播书籍总数", type = "number", min = 1, max = 12 },
        { key = "skip_current", label = "跳过当前阅读的书(仅最近阅读)", type = "bool" },
        { key = "center_height", label = "中间封面高度", type = "number", min = 80, max = 600, step = 5 },
        { key = "side_percent", label = "两侧封面相对大小(%)", type = "number", min = 30, max = 100, step = 5 },
        { key = "show_label", label = "显示顶部标题", type = "bool" },
        { key = "label", label = "顶部标题文字", type = "string" },
        { key = "show_title", label = "显示当前书名", type = "bool" },
        { key = "title_size", label = "书名字号", type = "number", min = 8, max = 48 },
        { key = "show_progress", label = "显示阅读进度", type = "bool" },
        { key = "show_indicator", label = "显示圆点页码", type = "bool" },
        { key = "indicator_dots", label = "圆点数量(奇数,当前书始终在中间)", type = "number", min = 3, max = 9 },
        { key = "auto_seconds", label = "自动轮播间隔(秒,0 为关闭,墨水屏建议 ≥30)", type = "number", min = 0, max = 3600, step = 5 },
    },
    build = function(ctx)
        local o = ctx.opts
        local files
        if o.source == "favorites" then
            files = L:getFavorites(o.count)
        else
            files = L:getRecent(o.count, o.skip_current and 1 or 0)
        end
        if #files == 0 then
            return ctx.center(TextWidget:new{ text = "暂无书籍", face = ctx.font("cfont", 18), max_width = ctx.width })
        end
        local n = #files
        local st = L:state(ctx.entry)
        st.index = ((st.index or 1) - 1) % n + 1
        local function go(delta)
            st.index = ((st.index - 1 + delta) % n) + 1
            UIManager:nextTick(function() L:refreshInstance() end)
        end
        local function mid(widget) -- 水平居中
            return CenterContainer:new{ dimen = Geom:new{ w = ctx.width, h = widget:getSize().h }, widget }
        end

        local cur = files[st.index]
        local gap = ctx.px(14)
        local center_h = ctx.px(o.center_height)
        local side_h = math.floor(center_h * math.max(30, math.min(100, o.side_percent)) / 100)

        -- 中间: 当前书 (点击打开)
        local center_cover = L:makeCover(cur, center_h, math.floor(ctx.width * 0.36), ctx.font)
        center_cover = tappable(center_cover, function() L:openBook(cur) end)

        -- 两侧: 上一本 / 下一本 (点击切换); 只有 2 本时仅显示右侧
        local left_file = n >= 3 and files[(st.index - 2) % n + 1] or nil
        local right_file = n >= 2 and files[st.index % n + 1] or nil
        local function side(file, delta)
            if not file then return nil, 0 end
            local w, sw = L:makeCover(file, side_h, math.floor(ctx.width * 0.26), ctx.font)
            return tappable(w, function() go(delta) end), sw
        end
        local lw, lsw = side(left_file, -1)
        local rw, rsw = side(right_file, 1)
        local slot_w = math.max(lsw, rsw)
        local function slot(widget) -- 两侧槽位等宽, 保证中间封面始终居中
            if widget then
                return CenterContainer:new{ dimen = Geom:new{ w = slot_w, h = widget:getSize().h }, widget }
            end
            return HorizontalSpan:new{ width = slot_w }
        end
        local row = HorizontalGroup:new{
            align = "center",
            slot(lw), HorizontalSpan:new{ width = gap }, center_cover, HorizontalSpan:new{ width = gap }, slot(rw),
        }

        local vg = VerticalGroup:new{ align = "center" }
        if o.show_label and o.label ~= "" then
            vg[#vg + 1] = mid(TextWidget:new{ text = o.label, face = ctx.font("cfont", 16), bold = true, max_width = ctx.width })
            vg[#vg + 1] = VerticalSpan:new{ width = ctx.px(10) }
        end
        vg[#vg + 1] = mid(row)
        if o.show_title then
            local meta = L:getBookMeta(cur)
            vg[#vg + 1] = VerticalSpan:new{ width = ctx.px(10) }
            vg[#vg + 1] = mid(TextWidget:new{
                text = meta.title, face = ctx.font("cfont", o.title_size), bold = true, max_width = ctx.width,
            })
            if o.show_progress then
                vg[#vg + 1] = VerticalSpan:new{ width = ctx.px(3) }
                vg[#vg + 1] = mid(TextWidget:new{
                    text = string.format("阅读进度 %d%%", math.floor(meta.percent * 100 + 0.5)),
                    face = ctx.font("cfont", 16), max_width = ctx.width,
                })
            end
        end
        if n > 1 and o.show_indicator then
            local dots = {}
            if n >= 3 then
                -- 窗口大小取奇数, 且不超过书数; ● 永远在正中, 与中间的大封面对应
                local w = math.min(o.indicator_dots, n)
                if w % 2 == 0 then w = w - 1 end
                w = math.max(w, 1)
                local half = (w - 1) / 2
                for off = -half, half do
                    dots[#dots + 1] = (off == 0) and "●" or "○"
                end
            else
                for ii = 1, n do dots[ii] = (ii == st.index) and "●" or "○" end
            end
            vg[#vg + 1] = VerticalSpan:new{ width = ctx.px(10) }
            vg[#vg + 1] = mid(TextWidget:new{
                text = table.concat(dots, " "), face = ctx.font("cfont", 14), max_width = ctx.width,
            })
        end

        if n > 1 then
            ctx.schedule(o.auto_seconds, function() go(1) end)
            return swipeable(vg, function() go(1) end, function() go(-1) end)
        end
        return vg
    end,
}

-- 收藏书籍 -----------------------------------------------------------------
L:registerModule{
    id = "favorites", title = "收藏书籍",
    defaults = { count = 4, cover_height = 120, show_title = true, title_size = 14 },
    options = {
        { key = "count", label = "书籍数量", type = "number", min = 1, max = 8 },
        { key = "cover_height", label = "封面高度", type = "number", min = 50, max = 400, step = 5 },
        { key = "show_title", label = "显示书名", type = "bool" },
        { key = "title_size", label = "书名字号", type = "number", min = 8, max = 30 },
    },
    build = function(ctx)
        local o = ctx.opts
        local files = L:getFavorites(math.min(o.count, 8))
        if #files == 0 then
            return ctx.center(TextWidget:new{ text = "收藏夹为空", face = ctx.font("cfont", 18), max_width = ctx.width })
        end
        return L:bookRow(ctx, files, o, ctx.width, #files)
    end,
}

-- 问候语 -------------------------------------------------------------------
L:registerModule{
    id = "greeting", title = "问候语",
    defaults = { name = "", size = 28, bold = true },
    options = {
        { key = "name", label = "称呼(可留空)", type = "string" },
        { key = "size", label = "字号", type = "number", min = 10, max = 100 },
        { key = "bold", label = "加粗", type = "bool" },
    },
    build = function(ctx)
        local o = ctx.opts
        local h = tonumber(os.date("%H"))
        local g = (h >= 5 and h < 11 and "早上好") or (h >= 11 and h < 13 and "中午好")
            or (h >= 13 and h < 18 and "下午好") or (h >= 18 and h < 23 and "晚上好") or "夜深了"
        if o.name and o.name ~= "" then g = g .. "," .. o.name end
        return ctx.center(TextWidget:new{ text = g, face = ctx.font("cfont", o.size), bold = o.bold, max_width = ctx.width })
    end,
}

-- 快捷指令 (每个实例自带一组按钮) -------------------------------------------
L:registerModule{
    id = "quick_actions", title = "快捷指令",
    defaults = { columns = 3, tile_height = 64, font_size = 18, icon_size = 36, show_labels = true, bold = false },
    options = {
        { key = "columns", label = "列数", type = "number", min = 1, max = 8 },
        { key = "tile_height", label = "按钮高度", type = "number", min = 30, max = 200, step = 2 },
        { key = "show_labels", label = "显示标签", type = "bool" },
        { key = "font_size", label = "标签字号", type = "number", min = 8, max = 40 },
        { key = "bold", label = "标签加粗", type = "bool" },
        { key = "icon_size", label = "图标大小", type = "number", min = 16, max = 120, step = 2 },
    },
    -- 额外菜单项: 编辑这一组按钮
    menu = function(entry)
        return {
            {
                text = "按钮设置…",
                sub_item_table_func = function()
                    local list = {}
                    L:fillActionList(list, entry)
                    return list
                end,
            },
        }
    end,
    build = function(ctx)
        local o = ctx.opts
        local actions = ctx.entry.actions or {}
        if #actions == 0 then return nil end
        local cols = math.max(1, math.min(o.columns, #actions))
        local gap = ctx.px(6)
        local cell_w = math.floor((ctx.width - (cols - 1) * gap) / cols)
        local tile_h = ctx.px(o.tile_height)
        local icon_px = ctx.px(o.icon_size)
        local vg = VerticalGroup:new{ align = o.align }
        local row
        for ii, entry in ipairs(actions) do
            if (ii - 1) % cols == 0 then
                if row then
                    vg[#vg + 1] = row
                    vg[#vg + 1] = VerticalSpan:new{ width = gap }
                end
                row = HorizontalGroup:new{ align = "top" }
            end
            local content = VerticalGroup:new{ align = "center" }
            local has_icon = entry.icon and entry.icon ~= ""
            if has_icon then
                content[#content + 1] = IconWidget:new{ icon = entry.icon, width = icon_px, height = icon_px }
            end
            if o.show_labels or not has_icon then
                if has_icon then content[#content + 1] = VerticalSpan:new{ width = ctx.px(3) } end
                content[#content + 1] = TextWidget:new{
                    text = L:actionLabel(entry), face = ctx.font("cfont", o.font_size), bold = o.bold,
                    max_width = cell_w - ctx.px(8),
                }
            end
            local tile = CenterContainer:new{ dimen = Geom:new{ w = cell_w, h = tile_h }, content }
            row[#row + 1] = tappable(tile, function() L:runAction(entry) end)
            if ii % cols ~= 0 and ii < #actions then row[#row + 1] = HorizontalSpan:new{ width = gap } end
        end
        if row then vg[#vg + 1] = row end
        return ctx.center(vg)
    end,
}

-- 状态 ---------------------------------------------------------------------
L:registerModule{
    id = "status", title = "状态",
    defaults = { show_battery = true, show_wifi = true, size = 16 },
    options = {
        { key = "show_battery", label = "显示电量", type = "bool" },
        { key = "show_wifi", label = "显示 Wi-Fi", type = "bool" },
        { key = "size", label = "字号", type = "number", min = 8, max = 40 },
    },
    build = function(ctx)
        local o = ctx.opts
        local parts = {}
        if o.show_battery and Device:hasBattery() then
            pcall(function()
                local pd = Device:getPowerDevice()
                local s = string.format("电量 %d%%", pd:getCapacity())
                if pd:isCharging() then s = s .. " +" end
                parts[#parts + 1] = s
            end)
        end
        if o.show_wifi and Device:hasWifiToggle() then
            pcall(function()
                local NetworkMgr = require("ui/network/manager")
                parts[#parts + 1] = NetworkMgr:isWifiOn() and "Wi-Fi 已开" or "Wi-Fi 已关"
            end)
        end
        if #parts == 0 then return nil end
        return ctx.center(TextWidget:new{
            text = table.concat(parts, "   |   "), face = ctx.font("cfont", o.size), max_width = ctx.width,
        })
    end,
}

-- 文字 ---------------------------------------------------------------------
L:registerModule{
    id = "text", title = "文字 / 引言",
    defaults = { text = "欢迎回来。", size = 20, bold = false },
    options = {
        { key = "text", label = "文字", type = "string" },
        { key = "size", label = "字号", type = "number", min = 8, max = 80 },
        { key = "bold", label = "加粗", type = "bool" },
    },
    build = function(ctx)
        local o = ctx.opts
        if not o.text or o.text == "" then return nil end
        return TextBoxWidget:new{
            text = o.text, face = ctx.font("cfont", o.size), bold = o.bold,
            width = ctx.width, alignment = o.align,
        }
    end,
}

-- 间隔 ---------------------------------------------------------------------
L:registerModule{
    id = "spacer", title = "间隔",
    defaults = { height = 30 },
    options = { { key = "height", label = "高度", type = "number", min = 4, max = 400, step = 2 } },
    build = function(ctx)
        return VerticalSpan:new{ width = ctx.px(ctx.opts.height) }
    end,
}

-- 自定义模块 (koreader/launcher/modules/*.lua) -------------------------------
local function loadUserModules()
    if mode(MODULE_DIR) ~= "directory" then return end
    for name in lfs.dir(MODULE_DIR) do
        if name:match("%.lua$") then
            local ok, spec = pcall(dofile, MODULE_DIR .. "/" .. name)
            if ok and type(spec) == "table" then
                L:registerModule(spec)
            else
                logger.warn("launcher: failed to load module", name, spec)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- 启动器窗口
-- ---------------------------------------------------------------------------

local LauncherWidget = InputContainer:extend{
    name = "launcher_homescreen",
    covers_fullscreen = true,
}

local NO_FORWARD = { onGesture = true, onKeyPress = true, onKeyRepeat = true, onKeyRelease = true }

function LauncherWidget:_layout()
    local sw, sh = Screen:getWidth(), Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = sw, h = sh }
    local zone = Geom:new{ x = 0, y = 0, w = sw, h = math.floor(sh * MENU_ZONE_H) }
    self.ges_events = {
        -- 顶部下滑 / 点按 → 交给 FileManager 的菜单 (下滑页面)
        LauncherSwipe = { GestureRange:new{ ges = "swipe", range = zone } },
        LauncherTap = { GestureRange:new{ ges = "tap", range = zone } },
    }
    self.key_events = Device:hasKeys() and { LauncherBack = { { "Back" } } } or {}
end

function LauncherWidget:init()
    self:_layout()
    self:rebuild()
    self:_schedule()
end

function LauncherWidget:rebuild(full)
    local cfg = L.cfg
    local sw, sh = self.dimen.w, self.dimen.h

    -- 清掉模块定时器 (模块重建时会重新注册)
    for ii, f in ipairs(self._mod_timers or {}) do UIManager:unschedule(f) end
    self._mod_timers = {}

    -- 壁纸层只在首次 / 屏幕尺寸变化时处理, 之后只换内容层
    if full or not self._layers then
        if self[1] then
            self[1]:free()
            self[1] = nil
        end
        self._content = nil
        self._layers = OverlapGroup:new{ dimen = Geom:new{ w = sw, h = sh } }
        local wp = L:buildWallpaper(sw, sh)
        if wp then table.insert(self._layers, wp) end
        self[1] = FrameContainer:new{
            background = Blitbuffer.COLOR_WHITE, bordersize = 0, padding = 0, margin = 0, self._layers,
        }
    end
    if self._content then
        table.remove(self._layers, #self._layers)
        self._content:free()
        self._content = nil
    end

    local margin = scale(cfg.margin)
    local gap = scale(cfg.spacing)
    local avail_w, avail_h = sw - 2 * margin, sh - 2 * margin

    local group = VerticalGroup:new{ align = "left" }
    local used, count = 0, 0
    for ii, entry in ipairs(cfg.modules) do
        local spec = L.modules[entry.id]
        if entry.enabled and spec then
            local opts = mergedOpts(entry, spec)
            local mw = math.floor(avail_w * math.max(20, math.min(100, opts.width_pct)) / 100)
            local ok, w = pcall(spec.build, L:makeCtx(mw, opts, entry, self))
            if not ok then
                logger.warn("launcher: module build failed", entry.id, w)
                w = nil
            end
            if w then
                local bh = w:getSize().h
                local holder = alignBox(opts.align, avail_w, bh, w)
                local above = scale(opts.space_above) + (count > 0 and gap or 0)
                if used + above + bh > avail_h then
                    holder:free()
                    break -- 放不下就不再继续 (后面的模块被裁掉)
                end
                if above > 0 then group[#group + 1] = VerticalSpan:new{ width = above } end
                group[#group + 1] = holder
                used = used + above + bh
                count = count + 1
            end
        end
    end

    local top = margin
    if cfg.valign == "center" then
        top = top + math.floor((avail_h - used) / 2)
    elseif cfg.valign == "bottom" then
        top = top + (avail_h - used)
    end
    self._content = VerticalGroup:new{
        align = "left",
        VerticalSpan:new{ width = top },
        HorizontalGroup:new{ HorizontalSpan:new{ width = margin }, group },
    }
    self._layers[#self._layers + 1] = self._content
end

function LauncherWidget:_schedule()
    if self._tick then UIManager:unschedule(self._tick) end
    local m = L.cfg.refresh_minutes
    if m and m > 0 then
        self._tick = function()
            local top = UIManager.getTopmostVisibleWidget and UIManager:getTopmostVisibleWidget()
            if not top or top == self then
                self:rebuild()
                UIManager:setDirty(self, "ui")
            end
            self:_schedule()
        end
        UIManager:scheduleIn(m * 60, self._tick)
    end
end

function LauncherWidget:onShow()
    UIManager:setDirty(self, function() return "flashui", self.dimen end)
end

function LauncherWidget:onCloseWidget()
    if self._tick then UIManager:unschedule(self._tick) end
    for ii, f in ipairs(self._mod_timers or {}) do UIManager:unschedule(f) end
    self._mod_timers = {}
    if self[1] then
        self[1]:free()
        self[1] = nil
    end
    if L.instance == self then L.instance = nil end
    UIManager:setDirty(nil, "full")
end

function LauncherWidget:_onResize()
    self:_layout()
    self:rebuild(true)
    UIManager:setDirty(self, "full")
end
LauncherWidget.onSetDimensions = LauncherWidget._onResize
LauncherWidget.onScreenResize = LauncherWidget._onResize

function LauncherWidget:onLauncherBack()
    L:close()
    return true
end

function LauncherWidget:onLauncherSwipe(arg, ges)
    local fm = FileManager.instance
    if fm and fm.menu then
        if fm.menu.onSwipeShowMenu then
            return fm.menu:onSwipeShowMenu(ges)
        elseif ges.direction == "south" then
            return fm.menu:onShowMenu()
        end
    end
end

function LauncherWidget:onLauncherTap(arg, ges)
    local fm = FileManager.instance
    if fm and fm.menu and fm.menu.onTapShowMenu then
        return fm.menu:onTapShowMenu(ges)
    end
end

function LauncherWidget:onShowLauncherHomescreen()
    return true
end

-- Dispatcher 执行快捷指令时发出的事件, 启动器没处理的转发给 FileManager
function LauncherWidget:handleEvent(event)
    if InputContainer.handleEvent(self, event) then return true end
    if L.dispatching and not NO_FORWARD[event.handler] then
        local fm = FileManager.instance
        if fm then return fm:handleEvent(event) end
    end
    return false
end

function L:show(force)
    if not force and not self.cfg.enabled then return end
    if not FileManager.instance then return end
    self:close()
    self._state = nil -- 轮播等模块的状态复位: 每次进入都默认聚焦第 1 本 (当前阅读) 在中间
    self._meta = nil  -- 书籍信息缓存复位: 读完书回来时进度会刷新
    self.instance = LauncherWidget:new{}
    UIManager:show(self.instance, "full")
end

function L:close()
    local w = self.instance
    if w then
        self.instance = nil
        UIManager:close(w, "full")
    end
end

-- ---------------------------------------------------------------------------
-- 设置菜单
-- ---------------------------------------------------------------------------

local function askNumber(title, value, min, max, cb, step)
    UIManager:show(SpinWidget:new{
        title_text = title, value = value, value_min = min, value_max = max,
        value_step = step or 1, value_hold_step = (step or 1) * 5, ok_text = "确定",
        callback = function(spin) cb(spin.value) end,
    })
end

local function askText(title, value, cb)
    local dlg
    dlg = InputDialog:new{
        title = title, input = value or "",
        buttons = { {
            { text = "取消", id = "close", callback = function() UIManager:close(dlg) end },
            { text = "保存", is_enter_default = true, callback = function()
                local v = dlg:getInputText()
                UIManager:close(dlg)
                cb(v)
            end },
        } },
    }
    UIManager:show(dlg)
    dlg:onShowKeyboard()
end

local function moveInList(list, item, delta)
    for ii, v in ipairs(list) do
        if v == item then
            local j = ii + delta
            if j >= 1 and j <= #list then
                list[ii], list[j] = list[j], list[ii]
            end
            return
        end
    end
end

local function removeFromList(list, item)
    for ii, v in ipairs(list) do
        if v == item then table.remove(list, ii) return end
    end
end

--- 列表项的 "上移 / 下移 / 删除" 三个菜单项 (模块列表与按钮列表共用)
--- 操作后保存、刷新上级列表, 并回到上级菜单 (菜单保持打开)
local function reorderItems(items_list, item, refill, delete_text)
    local function act(fn)
        return function(tm)
            fn()
            L:save()
            refill()
            tm:backToUpperMenu()
        end
    end
    return {
        { text = "上移", keep_menu_open = true, callback = act(function() moveInList(items_list, item, -1) end) },
        { text = "下移", keep_menu_open = true, callback = act(function() moveInList(items_list, item, 1) end) },
        { text = delete_text, keep_menu_open = true, callback = act(function() removeFromList(items_list, item) end) },
    }
end

local function radioItems(options, get, set)
    local items = {}
    for ii, o in ipairs(options) do
        items[#items + 1] = {
            text = o.text, radio = true, keep_menu_open = true,
            checked_func = function() return get() == o.value end,
            callback = function() set(o.value) end,
        }
    end
    return items
end

--- 由选项声明自动生成菜单项
function L:optionItems(entry, spec, options)
    entry.opts = entry.opts or {}
    local items = {}
    for ii, opt in ipairs(options or {}) do
        local function get()
            local v = entry.opts[opt.key]
            if v == nil then v = defaultFor(spec, opt.key) end
            return v
        end
        local function set(v)
            entry.opts[opt.key] = v
            self:save()
        end
        if opt.type == "bool" then
            items[#items + 1] = {
                text = opt.label, keep_menu_open = true,
                checked_func = function() return get() == true end,
                callback = function() set(not get()) end,
            }
        elseif opt.type == "number" then
            items[#items + 1] = {
                text_func = function() return opt.label .. ": " .. tostring(get()) end,
                keep_menu_open = true,
                callback = function(tm)
                    askNumber(opt.label, get(), opt.min or 0, opt.max or 100, function(v)
                        set(v)
                        tm:updateItems()
                    end, opt.step)
                end,
            }
        elseif opt.type == "string" then
            items[#items + 1] = {
                text_func = function() return opt.label .. ": " .. tostring(get() or "") end,
                keep_menu_open = true,
                callback = function(tm)
                    askText(opt.label, tostring(get() or ""), function(v)
                        set(v)
                        tm:updateItems()
                    end)
                end,
            }
        elseif opt.type == "choice" then
            local choices = {}
            for jj, c in ipairs(opt.choices or {}) do
                choices[#choices + 1] = type(c) == "table" and c or { text = tostring(c), value = c }
            end
            items[#items + 1] = {
                text_func = function() return opt.label .. ": " .. tostring(get()) end,
                sub_item_table = radioItems(choices, get, set),
            }
        end
    end
    return items
end

function L:moduleMenu(entry, list)
    local spec = self.modules[entry.id]
    local items = {
        {
            text = "启用", keep_menu_open = true,
            checked_func = function() return entry.enabled == true end,
            callback = function() entry.enabled = not entry.enabled self:save() end,
        },
    }
    local edit = reorderItems(self.cfg.modules, entry, function() self:fillModuleList(list) end, "删除此模块")
    edit[#edit].separator = true
    for ii, it in ipairs(edit) do items[#items + 1] = it end
    if not spec then return items end
    items[#items + 1] = {
        text = "大小与位置",
        sub_item_table_func = function() return self:optionItems(entry, spec, COMMON_OPTIONS) end,
    }
    local content = self:optionItems(entry, spec, spec.options)
    if #content > 0 then
        items[#items + 1] = { text = "内容", sub_item_table = content }
    end
    if spec.menu then
        local ok, extra = pcall(spec.menu, entry)
        if ok and type(extra) == "table" then
            for ii, it in ipairs(extra) do items[#items + 1] = it end
        end
    end
    return items
end

function L:fillModuleList(list)
    for ii = #list, 1, -1 do list[ii] = nil end
    list[1] = {
        text = "添加模块…", separator = true,
        sub_item_table_func = function()
            local items = {}
            for ii, id in ipairs(self.module_ids) do
                local spec = self.modules[id]
                items[#items + 1] = {
                    text = spec.title, keep_menu_open = true,
                    callback = function(tm)
                        local e = { id = id, enabled = true, opts = {} }
                        if id == "quick_actions" then e.actions = defaultActions() end
                        table.insert(self.cfg.modules, e)
                        self:save()
                        self:fillModuleList(list)
                        tm:backToUpperMenu()
                    end,
                }
            end
            return items
        end,
    }
    for ii, entry in ipairs(self.cfg.modules) do
        list[#list + 1] = {
            text_func = function()
                return (entry.enabled and "[x] " or "[ ] ") .. self:entryTitle(entry)
            end,
            sub_item_table_func = function() return self:moduleMenu(entry, list) end,
        }
    end
end

-- 快捷按钮编辑 -------------------------------------------------------------
local function keepOpen(items)
    for ii, it in ipairs(items) do
        if not it.sub_item_table_func then it.keep_menu_open = true end
        if type(it.sub_item_table) == "table" then keepOpen(it.sub_item_table) end
    end
end

function L:actionPicker(action)
    action.settings = action.settings or {}
    local caller = setmetatable({}, {
        __newindex = function(_t, k, _v)
            if k == "updated" then -- Dispatcher 选择回调会写 caller.updated = true
                action.builtin = nil
                self:save()
            end
        end,
    })
    local picker = {}
    local ok, err = pcall(Dispatcher.addSubMenu, Dispatcher, caller, picker, action, "settings")
    if not ok then
        logger.warn("launcher: dispatcher picker failed", err)
        picker = { { text = "当前 KOReader 版本不支持动作选择器", enabled_func = function() return false end } }
    end
    keepOpen(picker)
    return picker
end

function L:actionMenu(action, list, owner)
    local function setBuiltin(name)
        return function(tm)
            action.builtin = name
            action.settings = {}
            self:save()
            tm:updateItems()
        end
    end
    local items = {
        {
            text_func = function() return "标签: " .. self:actionLabel(action) end,
            keep_menu_open = true,
            callback = function(tm)
                askText("标签", action.label or "", function(v)
                    action.label = v
                    self:save()
                    tm:updateItems()
                end)
            end,
        },
        {
            text_func = function()
                local s = self:actionSummary(action)
                return "动作: " .. (s ~= "" and s or "(无)")
            end,
            sub_item_table_func = function() return self:actionPicker(action) end,
        },
        {
            text_func = function() return "图标名(可选): " .. (action.icon or "") end,
            keep_menu_open = true,
            callback = function(tm)
                askText("图标名(可选,如 home、favorites、history)", action.icon or "", function(v)
                    action.icon = v
                    self:save()
                    tm:updateItems()
                end)
            end,
        },
        { text = "使用内置:打开文件浏览器", keep_menu_open = true, callback = setBuiltin("files") },
        { text = "使用内置:打开顶部菜单", keep_menu_open = true, callback = setBuiltin("menu"), separator = true },
    }
    local edit = reorderItems(owner.actions, action, function() self:fillActionList(list, owner) end, "删除")
    for ii, it in ipairs(edit) do items[#items + 1] = it end
    return items
end

function L:fillActionList(list, owner)
    owner.actions = owner.actions or {}
    for ii = #list, 1, -1 do list[ii] = nil end
    list[#list + 1] = {
        text = "添加按钮", keep_menu_open = true,
        callback = function(tm)
            table.insert(owner.actions, { label = "新按钮", settings = {} })
            self:save()
            self:fillActionList(list, owner)
            tm:updateItems()
        end,
    }
    list[#list + 1] = {
        text = "恢复默认按钮", separator = true, keep_menu_open = true,
        callback = function(tm)
            owner.actions = defaultActions()
            self:save()
            self:fillActionList(list, owner)
            tm:updateItems()
        end,
    }
    for ii, action in ipairs(owner.actions) do
        list[#list + 1] = {
            text_func = function() return string.format("%d. %s", ii, self:actionLabel(action)) end,
            sub_item_table_func = function() return self:actionMenu(action, list, owner) end,
        }
    end
end

function L:wallpaperMenu()
    local cfg = self.cfg
    return {
        {
            text_func = function()
                local p = cfg.wallpaper
                return "当前: " .. ((p and p ~= "") and p or "(无)")
            end,
            enabled_func = function() return false end,
        },
        {
            text = "选择壁纸图片…",
            keep_menu_open = true,
            callback = function(tm)
                UIManager:show(PathChooser:new{
                    title = "选择壁纸图片",
                    path = (mode(cfg.wallpaper or "") == "file") and cfg.wallpaper:match("^(.*)/[^/]*$") or WALLPAPER_DIR,
                    select_directory = false,
                    file_filter = isImage,
                    onConfirm = function(p)
                        cfg.wallpaper = p
                        self:save()
                        tm:updateItems()
                    end,
                })
            end,
        },
        {
            text = "选择壁纸文件夹(每次随机一张)…",
            keep_menu_open = true,
            callback = function(tm)
                UIManager:show(PathChooser:new{
                    title = "选择壁纸文件夹",
                    path = WALLPAPER_DIR,
                    select_file = false,
                    show_files = false,
                    onConfirm = function(p)
                        cfg.wallpaper = p
                        self:save()
                        tm:updateItems()
                    end,
                })
            end,
        },
        {
            text = "清除壁纸", keep_menu_open = true, separator = true,
            callback = function(tm)
                cfg.wallpaper = ""
                self:save()
                tm:updateItems()
            end,
        },
        {
            text_func = function()
                local t = tonumber(cfg.wallpaper_tone) or 0
                local desc = t < 0 and "变暗" or (t > 0 and "变浅" or "原图")
                return string.format("壁纸深浅: %d(%s)", t, desc)
            end,
            keep_menu_open = true,
            callback = function(tm)
                askNumber("壁纸深浅(负数变暗,正数变浅,0 为原图)", tonumber(cfg.wallpaper_tone) or 0, -100, 100, function(v)
                    cfg.wallpaper_tone = v
                    self:save()
                    tm:updateItems()
                end, 5)
            end,
        },
        {
            text = "壁纸模式",
            sub_item_table = radioItems({
                { text = "填充(裁剪铺满)", value = "cover" },
                { text = "适应(保持比例)", value = "fit" },
                { text = "拉伸", value = "stretch" },
            }, function() return cfg.wallpaper_mode end, function(v) cfg.wallpaper_mode = v self:save() end),
        },
    }
end

function L:layoutMenu()
    local cfg = self.cfg
    local function spinItem(label, key, min, max)
        return {
            text_func = function() return label .. ": " .. tostring(cfg[key]) end,
            keep_menu_open = true,
            callback = function(tm)
                askNumber(label, cfg[key], min, max, function(v)
                    cfg[key] = v
                    self:save()
                    tm:updateItems()
                end)
            end,
        }
    end
    return {
        spinItem("外边距", "margin", 0, 100),
        spinItem("模块默认间距", "spacing", 0, 100),
        spinItem("自动刷新(分钟,0 为关闭)", "refresh_minutes", 0, 60),
        {
            text = "所有模块的垂直位置",
            sub_item_table = radioItems({
                { text = "顶部", value = "top" },
                { text = "居中", value = "center" },
                { text = "底部", value = "bottom" },
            }, function() return cfg.valign end, function(v) cfg.valign = v self:save() end),
        },
    }
end

function L:buildMenu()
    local cfg = self.cfg
    local module_list = {}
    self:fillModuleList(module_list)
    return {
        {
            text = "立即显示简易桌面",
            callback = function(tm)
                if tm and tm.closeMenu then tm:closeMenu() end
                self:show(true)
            end,
            separator = true,
        },
        {
            text = "启用简易桌面", keep_menu_open = true,
            checked_func = function() return cfg.enabled end,
            callback = function() cfg.enabled = not cfg.enabled self:save() end,
        },
        {
            text = "将简易桌面设为文件浏览器的初始界面", keep_menu_open = true,
            checked_func = function() return cfg.auto_show end,
            callback = function() cfg.auto_show = not cfg.auto_show self:save() end,
        },
        {
            text = "文件浏览器的 Home 键进入简易桌面", keep_menu_open = true,
            checked_func = function() return cfg.home_to_launcher end,
            callback = function() cfg.home_to_launcher = not cfg.home_to_launcher self:save() end,
            separator = true,
        },
        { text = "模块(添加 / 删除 / 排序 / 自定义)", sub_item_table = module_list },
        { text = "壁纸", sub_item_table_func = function() return self:wallpaperMenu() end },
        { text = "布局", sub_item_table_func = function() return self:layoutMenu() end },
        { text = "在线更新", sub_item_table_func = function() return self:updateMenu() end },
    }
end

function L:addToMainMenu(menu_items)
    menu_items.launcher_homescreen = {
        text = "简易桌面",
        sorting_hint = "more_tools",
        sub_item_table_func = function() return L:buildMenu() end,
    }
end

-- ---------------------------------------------------------------------------
-- 在线更新 (从 GitHub 上的具体文件下载; 仅手动触发)
-- ---------------------------------------------------------------------------

--- 比较 x.x.x 版本号: a>b 返回 1, a<b 返回 -1, 相等返回 0 (缺省段按 0 处理)
local function cmpVersion(a, b)
    local function parts(v)
        local t = {}
        for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end
        return t
    end
    local pa, pb = parts(a), parts(b)
    for ii = 1, math.max(#pa, #pb) do
        local x, y = pa[ii] or 0, pb[ii] or 0
        if x ~= y then return x > y and 1 or -1 end
    end
    return 0
end

local function httpGet(url)
    local ltn12 = require("ltn12")
    local http = url:match("^https") and require("ssl.https") or require("socket.http")
    local socketutil = require("socketutil")
    local chunks = {}
    pcall(socketutil.set_timeout, socketutil, 10, 40)
    local ok, r1, code, _h, status = pcall(http.request, {
        url = url, method = "GET", sink = ltn12.sink.table(chunks),
        headers = { ["User-Agent"] = "KOReader-launcher-updater", ["Cache-Control"] = "no-cache" },
    })
    pcall(socketutil.reset_timeout, socketutil)
    if not ok then return nil, tostring(r1) end
    if code ~= 200 then return nil, tostring(status or code) end
    return table.concat(chunks)
end

local function readFile(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local data = f:read("*a")
    f:close()
    return data
end

local function writeFile(path, data)
    local f, err = io.open(path, "wb")
    if not f then return false, err end
    f:write(data)
    f:close()
    return true
end

function L:selfPath()
    local src = SELF_SOURCE:gsub("^@", "")
    if src:match("%.lua$") and mode(src) == "file" then return src end
    return DataStorage:getDataDir() .. "/patches/2-simple-launcher.lua"
end

--- 覆盖当前补丁文件; 是否先备份为 .bak 由用户在菜单中决定
function L:installUpdate(body, remote_v)
    local path = self:selfPath()
    if self.cfg.backup_on_update then
        local old = readFile(path)
        if old then writeFile(path .. ".bak", old) end -- .bak 不会被 KOReader 当作补丁加载
    end
    -- 先写临时文件再改名: 写入失败时原文件不受影响
    local tmp = path .. ".new"
    local ok, err = writeFile(tmp, body)
    if ok then
        ok, err = os.rename(tmp, path)
    end
    if not ok then
        toast("更新失败:" .. tostring(err), 5)
        return
    end
    local msg = string.format("已更新到 v%s,需要重启 KOReader 才能生效。", tostring(remote_v or "?"))
    if UIManager.askForRestart then
        UIManager:askForRestart(msg)
    else
        toast(msg .. "\n请手动重启。", 5)
    end
end

--- force: 版本相同也重新下载并覆盖
function L:checkUpdate(force)
    local function run()
        local info = InfoMessage:new{ text = "正在检查更新…" }
        UIManager:show(info)
        UIManager:forceRePaint()
        -- 附带时间戳, 避免 GitHub raw 的 CDN 缓存返回旧文件
        local body, err = httpGet(UPDATE_URL .. "?t=" .. os.time())
        UIManager:close(info)
        if not body then
            toast("下载失败:" .. tostring(err), 5)
            return
        end
        if not (loadstring or load)(body) or not body:find('package.loaded["simple_launcher"]', 1, true) then
            toast("下载的内容不是有效的简易桌面补丁,已取消更新。", 5)
            return
        end
        -- 线上版本号: 优先读代码里的 VERSION 常量, 其次读 LAUNCHER_VERSION 标记
        local remote_v = body:match('local VERSION = "(%d+[%.%d]*)"')
            or body:match("LAUNCHER_VERSION:%s*(%d+[%.%d]*)")
        if not force and (not remote_v or cmpVersion(remote_v, VERSION) <= 0) then
            toast(string.format("已是最新版本(本地 v%s,线上 v%s)。", VERSION, tostring(remote_v or "?")))
            return
        end
        UIManager:show(ConfirmBox:new{
            text = string.format("发现新版本 v%s(当前 v%s),是否更新?\n%s",
                tostring(remote_v or "?"), VERSION,
                self.cfg.backup_on_update and "旧文件会备份为 .bak。" or "不会备份旧文件。"),
            ok_text = "更新", cancel_text = "取消",
            ok_callback = function() self:installUpdate(body, remote_v) end,
        })
    end
    -- 未联网时 KOReader 会先提示连接 Wi-Fi
    require("ui/network/manager"):runWhenOnline(run)
end

function L:updateMenu()
    local cfg = self.cfg
    return {
        {
            text = string.format("当前版本: v%s", VERSION),
            enabled_func = function() return false end,
        },
        {
            text = "更新时备份原文件(.bak)", keep_menu_open = true,
            checked_func = function() return cfg.backup_on_update end,
            callback = function() cfg.backup_on_update = not cfg.backup_on_update self:save() end,
            separator = true,
        },
        { text = "检查更新", keep_menu_open = true, callback = function() self:checkUpdate(false) end },
        { text = "强制重新下载并覆盖", keep_menu_open = true, callback = function() self:checkUpdate(true) end },
    }
end

-- ---------------------------------------------------------------------------
-- 挂钩 KOReader
-- ---------------------------------------------------------------------------

L:load()
loadUserModules()

pcall(Dispatcher.registerAction, Dispatcher, "launcher_homescreen_show", {
    category = "none", event = "ShowLauncherHomescreen", title = "显示简易桌面", general = true,
})
function FileManager:onShowLauncherHomescreen()
    L:show(true)
    return true
end

function L:onFileManagerShown()
    local fm = FileManager.instance
    if not fm then return end
    self:patchHomeButton(fm)
    if fm.menu and not fm.menu._launcher_registered then
        fm.menu._launcher_registered = true
        fm.menu:registerToMainMenu(self)
        pcall(fm.menu.setUpdateItemTable, fm.menu)
    end
    if self.cfg.enabled and self.cfg.auto_show then
        self:show() -- 同步显示: 启动时不会先闪出文件列表
    end
end

local orig_showFiles = FileManager.showFiles
if orig_showFiles then
    FileManager.showFiles = function(fm_class, ...)
        local ret = orig_showFiles(fm_class, ...)
        L:onFileManagerShown()
        return ret
    end
end

-- 文件浏览器里的 "房子" 按钮 → 启动器
function L:homeToLauncher()
    if self.cfg.enabled and self.cfg.home_to_launcher and not self.instance and FileManager.instance then
        self:show(true)
        return true
    end
    return false
end

-- 直接改写标题栏左上角按钮的回调 (不依赖具体函数名, 兼容性最好)
function L:patchHomeButton(fm)
    local tb = fm and fm.title_bar
    if not tb or tb._launcher_patched then return end
    tb._launcher_patched = true
    if type(tb.left_icon_tap_callback) == "function" then
        local orig = tb.left_icon_tap_callback
        tb.left_icon_tap_callback = function(...)
            if L:homeToLauncher() then return end
            return orig(...)
        end
    end
    local btn = tb.left_button
    if btn and type(btn.callback) == "function" then
        local orig = btn.callback
        btn.callback = function(...)
            if L:homeToLauncher() then return end
            return orig(...)
        end
    end
end

-- 同时包装可能的 Home 入口 (键盘 Home 键 / Dispatcher 的 go_home 等)
for ii, name in ipairs{ "goHome", "onHome", "onGoHome" } do
    local orig = FileManager[name]
    if type(orig) == "function" then
        FileManager[name] = function(fm_self, ...)
            if L:homeToLauncher() then return true end
            return orig(fm_self, ...)
        end
    end
end

-- 标题栏每次重建后重新挂钩
local orig_setupLayout = FileManager.setupLayout
if type(orig_setupLayout) == "function" then
    FileManager.setupLayout = function(fm_self, ...)
        local ret = orig_setupLayout(fm_self, ...)
        L:patchHomeButton(fm_self)
        return ret
    end
end

-- 打开书之前先关闭启动器, 避免它残留在阅读器下面
local orig_showReader = ReaderUI.showReader
if orig_showReader then
    ReaderUI.showReader = function(reader_class, ...)
        L:close()
        return orig_showReader(reader_class, ...)
    end
end
