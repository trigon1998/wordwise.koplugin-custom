local ContextScorer = dofile("context_scorer.lua")

local entry = {
    context_keywords = "bond, interest rate",
    requires_context = 1,
}

local words = { "The", "interest", "rate", "rose" }
local prepared = ContextScorer.prepare(words)
local score_from_prepared = ContextScorer.scorePrepared(entry, prepared)
local accepted, confidence = ContextScorer.acceptPrepared(entry, prepared)

if score_from_prepared ~= 1 then
    error("prepared context score mismatch: " .. tostring(score_from_prepared))
end
if not accepted or confidence ~= 1 then
    error("prepared context acceptance mismatch")
end

local rejected, rejected_score = ContextScorer.acceptPrepared(entry, {})
if rejected or rejected_score ~= 0 then
    error("required context must reject an empty prepared set")
end

local sense_entry = {
    short_en = "funds used for production",
    short_vi = "vốn",
    sense2_en = "city holding government",
    sense2_vi = "thủ đô",
    context_keywords = "investment,firm,asset,production",
    sense2_context_keywords = "city,government,nation,state",
}
local primary_sense, primary_score, primary_kind =
    ContextScorer.selectSense(sense_entry, ContextScorer.prepare({ "investment", "firm" }))
if primary_kind ~= "primary" or primary_score ~= 2
        or primary_sense.short_en ~= "funds used for production" then
    error("primary sense selection mismatch")
end
local alternate_sense, alternate_score, alternate_kind =
    ContextScorer.selectSense(sense_entry, ContextScorer.prepare({ "city", "government" }))
if alternate_kind ~= "alternate" or alternate_score ~= 2
        or alternate_sense.short_en ~= "city holding government"
        or alternate_sense.short_vi ~= "thủ đô" then
    error("alternate sense selection mismatch")
end
local fallback_sense, fallback_score, fallback_kind =
    ContextScorer.selectSense(sense_entry, ContextScorer.prepare({ "unrelated" }))
if fallback_kind ~= "primary" or fallback_score ~= 0
        or fallback_sense.short_en ~= "funds used for production" then
    error("context fallback mismatch")
end

print("RC1.4.1 context scorer tests: PASS")
