-- SQLite data access for the custom bilingual Word Wise schema.
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local ENTRY_SQL_LEGACY = [[
SELECT term, lemma, short_en, short_vi, difficulty, pos, domain,
       sense2_en, sense2_vi, context_keywords, phrase_len, priority,
       requires_context, register_label
FROM entries WHERE term = ?1 COLLATE NOCASE LIMIT 1;
]]
local ENTRY_SQL_WITH_SENSE_CONTEXT = [[
SELECT term, lemma, short_en, short_vi, difficulty, pos, domain,
       sense2_en, sense2_vi, context_keywords, sense2_context_keywords,
       phrase_len, priority, requires_context, register_label
FROM entries WHERE term = ?1 COLLATE NOCASE LIMIT 1;
]]
local ALIAS_SQL = [[
SELECT alias, term, case_sensitive FROM aliases
WHERE alias = ?1 COLLATE NOCASE
ORDER BY case_sensitive DESC, term COLLATE NOCASE;
]]
local IRREGULAR_SQL = [[
SELECT i.lemma
FROM irregular_forms AS i
JOIN entries AS e ON e.term = i.lemma COLLATE NOCASE
WHERE i.surface = ?1 COLLATE NOCASE
LIMIT 1;
]]
local META_SQL = "SELECT value FROM metadata WHERE key = ?1 LIMIT 1;"
local PHRASE_ENTRY_SQL = [[
SELECT term FROM entries WHERE phrase_len BETWEEN 2 AND 5;
]]
local PHRASE_ALIAS_SQL = [[
SELECT alias FROM aliases WHERE instr(trim(alias), ' ') > 0;
]]

local WordWiseDB = {}
WordWiseDB.__index = WordWiseDB
local EMPTY_PHRASE_LENGTHS = {}

local NO_DEINFLECT = {
    morning = true, evening = true, passing = true, news = true,
    physics = true, economics = true, series = true, species = true,
}

local POS_NOUN_OR_VERB = { noun = true, verb = true }
local POS_VERB = { verb = true }
local POS_ADJECTIVE = { adjective = true }

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

local function phrase_shape(surface)
    local normalized = normalize(surface)
    local first
    local length = 0
    for word in normalized:gmatch("%S+") do
        if not first then first = word end
        length = length + 1
    end
    return first, length
end

local function regular_candidates(w)
    if NO_DEINFLECT[w] then return {} end
    local out, seen = {}, {}
    local function add(s, allowed_pos)
        if s and #s >= 3 and not seen[s] then
            seen[s] = true
            out[#out + 1] = { term = s, allowed_pos = allowed_pos }
        end
    end
    local n = #w
    if n >= 5 and w:sub(-3) == "ies" then
        add(w:sub(1, n - 3) .. "y", POS_NOUN_OR_VERB)
    end
    if n >= 5 and (w:sub(-4) == "ches" or w:sub(-4) == "shes"
        or w:sub(-3) == "xes" or w:sub(-3) == "zes"
        or w:sub(-3) == "ses" or w:sub(-3) == "oes") then
        add(w:sub(1, n - 2), POS_NOUN_OR_VERB)
    end
    if n >= 4 and w:sub(-1) == "s" then
        add(w:sub(1, n - 1), POS_NOUN_OR_VERB)
    end
    if n >= 5 and w:sub(-2) == "ly" then
        if w:sub(-3) == "ily" then
            add(w:sub(1, n - 3) .. "y", POS_ADJECTIVE)
        end
        add(w:sub(1, n - 2), POS_ADJECTIVE)
    end
    if n >= 5 and w:sub(-3) == "ied" then
        add(w:sub(1, n - 3) .. "y", POS_VERB)
    end
    if n >= 5 and w:sub(-2) == "ed" then
        local stem = w:sub(1, n - 2)
        local last = stem:sub(-1)
        local prev = stem:sub(-2, -2)
        if last == prev and last:match("[bdgmnprt]") then
            add(stem:sub(1, -2), POS_VERB)
        end
        add(stem, POS_VERB)                  -- passed -> pass, walked -> walk
        add(w:sub(1, n - 1), POS_VERB)       -- loved -> love
    end
    if n >= 6 and w:sub(-3) == "ing" then
        local stem = w:sub(1, n - 3)
        local last = stem:sub(-1)
        local prev = stem:sub(-2, -2)
        if last == prev and last:match("[bdgmnprt]") then
            add(stem:sub(1, -2), POS_VERB)
        end
        add(stem, POS_VERB)                  -- hurrying -> hurry
        add(stem .. "e", POS_VERB)          -- making -> make
    end
    return out
end

local function pos_matches(entry, allowed_pos)
    if not entry or not allowed_pos then return false end
    local pos = normalize(entry.pos)
    for expected in pairs(allowed_pos) do
        if pos == expected or pos:find(expected, 1, true) then return true end
    end
    return false
end

local function row_to_entry(row, has_sense_context)
    if not row then return nil end
    local sense2_context_keywords
    local phrase_index, priority_index, requires_index, register_index = 11, 12, 13, 14
    if has_sense_context then
        sense2_context_keywords = row[11]
        phrase_index, priority_index, requires_index, register_index = 12, 13, 14, 15
    end
    return {
        term = row[1], key = row[2] or row[1], lemma = row[2] or row[1],
        short_en = trim(row[3]), short_vi = trim(row[4]),
        difficulty = tonumber(row[5]) or 1, pos = trim(row[6]),
        domain = row[7] or "general", sense2_en = trim(row[8]),
        sense2_vi = trim(row[9]), context_keywords = trim(row[10]),
        sense2_context_keywords = trim(sense2_context_keywords),
        phrase_len = tonumber(row[phrase_index]) or 1,
        priority = tonumber(row[priority_index]) or 50,
        requires_context = tonumber(row[requires_index]) or 0,
        register_label = trim(row[register_index]),
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
        local probe_ok, probe = pcall(function()
            return conn:prepare("SELECT sense2_context_keywords FROM entries LIMIT 0;")
        end)
        if probe_ok and probe then
            pcall(function() probe:close() end)
            self.has_sense_context = true
        else
            self.has_sense_context = false
        end
        self.entry_stmt = conn:prepare(self.has_sense_context
            and ENTRY_SQL_WITH_SENSE_CONTEXT or ENTRY_SQL_LEGACY)
        self.alias_stmt = conn:prepare(ALIAS_SQL)
        self.irregular_stmt = conn:prepare(IRREGULAR_SQL)
        self.meta_stmt = conn:prepare(META_SQL)
        self.phrase_entry_stmt = conn:prepare(PHRASE_ENTRY_SQL)
        self.phrase_alias_stmt = conn:prepare(PHRASE_ALIAS_SQL)
    end)
    if not ok2 or not self.entry_stmt or not self.alias_stmt or not self.irregular_stmt
        or not self.meta_stmt or not self.phrase_entry_stmt or not self.phrase_alias_stmt then
        logger.warn("WordWiseDB: schema prepare failed", tostring(err))
        pcall(function() conn:close() end)
        return nil, "incompatible database schema"
    end
    return self
end

function WordWiseDB:_ensurePhraseIndex()
    if self.phrase_lengths_by_head then return end
    local index = {}
    local function add(surface)
        local first, length = phrase_shape(surface)
        if not first or length < 2 or length > 5 then return end
        local lengths = index[first]
        if not lengths then
            lengths = {}
            index[first] = lengths
        end
        lengths[length] = true
    end

    local ok, err = pcall(function()
        for _, stmt in ipairs({ self.phrase_entry_stmt, self.phrase_alias_stmt }) do
            stmt:reset():clearbind()
            while true do
                local row = stmt:step()
                if not row then break end
                add(row[1])
            end
            stmt:clearbind():reset()
        end
    end)
    if not ok then
        logger.warn("WordWiseDB: phrase index failed", tostring(err))
        error(err)
    end

    for first, length_set in pairs(index) do
        local lengths = {}
        for length = 5, 2, -1 do
            if length_set[length] then lengths[#lengths + 1] = length end
        end
        index[first] = lengths
    end
    self.phrase_lengths_by_head = index

    -- These statements are one-shot: release them after building the compact
    -- first-word index so only the active dictionary keeps lookup statements.
    for _, name in ipairs({ "phrase_entry_stmt", "phrase_alias_stmt" }) do
        local stmt = self[name]
        if stmt then pcall(function() stmt:close() end) end
        self[name] = nil
    end
end

function WordWiseDB:getPhraseLengths(first_word)
    self:_ensurePhraseIndex()
    local first = phrase_shape(first_word)
    return (first and self.phrase_lengths_by_head[first]) or EMPTY_PHRASE_LENGTHS
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
        result = row_to_entry(self.entry_stmt:step(), self.has_sense_context)
        self.entry_stmt:clearbind():reset()
    end)
    if not ok then
        logger.warn("WordWiseDB: entry lookup failed", term, tostring(err))
        error(err)
    end
    return result
end

function WordWiseDB:_alias(surface, case_sensitive_only)
    local target, ambiguous
    local ok, err = pcall(function()
        self.alias_stmt:reset():clearbind()
        self.alias_stmt:bind(surface)
        while true do
            local row = self.alias_stmt:step()
            if not row then break end
            local stored_alias = row[1]
            local case_sensitive = tonumber(row[3]) == 1
            local eligible = case_sensitive_only
                and case_sensitive and surface == stored_alias
                or not case_sensitive_only
                    and (not case_sensitive or surface == stored_alias)
            if eligible then
                if target and target:lower() ~= tostring(row[2]):lower() then
                    ambiguous = true
                else
                    target = row[2]
                end
            end
        end
        self.alias_stmt:clearbind():reset()
    end)
    if not ok then
        logger.warn("WordWiseDB: alias lookup failed", surface, tostring(err))
        error(err)
    end
    -- Multiple meanings for the same alias cannot be resolved by row order.
    -- Fail closed and require the data pack to provide one canonical target.
    if ambiguous then return nil, true end
    return target, false
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
    local result
    -- A deliberately case-sensitive acronym such as BOP or ROE must beat the
    -- unrelated lowercase exact word (bop/roe).  Ordinary aliases still stay
    -- behind exact lookup, preserving the canonical exact-entry rule.
    local target, ambiguous = self:_alias(surface, true)
    if target then
        result = self:_entry(target)
    elseif not ambiguous then
        result = self:_entry(norm)
        if not result then
            target, ambiguous = self:_alias(surface, false)
            if target then result = self:_entry(target) end
        end
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
        local matches, matched_terms = {}, {}
        for _, candidate in ipairs(regular_candidates(norm)) do
            local entry = self:_entry(candidate.term)
            if entry and pos_matches(entry, candidate.allowed_pos)
                and not matched_terms[entry.term:lower()] then
                matched_terms[entry.term:lower()] = true
                matches[#matches + 1] = entry
            end
        end
        -- Orthographic deinflection can produce two real words (for example
        -- singing -> sing/singe).  Guessing in that situation is exactly how
        -- gaming was previously mapped to the unrelated noun "gam".  Fail
        -- closed unless the database leaves one unambiguous, POS-valid lemma.
        if #matches == 1 then result = matches[1] end
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
    for _, stmt in ipairs({
        self.entry_stmt, self.alias_stmt, self.irregular_stmt, self.meta_stmt,
        self.phrase_entry_stmt, self.phrase_alias_stmt,
    }) do
        if stmt then pcall(function() stmt:close() end) end
    end
    if self.conn then pcall(function() self.conn:close() end) end
    self.conn = nil
end

return WordWiseDB
