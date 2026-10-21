-- Infinite technologies (from any mod) must never be affected by the global
-- technology price multiplier. The mod drives that multiplier, so without this
-- every infinite tech would get more expensive as debt accumulates.
local count = 0
for _, tech in pairs(data.raw.technology) do
  if tech.max_level == "infinite" and not tech.ignore_tech_cost_multiplier then
    tech.ignore_tech_cost_multiplier = true
    count = count + 1
  end
end
log("[research-debt] marked " .. count .. " infinite technologies with ignore_tech_cost_multiplier")
