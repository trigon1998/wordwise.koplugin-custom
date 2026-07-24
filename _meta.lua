local _ = require("gettext")

local source = debug.getinfo(1, "S").source
local plugin_dir = source:match("^@(.*/)") or "./"
local UpdateConfig = dofile(plugin_dir .. "update_config.lua")

return {
    name = "wordwise",
    fullname = _("Word Wise"),
    description = _([[Shows compact English–Vietnamese inline hints for difficult words and specialist terms. Includes separate General, Economics, and Physics databases stored in the KOReader data directory.]]),
    version = UpdateConfig.version,
}
