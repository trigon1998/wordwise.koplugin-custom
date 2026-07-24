-- Domain-aware known-word storage, separate from replaceable dictionary files.
local SQ3 = require("lua-ljsqlite3/init")
local logger = require("logger")

local KnownWords = {}
KnownWords.__index = KnownWords

function KnownWords.open(path)
    local ok, conn = pcall(SQ3.open, path)
    if not ok or not conn then return nil end
    local self = setmetatable({ conn = conn, cache = {} }, KnownWords)
    local ok2, err = pcall(function()
        conn:exec([[CREATE TABLE IF NOT EXISTS known_words(
            term TEXT NOT NULL COLLATE NOCASE,
            scope TEXT NOT NULL,
            PRIMARY KEY(term, scope)
        );]])
        self.check_stmt = conn:prepare([[SELECT 1 FROM known_words
            WHERE term = ?1 COLLATE NOCASE AND (scope = '*' OR scope = ?2) LIMIT 1;]])
        self.add_stmt = conn:prepare("INSERT OR REPLACE INTO known_words(term, scope) VALUES(?1, ?2);")
        self.remove_stmt = conn:prepare("DELETE FROM known_words WHERE term = ?1 COLLATE NOCASE AND scope = ?2;")
    end)
    if not ok2 then
        logger.warn("WordWise known words init failed", tostring(err))
        pcall(function() conn:close() end)
        return nil
    end
    return self
end

function KnownWords:isKnown(term, domain)
    if not term then return false end
    local key = term:lower() .. "\0" .. domain
    if self.cache[key] ~= nil then return self.cache[key] end
    local found = false
    local ok = pcall(function()
        self.check_stmt:reset():clearbind()
        self.check_stmt:bind(term, domain)
        found = self.check_stmt:step() ~= nil
        self.check_stmt:clearbind():reset()
    end)
    self.cache[key] = ok and found or false
    return self.cache[key]
end

function KnownWords:setKnown(term, scope, known)
    if not term then return end
    local stmt = known and self.add_stmt or self.remove_stmt
    pcall(function()
        stmt:reset():clearbind()
        stmt:bind(term, scope)
        stmt:step()
        stmt:clearbind():reset()
    end)
    self.cache = {}
end

function KnownWords:close()
    for _, stmt in ipairs({ self.check_stmt, self.add_stmt, self.remove_stmt }) do
        if stmt then pcall(function() stmt:close() end) end
    end
    if self.conn then pcall(function() self.conn:close() end) end
end

return KnownWords
