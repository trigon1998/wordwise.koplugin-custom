local BookClassifier = {}

local ECON = {
    "marketing", "consumer", "business", "management", "economics", "economic",
    "finance", "accounting", "investment", "brand", "market", "kotler", "solomon",
    "banking", "trade", "entrepreneur", "strategy", "macroeconomic", "microeconomic",
}
local PHYS = {
    "physics", "quantum", "relativity", "cosmology", "astronomy", "universe", "hawking",
    "particle", "spacetime", "black hole", "thermodynamics", "mechanics", "electromagnetic",
}
local VI_BYTES = {
    "ă", "â", "đ", "ê", "ô", "ơ", "ư", "á", "à", "ả", "ã", "ạ", "é", "è",
    "ẻ", "ẽ", "ẹ", "í", "ì", "ỉ", "ĩ", "ị", "ó", "ò", "ỏ", "õ", "ọ", "ú",
    "ù", "ủ", "ũ", "ụ", "ý", "ỳ", "ỷ", "ỹ", "ỵ",
}

local function score(text, list)
    local n = 0
    text = (text or ""):lower()
    for _, keyword in ipairs(list) do
        if text:find(keyword, 1, true) then n = n + 1 end
    end
    return n
end

function BookClassifier.suggest(title_and_path, sample)
    local text = (title_and_path or "") .. " " .. (sample or "")
    local econ, phys = score(text, ECON), score(text, PHYS)
    if phys > econ and phys >= 1 then return "physics", phys end
    if econ > phys and econ >= 1 then return "economics", econ end
    return "general", math.max(econ, phys)
end

function BookClassifier.isVietnameseDominant(sample)
    if not sample or sample == "" then return false end
    local marks = 0
    local lowered = sample:lower()
    for _, ch in ipairs(VI_BYTES) do
        local _, count = lowered:gsub(ch, "")
        marks = marks + count
    end
    local ascii_words = 0
    for _ in lowered:gmatch("%f[%a][a-z][a-z]+%f[^%a]") do ascii_words = ascii_words + 1 end
    return marks >= 12 and marks > ascii_words / 8
end

return BookClassifier
