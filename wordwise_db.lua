-- SQLite data access for the custom bilingual Word Wise schema.
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local ENTRY_SQL = [[
SELECT term, lemma, short_en, short_vi, difficulty, pos, domain,
       sense2_en, sense2_vi, context_keywords, phrase_len, priority,
       requires_context, register_label
FROM entries WHERE term = ?1 COLLATE NOCASE LIMIT 1;
]]
local ALIAS_SQL = [[
SELECT alias, term, case_sensitive FROM aliases
WHERE alias = ?1 COLLATE NOCASE ORDER BY case_sensitive DESC LIMIT 4;
]]
local IRREGULAR_SQL = [[
SELECT lemma FROM irregular_forms WHERE surface = ?1 COLLATE NOCASE LIMIT 1;
]]
local META_SQL = "SELECT value FROM metadata WHERE key = ?1 LIMIT 1;"

local WordWiseDB = {}
WordWiseDB.__index = WordWiseDB

local NO_DEINFLECT = {
    morning = true, evening = true, passing = true, news = true,
    physics = true, economics = true, series = true, species = true,
}

local function trim(s)
    if not s then return nil end
    s = s:gsub("^%s+", ""):gsub("%s+$", "")
    return s ~= "" and s or nil
end

local function normalize(s)
    if not s then return "" end
    s = s:gsub("’", "'"):gsub("‘", "'")
         :gsub("–", "-"):gsub("—", "-")
         :gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
    return s:lower()
end

local function regular_candidates(w)
    if NO_DEINFLECT[w] then return { w } end
    local out, seen = { w }, { [w] = true }
    local function add(s)
        if s and #s >= 3 and not seen[s] then
            seen[s] = true
            out[#out + 1] = s
        end
    end
    local n = #w
    if n >= 5 and w:sub(-3) == "ies" then add(w:sub(1, n - 3) .. "y") end
    if n >= 4 and w:sub(-1) == "s" then add(w:sub(1, n - 1)) end
    if n >= 5 and (w:sub(-4) == "ches" or w:sub(-4) == "shes"
        or w:sub(-3) == "xes" or w:sub(-3) == "zes"
        or w:sub(-3) == "ses" or w:sub(-3) == "oes") then
        add(w:sub(1, n - 2))
    end
    if n >= 5 and w:sub(-2) == "ly" then
        if w:sub(-3) == "ily" then add(w:sub(1, n - 3) .. "y") end
        add(w:sub(1, n - 2))
    end
    if n >= 5 and w:sub(-3) == "ied" then add(w:sub(1, n - 3) .. "y") end
    if n >= 5 and w:sub(-2) == "ed" then
        local stem = w:sub(1, n - 2)
        local last = stem:sub(-1)
        local prev = stem:sub(-2, -2)
        if last == prev and last:match("[bdgmnprt]") then add(stem:sub(1, -2)) end
        add(stem)                  -- passed -> pass, walked -> walk
        add(w:sub(1, n - 1))       -- loved -> love
    end
    if n >= 6 and w:sub(-3) == "ing" then
        local stem = w:sub(1, n - 3)
        local last = stem:sub(-1)
        local prev = stem:sub(-2, -2)
        if last == prev and last:match("[bdgmnprt]") then add(stem:sub(1, -2)) end
        add(stem)                  -- hurrying -> hurry
        add(stem .. "e")          -- making -> make
    end
    return out
end

local function row_to_entry(row)
    if not row then return nil end
    return {
        term = row[1], key = row[2] or row[1], lemma = row[2] or row[1],
        short_en = trim(row[3]), short_vi = trim(row[4]),
        difficulty = tonumber(row[5]) or 1, pos = trim(row[6]),
        domain = row[7] or "general", sense2_en = trim(row[8]),
        sense2_vi = trim(row[9]), context_keywords = trim(row[10]),
        phrase_len = tonumber(row[11]) or 1, priority = tonumber(row[12]) or 50,
        requires_context = tonumber(row[13]) or 0, register_label = trim(row[14]),
    }
end

function WordWiseDB.open(path)
    local ok, conn = pcall(SQ3.open, path)
    if not ok or not conn then
        logger.warn("WordWiseDB: cannot open", path, tostring(conn))
        return nil, "cannot open database"
    end
    local self = setmetatable({ conn = conn, cache = {}, cache_count = 0, path = path }, WordWiseDB)
    local ok2, err = pcall(function()
        self.entry_stmt = conn:prepare(ENTRY_SQL)
        self.alias_stmt = conn:prepare(ALIAS_SQL)
        self.irregular_stmt = conn:prepare(IRREGULAR_SQL)
        self.meta_stmt = conn:prepare(META_SQL)
    end)
    if not ok2 or not self.entry_stmt or not self.alias_stmt or not self.irregular_stmt then
        logger.warn("WordWiseDB: schema prepare failed", tostring(err))
        pcall(function() conn:close() end)
        return nil, "incompatible database schema"
    end
    return self
end

function WordWiseDB:_cache_put(key, value)
    if self.cache_count >= 3000 then
        self.cache = {}
        self.cache_count = 0
    end
    if self.cache[key] == nil then self.cache_count = self.cache_count + 1 end
    self.cache[key] = value or false
end

function WordWiseDB:_entry(term)
    local result
    local ok, err = pcall(function()
        self.entry_stmt:reset():clearbind()
        self.entry_stmt:bind(term)
        result = row_to_entry(self.entry_stmt:step())
        self.entry_stmt:clearbind():reset()
    end)
    if not ok then
        logger.warn("WordWiseDB: entry lookup failed", term, tostring(err))
        error(err)
    end
    return result
end

function WordWiseDB:_alias(surface)
    local target
    local ok, err = pcall(function()
        self.alias_stmt:reset():clearbind()
        self.alias_stmt:bind(surface)
        while true do
            local row = self.alias_stmt:step()
            if not row then break end
            local stored_alias = row[1]
            local case_sensitive = tonumber(row[3]) == 1
            if not case_sensitive or surface == stored_alias then
                target = row[2]
                break
            end
        end
        self.alias_stmt:clearbind():reset()
    end)
    if not ok then
        logger.warn("WordWiseDB: alias lookup failed", surface, tostring(err))
        error(err)
    end
    return target
end

function WordWiseDB:_irregular(surface)
    local lemma
    local ok, err = pcall(function()
        self.irregular_stmt:reset():clearbind()
        self.irregular_stmt:bind(surface)
        local row = self.irregular_stmt:step()
        lemma = row and row[1] or nil
        self.irregular_stmt:clearbind():reset()
    end)
    if not ok then
        logger.warn("WordWiseDB: irregular lookup failed", surface, tostring(err))
        error(err)
    end
    return lemma
end

function WordWiseDB:lookupExact(surface)
    local norm = normalize(surface)
    if norm == "" then return nil end
    local cache_key = "e:" .. surface
    local cached = self.cache[cache_key]
    if cached ~= nil then return cached or nil end
    local result = self:_entry(norm)
    if not result then
        local target = self:_alias(surface)
        if target then result = self:_entry(target) end
    end
    if result then result.surface = surface end
    self:_cache_put(cache_key, result)
    return result
end

function WordWiseDB:lookupWord(surface)
    local norm = normalize(surface)
    if norm == "" then return nil end
    local cache_key = "w:" .. surface
    local cached = self.cache[cache_key]
    if cached ~= nil then return cached or nil end

    local result = self:lookupExact(surface)
    if not result then
        local irregular = self:_irregular(norm)
        if irregular then result = self:_entry(irregular) end
    end
    if not result then
        for _, candidate in ipairs(regular_candidates(norm)) do
            result = self:_entry(candidate)
            if result then break end
        end
    end
    if result then result.surface = surface end
    self:_cache_put(cache_key, result)
    return result
end

function WordWiseDB:getMetadata(key)
    local value
    local ok = pcall(function()
        self.meta_stmt:reset():clearbind()
        self.meta_stmt:bind(key)
        local row = self.meta_stmt:step()
        value = row and row[1] or nil
        self.meta_stmt:clearbind():reset()
    end)
    return ok and value or nil
end

function WordWiseDB:clearCache()
    self.cache, self.cache_count = {}, 0
end

function WordWiseDB:close()
    for _, stmt in ipairs({ self.entry_stmt, self.alias_stmt, self.irregular_stmt, self.meta_stmt }) do
        if stmt then pcall(function() stmt:close() end) end
    end
    if self.conn then pcall(function() self.conn:close() end) end
    self.conn = nil
end

return WordWiseDB
