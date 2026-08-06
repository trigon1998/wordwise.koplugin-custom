--[[--
Word Wise bilingual inline hints for KOReader 2026.03.

This is a conservative overlay plugin for reflowable CRe documents. It never
rewrites the book. Dictionary files live in <KOReader data>/wordwise/databases,
while per-book choices remain in the normal KOReader sidecar.
--]]--

local Blitbuffer = require("ffi/blitbuffer")
local ButtonDialog = require("ui/widget/buttondialog")
local DataStorage = require("datastorage")
local Dispatcher = require("dispatcher")
local Event = require("ui/event")
local Font = require("ui/font")
local InfoMessage = require("ui/widget/infomessage")
local RenderText = require("ui/rendertext")
local SpinWidget = require("ui/widget/spinwidget")
local TextViewer = require("ui/widget/textviewer")
local UIManager = require("ui/uimanager")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local lfs = require("libs/libkoreader-lfs")
local logger = require("logger")
local _ = require("gettext")
local T = require("ffi/util").template

local BookClassifier = require("book_classifier")
local ContextScorer = require("context_scorer")
local KnownWords = require("known_words")
local UpdateConfig = require("update_config")
local WordWiseDB = require("wordwise_db")
local WordWiseUpdater = require("wordwise_updater")

local WW_DIR = DataStorage:getDataDir() .. "/wordwise"
local DB_DIR = WW_DIR .. "/databases"
local KNOWN_DB = WW_DIR .. "/known_words.db"

local PLUGIN_VERSION = UpdateConfig.version
local MAX_LEVEL = 5
local MAX_PHRASE_WORDS = 5
local DEFAULT_LEVELS = { general = 2, economics = 3, physics = 3 }
local DEFAULT_GLOSS_FONT_SIZE = 13
local MIN_GLOSS_FONT_SIZE = 10
local MAX_GLOSS_FONT_SIZE = 18
local MAX_HINTS_PER_PAGE = 10
local WORD_WALK_GUARD = 4000
local PAGE_CACHE_LIMIT = 3
local DEFAULT_AUTO_SPACING = 148
local DOMAIN_LABELS = { general = "General", economics = "Economics", physics = "Physics" }
local DEFAULT_PHRASE_LENGTHS = { 5, 4, 3, 2 }
local LAYOUT_HASH_MOD_A = 2147483647
local LAYOUT_HASH_MOD_B = 2147483629

local WordWise = WidgetContainer:extend{
    name = "wordwise",
    is_doc_only = true,
}

local function ensure_dir(path)
    if lfs.attributes(path, "mode") ~= "directory" then
        local ok, err = pcall(lfs.mkdir, path)
        if not ok then logger.warn("Word Wise cannot create directory", path, tostring(err)) end
    end
end

local function normalize_token(text)
    if not text then return "" end
    text = text:gsub("’", "'"):gsub("‘", "'")
               :gsub("–", "-"):gsub("—", "-")
               :gsub("^[^A-Za-z0-9]+", ""):gsub("[^A-Za-z0-9'%-]+$", "")
    return text
end

local function domain_label(domain)
    return DOMAIN_LABELS[domain] or DOMAIN_LABELS.general
end

local function bilingual_gloss(short_en, short_vi)
    short_en = tostring(short_en or "")
    if short_vi and short_vi ~= "" then return short_en .. " · " .. short_vi end
    return short_en
end

local function add_layout_value(hash_a, hash_b, value)
    local text = tostring(value or "")
    for i = 1, #text do
        local byte = text:byte(i)
        hash_a = (hash_a * 33 + byte) % LAYOUT_HASH_MOD_A
        hash_b = (hash_b * 65599 + byte) % LAYOUT_HASH_MOD_B
    end
    -- Keep adjacent fields distinct even when one of them is empty.
    hash_a = (hash_a * 33 + 31) % LAYOUT_HASH_MOD_A
    hash_b = (hash_b * 65599 + 31) % LAYOUT_HASH_MOD_B
    return hash_a, hash_b
end

function WordWise:isSupportedDocument()
    return self.ui and self.ui.document and self.ui.rolling ~= nil and not self.ui.paging
end

function WordWise:getDomain()
    local ds = self.ui and self.ui.doc_settings
    local domain = ds and ds:readSetting("wordwise_domain") or nil
    return DOMAIN_LABELS[domain] and domain or "general"
end

function WordWise:getHintLevel()
    local ds = self.ui and self.ui.doc_settings
    local stored = ds and ds:readSetting("wordwise_hint_level") or nil
    return tonumber(stored) or DEFAULT_LEVELS[self:getDomain()] or 2
end

function WordWise:getGlossFontSize()
    return tonumber(G_reader_settings:readSetting("wordwise_gloss_font_size")) or DEFAULT_GLOSS_FONT_SIZE
end

function WordWise:getGlossFontName()
    return G_reader_settings:readSetting("wordwise_gloss_font_name") or "infofont"
end

function WordWise:isQuickTapEnabled()
    local ds = self.ui and self.ui.doc_settings
    local value = ds and ds:readSetting("wordwise_quick_tap")
    return value == nil or value == true
end

function WordWise:isAutoSpacingEnabled()
    local ds = self.ui and self.ui.doc_settings
    local value = ds and ds:readSetting("wordwise_auto_spacing")
    return value == nil or value == true
end

function WordWise:isEnabled()
    local ds = self.ui and self.ui.doc_settings
    return (ds and ds:isTrue("wordwise_enabled")) or false
end

function WordWise:isPerformanceDiagnosticsEnabled()
    return G_reader_settings:readSetting("wordwise_performance_diagnostics") == true
end

function WordWise:resetPerformanceStats()
    self.performance_stats = {
        compute_requests = 0,
        coalesced_requests = 0,
        scans = 0,
        page_cache_hits = 0,
        page_cache_misses = 0,
        total_phrase_probes = 0,
        last_words = 0,
        last_phrase_probes = 0,
        last_scan_ms = 0,
        max_scan_ms = 0,
    }
end

function WordWise:getPerformanceStats()
    if not self.performance_stats then self:resetPerformanceStats() end
    return self.performance_stats
end

function WordWise:setPerformanceDiagnostics(enabled)
    G_reader_settings:saveSetting("wordwise_performance_diagnostics", enabled == true)
    self:resetPerformanceStats()
end

function WordWise:buildGlossFace()
    local choice = self:getGlossFontName()
    local name = choice
    if choice == "same_as_book" then
        local configurable = self.ui and self.ui.font and self.ui.font.configurable
        name = configurable and configurable.font_face or "infofont"
    end
    local ok, face = pcall(function() return Font:getFace(name, self:getGlossFontSize()) end)
    if not ok or not face then face = Font:getFace("infofont", self:getGlossFontSize()) end
    self.gloss_face = face
    self.gloss_face_book_font = choice == "same_as_book" and tostring(name) or nil
end

function WordWise:getDBPath(domain)
    domain = domain or self:getDomain()
    return DB_DIR .. "/wordwise_" .. domain .. ".db"
end

function WordWise:closeDB()
    if self.db then self.db:close() end
    self.db = nil
    self.db_domain = nil
end

function WordWise:getDB()
    local domain = self:getDomain()
    if self.db and self.db_domain == domain then return self.db end
    self:closeDB()
    local path = self:getDBPath(domain)
    if lfs.attributes(path, "mode") ~= "file" then return nil, "database file not found: " .. path end
    local db, err = WordWiseDB.open(path)
    if not db then return nil, err or "database could not be opened" end
    self.db, self.db_domain = db, domain
    return db
end

function WordWise:getKnownWords()
    if self.known_words then return self.known_words end
    ensure_dir(WW_DIR)
    self.known_words = KnownWords.open(KNOWN_DB)
    return self.known_words
end

function WordWise:isKnown(lemma)
    local kw = self:getKnownWords()
    return kw and kw:isKnown(lemma, self:getDomain()) or false
end

function WordWise:setKnown(lemma, scope, known)
    local kw = self:getKnownWords()
    if kw then kw:setKnown(lemma, scope, known) end
    self:clearPageCache()
    self:refresh()
end

function WordWise:init()
    local database_update_ok, database_update_result = true, nil
    if WordWiseUpdater.applyPendingDataUpdate then
        local call_ok, applied, result = pcall(WordWiseUpdater.applyPendingDataUpdate)
        database_update_ok = call_ok and applied ~= false
        database_update_result = call_ok and result or applied
        if not database_update_ok then
            logger.warn("Word Wise pending database update failed", tostring(database_update_result))
        end
    end
    ensure_dir(WW_DIR)
    ensure_dir(DB_DIR)
    self.hints = {}
    self.page_cache, self.page_cache_order = {}, {}
    self.spacing_candidate, self.spacing_candidate_count = nil, 0
    self.spacing_cooldown = 0
    self.compute_pending = nil
    self:resetPerformanceStats()
    self.failure_notified = false
    self:buildGlossFace()
    self.proper_names = {}
    pcall(function()
        local props = self.ui.document:getProps() or {}
        local authors = props.authors or props.author or ""
        if type(authors) == "table" then authors = table.concat(authors, " ") end
        for name in tostring(authors):gmatch("[A-Za-z][A-Za-z'’-]+") do
            if #name >= 3 then self.proper_names[name:lower()] = true end
        end
    end)

    self.overlay = { paintTo = function(_, bb, x, y) self:paintHints(bb, x, y) end }
    if self.ui.view then self.ui.view:registerViewModule("wordwise", self.overlay) end

    if self.ui.registerTouchZones then
        self.ui:registerTouchZones({
            {
                id = "wordwise_hint_tap",
                ges = "tap",
                screen_zone = { ratio_x = 0, ratio_y = 0, ratio_w = 1, ratio_h = 1 },
                handler = function(ges) return self:onHintTap(ges) end,
                -- Let taps on visible Word Wise hints win over KOReader's
                -- built-in top/bottom menu zones. Returning false from
                -- onHintTap keeps the default gesture active everywhere else.
                overrides = {
                    "readerconfigmenu_ext_tap",
                    "readerconfigmenu_tap",
                },
            },
        })
    end

    self:onDispatcherRegisterActions()
    self.ui.menu:registerToMainMenu(self)
    UIManager:nextTick(function()
        if not database_update_ok then
            UIManager:show(InfoMessage:new{
                text = _("Word Wise kept the previous databases because the pending database update failed:")
                    .. "\n" .. tostring(database_update_result),
            })
        elseif database_update_result then
            UIManager:show(InfoMessage:new{
                text = _("Word Wise code and databases are now synchronized at v")
                    .. tostring(database_update_result) .. ".",
                timeout = 4,
            })
        elseif WordWiseUpdater.maybeOfferDatabaseUpdate then
            WordWiseUpdater.maybeOfferDatabaseUpdate()
        end
    end)
end

function WordWise:currentLineSpacing()
    return (self.ui.font and self.ui.font.configurable
        and self.ui.font.configurable.line_spacing) or 100
end

function WordWise:defaultLineSpacing()
    return G_reader_settings:readSetting("copt_line_spacing")
        or (G_defaults and G_defaults:readSetting("DCREREADER_CONFIG_LINE_SPACE_PERCENT_MEDIUM"))
        or 100
end

function WordWise:captureOriginalSpacing()
    local ds = self.ui and self.ui.doc_settings
    if ds and ds:readSetting("wordwise_original_line_spacing") == nil then
        ds:saveSetting("wordwise_original_line_spacing", self:currentLineSpacing())
    end
end

function WordWise:setLineSpacingValue(value)
    if not self:isSupportedDocument() then return end
    local configurable = self.ui.font and self.ui.font.configurable
    if not configurable then return end
    value = math.max(100, math.min(190, tonumber(value) or 100))
    if configurable.line_spacing == value then return end
    configurable.line_spacing = value
    self.ui.document:setInterlineSpacePercent(value)
    self:clearPageCache()
    self.ui:handleEvent(Event:new("UpdatePos"))
end

function WordWise:restoreOriginalSpacing()
    if not self:isSupportedDocument() then return end
    local ds = self.ui and self.ui.doc_settings
    local original = ds and ds:readSetting("wordwise_original_line_spacing") or nil
    self:setLineSpacingValue(tonumber(original) or self:defaultLineSpacing())
    -- Capture the user's current spacing afresh the next time Word Wise is enabled.
    if ds and ds.delSetting then pcall(function() ds:delSetting("wordwise_original_line_spacing") end) end
end

function WordWise:considerAutoSpacing(hint_count)
    if not self:isAutoSpacingEnabled() or not self:isEnabled() then return end
    local target
    if hint_count <= 3 then target = 132
    elseif hint_count <= 7 then target = 148
    else target = 165 end

    if self.spacing_cooldown > 0 then
        self.spacing_cooldown = self.spacing_cooldown - 1
        return
    end
    if math.abs(self:currentLineSpacing() - target) <= 2 then
        self.spacing_candidate, self.spacing_candidate_count = nil, 0
        return
    end
    if self.spacing_candidate == target then
        self.spacing_candidate_count = self.spacing_candidate_count + 1
    else
        self.spacing_candidate, self.spacing_candidate_count = target, 1
    end
    if self.spacing_candidate_count >= 3 then
        self.spacing_candidate, self.spacing_candidate_count = nil, 0
        self.spacing_cooldown = 5
        UIManager:nextTick(function()
            if self:isEnabled() and self:isAutoSpacingEnabled() then self:setLineSpacingValue(target) end
        end)
    end
end

function WordWise:handleFailure(reason)
    logger.warn("Word Wise disabled safely:", tostring(reason))
    local ds = self.ui and self.ui.doc_settings
    if ds then ds:saveSetting("wordwise_enabled", false) end
    self.hints = {}
    self:closeDB()
    if ds and ds:readSetting("wordwise_original_line_spacing") ~= nil then
        self:restoreOriginalSpacing()
    end
    UIManager:setDirty("all", "ui")
    if not self.failure_notified then
        self.failure_notified = true
        UIManager:show(InfoMessage:new{
            text = _("Word Wise was disabled because its database or plugin data could not be loaded. Reading, highlights, and notes were not changed."),
        })
    end
end

function WordWise:sampleCurrentPage(max_words)
    if not self:isSupportedDocument() then return "" end
    local doc = self.ui.document
    local page = doc:getCurrentPage()
    local start_xp = doc:getPageXPointer(page)
    if not start_xp then return "" end
    local words, xp, guard = {}, doc:getNextVisibleWordStart(start_xp), 0
    while xp and guard < (max_words or 250) do
        guard = guard + 1
        if not doc:isXPointerInCurrentPage(xp) then break end
        local end_xp = doc:getNextVisibleWordEnd(xp)
        if not end_xp then break end
        local word = doc:getTextFromXPointers(xp, end_xp)
        if word and word ~= "" then words[#words + 1] = word end
        local next_xp = doc:getNextVisibleWordStart(end_xp)
        if not next_xp or next_xp == xp then break end
        xp = next_xp
    end
    return table.concat(words, " ")
end

function WordWise:getBookIdentityText()
    local text = ""
    local ok, props = pcall(function() return self.ui.document:getProps() end)
    if ok and type(props) == "table" then
        text = table.concat({ props.title or "", props.authors or props.author or "", props.subject or "" }, " ")
    end
    text = text .. " " .. tostring(self.ui.document.file or "")
    return text
end

function WordWise:applyDomainChoice(domain, enable_after)
    local ds = self.ui.doc_settings
    ds:saveSetting("wordwise_domain", domain)
    ds:saveSetting("wordwise_domain_confirmed", true)
    ds:saveSetting("wordwise_hint_level", DEFAULT_LEVELS[domain])
    self:closeDB()
    self:clearPageCache()
    if enable_after then self:setEnabled(true) else self:refresh() end
end

function WordWise:showDomainDialog(force)
    if not self:isSupportedDocument() then return end
    local sample = self:sampleCurrentPage(250)
    if not force and BookClassifier.isVietnameseDominant(sample) then
        local ds = self.ui.doc_settings
        ds:saveSetting("wordwise_domain", "general")
        ds:saveSetting("wordwise_domain_confirmed", true)
        ds:saveSetting("wordwise_enabled", false)
        UIManager:show(InfoMessage:new{
            text = _("This book appears to be mainly Vietnamese, so Word Wise is off by default. You can enable it manually for English passages."),
        })
        return
    end

    local suggested = BookClassifier.suggest(self:getBookIdentityText(), sample)
    local dialog
    local function button(domain)
        local text = domain_label(domain)
        if domain == suggested then text = text .. " (suggested)" end
        return {
            text = text,
            callback = function()
                UIManager:close(dialog)
                self:applyDomainChoice(domain, true)
            end,
        }
    end
    dialog = ButtonDialog:new{
        title = _("Select Word Wise database"),
        buttons = {
            { button("general") },
            { button("economics") },
            { button("physics") },
        },
    }
    UIManager:show(dialog)
end

function WordWise:onReaderReady()
    if not self:isSupportedDocument() then return end
    local ds = self.ui.doc_settings
    if not ds:isTrue("wordwise_domain_confirmed") then
        UIManager:nextTick(function() self:showDomainDialog(false) end)
    elseif self:isEnabled() then
        UIManager:nextTick(function()
            local db, err = self:getDB()
            if db then self:refresh() else self:handleFailure(err) end
        end)
    end
end

function WordWise:onCloseDocument()
    self.compute_pending = nil
    self:closeDB()
    if self.known_words then self.known_words:close() end
    self.known_words = nil
    self.hints = {}
    self.page_cache, self.page_cache_order = {}, {}
end

function WordWise:schedulePageHintCompute()
    local stats
    if self:isPerformanceDiagnosticsEnabled() then
        stats = self:getPerformanceStats()
        stats.compute_requests = stats.compute_requests + 1
    end
    if self.compute_pending then
        if stats then stats.coalesced_requests = stats.coalesced_requests + 1 end
        return
    end

    local token = {}
    self.compute_pending = token
    UIManager:nextTick(function()
        if self.compute_pending ~= token then return end
        self.compute_pending = nil
        self:safeComputePageHints()
    end)
end

function WordWise:onPosUpdate() self:schedulePageHintCompute() end
function WordWise:onPageUpdate() self:schedulePageHintCompute() end
function WordWise:onSetDimensions()
    -- Rotation can briefly leave the previous page coordinates on screen.
    -- Drop both hints and cached coordinates before KOReader finishes reflowing.
    self.compute_pending = nil
    self.hints = {}
    self:clearPageCache()
end

function WordWise:clearPageCache()
    self.page_cache, self.page_cache_order = {}, {}
end

function WordWise:cachePage(key, hints)
    self.page_cache[key] = hints
    self.page_cache_order[#self.page_cache_order + 1] = key
    while #self.page_cache_order > PAGE_CACHE_LIMIT do
        local old = table.remove(self.page_cache_order, 1)
        if old ~= key then self.page_cache[old] = nil end
    end
end

function WordWise:collectVisibleWords()
    local doc = self.ui.document
    local page = doc:getCurrentPage()
    local start_xp = doc:getPageXPointer(page)
    if not start_xp then return {}, page end
    local records, xp, guard = {}, doc:getNextVisibleWordStart(start_xp), 0
    while xp and guard < WORD_WALK_GUARD do
        guard = guard + 1
        if not doc:isXPointerInCurrentPage(xp) then break end
        local end_xp = doc:getNextVisibleWordEnd(xp)
        if not end_xp then break end
        local surface = doc:getTextFromXPointers(xp, end_xp)
        local key = normalize_token(surface)
        if key ~= "" then
            local boxes = doc:getScreenBoxesFromPositions(xp, end_xp, true)
            local box = boxes and boxes[1]
            if box and box.w > 0 and box.h > 0 then
                records[#records + 1] = { surface = surface, key = key, xp = xp, end_xp = end_xp, box = box }
            end
        end
        local next_xp = doc:getNextVisibleWordStart(end_xp)
        if not next_xp or next_xp == xp then break end
        xp = next_xp
    end
    return records, page
end

function WordWise:pageLayoutSignature(records)
    local hash_a, hash_b = 5381, 17
    local dimen = self.ui and self.ui.view and self.ui.view.dimen
    local configurable = self.ui and self.ui.font and self.ui.font.configurable
    local function add(value)
        hash_a, hash_b = add_layout_value(hash_a, hash_b, value)
    end

    add(dimen and dimen.x)
    add(dimen and dimen.y)
    add(dimen and dimen.w)
    add(dimen and dimen.h)
    add(configurable and configurable.font_face)
    add(configurable and configurable.font_size)
    add(configurable and configurable.line_spacing)
    add(#(records or {}))
    for _, record in ipairs(records or {}) do
        local box = record.box or {}
        add(record.key)
        add(box.x)
        add(box.y)
        add(box.w)
        add(box.h)
    end
    return tostring(hash_a) .. ":" .. tostring(hash_b)
end

function WordWise:contextWords(records, first, last)
    local words = {}
    for i = math.max(1, first - 10), math.min(#records, last + 10) do
        words[#words + 1] = records[i].key
    end
    return words
end

function WordWise:contextExcerpt(records, first, last)
    local parts = {}
    for i = math.max(1, first - 8), math.min(#records, last + 8) do
        parts[#parts + 1] = records[i].surface
    end
    return table.concat(parts, " ")
end

function WordWise:combinedBox(records, first, last)
    local box = records[first].box
    local last_box = records[last].box
    if last > first and math.abs((last_box.y or 0) - (box.y or 0)) <= 2 then
        local x0 = math.min(box.x, last_box.x)
        local x1 = math.max(box.x + box.w, last_box.x + last_box.w)
        return { x = x0, y = box.y, w = x1 - x0, h = math.max(box.h, last_box.h) }
    end
    return { x = box.x, y = box.y, w = box.w, h = box.h }
end

function WordWise:makeHint(entry, surface, records, first, last, confidence)
    local gloss = bilingual_gloss(entry.short_en, entry.short_vi)
    return {
        text = gloss, surface = surface, lemma = entry.lemma or entry.term,
        short_en = entry.short_en, short_vi = entry.short_vi,
        sense2_en = entry.sense2_en, sense2_vi = entry.sense2_vi,
        pos = entry.pos, domain = entry.domain, register_label = entry.register_label,
        difficulty = entry.difficulty, phrase_len = entry.phrase_len or (last - first + 1),
        priority = entry.priority or 50, confidence = confidence or 0,
        box = self:combinedBox(records, first, last),
        context = self:contextExcerpt(records, first, last),
    }
end

function WordWise:finishPerformanceScan(started, word_count, phrase_probes, cache_hit)
    if not started then return end
    local stats = self:getPerformanceStats()
    local elapsed_ms = math.max(0, (os.clock() - started) * 1000)
    stats.last_words = word_count or 0
    stats.last_phrase_probes = phrase_probes or 0
    stats.total_phrase_probes = stats.total_phrase_probes + (phrase_probes or 0)
    stats.last_scan_ms = elapsed_ms
    stats.max_scan_ms = math.max(stats.max_scan_ms, elapsed_ms)
    if cache_hit then
        stats.page_cache_hits = stats.page_cache_hits + 1
    else
        stats.page_cache_misses = stats.page_cache_misses + 1
    end
end

function WordWise:computePageHints()
    self.hints = {}
    if not (self:isEnabled() and self:isSupportedDocument()) then return end
    local started
    if self:isPerformanceDiagnosticsEnabled() then
        started = os.clock()
        local stats = self:getPerformanceStats()
        stats.scans = stats.scans + 1
    end
    local db, err = self:getDB()
    if not db then error(err or "database unavailable") end

    local records, page = self:collectVisibleWords()
    if self:getGlossFontName() == "same_as_book" then
        local configurable = self.ui and self.ui.font and self.ui.font.configurable
        local book_font = tostring(configurable and configurable.font_face or "infofont")
        if self.gloss_face_book_font ~= book_font then self:buildGlossFace() end
    end
    local cache_key = table.concat({ tostring(page), self:getDomain(), tostring(self:getHintLevel()),
        tostring(self:getGlossFontName()), tostring(self:getGlossFontSize()),
        tostring(self:currentLineSpacing()), self:pageLayoutSignature(records) }, "|")
    local cached = self.page_cache[cache_key]
    if cached then
        self.hints = cached
        self:considerAutoSpacing(#cached)
        self:finishPerformanceScan(started, #records, 0, true)
        return
    end

    local cap_counts, lower_counts = {}, {}
    for _, record in ipairs(records) do
        local lower = record.key:lower()
        if record.surface:match("^[A-Z][a-z][A-Za-z'’-]*$") then
            cap_counts[lower] = (cap_counts[lower] or 0) + 1
        else
            lower_counts[lower] = (lower_counts[lower] or 0) + 1
        end
    end

    local candidates, i, level, phrase_probes = {}, 1, self:getHintLevel(), 0
    while i <= #records do
        local matched, consumed
        local remaining = math.min(MAX_PHRASE_WORDS, #records - i + 1)
        local phrase_lengths = db.getPhraseLengths
            and db:getPhraseLengths(records[i].key) or DEFAULT_PHRASE_LENGTHS
        for _, length in ipairs(phrase_lengths) do
            if length <= remaining then
                phrase_probes = phrase_probes + 1
                local surfaces = {}
                for j = i, i + length - 1 do surfaces[#surfaces + 1] = records[j].key end
                local phrase = table.concat(surfaces, " ")
                local entry = db:lookupExact(phrase)
                if entry and entry.difficulty <= level and not self:isKnown(entry.lemma or entry.term) then
                    local context = self:contextWords(records, i, i + length - 1)
                    local accepted, confidence = ContextScorer.accept(entry, context)
                    if accepted then
                        matched = self:makeHint(entry, phrase, records, i, i + length - 1, confidence)
                        consumed = length
                        break
                    end
                end
            end
        end

        if not matched then
            local record = records[i]
            local useful = #record.key >= 3 or record.key:match("^[A-Z][A-Z0-9]+$")
            if useful and not record.key:find("https?", 1, true) then
                local entry = db:lookupWord(record.key)
                if entry and entry.difficulty <= level and not self:isKnown(entry.lemma or entry.term) then
                    local lower = record.key:lower()
                    local repeated_capitalized = (cap_counts[lower] or 0) >= 2
                        and (lower_counts[lower] or 0) == 0
                    local looks_like_name = entry.domain == "general"
                        and ((self.proper_names and self.proper_names[lower]) or repeated_capitalized)
                    if not looks_like_name then
                        local context = self:contextWords(records, i, i)
                        local accepted, confidence = ContextScorer.accept(entry, context)
                        if accepted then matched = self:makeHint(entry, record.surface, records, i, i, confidence) end
                    end
                end
            end
            consumed = 1
        end
        if matched then candidates[#candidates + 1] = matched end
        i = i + consumed
    end

    table.sort(candidates, function(a, b)
        if a.phrase_len ~= b.phrase_len then return a.phrase_len > b.phrase_len end
        if a.difficulty ~= b.difficulty then return a.difficulty < b.difficulty end
        if a.confidence ~= b.confidence then return a.confidence > b.confidence end
        if a.priority ~= b.priority then return a.priority > b.priority end
        return a.box.y < b.box.y
    end)
    while #candidates > MAX_HINTS_PER_PAGE do table.remove(candidates) end
    table.sort(candidates, function(a, b)
        if a.box.y ~= b.box.y then return a.box.y < b.box.y end
        return a.box.x < b.box.x
    end)

    self.hints = candidates
    self:cachePage(cache_key, candidates)
    self:considerAutoSpacing(#candidates)
    self:finishPerformanceScan(started, #records, phrase_probes, false)
end

function WordWise:safeComputePageHints()
    local ok, err = pcall(function() self:computePageHints() end)
    if not ok then self:handleFailure(err) end
end

local GLOSS_HGAP = 8
local GLOSS_WORD_GAP = 3
local GLOSS_SCREEN_TOP_MARGIN = 2
local CARET_DEPTH = 6

-- Position a gloss from an estimate of the target glyph's real top edge.
--
-- CRE exposes a coarse word/line box, not the glyph pixel boundary. RC1.3.3
-- tried to reconstruct that boundary from line-spacing percentage and box.h;
-- on the target reader that estimate remained too high. This round measures
-- the target surface with the active book face, centers those glyph metrics
-- inside the CRE box and anchors the gloss directly above that estimate.
--
-- The old centered baseline remains a lower bound. If a compact line cannot
-- fit the gloss without moving it upward or touching the target, the hint is
-- hidden instead of being forced into the preceding line.
function WordWise:hintVerticalPlacement(box, gloss_size, target_size)
    if not (box and gloss_size and target_size) then return nil end
    local box_h = math.max(1, tonumber(box.h) or 1)
    local target_height = math.max(1,
        (tonumber(target_size.y_top) or 0) + (tonumber(target_size.y_bottom) or 0))
    target_height = math.min(box_h, target_height)

    local target_top = math.floor(
        (tonumber(box.y) or 0) + (box_h - target_height) / 2 + 0.5)
    target_top = math.max(tonumber(box.y) or 0,
        math.min((tonumber(box.y) or 0) + box_h - 1, target_top))

    local direct_baseline = target_top - GLOSS_WORD_GAP
        - (tonumber(gloss_size.y_bottom) or 0)
    local centered_baseline = (tonumber(box.y) or 0)
        + ((tonumber(gloss_size.y_top) or 0)
            - (tonumber(gloss_size.y_bottom) or 0)) / 2
    local baseline = math.floor(math.max(centered_baseline, direct_baseline) + 0.5)
    local top = baseline - (tonumber(gloss_size.y_top) or 0)
    if top < GLOSS_SCREEN_TOP_MARGIN then return nil end

    local bottom = baseline + (tonumber(gloss_size.y_bottom) or 0)
    if bottom > target_top - 1 then return nil end
    local marker_y = bottom + 1
    local caret_depth = math.max(0, math.min(CARET_DEPTH, target_top - marker_y))
    return {
        baseline = baseline,
        marker_y = marker_y,
        caret_depth = caret_depth,
        target_top = target_top,
        top = top,
        bottom = bottom,
    }
end

local function drawWordMarker(bb, x0, x1, cx, ytop, color, depth)
    local half = tonumber(depth) or CARET_DEPTH
    if half <= 0 then return end
    if cx - half < x0 then cx = x0 + half end
    if cx + half > x1 then cx = x1 - half end
    if cx - half > x0 then bb:paintRect(x0, ytop, (cx - half) - x0, 1, color) end
    if x1 > cx + half then bb:paintRect(cx + half, ytop, x1 - (cx + half), 1, color) end
    for i = 0, half do
        bb:setPixel(cx - half + i, ytop + i, color)
        bb:setPixel(cx + half - i, ytop + i, color)
    end
end

function WordWise:paintHints(bb, x, y)
    if not (self:isEnabled() and self.hints and #self.hints > 0) then return end
    local screen_w = bb:getWidth()
    local color = Blitbuffer.COLOR_DARK_GRAY or Blitbuffer.COLOR_BLACK
    local items = {}
    local configurable = self.ui and self.ui.font and self.ui.font.configurable
    local target_face
    if configurable and configurable.font_face and configurable.font_size then
        local ok, face = pcall(function()
            return Font:getFace(configurable.font_face, configurable.font_size)
        end)
        if ok then target_face = face end
    end

    for _, hint in ipairs(self.hints) do
        hint.hitbox = nil
        local size = RenderText:sizeUtf8Text(0, screen_w, self.gloss_face, hint.text, true, false)
        local width = size.x
        local tx = math.floor(hint.box.x + (hint.box.w - width) / 2 + 0.5)
        local max_x = screen_w - width - 2
        if tx > max_x then tx = max_x end
        if tx < 2 then tx = 2 end
        local target_size
        if target_face then
            local ok, measured = pcall(function()
                return RenderText:sizeUtf8Text(
                    0, screen_w, target_face, hint.surface, true, false)
            end)
            if ok then target_size = measured end
        end
        local vertical = self:hintVerticalPlacement(hint.box, size, target_size)
        if vertical then
            items[#items + 1] = {
                hint = hint, x0 = tx, x1 = tx + width, band = hint.box.y,
                baseline = vertical.baseline, marker_y = vertical.marker_y,
                caret_depth = vertical.caret_depth,
                word_cx = math.floor(hint.box.x + hint.box.w / 2 + 0.5),
                top = vertical.top, bottom = vertical.bottom,
            }
        end
    end

    table.sort(items, function(a, b)
        if a.band ~= b.band then return a.band < b.band end
        if a.hint.phrase_len ~= b.hint.phrase_len then return a.hint.phrase_len > b.hint.phrase_len end
        if a.hint.difficulty ~= b.hint.difficulty then return a.hint.difficulty < b.hint.difficulty end
        if a.hint.confidence ~= b.hint.confidence then return a.hint.confidence > b.hint.confidence end
        return a.x0 < b.x0
    end)

    local placed = {}
    for _, item in ipairs(items) do
        if item.baseline > 2 then
            local list = placed[item.band] or {}
            placed[item.band] = list
            local fits = true
            for _, interval in ipairs(list) do
                if item.x0 < interval[2] + GLOSS_HGAP and item.x1 + GLOSS_HGAP > interval[1] then
                    fits = false
                    break
                end
            end
            if fits then
                list[#list + 1] = { item.x0, item.x1 }
                RenderText:renderUtf8Text(bb, item.x0, item.baseline, self.gloss_face,
                    item.hint.text, true, false, color)
                drawWordMarker(bb, item.x0, item.x1, item.word_cx, item.marker_y,
                    color, item.caret_depth)
                item.hint.hitbox = {
                    x = math.min(item.x0, item.hint.box.x) - 4,
                    y = math.min(item.top, item.hint.box.y) - 4,
                    w = math.max(item.x1, item.hint.box.x + item.hint.box.w)
                        - math.min(item.x0, item.hint.box.x) + 8,
                    h = math.max(item.bottom, item.hint.box.y + item.hint.box.h)
                        - math.min(item.top, item.hint.box.y) + 8,
                }
            end
        end
    end
end

function WordWise:showHintPopup(hint)
    local title = hint.surface
    if hint.lemma and hint.lemma:lower() ~= tostring(hint.surface):lower() then
        title = title .. "  →  " .. hint.lemma
    end
    local lines = {
        bilingual_gloss(hint.short_en, hint.short_vi),
        "",
        "Domain: " .. domain_label(self:getDomain()),
    }
    if hint.pos and hint.pos ~= "other" then lines[#lines + 1] = "Part of speech: " .. hint.pos end
    if hint.register_label then lines[#lines + 1] = "Register: " .. hint.register_label end
    if hint.sense2_en then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Other possible sense: "
            .. bilingual_gloss(hint.sense2_en, hint.sense2_vi)
    end
    if hint.context and hint.context ~= "" then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Book context:"
        lines[#lines + 1] = hint.context
    end

    local viewer
    viewer = TextViewer:new{
        title = title,
        text = table.concat(lines, "\n"),
        buttons_table = {
            {
                {
                    text = "Known in " .. domain_label(self:getDomain()),
                    callback = function()
                        UIManager:close(viewer)
                        self:setKnown(hint.lemma, self:getDomain(), true)
                    end,
                },
                {
                    text = "Known in all domains",
                    callback = function()
                        UIManager:close(viewer)
                        self:setKnown(hint.lemma, "*", true)
                    end,
                },
            },
            {
                {
                    text = "Open dictionary",
                    callback = function()
                        UIManager:close(viewer)
                        UIManager:nextTick(function() self:openDictionary(hint.surface) end)
                    end,
                },
            },
        },
    }
    UIManager:show(viewer)
end

function WordWise:openDictionary(word)
    local ok = false
    if self.ui.dictionary and self.ui.dictionary.onLookupWord then
        ok = pcall(function() self.ui.dictionary:onLookupWord(word) end)
    end
    if not ok then ok = pcall(function() self.ui:handleEvent(Event:new("LookupWord", word)) end) end
    if not ok then
        UIManager:show(InfoMessage:new{ text = _("Could not open the dictionary for this word.") })
    end
end

function WordWise:onHintTap(ges)
    if not (self:isEnabled() and self:isQuickTapEnabled() and self.hints) then return false end
    local pos = ges and ges.pos or ges
    local px, py = pos and pos.x, pos and pos.y
    if not px or not py then return false end
    for i = #self.hints, 1, -1 do
        local hint = self.hints[i]
        -- paintHints assigns hitbox only after the hint is actually rendered.
        -- A collision-hidden hint therefore cannot intercept a tap.
        local box = hint.hitbox
        if box and px >= box.x and px <= box.x + box.w and py >= box.y and py <= box.y + box.h then
            self:showHintPopup(hint)
            return true
        end
    end
    return false
end

function WordWise:refresh()
    self.compute_pending = nil
    self:safeComputePageHints()
    UIManager:setDirty("all", "ui")
end

function WordWise:setEnabled(on)
    if not self:isSupportedDocument() then return end
    if on then
        local db, err = self:getDB()
        if not db then
            self:handleFailure(err)
            return
        end
        self:captureOriginalSpacing()
        self.ui.doc_settings:saveSetting("wordwise_enabled", true)
        if self:isAutoSpacingEnabled() then self:setLineSpacingValue(DEFAULT_AUTO_SPACING) end
        self.failure_notified = false
        self:refresh()
    else
        self.ui.doc_settings:saveSetting("wordwise_enabled", false)
        self.hints = {}
        self:clearPageCache()
        self:restoreOriginalSpacing()
        UIManager:setDirty("all", "ui")
    end
end

function WordWise:setHintLevel(value)
    self.ui.doc_settings:saveSetting("wordwise_hint_level", value)
    self:clearPageCache()
    self:refresh()
end

function WordWise:setGlossFontSize(value)
    G_reader_settings:saveSetting("wordwise_gloss_font_size", value)
    self:buildGlossFace()
    self:clearPageCache()
    self:refresh()
end

function WordWise:setGlossFontName(value)
    G_reader_settings:saveSetting("wordwise_gloss_font_name", value)
    self:buildGlossFace()
    self:clearPageCache()
    self:refresh()
end

function WordWise:setAutoSpacing(on)
    self.ui.doc_settings:saveSetting("wordwise_auto_spacing", on)
    self.spacing_candidate, self.spacing_candidate_count = nil, 0
    if on and self:isEnabled() then self:setLineSpacingValue(DEFAULT_AUTO_SPACING) end
end

function WordWise:setManualSpacing(value)
    self.ui.doc_settings:saveSetting("wordwise_auto_spacing", false)
    self:setLineSpacingValue(value)
end

function WordWise:diagnosticsText()
    local db, err = self:getDB()
    local lines = {
        "Plugin version: " .. PLUGIN_VERSION,
    }
    if not db then
        lines[#lines + 1] = "Database error: " .. tostring(err)
        return table.concat(lines, "\n")
    end
    local details = {
        "Database: " .. self:getDBPath(),
        "Domain: " .. domain_label(self:getDomain()),
        "Database build: " .. tostring(db:getMetadata("build_version") or "unknown"),
        "Entries: " .. tostring(db:getMetadata("entry_count") or "unknown"),
        "Phrases: " .. tostring(db:getMetadata("phrase_count") or "unknown"),
        "Reviewed Vietnamese: " .. tostring(db:getMetadata("reviewed_vi_count")
            or db:getMetadata("verified_vi_count") or "unknown"),
        "English-only entries: " .. tostring(db:getMetadata("english_only_count") or "unknown"),
        "Phrase matcher: up to " .. tostring(MAX_PHRASE_WORDS) .. " words",
        "Hint level: " .. tostring(self:getHintLevel()),
        "Current line spacing: " .. tostring(self:currentLineSpacing()) .. "%",
        "Page hints: " .. tostring(#(self.hints or {})),
        "Update repository: " .. (WordWiseUpdater.getRepository() or "not configured"),
        "OTA database bundle: " .. (WordWiseUpdater.getInstalledDatabaseBundleVersion
            and (WordWiseUpdater.getInstalledDatabaseBundleVersion() or "not synchronized")
            or "not available"),
    }
    if self:isPerformanceDiagnosticsEnabled() then
        local stats = self:getPerformanceStats()
        details[#details + 1] = string.format(
            "Performance: %d requests · %d coalesced",
            stats.compute_requests, stats.coalesced_requests)
        details[#details + 1] = string.format(
            "Scans: %d · page cache hits: %d",
            stats.scans, stats.page_cache_hits)
        details[#details + 1] = string.format(
            "Last scan: %d words · %d phrase probes · %.1f ms",
            stats.last_words, stats.last_phrase_probes, stats.last_scan_ms)
    else
        details[#details + 1] = "Performance counters: off"
    end
    for _, line in ipairs(details) do lines[#lines + 1] = line end
    return table.concat(lines, "\n")
end

function WordWise:onDispatcherRegisterActions()
    Dispatcher:registerAction("wordwise_toggle", {
        category = "none", event = "WordWiseToggle",
        title = _("Toggle Word Wise hints"), reader = true,
    })
end

function WordWise:addToMainMenu(menu_items)
    menu_items.wordwise = {
        text = _("Word Wise"),
        sorting_hint = "more_tools",
        sub_item_table_func = function() return self:getSubMenu() end,
    }
end

function WordWise:getSubMenu()
    return {
        {
            text = _("Enable inline hints"),
            checked_func = function() return self:isEnabled() end,
            enabled_func = function() return self:isSupportedDocument() end,
            callback = function() self:setEnabled(not self:isEnabled()) end,
        },
        {
            text_func = function() return "Database: " .. domain_label(self:getDomain()) end,
            sub_item_table_func = function()
                local items = {}
                for _, domain in ipairs({ "general", "economics", "physics" }) do
                    items[#items + 1] = {
                        text = domain_label(domain), radio = true,
                        checked_func = function() return self:getDomain() == domain end,
                        callback = function() self:applyDomainChoice(domain, self:isEnabled()) end,
                    }
                end
                return items
            end,
        },
        {
            text_func = function() return T(_("Hint level: %1"), self:getHintLevel()) end,
            sub_item_table_func = function()
                local items = {}
                local labels = { "1 — rarest only", "2", "3", "4", "5 — most hints" }
                for level = 1, MAX_LEVEL do
                    items[level] = {
                        text = labels[level], radio = true,
                        checked_func = function() return self:getHintLevel() == level end,
                        callback = function() self:setHintLevel(level) end,
                    }
                end
                return items
            end,
        },
        {
            text_func = function() return T(_("Hint font size: %1"), self:getGlossFontSize()) end,
            keep_menu_open = true,
            callback = function(touchmenu_instance)
                UIManager:show(SpinWidget:new{
                    title_text = _("Hint font size"),
                    value = self:getGlossFontSize(), value_min = MIN_GLOSS_FONT_SIZE,
                    value_max = MAX_GLOSS_FONT_SIZE, default_value = DEFAULT_GLOSS_FONT_SIZE,
                    keep_shown_on_apply = true,
                    callback = function(spin)
                        self:setGlossFontSize(spin.value)
                        if touchmenu_instance then touchmenu_instance:updateItems() end
                    end,
                })
            end,
        },
        {
            text = _("Hint font"),
            sub_item_table_func = function()
                local fonts = {
                    { "Noto Sans", "infofont" },
                    { "Same as book", "same_as_book" },
                    { "Roboto", "Roboto" },
                    { "Atkinson Hyperlegible", "Atkinson Hyperlegible" },
                }
                local items = {}
                for _, spec in ipairs(fonts) do
                    local label, value = spec[1], spec[2]
                    items[#items + 1] = {
                        text = label, radio = true,
                        checked_func = function() return self:getGlossFontName() == value end,
                        callback = function() self:setGlossFontName(value) end,
                    }
                end
                return items
            end,
        },
        {
            text = _("Quick tap opens Word Wise popup"),
            checked_func = function() return self:isQuickTapEnabled() end,
            callback = function()
                self.ui.doc_settings:saveSetting("wordwise_quick_tap", not self:isQuickTapEnabled())
            end,
        },
        {
            text = _("Line spacing"),
            sub_item_table_func = function()
                return {
                    {
                        text = _("Automatic"), radio = true,
                        checked_func = function() return self:isAutoSpacingEnabled() end,
                        callback = function() self:setAutoSpacing(true) end,
                    },
                    {
                        text = "132% — low density", radio = true,
                        checked_func = function() return not self:isAutoSpacingEnabled() and self:currentLineSpacing() == 132 end,
                        callback = function() self:setManualSpacing(132) end,
                    },
                    {
                        text = "148% — medium density", radio = true,
                        checked_func = function() return not self:isAutoSpacingEnabled() and self:currentLineSpacing() == 148 end,
                        callback = function() self:setManualSpacing(148) end,
                    },
                    {
                        text = "165% — high density", radio = true,
                        checked_func = function() return not self:isAutoSpacingEnabled() and self:currentLineSpacing() == 165 end,
                        callback = function() self:setManualSpacing(165) end,
                    },
                }
            end,
        },
        {
            text = _("Detect book category again"),
            callback = function() self:showDomainDialog(true) end,
        },
        {
            text = _("Updates"),
            sub_item_table_func = function() return WordWiseUpdater.getMenuItems() end,
        },
        {
            text = _("Performance counters"),
            checked_func = function() return self:isPerformanceDiagnosticsEnabled() end,
            callback = function()
                self:setPerformanceDiagnostics(not self:isPerformanceDiagnosticsEnabled())
            end,
        },
        {
            text = _("Clear cache"),
            callback = function()
                self:clearPageCache()
                if self.db then self.db:clearCache() end
                self:resetPerformanceStats()
                self:refresh()
                UIManager:show(InfoMessage:new{ text = _("Word Wise cache cleared.") })
            end,
        },
        {
            text = _("Diagnostics"),
            callback = function() UIManager:show(InfoMessage:new{ text = self:diagnosticsText() }) end,
        },
    }
end

function WordWise:onWordWiseToggle()
    self:setEnabled(not self:isEnabled())
    return true
end

return WordWise
