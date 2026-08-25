local function rows_for(sql, bound)
    if sql:find("SELECT context_keywords FROM sense2_context", 1, true) then
        return { { "city,government,nation,state" } }
    end
    if sql:find("SELECT name FROM sqlite_master", 1, true) then
        return { { "sense2_context" } }
    end
    if sql:find("SELECT i.lemma", 1, true) then
        if bound == "dawdling" then return { { "dawdle" } } end
        return {}
    end
    if sql:find("FROM entries WHERE term", 1, true) then
        if bound == "dawdle" then
            return {
                { "dawdle", "dawdle", "to spend time idly and unfruitfully",
                  "lãng phí thời gian", 1, "verb", "general", "", "", "", 1, 0, 0, nil },
            }
        end
        if bound == "capital" then
            return {
                { "capital", "capital", "wealth used in business", "vốn",
                  2, "noun", "economics", "city where government sits", "thủ đô",
                  "asset,investment", 1, 100, 0, nil },
            }
        end
    end
    return {}
end

local connection = {}
function connection:prepare(sql)
    if sql:find("sense2_context_keywords", 1, true) then
        error("no such column: sense2_context_keywords")
    end
    local cursor = 0
    local bound
    local statement = {}
    function statement:reset() cursor = 0; return self end
    function statement:clearbind() bound = nil; return self end
    function statement:bind(value) bound = value; return self end
    function statement:step()
        cursor = cursor + 1
        return rows_for(sql, bound)[cursor]
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
local db, err = WordWiseDB.open("/tmp/wordwise-legacy.db")
assert(db, err or "legacy schema must open")
assert(db.has_sense_context == false, "legacy probe must select schema v2")
assert(db.has_sense_context_table == true, "schema-v2 side table must be detected")
local entry = db:lookupExact("capital")
assert(entry, "legacy entry lookup must work")
assert(entry.short_en == "wealth used in business", "legacy primary gloss mismatch")
assert(entry.sense2_en == "city where government sits", "legacy sense2 gloss mismatch")
assert(entry.sense2_context_keywords == "city,government,nation,state",
    "schema-v2 side table must restore alternate keywords")
local inflected = db:lookupWord("dawdling")
assert(inflected, "legacy irregular surface must resolve")
assert(inflected.term == "dawdle", "irregular surface must resolve to reviewed lemma")
assert(inflected.surface == "dawdling", "resolved entry must retain surface form")
assert(inflected.short_vi == "lãng phí thời gian", "coverage gloss must survive irregular lookup")
db:close()

print("RC1.4.5 legacy database compatibility tests: PASS")
