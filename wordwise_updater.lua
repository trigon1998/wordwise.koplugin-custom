-- Full GitHub Releases updater for Word Wise plugin code and dictionary data.
--
-- Safety properties:
--   * manual checks only (no wake/startup polling);
--   * public owner/repository names are strictly validated;
--   * exact code/data ZIPs and companion SHA-256 assets are required;
--   * both archives are extracted to staging directories with fixed allow-lists;
--   * every Lua file is compiled and the staged version is checked;
--   * every staged database is hash-checked, integrity-checked and matched to
--     the release manifest before a pending install is created;
--   * current plugin files and dictionary databases are backed up;
--   * dictionary replacement happens at the next plugin start, before any
--     database connection is opened, with interrupted-install recovery;
--   * known_words.db and per-book settings are never archive targets.

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
local DATABASE_BUNDLE_SETTING = "wordwise_database_bundle_version"
local DATABASE_PROMPT_SETTING = "wordwise_database_prompt_version"
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

local DATA_FILES = {
    {
        domain = "general",
        name = "wordwise_general.db",
        archive_path = "koreader/wordwise/databases/wordwise_general.db",
    },
    {
        domain = "economics",
        name = "wordwise_economics.db",
        archive_path = "koreader/wordwise/databases/wordwise_economics.db",
    },
    {
        domain = "physics",
        name = "wordwise_physics.db",
        archive_path = "koreader/wordwise/databases/wordwise_physics.db",
    },
}

local DATA_FILE_BY_ARCHIVE_PATH = {}
local DATA_FILE_BY_NAME = {}
for _, spec in ipairs(DATA_FILES) do
    DATA_FILE_BY_ARCHIVE_PATH[spec.archive_path] = spec
    DATA_FILE_BY_NAME[spec.name] = spec
end

local DATA_AUXILIARY_FILES = {
    ["manifest.json"] = "manifest.json",
    ["WordWise_Databases_README.txt"] = "README.txt",
}

local DATA_ALLOWED_DIRECTORIES = {
    koreader = true,
    ["koreader/wordwise"] = true,
    ["koreader/wordwise/databases"] = true,
}

local DATABASE_SCHEMA_COLUMNS = {
    entries = {
        "term", "lemma", "short_en", "short_vi", "difficulty", "pos", "domain",
        "sense2_en", "sense2_vi", "context_keywords", "phrase_len", "priority",
        "requires_context", "register_label", "source",
    },
    aliases = { "alias", "term", "case_sensitive" },
    irregular_forms = { "surface", "lemma" },
    metadata = { "key", "value" },
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

function Updater.dataAssetNamesForVersion(version)
    local base = Config.data_asset_basename .. tostring(version)
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

function Updater.selectCurrentRelease(releases, current_version, _include_prereleases)
    for _, release in ipairs(releases or {}) do
        local version = release_version(release)
        if version == current_version
            and not release.draft then
            return release
        end
    end
    return nil
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

local function download_file(url, destination, max_bytes)
    pcall(os.remove, destination)
    local maximum = max_bytes or Config.max_archive_bytes
    local downloaded = false
    local ok_require, http, socket, socketutil = pcall(function()
        return require("socket/http"),
            require("socket"),
            require("socketutil")
    end)
    if ok_require then
        local file = io.open(destination, "wb")
        if file then
            local received, overflow = 0, false
            local ok_request, code = pcall(function()
                socketutil:set_timeout(socketutil.FILE_BLOCK_TIMEOUT, socketutil.FILE_TOTAL_TIMEOUT)
                local status = socket.skip(1, http.request({
                    url = url,
                    method = "GET",
                    headers = { ["User-Agent"] = user_agent() },
                    sink = function(chunk)
                        if chunk then
                            received = received + #chunk
                            if received > maximum then
                                overflow = true
                                return nil, "download exceeds size limit"
                            end
                            if not file:write(chunk) then return nil, "download write failed" end
                        end
                        return 1
                    end,
                    redirect = true,
                }))
                socketutil:reset_timeout()
                return status
            end)
            pcall(function() socketutil:reset_timeout() end)
            pcall(function() file:close() end)
            downloaded = ok_request and code == 200 and not overflow
        end
    end
    if not downloaded then
        pcall(os.remove, destination)
        local result = os.execute(string.format(
            "curl -sfL --max-time 120 --max-filesize %d -o %q %q",
            maximum, destination, url))
        downloaded = result == 0 or result == true
    end
    if not downloaded then
        pcall(os.remove, destination)
        return false, "download failed"
    end
    local size = lfs.attributes(destination, "size")
    if not size or size <= 0 or size > maximum then
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

local function expected_sha256(path, expected_name)
    local file = io.open(path, "rb")
    if not file then return nil end
    local content = file:read(1024)
    file:close()
    local hash, name
    if content then
        hash, name = content:match("^%s*([0-9a-fA-F]+)%s+%*?([^\r\n]+)%s*$")
    end
    if not hash or #hash ~= 64 then return nil end
    if expected_name and trim(name) ~= expected_name then return nil end
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

local function atomic_write_text(path, content)
    local temporary = path .. ".tmp"
    pcall(os.remove, temporary)
    local file = io.open(temporary, "wb")
    if not file then return false, "cannot write update state" end
    local ok, err = pcall(function()
        assert(file:write(tostring(content or "")))
        assert(file:flush())
    end)
    file:close()
    if not ok then
        pcall(os.remove, temporary)
        return false, tostring(err)
    end
    local renamed, rename_err = os.rename(temporary, path)
    if not renamed then
        pcall(os.remove, temporary)
        return false, tostring(rename_err or "cannot commit update state")
    end
    return true
end

local function read_first_line(path)
    local file = io.open(path, "rb")
    if not file then return nil end
    local value = trim(file:read("*l"))
    file:close()
    return value ~= "" and value or nil
end

local function update_paths()
    local base = DataStorage:getSettingsDir() .. "/" .. UPDATE_DIR_NAME
    local wordwise = DataStorage:getDataDir() .. "/wordwise"
    return {
        base = base,
        archive = base .. "/update.zip",
        checksum = base .. "/update.zip.sha256",
        data_archive = base .. "/databases.zip",
        data_checksum = base .. "/databases.zip.sha256",
        stage = base .. "/stage",
        staged_plugin = base .. "/stage/" .. Config.plugin_id,
        staged_data = base .. "/database-stage",
        staged_manifest = base .. "/database-stage/manifest.json",
        backup = base .. "/backup",
        data_backup = base .. "/database-backup",
        data_restore_rollback = base .. "/database-restore-rollback",
        installed_data_manifest = base .. "/installed-database-manifest.json",
        pending_data_version = base .. "/pending-database-version.txt",
        data_install_state = base .. "/database-installing.txt",
        plugin = DataStorage:getDataDir() .. "/plugins/" .. Config.plugin_id,
        wordwise = wordwise,
        databases = wordwise .. "/databases",
    }
end

local function pending_data_version(paths)
    return read_first_line(paths.pending_data_version)
end

local function prepare_paths(paths, with_code, with_data)
    if not ensure_directory(paths.base) then return false, "cannot create update workspace" end
    if pending_data_version(paths) then
        return false, "a verified database update is waiting for a KOReader restart"
    end
    local ok, err
    if with_code then
        ok, err = reset_directory(paths.stage)
        if not ok then return false, err end
        if not ensure_directory(paths.staged_plugin) then
            return false, "cannot create plugin staging directory"
        end
    end
    if with_data then
        ok, err = reset_directory(paths.staged_data)
        if not ok then return false, err end
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

local function extract_data_release(archive_path, destination)
    local ok_archiver, Archiver = pcall(require, "ffi/archiver")
    if not ok_archiver or not Archiver or not Archiver.Reader then
        return false, "archive extractor unavailable"
    end
    local archive = Archiver.Reader:new()
    if not archive:open(archive_path) then
        local err = archive.err or "cannot open database archive"
        archive:close()
        return false, err
    end

    local seen, all_seen, total_size = {}, {}, 0
    local failure
    for entry in archive:iterate() do
        local path = tostring(entry.path or ""):gsub("\\", "/")
        if all_seen[path] then
            failure = "duplicate path in database update: " .. path
            break
        end
        if entry.mode == "directory" then
            local directory = path:gsub("/+$", "")
            if not DATA_ALLOWED_DIRECTORIES[directory] then
                failure = "unexpected directory in database update: " .. path
                break
            end
        elseif entry.mode == "file" then
            local spec = DATA_FILE_BY_ARCHIVE_PATH[path]
            local target_name = spec and spec.name or DATA_AUXILIARY_FILES[path]
            local size = tonumber(entry.size) or -1
            local maximum = spec and Config.max_database_bytes or Config.max_data_metadata_bytes
            if not target_name then
                failure = "unexpected file in database update: " .. path
                break
            end
            if seen[path] then
                failure = "duplicate file in database update: " .. path
                break
            end
            if size <= 0 or size > maximum then
                failure = "invalid file size in database update: " .. path
                break
            end
            total_size = total_size + size
            if total_size > Config.max_data_unpacked_bytes then
                failure = "unpacked database update is too large"
                break
            end
            if not archive:extractToPath(entry.path, destination .. "/" .. target_name) then
                failure = archive.err or ("cannot extract " .. path)
                break
            end
            seen[path] = true
        else
            failure = "unsupported database archive entry: " .. path
            break
        end
        all_seen[path] = true
    end
    if not failure and archive.err then failure = archive.err end
    archive:close()
    if failure then return false, failure end

    for path in pairs(DATA_AUXILIARY_FILES) do
        if not seen[path] then return false, "missing database package file: " .. path end
    end
    for _, spec in ipairs(DATA_FILES) do
        if not seen[spec.archive_path] then
            return false, "missing database package file: " .. spec.archive_path
        end
    end
    return true
end

local function nonnegative_integer(value)
    return type(value) == "number" and value >= 0 and value % 1 == 0
end

function Updater.validateDataManifest(manifest, release_version_expected)
    if type(manifest) ~= "table" then return nil, "invalid database manifest" end
    if manifest.format ~= 1 or manifest.package_type ~= "database-only" then
        return nil, "unsupported database package format"
    end
    if tostring(manifest.build_version or "") ~= tostring(release_version_expected) then
        return nil, "release tag and database build do not match"
    end
    if manifest.known_words_included ~= false or manifest.book_settings_included ~= false then
        return nil, "database package attempts to include user data"
    end
    if type(manifest.databases) ~= "table" or #manifest.databases ~= #DATA_FILES then
        return nil, "database manifest must describe exactly three databases"
    end

    local records = {}
    for _, record in ipairs(manifest.databases) do
        if type(record) ~= "table" then return nil, "invalid database manifest record" end
        local spec = DATA_FILE_BY_ARCHIVE_PATH[tostring(record.archive_path or "")]
        if not spec or tostring(record.database_domain or "") ~= spec.domain then
            return nil, "database manifest path/domain mismatch"
        end
        if records[spec.name] then return nil, "duplicate database manifest record" end
        local hash = tostring(record.sha256 or "")
        if #hash ~= 64 or hash:find("[^0-9a-fA-F]") then
            return nil, "invalid database SHA-256 in manifest"
        end
        if not nonnegative_integer(record.bytes) or record.bytes <= 0
            or record.bytes > Config.max_database_bytes then
            return nil, "invalid database byte count in manifest"
        end
        for _, field in ipairs({
            "entries", "phrases", "aliases", "irregulars",
            "reviewed_vietnamese", "english_only",
        }) do
            if not nonnegative_integer(record[field]) then
                return nil, "invalid database count in manifest: " .. field
            end
        end
        if record.reviewed_vietnamese + record.english_only ~= record.entries then
            return nil, "Vietnamese/English-only counts do not equal entry count"
        end
        if record.phrases > record.entries then
            return nil, "phrase count exceeds entry count"
        end
        if type(record.translation_policy) ~= "string" or record.translation_policy == "" then
            return nil, "missing translation policy in database manifest"
        end
        records[spec.name] = record
    end
    for _, spec in ipairs(DATA_FILES) do
        if not records[spec.name] then return nil, "database manifest is incomplete" end
    end
    return records
end

local function read_json_file(path, maximum)
    local size = lfs.attributes(path, "size")
    if not size or size <= 0 or size > maximum then return nil, "invalid JSON file size" end
    local file = io.open(path, "rb")
    if not file then return nil, "cannot read database manifest" end
    local body = file:read("*a")
    file:close()
    local ok_json, json = pcall(require, "json")
    if not ok_json then return nil, "JSON decoder unavailable" end
    local ok_decode, decoded = pcall(json.decode, body)
    if not ok_decode then return nil, "cannot decode database manifest" end
    return decoded
end

local function sql_first_value(connection, sql)
    local statement = connection:prepare(sql)
    local row = statement:step()
    statement:close()
    return row and row[1] or nil
end

local function validate_database_columns(connection)
    for table_name, expected in pairs(DATABASE_SCHEMA_COLUMNS) do
        local statement = connection:prepare("PRAGMA table_info(" .. table_name .. ");")
        local actual = {}
        while true do
            local row = statement:step()
            if not row then break end
            actual[#actual + 1] = tostring(row[2] or "")
        end
        statement:close()
        if #actual ~= #expected then return false, "schema mismatch: " .. table_name end
        for index, name in ipairs(expected) do
            if actual[index] ~= name then return false, "schema mismatch: " .. table_name end
        end
    end
    return true
end

local function validate_sqlite_database(path, spec, version, record, verify_counts)
    local ok_sq3, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_sq3 or not SQ3 or not SQ3.open then return false, "SQLite unavailable" end
    local ok_open, connection = pcall(SQ3.open, path)
    if not ok_open or not connection then return false, "cannot open staged database: " .. spec.name end

    local ok, err = pcall(function()
        connection:exec("PRAGMA query_only = ON;")
        if tostring(sql_first_value(connection, "PRAGMA integrity_check;") or "") ~= "ok" then
            error("SQLite integrity check failed")
        end
        if sql_first_value(connection, "PRAGMA foreign_key_check;") ~= nil then
            error("SQLite foreign-key check failed")
        end
        local columns_ok, columns_err = validate_database_columns(connection)
        if not columns_ok then error(columns_err) end
        local build = sql_first_value(connection,
            "SELECT value FROM metadata WHERE key='build_version' LIMIT 1;")
        local domain = sql_first_value(connection,
            "SELECT value FROM metadata WHERE key='database_domain' LIMIT 1;")
        local schema = sql_first_value(connection,
            "SELECT value FROM metadata WHERE key='schema_version' LIMIT 1;")
        local policy = sql_first_value(connection,
            "SELECT value FROM metadata WHERE key='translation_policy' LIMIT 1;")
        if tostring(build or "") ~= tostring(version) then error("database build version mismatch") end
        if tostring(domain or "") ~= spec.domain then error("database domain mismatch") end
        if tostring(schema or "") ~= "2" then error("unsupported database schema") end
        if record and tostring(policy or "") ~= tostring(record.translation_policy) then
            error("database translation policy mismatch")
        end
        if verify_counts and record then
            local counts = {
                entries = tonumber(sql_first_value(connection, "SELECT COUNT(*) FROM entries;")),
                reviewed_vietnamese = tonumber(sql_first_value(connection,
                    "SELECT COUNT(*) FROM entries WHERE short_vi <> '';")),
                english_only = tonumber(sql_first_value(connection,
                    "SELECT COUNT(*) FROM entries WHERE short_vi = '';")),
                aliases = tonumber(sql_first_value(connection, "SELECT COUNT(*) FROM aliases;")),
                irregulars = tonumber(sql_first_value(connection, "SELECT COUNT(*) FROM irregular_forms;")),
                phrases = tonumber(sql_first_value(connection,
                    "SELECT COUNT(*) FROM entries WHERE phrase_len > 1;")),
            }
            for field, value in pairs(counts) do
                if value ~= tonumber(record[field]) then error("database count mismatch: " .. field) end
            end
        end
    end)
    pcall(function() connection:close() end)
    if not ok then return false, spec.name .. ": " .. tostring(err) end
    return true
end

local function validate_data_directory(directory, manifest_path, version)
    local manifest, err = read_json_file(manifest_path, Config.max_data_metadata_bytes)
    if not manifest then return false, err end
    local records
    records, err = Updater.validateDataManifest(manifest, version)
    if not records then return false, err end

    for _, spec in ipairs(DATA_FILES) do
        local path = directory .. "/" .. spec.name
        local record = records[spec.name]
        local size = lfs.attributes(path, "size")
        if size ~= tonumber(record.bytes) then return false, spec.name .. ": byte count mismatch" end
        local actual, hash_err = sha256_file(path)
        if not actual or actual:lower() ~= tostring(record.sha256):lower() then
            return false, hash_err or (spec.name .. ": SHA-256 verification failed")
        end
        local valid, database_err = validate_sqlite_database(
            path, spec, version, record, true)
        if not valid then return false, database_err end
    end
    return true
end

local function validate_staged_data(paths, version)
    return validate_data_directory(paths.staged_data, paths.staged_manifest, version)
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

local function set_database_bundle_version(version)
    if not G_reader_settings then return end
    if version and version ~= "" and version ~= "unknown" and version ~= "mixed" then
        G_reader_settings:saveSetting(DATABASE_BUNDLE_SETTING, version)
    elseif G_reader_settings.delSetting then
        G_reader_settings:delSetting(DATABASE_BUNDLE_SETTING)
    end
end

function Updater.getInstalledDatabaseBundleVersion()
    if not G_reader_settings then return nil end
    local version = G_reader_settings:readSetting(DATABASE_BUNDLE_SETTING)
    version = trim(version)
    return version ~= "" and version or nil
end

local function database_build_version(path, expected_domain)
    if lfs.attributes(path, "mode") ~= "file" then return nil end
    local ok_sq3, SQ3 = pcall(require, "lua-ljsqlite3/init")
    if not ok_sq3 or not SQ3 or not SQ3.open then return nil end
    local ok_open, connection = pcall(SQ3.open, path)
    if not ok_open or not connection then return nil end
    local ok, build, domain, schema = pcall(function()
        connection:exec("PRAGMA query_only = ON;")
        return sql_first_value(connection,
                "SELECT value FROM metadata WHERE key='build_version' LIMIT 1;"),
            sql_first_value(connection,
                "SELECT value FROM metadata WHERE key='database_domain' LIMIT 1;"),
            sql_first_value(connection,
                "SELECT value FROM metadata WHERE key='schema_version' LIMIT 1;")
    end)
    pcall(function() connection:close() end)
    if not ok or tostring(domain or "") ~= expected_domain or tostring(schema or "") ~= "2" then
        return nil
    end
    return trim(build)
end

local function detect_database_bundle_version(paths)
    local common
    for _, spec in ipairs(DATA_FILES) do
        local version = database_build_version(paths.databases .. "/" .. spec.name, spec.domain)
        if not version or version == "" then return nil end
        if common and common ~= version then return nil end
        common = version
    end
    return common
end

function Updater.databaseUpdateNeeded(expected_version, verify_integrity)
    expected_version = tostring(expected_version or Config.version)
    local paths = update_paths()
    local stored = Updater.getInstalledDatabaseBundleVersion()
    if stored == expected_version and not verify_integrity then
        for _, spec in ipairs(DATA_FILES) do
            if lfs.attributes(paths.databases .. "/" .. spec.name, "mode") ~= "file" then
                return true, stored
            end
        end
        return false, stored
    end
    local detected = detect_database_bundle_version(paths)
    if detected == expected_version then
        if verify_integrity then
            if lfs.attributes(paths.installed_data_manifest, "mode") == "file" then
                local valid = validate_data_directory(
                    paths.databases, paths.installed_data_manifest, expected_version)
                if not valid then return true, detected end
            else
                for _, spec in ipairs(DATA_FILES) do
                    local valid = validate_sqlite_database(
                        paths.databases .. "/" .. spec.name,
                        spec, expected_version, nil, false)
                    if not valid then return true, detected end
                end
            end
        end
        set_database_bundle_version(detected)
        return false, detected
    end
    return true, detected or stored
end

local function read_data_backup_version(paths)
    return read_first_line(paths.data_backup .. "/backup_version.txt")
end

local function read_missing_database_set(paths)
    local missing = {}
    local file = io.open(paths.data_backup .. "/missing_databases.txt", "rb")
    if not file then return missing end
    for line in file:lines() do
        local name = trim(line)
        if DATA_FILE_BY_NAME[name] then missing[name] = true end
    end
    file:close()
    return missing
end

local function backup_current_databases(paths)
    local ok, err = reset_directory(paths.data_backup)
    if not ok then return false, err end
    local missing = {}
    for _, spec in ipairs(DATA_FILES) do
        local source = paths.databases .. "/" .. spec.name
        if lfs.attributes(source, "mode") == "file" then
            local copied, copy_err = copy_file(source, paths.data_backup .. "/" .. spec.name)
            if not copied then return false, "database backup failed: " .. tostring(copy_err) end
        else
            missing[#missing + 1] = spec.name
        end
    end
    if lfs.attributes(paths.installed_data_manifest, "mode") == "file" then
        local copied, copy_err = copy_file(
            paths.installed_data_manifest, paths.data_backup .. "/manifest.json")
        if not copied then return false, "database manifest backup failed: " .. tostring(copy_err) end
    end
    local missing_file = io.open(paths.data_backup .. "/missing_databases.txt", "wb")
    if not missing_file then return false, "cannot write database backup metadata" end
    for _, name in ipairs(missing) do missing_file:write(name, "\n") end
    missing_file:close()

    local previous = Updater.getInstalledDatabaseBundleVersion()
        or detect_database_bundle_version(paths) or "unknown"
    return atomic_write_text(paths.data_backup .. "/backup_version.txt", previous .. "\n")
end

local function restore_database_backup(paths)
    local missing = read_missing_database_set(paths)
    for _, spec in ipairs(DATA_FILES) do
        local backup = paths.data_backup .. "/" .. spec.name
        local target = paths.databases .. "/" .. spec.name
        if lfs.attributes(backup, "mode") == "file" then
            local restored, restore_err = atomic_replace(backup, target)
            if not restored then return false, restore_err end
        elseif missing[spec.name] then
            if lfs.attributes(target, "mode") == "file" and not os.remove(target) then
                return false, "cannot remove newly installed database: " .. spec.name
            end
        else
            return false, "database backup is incomplete: " .. spec.name
        end
    end
    local backup_manifest = paths.data_backup .. "/manifest.json"
    if lfs.attributes(backup_manifest, "mode") == "file" then
        local copied, copy_err = atomic_replace(backup_manifest, paths.installed_data_manifest)
        if not copied then return false, copy_err end
    else
        pcall(os.remove, paths.installed_data_manifest)
    end
    return true
end

local function discard_pending_data(paths)
    pcall(os.remove, paths.pending_data_version)
    pcall(os.remove, paths.data_install_state)
    if lfs.attributes(paths.staged_data, "mode") then pcall(clear_tree, paths.staged_data) end
end

local function mark_pending_data(paths, version)
    return atomic_write_text(paths.pending_data_version, tostring(version) .. "\n")
end

function Updater.applyPendingDataUpdate()
    local paths = update_paths()
    if read_first_line(paths.data_install_state) then
        local restored, restore_err = restore_database_backup(paths)
        if not restored then
            return false, "interrupted database update recovery failed: " .. tostring(restore_err)
        end
        pcall(os.remove, paths.data_install_state)
    end

    local version = pending_data_version(paths)
    if not version then return true, nil end
    local valid, err = validate_staged_data(paths, version)
    if not valid then
        discard_pending_data(paths)
        return false, "pending database update was rejected: " .. tostring(err)
    end
    if not ensure_directory(paths.wordwise) or not ensure_directory(paths.databases) then
        return false, "cannot create Word Wise database directory"
    end
    local backed_up, backup_err = backup_current_databases(paths)
    if not backed_up then return false, backup_err end
    local marked, mark_err = atomic_write_text(paths.data_install_state, version .. "\n")
    if not marked then return false, mark_err end

    for _, spec in ipairs(DATA_FILES) do
        local replaced, replace_err = atomic_replace(
            paths.staged_data .. "/" .. spec.name,
            paths.databases .. "/" .. spec.name)
        if not replaced then
            local rollback_ok, rollback_err = restore_database_backup(paths)
            if rollback_ok then pcall(os.remove, paths.data_install_state) end
            local message = "database installation failed: " .. tostring(replace_err)
            if not rollback_ok then
                message = message .. "; rollback failed: " .. tostring(rollback_err)
            end
            return false, message
        end
    end

    local manifest_saved, manifest_err = atomic_replace(
        paths.staged_manifest, paths.installed_data_manifest)
    if not manifest_saved then
        local rollback_ok, rollback_err = restore_database_backup(paths)
        if rollback_ok then pcall(os.remove, paths.data_install_state) end
        local message = "database manifest installation failed: " .. tostring(manifest_err)
        if not rollback_ok then message = message .. "; rollback failed: " .. tostring(rollback_err) end
        return false, message
    end

    set_database_bundle_version(version)
    if G_reader_settings and G_reader_settings.delSetting then
        G_reader_settings:delSetting(DATABASE_PROMPT_SETTING)
    end
    pcall(os.remove, paths.data_install_state)
    pcall(os.remove, paths.pending_data_version)
    if lfs.attributes(paths.staged_data, "mode") then pcall(clear_tree, paths.staged_data) end
    return true, version
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

function Updater.releaseAssets(release)
    local version = release_version(release)
    local code_name, code_checksum_name = Updater.assetNamesForVersion(version)
    local data_name, data_checksum_name = Updater.dataAssetNamesForVersion(version)
    local result = {
        version = version,
        code_name = code_name,
        code_checksum_name = code_checksum_name,
        data_name = data_name,
        data_checksum_name = data_checksum_name,
    }
    for _, asset in ipairs(release.assets or {}) do
        local field
        if asset.name == code_name then field = "code_url" end
        if asset.name == code_checksum_name then field = "code_checksum_url" end
        if asset.name == data_name then field = "data_url" end
        if asset.name == data_checksum_name then field = "data_checksum_url" end
        if field then
            if result[field] ~= nil then result.duplicate = true end
            result[field] = asset.browser_download_url
            if type(result[field]) ~= "string" or not result[field]:match("^https://") then
                result.invalid = true
            end
        end
    end
    result.has_code = not result.duplicate and not result.invalid
        and result.code_url ~= nil and result.code_checksum_url ~= nil
    result.has_data = not result.duplicate and not result.invalid
        and result.data_url ~= nil and result.data_checksum_url ~= nil
    result.complete = result.has_code and result.has_data
    return result
end

local function cleanup_downloads(paths, keep_pending_data)
    pcall(os.remove, paths.archive)
    pcall(os.remove, paths.checksum)
    pcall(os.remove, paths.data_archive)
    pcall(os.remove, paths.data_checksum)
    if lfs.attributes(paths.stage, "mode") then pcall(clear_tree, paths.stage) end
    if not keep_pending_data then discard_pending_data(paths) end
end

local function verify_downloaded_archive(archive, checksum, expected_name)
    local expected = expected_sha256(checksum, expected_name)
    local actual, hash_err = sha256_file(archive)
    if not expected or not actual or expected ~= actual:lower() then
        return false, hash_err or _("SHA-256 verification failed.")
    end
    return true
end

local function install_release(release, data_only)
    local version = release_version(release)
    local assets = Updater.releaseAssets(release)
    if not assets.has_data or (not data_only and not assets.has_code) then
        show_error(_("The release is missing a required code/database ZIP or SHA-256 file."))
        return
    end

    UIManager:show(InfoMessage:new{
        text = data_only and _("Downloading Word Wise database update...")
            or _("Downloading Word Wise code and databases..."),
        timeout = 1,
    })
    UIManager:scheduleIn(0.1, function()
        local paths = update_paths()
        local ok, err = prepare_paths(paths, not data_only, true)
        if not ok then show_error(err) return end

        local extracted
        if not data_only then
            ok, err = download_file(assets.code_url, paths.archive, Config.max_archive_bytes)
            if not ok then cleanup_downloads(paths, false) show_error(err) return end
            ok, err = download_file(
                assets.code_checksum_url, paths.checksum, Config.max_data_metadata_bytes)
            if not ok then cleanup_downloads(paths, false) show_error(err) return end
            ok, err = verify_downloaded_archive(
                paths.archive, paths.checksum, assets.code_name)
            if not ok then cleanup_downloads(paths, false) show_error(err) return end
            extracted, err = extract_release(paths.archive, paths.staged_plugin)
            if not extracted then cleanup_downloads(paths, false) show_error(err) return end
            ok, err = validate_staged_release(paths, version, extracted)
            if not ok then cleanup_downloads(paths, false) show_error(err) return end
        end

        ok, err = download_file(
            assets.data_url, paths.data_archive, Config.max_data_archive_bytes)
        if not ok then cleanup_downloads(paths, false) show_error(err) return end
        ok, err = download_file(
            assets.data_checksum_url, paths.data_checksum, Config.max_data_metadata_bytes)
        if not ok then cleanup_downloads(paths, false) show_error(err) return end
        ok, err = verify_downloaded_archive(
            paths.data_archive, paths.data_checksum, assets.data_name)
        if not ok then cleanup_downloads(paths, false) show_error(err) return end
        ok, err = extract_data_release(paths.data_archive, paths.staged_data)
        if not ok then cleanup_downloads(paths, false) show_error(err) return end
        ok, err = validate_staged_data(paths, version)
        if not ok then cleanup_downloads(paths, false) show_error(err) return end
        ok, err = mark_pending_data(paths, version)
        if not ok then cleanup_downloads(paths, false) show_error(err) return end

        if not data_only then
            ok, err = commit_staged_release(paths, extracted)
            if not ok then cleanup_downloads(paths, false) show_error(err) return end
        end
        cleanup_downloads(paths, true)

        UIManager:show(ConfirmBox:new{
            text = (data_only
                    and _("Word Wise databases are verified and ready for v")
                    or _("Word Wise code and databases are verified and ready for v"))
                .. version .. ".\n\n" .. _("Restart KOReader to finish the update now?"),
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
    local paths = update_paths()
    local pending = pending_data_version(paths)
    if pending then
        UIManager:show(ConfirmBox:new{
            text = _("A verified Word Wise database update is waiting for restart.")
                .. "\n\n" .. _("Restart KOReader now?"),
            ok_text = _("Restart"),
            ok_callback = function() UIManager:restartKOReader() end,
        })
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
            local data_only = false
            local release = Updater.selectRelease(
                releases, installed_version(), Updater.includesPrereleases())
            if not release then
                local data_needed = Updater.databaseUpdateNeeded(installed_version(), true)
                if data_needed then
                    release = Updater.selectCurrentRelease(
                        releases, installed_version(), Updater.includesPrereleases())
                    data_only = release ~= nil
                end
                if not release then
                    UIManager:show(InfoMessage:new{
                        text = data_needed and _("The matching database release is unavailable.")
                            or (_("Word Wise is up to date.") .. "\n\n"
                                .. _("Version: ") .. "v" .. installed_version()),
                        timeout = 3,
                    })
                    return
                end
            end
            local assets = Updater.releaseAssets(release)
            if not assets.complete then
                offer_releases_page(repository,
                    _("The newest release does not contain all four code/database update assets."))
                return
            end

            local version = release_version(release)
            local database_version = Updater.getInstalledDatabaseBundleVersion() or _("not synchronized")
            local viewer
            viewer = TextViewer:new{
                title = data_only and _("Word Wise database update available")
                    or _("Word Wise update available"),
                text = _("Installed: ") .. "v" .. installed_version() .. "\n"
                    .. _("Installed databases: ") .. tostring(database_version) .. "\n"
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
                            text = data_only and _("Update databases") or _("Update all and restart"),
                            callback = function()
                                UIManager:close(viewer)
                                install_release(release, data_only)
                            end,
                        },
                    },
                },
            }
            UIManager:show(viewer)
        end)
    end)
end

function Updater.maybeOfferDatabaseUpdate()
    if pending_data_version(update_paths()) then return end
    local prompted = G_reader_settings
        and G_reader_settings:readSetting(DATABASE_PROMPT_SETTING) or nil
    if tostring(prompted or "") == Config.version then return end
    local needed = Updater.databaseUpdateNeeded(Config.version)
    if not needed then return end
    if G_reader_settings then
        G_reader_settings:saveSetting(DATABASE_PROMPT_SETTING, Config.version)
    end
    UIManager:show(ConfirmBox:new{
        text = _("Word Wise plugin code is newer than its dictionary databases.")
            .. "\n\n"
            .. _("Download the verified database bundle now? Known words and book settings will be preserved."),
        ok_text = _("Download"),
        ok_callback = function() Updater.check() end,
    })
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
    local data_version = read_data_backup_version(paths)
    UIManager:show(ConfirmBox:new{
        text = _("Restore Word Wise v") .. version .. "?\n\n"
            .. (data_version and (_("Database backup: ") .. data_version .. "\n") or "")
            .. _("Known words and book settings will not be changed."),
        ok_text = _("Restore"),
        ok_callback = function()
            discard_pending_data(paths)
            if data_version then
                if data_version ~= "unknown" and data_version ~= "mixed" then
                    local missing = read_missing_database_set(paths)
                    for _, spec in ipairs(DATA_FILES) do
                        local backup = paths.data_backup .. "/" .. spec.name
                        if lfs.attributes(backup, "mode") == "file" then
                            local valid, validation_err = validate_sqlite_database(
                                backup, spec, data_version, nil, false)
                            if not valid then show_error(validation_err) return end
                        elseif not missing[spec.name] then
                            show_error(_("Database backup is incomplete: ") .. spec.name)
                            return
                        end
                    end
                end
                local ok, err = reset_directory(paths.data_restore_rollback)
                if not ok then show_error(err) return end
                for _, spec in ipairs(DATA_FILES) do
                    local current = paths.databases .. "/" .. spec.name
                    if lfs.attributes(current, "mode") ~= "file" then
                        show_error(_("Current database is missing: ") .. spec.name)
                        return
                    end
                    local copied, copy_err = copy_file(
                        current, paths.data_restore_rollback .. "/" .. spec.name)
                    if not copied then show_error(copy_err) return end
                end
                local data_ok, data_err = restore_database_backup(paths)
                if not data_ok then
                    for _, spec in ipairs(DATA_FILES) do
                        pcall(atomic_replace,
                            paths.data_restore_rollback .. "/" .. spec.name,
                            paths.databases .. "/" .. spec.name)
                    end
                    show_error(data_err)
                    return
                end
                set_database_bundle_version(data_version)
                pcall(clear_tree, paths.data_restore_rollback)
            end

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
                text = (data_version and _("Previous Word Wise code and databases restored.")
                    or _("Previous Word Wise code restored.")) .. "\n\n"
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
            text = _("Check code and database updates"),
            enabled_func = function() return Updater.getRepository() ~= nil end,
            callback = function() Updater.check() end,
        },
        {
            text = _("Installed version: ") .. Config.version,
            enabled_func = function() return false end,
        },
        {
            text_func = function()
                local pending = pending_data_version(paths)
                local version = Updater.getInstalledDatabaseBundleVersion()
                if pending then return _("Database update pending restart: ") .. pending end
                return _("Installed databases: ") .. (version or _("not synchronized"))
            end,
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
