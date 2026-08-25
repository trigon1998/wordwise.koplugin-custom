package.path = "./?.lua;" .. package.path

local function unified_rows(sql, first, second)
    if sql:find("sense2_context_keywords FROM entries", 1, true) then
        error("schema-v2 unified database must not expose v3 entry column")
    end
    if sql:find("SELECT name FROM sqlite_master", 1, true) then
        return { { "sense2_context" } }
    end
    if sql:find("PRAGMA table_info(sense2_context)", 1, true) then
        return { { nil, "term" }, { nil, "domain" }, { nil, "context_keywords" } }
    end
    if sql:find("FROM entries WHERE term", 1, true) then
        if first == "capital" then
            return {
                { "capital", "capital", "wealth used in business", "vốn", 2, "noun", "economics",
                  "city where government sits", "thủ đô", "asset,investment", 1, 100, 0, nil },
                { "capital", "capital", "wealth used in business", "vốn", 2, "noun", "general",
                  "city where government sits", "thủ đô", "asset,investment", 1, 80, 0, nil },
            }
        end
        if first == "dawdle" then
            return {
                { "dawdle", "dawdle", "to spend time idly and unfruitfully", "lãng phí thời gian", 1,
                  "verb", "general", nil, nil, nil, 1, 50, 0, nil },
            }
        end
    end
    if sql:find("SELECT i.lemma", 1, true) and first == "dawdling" then
        return { { "dawdle" } }
    end
    if sql:find("SELECT domain, context_keywords FROM sense2_context", 1, true) then
        if first == "capital" then
            return { { "economics", "asset,investment" }, { "general", "city,government" } }
        end
    end
    return {}
end

local connection = {}
function connection:prepare(sql)
    if sql:find("sense2_context_keywords FROM entries", 1, true) then
        error("no such column: sense2_context_keywords")
    end
    local row_index, first, second = 0, nil, nil
    local statement = {}
    function statement:reset() row_index = 0; return self end
    function statement:clearbind() first, second = nil, nil; return self end
    function statement:bind(value)
        if first == nil then first = value else second = value end
        return self
    end
    function statement:step()
        row_index = row_index + 1
        return unified_rows(sql, first, second)[row_index]
    end
    function statement:close() end
    return statement
end
function connection:close() self.closed = true end

package.preload["lua-ljsqlite3/init"] = function()
    return { open = function() return connection end }
end
package.preload["logger"] = function()
    return { warn = function() end }
end

local WordWiseDB = require("wordwise_db")
local db, err = WordWiseDB.open("/tmp/wordwise-unified.db")
assert(db, err or "unified database must open")
assert(db.has_sense_context == false, "unified bridge data must use physical schema-v2")
assert(db.has_sense_context_table == true, "unified database must expose context side table")
assert(db.has_domain_context == true, "unified context table must be keyed by domain")

local candidates = db:lookupCandidates("capital")
assert(#candidates == 2, "unified lookup must return both domain candidates")
assert(candidates[1].domain == "economics", "candidate order must be deterministic")
assert(candidates[1].sense2_context_keywords == "asset,investment",
    "economics side-table context must be loaded")
assert(candidates[2].sense2_context_keywords == "city,government",
    "general side-table context must be loaded")
assert(db:lookupExact("capital") == nil,
    "single-result exact lookup must fail closed for multiple domain candidates")
assert(db:lookupWord("capital") == nil,
    "single-result word lookup must fail closed for multiple domain candidates")

local inflected = db:lookupWordCandidates("dawdling")
assert(#inflected == 1 and inflected[1].term == "dawdle",
    "unified irregular lookup must resolve dawdling")
assert(inflected[1].surface == "dawdling", "surface form must be preserved")

print("RC1.4.6 unified database tests: PASS")
