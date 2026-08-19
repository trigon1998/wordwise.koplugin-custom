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

print("RC1.3.7 context scorer tests: PASS")
