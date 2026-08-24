package.path = "./?.lua;" .. package.path

local function rows_for(sql)
    if sql:find("SELECT context_keywords FROM sense2_context", 1, true) then
        return { { "city,government,nation,state" } }
    end
    if sql:find("SELECT name FROM sqlite_master", 1, true) then
        return { { "sense2_context" } }
    end
    if sql:find("FROM entries WHERE term", 1, true) then
        return {
            { "capital", "capital", "wealth used in business", "vốn",
              2, "noun", "economics", "city where government sits", "thủ đô",
              "asset,investment", 1, 100, 0, nil },
        }
    end
    return {}
end

local connection = {}
function connection:prepare(sql)
    if sql:find("sense2_context_keywords", 1, true) then
        error("no such column: sense2_context_keywords")
    end
    local rows = rows_for(sql)
    local cursor = 0
    local statement = {}
    function statement:reset() cursor = 0; return self end
    function statement:clearbind() return self end
    function statement:bind() return self end
    function statement:step()
        cursor = cursor + 1
        return rows[cursor]
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
db:close()

print("RC1.4.3 legacy database compatibility tests: PASS")
