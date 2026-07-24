package.path = "./?.lua;" .. package.path

local function widget_class()
    local class = {}
    function class:new(value) return value or {} end
    return class
end

local WidgetContainer = {}
function WidgetContainer:extend(definition)
    definition.__index = definition
    return definition
end

package.preload["ffi/blitbuffer"] = function()
    return { COLOR_DARK_GRAY = 1, COLOR_BLACK = 0 }
end
package.preload["ui/widget/buttondialog"] = function() return widget_class() end
package.preload["datastorage"] = function()
    return { getDataDir = function() return "/tmp/wordwise-test" end }
end
package.preload["dispatcher"] = function() return { registerAction = function() end } end
package.preload["ui/event"] = function() return widget_class() end
package.preload["ui/font"] = function()
    return { getFace = function(name, size) return { name = name, size = size } end }
end
package.preload["ui/widget/infomessage"] = function() return widget_class() end
package.preload["ui/rendertext"] = function() return {} end
package.preload["ui/widget/spinwidget"] = function() return widget_class() end
package.preload["ui/widget/textviewer"] = function() return widget_class() end
package.preload["ui/uimanager"] = function()
    return {
        close = function() end,
        nextTick = function(callback) callback() end,
        setDirty = function() end,
        show = function() end,
    }
end
package.preload["ui/widget/container/widgetcontainer"] = function() return WidgetContainer end
package.preload["libs/libkoreader-lfs"] = function()
    return { attributes = function() return nil end, mkdir = function() return true end }
end
package.preload["logger"] = function() return { warn = function() end } end
package.preload["gettext"] = function() return function(text) return text end end
package.preload["ffi/util"] = function()
    return { template = function(text) return text end }
end
package.preload["book_classifier"] = function()
    return { isVietnameseDominant = function() return false end, suggest = function() return "general" end }
end
package.preload["context_scorer"] = function()
    return { accept = function() return true, 0.9 end }
end
package.preload["known_words"] = function() return { open = function() return nil end } end
package.preload["wordwise_db"] = function() return { open = function() return nil end } end
package.preload["wordwise_updater"] = function()
    return {
        getRepository = function() return nil end,
        getMenuItems = function() return {} end,
    }
end

G_reader_settings = {
    readSetting = function() return nil end,
    saveSetting = function() end,
}

local WordWise = dofile("main.lua")

local function instance(values)
    return setmetatable(values or {}, { __index = WordWise })
end

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local layout = instance({
    ui = {
        view = { dimen = { x = 0, y = 0, w = 100, h = 200 } },
        font = { configurable = { font_face = "Book A", font_size = 28, line_spacing = 148 } },
    },
})
local records = {
    { key = "alpha", box = { x = 10, y = 20, w = 30, h = 12 } },
    { key = "beta", box = { x = 45, y = 20, w = 25, h = 12 } },
}
local signature = layout:pageLayoutSignature(records)
assert_equal(layout:pageLayoutSignature(records), signature, "layout signature must be stable")
records[1].box.x = 11
assert(layout:pageLayoutSignature(records) ~= signature,
    "word-coordinate changes must invalidate the layout signature")
records[1].box.x = 10
layout.ui.font.configurable.font_size = 29
assert(layout:pageLayoutSignature(records) ~= signature,
    "book-font-size changes must invalidate the layout signature")
layout.ui.font.configurable.font_size = 28
layout.ui.view.dimen.w = 200
assert(layout:pageLayoutSignature(records) ~= signature,
    "viewport/orientation changes must invalidate the layout signature")

local opened
local tap = instance({
    hints = {
        { surface = "hidden", box = { x = 50, y = 50, w = 20, h = 20 } },
        {
            surface = "visible",
            box = { x = 10, y = 10, w = 20, h = 20 },
            hitbox = { x = 8, y = 8, w = 24, h = 24 },
        },
    },
})
function tap:isEnabled() return true end
function tap:isQuickTapEnabled() return true end
function tap:showHintPopup(hint) opened = hint end
assert_equal(tap:onHintTap({ pos = { x = 55, y = 55 } }), false,
    "a collision-hidden hint must not receive taps")
assert_equal(opened, nil, "hidden hint must not open a popup")
assert_equal(tap:onHintTap({ pos = { x = 15, y = 15 } }), true,
    "a rendered hint must receive taps")
assert_equal(opened.surface, "visible", "visible hint must open its popup")

tap.page_cache = { stale = {} }
tap.page_cache_order = { "stale" }
tap:onSetDimensions()
assert_equal(#tap.hints, 0, "rotation must clear current hints")
assert_equal(next(tap.page_cache), nil, "rotation must clear cached coordinates")

local phrase_records = {}
for index, word in ipairs({ "earnings", "before", "interest", "and", "taxes" }) do
    phrase_records[index] = {
        key = word,
        surface = word,
        box = { x = (index - 1) * 20, y = 40, w = 18, h = 12 },
    }
end

local exact_lookups = 0
local phrase_db = {}
function phrase_db:lookupExact(term)
    exact_lookups = exact_lookups + 1
    if term == "earnings before interest and taxes" then
        return {
            term = term,
            lemma = term,
            short_en = "profit before financing and tax",
            short_vi = "lợi nhuận trước lãi vay và thuế",
            difficulty = 1,
            phrase_len = 5,
            priority = 100,
            domain = "economics",
        }
    end
end
function phrase_db:lookupWord() return nil end
function phrase_db:getMetadata(key)
    local values = { build_version = "2026.07.1-rc1", entry_count = 28118, phrase_count = 240 }
    return values[key]
end

local matcher = instance({
    hints = {},
    page_cache = {},
    page_cache_order = {},
    proper_names = {},
    ui = {
        view = { dimen = { x = 0, y = 0, w = 1080, h = 1440 } },
        font = { configurable = { font_face = "Book A", font_size = 28, line_spacing = 148 } },
    },
})
function matcher:isEnabled() return true end
function matcher:isSupportedDocument() return true end
function matcher:getDB() return phrase_db end
function matcher:collectVisibleWords() return phrase_records, 7 end
function matcher:getDomain() return "economics" end
function matcher:getHintLevel() return 5 end
function matcher:getGlossFontName() return "infofont" end
function matcher:getGlossFontSize() return 13 end
function matcher:currentLineSpacing() return self.ui.font.configurable.line_spacing end
function matcher:isKnown() return false end
function matcher:considerAutoSpacing() end

matcher:computePageHints()
assert_equal(#matcher.hints, 1, "five-word phrase must create one hint")
assert_equal(matcher.hints[1].phrase_len, 5, "five-word phrase length must be retained")
local first_pass_lookups = exact_lookups
matcher:computePageHints()
assert_equal(exact_lookups, first_pass_lookups, "unchanged layout must reuse the page cache")
phrase_records[1].box.x = 2
matcher:computePageHints()
assert(exact_lookups > first_pass_lookups, "changed coordinates must bypass the stale page cache")

local diagnostics = matcher:diagnosticsText()
assert(diagnostics:find("Plugin version: 2026.07.1%-rc1%.2%.1"),
    "diagnostics must expose the RC1.2.1 plugin version")
assert(diagnostics:find("Phrase matcher: up to 5 words", 1, true),
    "diagnostics must expose five-word phrase support")

print("RC1.2.1 main behavior tests: PASS")
