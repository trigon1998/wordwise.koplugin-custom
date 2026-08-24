package.path = "./?.lua;" .. package.path

local function widget_class()
    local class = {}
    function class:new(value) return value or {} end
    return class
end

package.preload["ui/widget/confirmbox"] = function() return widget_class() end
package.preload["ui/widget/infomessage"] = function() return widget_class() end
package.preload["ui/widget/inputdialog"] = function() return widget_class() end
package.preload["ui/widget/textviewer"] = function() return widget_class() end
package.preload["ui/uimanager"] = function() return {} end
package.preload["datastorage"] = function()
    return {
        getDataDir = function() return "/tmp/koreader" end,
        getSettingsDir = function() return "/tmp/koreader/settings" end,
    }
end
package.preload["device"] = function()
    return { canOpenLink = function() return false end }
end
package.preload["libs/libkoreader-lfs"] = function() return {} end
package.preload["gettext"] = function() return function(text) return text end end

local settings = {}
G_reader_settings = {
    readSetting = function(_, key) return settings[key] end,
    saveSetting = function(_, key, value) settings[key] = value end,
    delSetting = function(_, key) settings[key] = nil end,
}

local Updater = require("wordwise_updater")
local metadata = dofile("_meta.lua")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

assert_equal(metadata.version, "2026.07.1-rc1.4.1",
    "_meta.lua must use the updater configuration version")
assert_equal(metadata.name, "wordwise",
    "_meta.lua must expose the plugin identity used by KOReader")

assert(Updater.isValidRepository("owner/wordwise.koplugin"),
    "normal public repository must be accepted")
assert(Updater.isValidRepository("owner-name/repo_name.lua"),
    "GitHub-safe punctuation must be accepted")
assert(not Updater.isValidRepository("owner only"),
    "repository without owner/name separator must be rejected")
assert(not Updater.isValidRepository("https://github.com/owner/repo"),
    "full URLs must be rejected")
assert(not Updater.isValidRepository("../owner/repo"),
    "path traversal must be rejected")
assert(not Updater.isValidRepository("owner/repo;touch-x"),
    "shell punctuation must be rejected")

assert_equal(Updater.compareVersions(
    "2026.07.1-rc1.4.1", "2026.07.1-rc1.4.0"), 1,
    "RC1.3 battery build must be newer than the OTA test")
assert_equal(Updater.compareVersions(
    "2026.07.1", "2026.07.1-rc1.99"), 1,
    "stable release must be newer than its RC")
assert_equal(Updater.compareVersions(
    "2026.07.1-beta2", "2026.07.1-rc1"), -1,
    "beta must sort before RC")
assert_equal(Updater.compareVersions("bad-version", "2026.07.1"), nil,
    "unsupported versions must fail closed")

local data_zip_name, data_checksum_name = Updater.dataAssetNamesForVersion("2026.07.1-rc1.4.1")
assert_equal(data_zip_name, "WordWise_Databases_2026.07.1-rc1.4.1.zip",
    "database ZIP name must be deterministic")
assert_equal(data_checksum_name, data_zip_name .. ".sha256",
    "database checksum must follow the ZIP name")

local zip_name, checksum_name = Updater.assetNamesForVersion("2026.07.1-rc1.4.1")
assert_equal(zip_name, "wordwise.koplugin-v2026.07.1-rc1.4.1.zip",
    "release ZIP name must be deterministic")
assert_equal(checksum_name, zip_name .. ".sha256",
    "checksum asset must follow the ZIP name")

local releases = {
    { tag_name = "v2026.07.1-rc1.4.1", prerelease = true, draft = false },
    { tag_name = "v2026.07.1-rc1.4.2", prerelease = true, draft = false },
    { tag_name = "v2026.08.1-rc1.0", prerelease = true, draft = true },
    { tag_name = "v2026.06.9", prerelease = false, draft = false },
}
assert_equal(
    Updater.selectRelease(releases, "2026.07.1-rc1.4.1", true).tag_name,
    "v2026.07.1-rc1.4.2",
    "RC channel must select the newest eligible non-draft release")
assert_equal(
    Updater.selectRelease(releases, "2026.07.1-rc1.4.1", false),
    nil,
    "stable channel must ignore prereleases")

local mixed_releases = {
    { tag_name = "v2026.07.2-beta1", prerelease = true, draft = false },
    { tag_name = "v2026.07.1", prerelease = false, draft = false },
}
assert_equal(
    Updater.selectRelease(mixed_releases, "2026.07.1-rc1.4.1", false).tag_name,
    "v2026.07.1",
    "stable channel must select a stable successor")

assert_equal(Updater.getRepository(), "trigon1998/wordwise.koplugin-custom",
    "release repository must default to the configured project")
assert(Updater.setRepository("my-owner/wordwise.koplugin"),
    "valid repository setting must save")
assert_equal(Updater.getRepository(), "my-owner/wordwise.koplugin",
    "saved repository must round-trip")
assert(not Updater.setRepository("not a repository"),
    "invalid repository must not overwrite the saved value")
assert_equal(Updater.getRepository(), "my-owner/wordwise.koplugin",
    "invalid input must preserve the previous repository")

local menu_items = Updater.getMenuItems()
assert_equal(#menu_items, 6, "Updates submenu must expose Full OTA controls")
assert_equal(menu_items[3].enabled_func(), true,
    "Full OTA check must be enabled after repository configuration")

assert_equal(Updater.includesPrereleases(), true,
    "an RC bootstrap must default to the RC channel")
Updater.setIncludesPrereleases(false)
assert_equal(Updater.includesPrereleases(), false,
    "release-channel preference must be saved")

local battery_release = {
    { tag_name = "v2026.07.1-rc1.4.1", prerelease = true, draft = false },
}
assert_equal(
    Updater.selectRelease(battery_release, "2026.07.1-rc1.4.0", true).tag_name,
    "v2026.07.1-rc1.4.1",
    "RC1.3.9 must discover the RC1.4.0 battery release")
assert_equal(
    Updater.selectRelease(battery_release, "2026.07.1-rc1.4.1", true),
    nil,
    "RC1.4.1 must not offer itself as an update")

print("RC1.4.1 updater logic tests: PASS")
