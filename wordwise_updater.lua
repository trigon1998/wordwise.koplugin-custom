-- Code-only GitHub Releases updater for Word Wise.
--
-- Safety properties:
--   * manual checks only (no wake/startup polling);
--   * public owner/repository names are strictly validated;
--   * the exact release ZIP and companion SHA-256 asset are required;
--   * archives are extracted to a staging directory with a fixed allow-list;
--   * every Lua file is compiled and the staged version is checked;
--   * current plugin files are backed up before any replacement;
--   * koreader/wordwise/ databases and user data are outside every path used
--     by this module.

local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local Device = require("device")
local InfoMessage = require("ui/widget/infomessage")
local InputDialog = require("ui/widget/inputdialog")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local lfs = require("libs/libkoreader-lfs")
local _ = require("gettext")

local Config = require("update_config")

local Updater = {}

local REPOSITORY_SETTING = "wordwise_update_repository"
local PRERELEASE_SETTING = "wordwise_update_prereleases"
local UPDATE_DIR_NAME = "wordwise_update"
local ARCHIVE_ROOT = Config.plugin_id .. "/"

local INSTALL_ORDER = {
    "book_classifier.lua",
    "context_scorer.lua",
    "known_words.lua",
    "wordwise_db.lua",
    "wordwise_updater.lua",
    "update_config.lua",
    "README.md",
    "NOTICE.md",
    "main.lua",
    "_meta.lua",
}

local ALLOWED_FILES = {}
for _, name in ipairs(INSTALL_ORDER) do ALLOWED_FILES[name] = true end

local REQUIRED_FILES = {
    "_meta.lua",
    "main.lua",
    "wordwise_db.lua",
    "known_words.lua",
    "context_scorer.lua",
    "book_classifier.lua",
    "wordwise_updater.lua",
    "update_config.lua",
}

local function trim(text)
    return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function Updater.isValidRepository(repository)
    repository = trim(repository)
    if #repository < 3 or #repository > 200 then return false end
    local owner, repo = repository:match("^([A-Za-z0-9_.-]+)/([A-Za-z0-9_.-]+)$")
    if not owner or not repo then return false end
    if owner:match("^%.") or owner:match("%.$") or repo:match("^%.") or repo:match("%.$") then
        return false
    end
    return true
end

function Updater.getRepository()
    local stored = G_reader_settings and G_reader_settings:readSetting(REPOSITORY_SETTING) or nil
    local repository = trim(stored ~= nil and stored or Config.default_repository)
    return Updater.isValidRepository(repository) and repository or nil
end

function Updater.setRepository(repository)
    repository = trim(repository)
    if repository == "" then
        if G_reader_settings and G_reader_settings.delSetting then
            G_reader_settings:delSetting(REPOSITORY_SETTING)
        end
        return true
    end
    if not Updater.isValidRepository(repository) then return false end
    G_reader_settings:saveSetting(REPOSITORY_SETTING, repository)
    return true
end

function Updater.includesPrereleases()
    local stored
    if G_reader_settings then stored = G_reader_settings:readSetting(PRERELEASE_SETTING) end
    if stored == nil then return Config.version:find("-", 1, true) ~= nil end
    return stored == true
end

function Updater.setIncludesPrereleases(enabled)
    G_reader_settings:saveSetting(PRERELEASE_SETTING, enabled == true)
end

local PRERELEASE_RANK = { dev = 0, alpha = 1, beta = 2, rc = 3 }

local function parse_version(version)
    local clean = tostring(version or ""):gsub("^v", "")
    local major, minor, patch, suffix = clean:match("^(%d+)%.(%d+)%.(%d+)(.*)$")
    if not major then return nil end
    local parsed = {
        tonumber(major), tonumber(minor), tonumber(patch),
        prerelease = suffix ~= "",
        rank = 0,
        tail = {},
    }
    if parsed.prerelease then
        local label = suffix:match("^%-([A-Za-z]+)")
        parsed.rank = PRERELEASE_RANK[(label or ""):lower()] or -1
        for number in suffix:gmatch("(%d+)") do
            parsed.tail[#parsed.tail + 1] = tonumber(number)
        end
    end
    return parsed
end

-- Returns 1 when left is newer, -1 when right is newer, 0 when equal,
-- or nil when either version is outside the supported format.
function Updater.compareVersions(left, right)
    local a, b = parse_version(left), parse_version(right)
    if not a or not b then return nil end
    for index = 1, 3 do
        if a[index] > b[index] then return 1 end
        if a[index] < b[index] then return -1 end
    end
    if a.prerelease ~= b.prerelease then
        return a.prerelease and -1 or 1
    end
    if not a.prerelease then return 0 end
    if a.rank > b.rank then return 1 end
    if a.rank < b.rank then return -1 end
    for index = 1, math.max(#a.tail, #b.tail) do
        local x, y = a.tail[index] or 0, b.tail[index] or 0
        if x > y then return 1 end
        if x < y then return -1 end
    end
    return 0
end

function Updater.assetNamesForVersion(version)
    local base = Config.asset_basename .. "-v" .. tostring(version)
    return base .. ".zip", base .. ".zip.sha256"
end

local function release_version(release)
    return release and release.tag_name and release.tag_name:gsub("^v", "") or nil
end

function Updater.selectRelease(releases, installed_version, include_prereleases)
    local selected
    for _, release in ipairs(releases or {}) do
        local version = release_version(release)
        local comparison = version and Updater.compareVersions(version, installed_version) or nil
        local eligible = not release.draft
            and (include_prereleases or not release.prerelease)
            and comparison == 1
        if eligible then
            if not selected
                or Updater.compareVersions(version, release_version(selected)) == 1 then
                selected = release
            end
        end
    end
    return selected
end

local function installed_version()
    return Config.version
end

local function user_agent()
    return Config.user_agent .. "/" .. installed_version()
end

local function show_error(message)
    UIManager:show(InfoMessage:new{
        text = _("Word Wise update error:") .. "\n" .. tostring(message),
        timeout = 5,
    })
end

local function http_get_json(url)
    local json = require("json")
    local ok_require, http, ltn12, socket, socketutil = pcall(function()
        return require("socket/http"),
            require("ltn12"),
            require("socket"),
            require("socketutil")
    end)
    if ok_require then
        local chunks = {}
        local ok_request, code = pcall(function()
            socketutil:set_timeout(socketutil.LARGE_BLOCK_TIMEOUT, socketutil.LARGE_TOTAL_TIMEOUT)
            local status = socket.skip(1, http.request({
                url = url,
                method = "GET",
                headers = {
                    ["User-Agent"] = user_agent(),
                    ["Accept"] = "application/vnd.github+json",
                    ["X-GitHub-Api-Version"] = "2022-11-28",
                },
                sink = ltn12.sink.table(chunks),
                redirect = true,
            }))
            socketutil:reset_timeout()
            return status
        end)
        pcall(function() socketutil:reset_timeout() end)
        if ok_request and code == 200 then
            local body = table.concat(chunks)
            if #body <= 2 * 1024 * 1024 then
                local ok_json, decoded = pcall(json.decode, body)
                if ok_json then return decoded end
            end
        end
    end

    local command = string.format(
        "curl -sfL --max-time 60 -H %q -H %q -H %q %q",
        "User-Agent: " .. user_agent(),
        "Accept: application/vnd.github+json",
        "X-GitHub-Api-Version: 2022-11-28",
        url)
    local handle = io.popen(command)
    if not handle then return nil end
    local body = handle:read("*a")
    handle:close()
    if not body or body == "" or #body > 2 * 1024 * 1024 then return nil end
    local ok_json, decoded = pcall(json.decode, body)
    return ok_json and decoded or nil
end

local function download_file(url, destination)
    pcall(os.remove, destination)
    local downloaded = false
    local ok_require, http, ltn12, socket, socketutil = pcall(function()
        return require("socket/http"),
            require("ltn12"),
            require("socket"),
            require("socketutil")
    end)
    if ok_require then
        local file = io.open(destination, "wb")
        if file then
            local ok_request, code = pcall(function()
                socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
                local status = socket.skip(1, http.request({
                    url = url,
                    method = "GET",
                    headers = { ["User-Agent"] = user_agent() },
                    sink = ltn12.sink.file(file),
                    redirect = true,
                }))
                socketutil:reset_timeout()
                return status
            end)
            pcall(function() socketutil:reset_timeout() end)
            pcall(function() file:close() end)
            downloaded = ok_request and code == 200
        end
    end
    if not downloaded then
        pcall(os.remove, destination)
        local result = os.execute(string.format(
            "curl -sfL --max-time 120 -o %q %q", destination, url))
        downloaded = result == 0 or result == true
    end
    if not downloaded then
        pcall(os.remove, destination)
        return false, "download failed"
    end
    local size = lfs.attributes(destination, "size")
    if not size or size <= 0 or size > Config.max_archive_bytes then
        pcall(os.remove, destination)
        return false, "download size is invalid"
    end
    return true
end

local function sha256_file(path)
    local ok_sha, sha = pcall(require, "ffi/sha2")
    if not ok_sha or not sha or not sha.sha256 then return nil, "SHA-256 unavailable" end
    local file = io.open(path, "rb")
    if not file then return nil, "cannot read downloaded archive" end
    local digest = sha.sha256()
    while true do
        local chunk = file:read(64 * 1024)
        if not chunk then break end
        digest(chunk)
    end
    file:close()
    return digest()
end

local function expected_sha256(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read(1024)
    file:close()
    local hash = content and content:match("^%s*([0-9a-fA-F]+)") or nil
    if not hash or #hash ~= 64 then return nil end
    return hash:lower()
end

local function clear_tree(path)
    local mode = lfs.attributes(path, "mode")
    if not mode then return true end
    if mode ~= "directory" then return os.remove(path) ~= nil end
    for name in lfs.dir(path) do
        if name ~= "." and name ~= ".." then
            if not clear_tree(path .. "/" .. name) then return false end
        end
    end
    return lfs.rmdir(path) ~= nil
end

local function reset_directory(path)
    if lfs.attributes(path, "mode") and not clear_tree(path) then
        return false, "cannot clear update directory"
    end
    local ok, err = lfs.mkdir(path)
    if not ok and lfs.attributes(path, "mode") ~= "directory" then
        return false, err or "cannot create update directory"
    end
    return true
end

local function ensure_directory(path)
    if lfs.attributes(path, "mode") == "directory" then return true end
    local ok = lfs.mkdir(path)
    return ok ~= nil or lfs.attributes(path, "mode") == "directory"
end

local function copy_file(source, destination)
    local input = io.open(source, "rb")
    if not input then return false, "cannot read " .. source end
    local output = io.open(destination, "wb")
    if not output then
        input:close()
        return false, "cannot write " .. destination
    end
    local ok, err = pcall(function()
        while true do
            local chunk = input:read(64 * 1024)
            if not chunk then break end
            assert(output:write(chunk))
        end
        assert(output:flush())
    end)
    input:close()
    output:close()
    if not ok then
        pcall(os.remove, destination)
        return false, tostring(err)
    end
    return true
end

local function atomic_replace(source, destination)
    local temporary = destination .. ".wordwise-update.tmp"
    pcall(os.remove, temporary)
    local ok, err = copy_file(source, temporary)
    if not ok then return false, err end
    local renamed, rename_err = os.rename(temporary, destination)
    if not renamed then
        pcall(os.remove, temporary)
        return false, tostring(rename_err or "atomic rename failed")
    end
    return true
end

local function update_paths()
    local base = DataStorage:getSettingsDir() .. "/" .. UPDATE_DIR_NAME
    return {
        base = base,
        archive = base .. "/update.zip",
        checksum = base .. "/update.zip.sha256",
        stage = base .. "/stage",
        staged_plugin = base .. "/stage/" .. Config.plugin_id,
        backup = base .. "/backup",
        plugin = DataStorage:getDataDir() .. "/plugins/" .. Config.plugin_id,
    }
end

local function prepare_paths(paths)
    if not ensure_directory(paths.base) then return false, "cannot create update workspace" end
    local ok, err = reset_directory(paths.stage)
    if not ok then return false, err end
    if not ensure_directory(paths.staged_plugin) then
        return false, "cannot create staging directory"
    end
    return true
end

local function extract_release(archive_path, destination)
    local ok_archiver, Archiver = pcall(require, "ffi/archiver")
    if not ok_archiver or not Archiver or not Archiver.Reader then
        return nil, "archive extractor unavailable"
    end
    local archive = Archiver.Reader:new()
    if not archive:open(archive_path) then
        local err = archive.err or "cannot open archive"
        archive:close()
        return nil, err
    end

    local seen, extracted, total_size = {}, {}, 0
    local failure
    for entry in archive:iterate() do
        local path = tostring(entry.path or ""):gsub("\\", "/")
        if entry.mode == "directory" then
            if path ~= Config.plugin_id and path ~= ARCHIVE_ROOT then
                failure = "unexpected directory in update: " .. path
                break
            end
        elseif entry.mode == "file" then
            local relative = path:match("^" .. Config.plugin_id:gsub("%.", "%%.") .. "/(.+)$")
            local size = tonumber(entry.size) or -1
            if not relative or relative:find("/", 1, true)
                or relative == "." or relative == ".."
                or not ALLOWED_FILES[relative] then
                failure = "unexpected file in update: " .. path
                break
            end
            if seen[relative] then
                failure = "duplicate file in update: " .. relative
                break
            end
            if size < 0 or size > Config.max_file_bytes then
                failure = "invalid file size in update: " .. relative
                break
            end
            total_size = total_size + size
            if total_size > Config.max_archive_bytes then
                failure = "unpacked update is too large"
                break
            end
            local target = destination .. "/" .. relative
            if not archive:extractToPath(entry.path, target) then
                failure = archive.err or ("cannot extract " .. relative)
                break
            end
            seen[relative] = true
            extracted[#extracted + 1] = relative
        else
            failure = "unsupported archive entry: " .. path
            break
        end
    end
    if not failure and archive.err then failure = archive.err end
    archive:close()
    if failure then return nil, failure end
    for _, required in ipairs(REQUIRED_FILES) do
        if not seen[required] then return nil, "missing required file: " .. required end
    end
    return extracted
end

local function validate_staged_release(paths, release_version_expected, extracted)
    for _, name in ipairs(extracted) do
        if name:match("%.lua$") then
            local chunk, err = loadfile(paths.staged_plugin .. "/" .. name)
            if not chunk then return false, "Lua syntax error in " .. name .. ": " .. tostring(err) end
        end
    end
    local ok_meta, metadata = pcall(dofile, paths.staged_plugin .. "/_meta.lua")
    if not ok_meta or type(metadata) ~= "table" then return false, "invalid plugin metadata" end
    if tostring(metadata.version or "") ~= tostring(release_version_expected) then
        return false, "release tag and plugin version do not match"
    end
    local ok_config, staged_config = pcall(dofile, paths.staged_plugin .. "/update_config.lua")
    if not ok_config or type(staged_config) ~= "table"
        or tostring(staged_config.version or "") ~= tostring(release_version_expected) then
        return false, "release tag and update configuration do not match"
    end
    return true
end

local function write_backup_version(path, version)
    local file = io.open(path .. "/backup_version.txt", "wb")
    if not file then return false end
    local ok = file:write(tostring(version), "\n")
    file:close()
    return ok ~= nil
end

local function read_backup_version(paths)
    local file = io.open(paths.backup .. "/backup_version.txt", "rb")
    if not file then return nil end
    local version = trim(file:read("*l"))
    file:close()
    return version ~= "" and version or nil
end

local function commit_staged_release(paths, extracted)
    local ok, err = reset_directory(paths.backup)
    if not ok then return false, err end

    local staged = {}
    for _, name in ipairs(extracted) do staged[name] = true end
    for _, name in ipairs(INSTALL_ORDER) do
        if staged[name] then
            local current = paths.plugin .. "/" .. name
            if lfs.attributes(current, "mode") == "file" then
                local copied, copy_err = copy_file(current, paths.backup .. "/" .. name)
                if not copied then return false, "backup failed: " .. tostring(copy_err) end
            end
        end
    end
    if not write_backup_version(paths.backup, installed_version()) then
        return false, "cannot write backup metadata"
    end

    local changed = {}
    for _, name in ipairs(INSTALL_ORDER) do
        if staged[name] then
            local target = paths.plugin .. "/" .. name
            local replaced, replace_err = atomic_replace(paths.staged_plugin .. "/" .. name, target)
            if not replaced then
                local rollback_ok = true
                for index = #changed, 1, -1 do
                    local changed_name = changed[index]
                    local backup_file = paths.backup .. "/" .. changed_name
                    local changed_target = paths.plugin .. "/" .. changed_name
                    if lfs.attributes(backup_file, "mode") == "file" then
                        local restored = atomic_replace(backup_file, changed_target)
                        rollback_ok = rollback_ok and restored
                    else
                        rollback_ok = (os.remove(changed_target) ~= nil) and rollback_ok
                    end
                end
                local message = "installation failed: " .. tostring(replace_err)
                if not rollback_ok then message = message .. "; rollback may be incomplete" end
                return false, message
            end
            changed[#changed + 1] = name
        end
    end
    return true
end

local function find_release_assets(release)
    local version = release_version(release)
    local zip_name, checksum_name = Updater.assetNamesForVersion(version)
    local zip_url, checksum_url
    for _, asset in ipairs(release.assets or {}) do
        if asset.name == zip_name then zip_url = asset.browser_download_url end
        if asset.name == checksum_name then checksum_url = asset.browser_download_url end
    end
    return zip_url, checksum_url, zip_name, checksum_name
end

local function cleanup_downloads(paths)
    pcall(os.remove, paths.archive)
    pcall(os.remove, paths.checksum)
    if lfs.attributes(paths.stage, "mode") then pcall(clear_tree, paths.stage) end
end

local function install_release(release)
    local version = release_version(release)
    local zip_url, checksum_url = find_release_assets(release)
    if not zip_url or not checksum_url then
        show_error(_("The release is missing its code ZIP or SHA-256 file."))
        return
    end

    UIManager:show(InfoMessage:new{ text = _("Downloading Word Wise update..."), timeout = 1 })
    UIManager:scheduleIn(0.1, function()
        local paths = update_paths()
        local ok, err = prepare_paths(paths)
        if not ok then show_error(err) return end

        ok, err = download_file(zip_url, paths.archive)
        if not ok then cleanup_downloads(paths) show_error(err) return end
        ok, err = download_file(checksum_url, paths.checksum)
        if not ok then cleanup_downloads(paths) show_error(err) return end

        local expected = expected_sha256(paths.checksum)
        local actual, hash_err = sha256_file(paths.archive)
        if not expected or not actual or expected ~= actual:lower() then
            cleanup_downloads(paths)
            show_error(hash_err or _("SHA-256 verification failed."))
            return
        end

        local extracted
        extracted, err = extract_release(paths.archive, paths.staged_plugin)
        if not extracted then cleanup_downloads(paths) show_error(err) return end
        ok, err = validate_staged_release(paths, version, extracted)
        if not ok then cleanup_downloads(paths) show_error(err) return end
        ok, err = commit_staged_release(paths, extracted)
        cleanup_downloads(paths)
        if not ok then show_error(err) return end

        UIManager:show(ConfirmBox:new{
            text = _("Word Wise was updated to v") .. version .. ".\n\n"
                .. _("Restart KOReader now?"),
            ok_text = _("Restart"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
    end)
end

local function strip_markdown(text)
    text = tostring(text or "")
    text = text:gsub("#+%s*", "")
        :gsub("%*%*(.-)%*%*", "%1")
        :gsub("`(.-)`", "%1")
    return text
end

local function offer_releases_page(repository, message)
    local url = "https://github.com/" .. repository .. "/releases"
    if Device:canOpenLink() then
        UIManager:show(ConfirmBox:new{
            text = message .. "\n\n" .. _("Open the releases page?"),
            ok_text = _("Open"),
            ok_callback = function() Device:openLink(url) end,
        })
    else
        show_error(message)
    end
end

function Updater.check()
    local repository = Updater.getRepository()
    if not repository then
        show_error(_("Set a public GitHub repository first."))
        return
    end
    local NetworkMgr = require("ui/network/manager")
    NetworkMgr:runWhenOnline(function()
        UIManager:show(InfoMessage:new{ text = _("Checking for Word Wise updates..."), timeout = 1 })
        UIManager:scheduleIn(0.1, function()
            local releases = http_get_json(
                "https://api.github.com/repos/" .. repository .. "/releases?per_page=30")
            if type(releases) ~= "table" or #releases == 0 then
                offer_releases_page(repository, _("Could not read GitHub releases."))
                return
            end
            local release = Updater.selectRelease(
                releases, installed_version(), Updater.includesPrereleases())
            if not release then
                UIManager:show(InfoMessage:new{
                    text = _("Word Wise is up to date.") .. "\n\n"
                        .. _("Version: ") .. "v" .. installed_version(),
                    timeout = 3,
                })
                return
            end
            local zip_url, checksum_url = find_release_assets(release)
            if not zip_url or not checksum_url then
                offer_releases_page(repository,
                    _("The newest release does not contain the required update assets."))
                return
            end

            local version = release_version(release)
            local viewer
            viewer = TextViewer:new{
                title = _("Word Wise update available"),
                text = _("Installed: ") .. "v" .. installed_version() .. "\n"
                    .. _("Available: ") .. "v" .. version .. "\n\n"
                    .. strip_markdown(release.body),
                add_default_buttons = false,
                buttons_table = {
                    {
                        {
                            text = _("Close"),
                            callback = function() UIManager:close(viewer) end,
                        },
                        {
                            text = _("Update and restart"),
                            callback = function()
                                UIManager:close(viewer)
                                install_release(release)
                            end,
                        },
                    },
                },
            }
            UIManager:show(viewer)
        end)
    end)
end

function Updater.editRepository()
    local dialog
    dialog = InputDialog:new{
        title = _("GitHub repository"),
        input = Updater.getRepository() or "",
        input_hint = "owner/repository",
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function() UIManager:close(dialog) end,
                },
                {
                    text = _("Save"),
                    is_enter_default = true,
                    callback = function()
                        local value = trim(dialog:getInputText())
                        if not Updater.setRepository(value) then
                            show_error(_("Use the format owner/repository."))
                            return
                        end
                        UIManager:close(dialog)
                    end,
                },
            },
        },
    }
    UIManager:show(dialog)
    dialog:onShowKeyboard()
end

function Updater.restorePreviousVersion()
    local paths = update_paths()
    local version = read_backup_version(paths)
    if not version then show_error(_("No previous-version backup is available.")) return end
    UIManager:show(ConfirmBox:new{
        text = _("Restore Word Wise v") .. version .. "?\n\n"
            .. _("Databases and known words will not be changed."),
        ok_text = _("Restore"),
        ok_callback = function()
            local restored = 0
            for _, name in ipairs(INSTALL_ORDER) do
                local source = paths.backup .. "/" .. name
                if lfs.attributes(source, "mode") == "file" then
                    local ok, err = atomic_replace(source, paths.plugin .. "/" .. name)
                    if not ok then show_error(err) return end
                    restored = restored + 1
                end
            end
            if restored == 0 then show_error(_("The backup is empty.")) return end
            UIManager:show(ConfirmBox:new{
                text = _("Previous Word Wise code restored.") .. "\n\n"
                    .. _("Restart KOReader now?"),
                ok_text = _("Restart"),
                ok_callback = function() UIManager:restartKOReader() end,
            })
        end,
    })
end

function Updater.getMenuItems()
    local paths = update_paths()
    return {
        {
            text_func = function()
                return _("Repository: ") .. (Updater.getRepository() or _("not configured"))
            end,
            keep_menu_open = true,
            callback = function() Updater.editRepository() end,
        },
        {
            text = _("Include prerelease/RC updates"),
            checked_func = function() return Updater.includesPrereleases() end,
            callback = function()
                Updater.setIncludesPrereleases(not Updater.includesPrereleases())
            end,
        },
        {
            text = _("Check for updates"),
            enabled_func = function() return Updater.getRepository() ~= nil end,
            callback = function() Updater.check() end,
        },
        {
            text = _("Installed version: ") .. Config.version,
            enabled_func = function() return false end,
        },
        {
            text_func = function()
                local version = read_backup_version(paths)
                return version and (_("Restore previous version: ") .. version)
                    or _("Restore previous version")
            end,
            enabled_func = function() return read_backup_version(paths) ~= nil end,
            callback = function() Updater.restorePreviousVersion() end,
        },
    }
end

return Updater
