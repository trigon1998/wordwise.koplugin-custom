package.path = "./?.lua;" .. package.path

local prepared_sql = {}
local phrase_steps = 0

local function rows_for(sql)
    if sql:find("SELECT term FROM entries WHERE phrase_len", 1, true) then
        return {
            { "earnings before interest and taxes" },
            { "earnings per share" },
            { "market economy" },
        }
    end
    if sql:find("SELECT alias FROM aliases WHERE instr", 1, true) then
        return {
            { "gross domestic product" },
            { "earnings before tax" },
        }
    end
    return {}
end

local function statement(sql)
    local rows = rows_for(sql)
    local cursor = 0
    local stmt = { sql = sql, closed = false }
    function stmt:reset()
        cursor = 0
        return self
    end
    function stmt:clearbind() return self end
    function stmt:bind() return self end
    function stmt:step()
        cursor = cursor + 1
        if #rows > 0 then phrase_steps = phrase_steps + 1 end
        return rows[cursor]
    end
    function stmt:close() self.closed = true end
    return stmt
end

local connection = {}
function connection:prepare(sql)
    local stmt = statement(sql)
    prepared_sql[#prepared_sql + 1] = stmt
    return stmt
end
function connection:close() self.closed = true end

package.preload["lua-ljsqlite3/init"] = function()
    return { open = function() return connection end }
end
package.preload["logger"] = function()
    return { warn = function() end }
end

local WordWiseDB = require("wordwise_db")

local function assert_equal(actual, expected, message)
    if actual ~= expected then
        error((message or "values differ") .. ": expected " .. tostring(expected)
            .. ", got " .. tostring(actual))
    end
end

local function assert_lengths(actual, expected, message)
    assert_equal(#actual, #expected, message)
    for index, value in ipairs(expected) do
        assert_equal(actual[index], value, message)
    end
end

local db, err = WordWiseDB.open("/tmp/wordwise-test.db")
assert(db, err or "database fixture must open")
assert_equal(#prepared_sql, 6,
    "all repeated and one-shot SQL statements must be prepared once")
assert(prepared_sql[3].sql:find("JOIN entries", 1, true),
    "irregular lookup must reject mappings without a target entry")

assert_lengths(db:getPhraseLengths("Earnings"), { 5, 3 },
    "phrase index must retain only available lengths in descending order")
assert_lengths(db:getPhraseLengths("gross"), { 3 },
    "multi-word aliases must contribute their first word")
assert_lengths(db:getPhraseLengths("market"), { 2 },
    "two-word entries must remain eligible")
assert_lengths(db:getPhraseLengths("ordinary"), {},
    "non-head words must return no phrase candidates")

local steps_after_build = phrase_steps
db:getPhraseLengths("earnings")
assert_equal(phrase_steps, steps_after_build,
    "phrase rows must be scanned only once per active database")

assert(prepared_sql[5].closed and prepared_sql[6].closed,
    "one-shot phrase statements must close after the compact index is built")

db:close()
assert(connection.closed, "closing Word Wise DB must close SQLite")

print("RC1.3.3 database optimization tests: PASS")
