local ContextScorer = {}

local function words_to_set(words)
    local set = {}
    for _, word in ipairs(words or {}) do
        local key = word:lower():gsub("[^a-z0-9%-]", "")
        if key ~= "" then set[key] = true end
    end
    return set
end

function ContextScorer.score(entry, context_words)
    if not entry then return 0 end
    local keywords = entry.context_keywords
    if not keywords or keywords == "" then return entry.requires_context == 1 and 0 or 1 end
    local set = words_to_set(context_words)
    local hits = 0
    for keyword in keywords:gmatch("[^,]+") do
        keyword = keyword:lower():gsub("^%s+", ""):gsub("%s+$", "")
        if set[keyword] then
            hits = hits + 1
        elseif keyword:find(" ", 1, true) then
            local all_present = true
            for part in keyword:gmatch("[^%s]+") do
                part = part:gsub("[^a-z0-9%-]", "")
                if part ~= "" and not set[part] then all_present = false break end
            end
            if all_present then hits = hits + 1 end
        end
    end
    return hits
end

function ContextScorer.accept(entry, context_words)
    local score = ContextScorer.score(entry, context_words)
    if entry.requires_context == 1 and score == 0 then return false, 0 end
    return true, score
end

return ContextScorer
