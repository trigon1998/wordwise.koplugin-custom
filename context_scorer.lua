local ContextScorer = {}

local function words_to_set(words)
    local set = {}
    for _, word in ipairs(words or {}) do
        local key = word:lower():gsub("[^a-z0-9%-]", "")
        if key ~= "" then set[key] = true end
    end
    return set
end

local function score_keywords(keywords, context_set)
    if not keywords or keywords == "" then return 0 end
    local set = context_set or {}
    local hits = 0
    for keyword in keywords:gmatch("[^,]+") do
        keyword = keyword:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if set[keyword] then
            hits = hits + 1
        elseif keyword:find(" ", 1, true) then
            local all_present = true
            for part in keyword:gmatch("[^%s]+") do
                part = part:gsub("[^a-z0-9%-]", "")
                if part ~= "" and not set[part] then
                    all_present = false
                    break
                end
            end
            if all_present then hits = hits + 1 end
        end
    end
    return hits
end

function ContextScorer.prepare(context_words)
    return words_to_set(context_words)
end

function ContextScorer.scorePrepared(entry, context_set)
    if not entry then return 0 end
    return score_keywords(entry.context_keywords, context_set)
end

function ContextScorer.scoreSense(entry, context_set, alternate)
    if not entry then return 0 end
    if alternate then
        return score_keywords(entry.sense2_context_keywords, context_set)
    end
    return ContextScorer.scorePrepared(entry, context_set)
end

-- Return the gloss/sense that has the strongest explicit context evidence.
-- Ties stay on the primary sense to preserve the old deterministic behavior.
-- A sense2 cannot win without at least one keyword hit.
function ContextScorer.selectSense(entry, context_set)
    if not entry then return nil, 0, "none" end
    local primary_score = ContextScorer.scoreSense(entry, context_set, false)
    local alternate_score = ContextScorer.scoreSense(entry, context_set, true)
    if entry.sense2_en and entry.sense2_en ~= ""
            and alternate_score > primary_score and alternate_score > 0 then
        return {
            short_en = entry.sense2_en,
            short_vi = entry.sense2_vi,
        }, alternate_score, "alternate"
    end
    return {
        short_en = entry.short_en,
        short_vi = entry.short_vi,
    }, primary_score, "primary"
end

function ContextScorer.acceptPrepared(entry, context_set)
    local selected, score, sense_kind = ContextScorer.selectSense(entry, context_set)
    if entry and entry.requires_context == 1 and score == 0 then
        return false, 0, nil, "none"
    end
    return true, score, selected, sense_kind
end

function ContextScorer.score(entry, context_words)
    return ContextScorer.scorePrepared(entry, ContextScorer.prepare(context_words))
end

function ContextScorer.accept(entry, context_words)
    return ContextScorer.acceptPrepared(entry, ContextScorer.prepare(context_words))
end

return ContextScorer
