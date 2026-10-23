local Config = require("scripts.config")

-- Science packs are plain items in 2.1 (they were "tool" prototypes before); accept both.
local function tool_exists(name)
  return (data.raw.item and data.raw.item[name] ~= nil) or (data.raw.tool and data.raw.tool[name] ~= nil)
end

-- Knowledge Consolidation: one infinite tech per science tier (see scripts/consolidation.lua).
local Consolidation = require("scripts.consolidation")
local cons_icons = {
  { icon = "__base__/graphics/technology/research-speed.png", icon_size = 256 },
  { icon = "__core__/graphics/icons/technology/constants/constant-recipe-productivity.png", icon_size = 128, shift = { 100, 100 } },
}
for tier, t in ipairs(Consolidation.TIERS) do
  local ok = true
  for _, pack in ipairs(t.packs) do if not tool_exists(pack) then ok = false end end
  for _, pre in ipairs(t.prerequisites) do if not data.raw.technology[pre] then ok = false end end
  if ok then
    local ingredients = {}
    for _, pack in ipairs(t.packs) do ingredients[#ingredients + 1] = { pack, 1 } end
    data:extend({
      {
        type = "technology",
        name = t.name,
        icons = cons_icons,
        localised_name = { "technology-name." .. t.name },
        localised_description = { "technology-description.rd-consolidation", tostring(tier), tostring(#Consolidation.TIERS) },
        effects = { { type = "nothing", effect_description = { "technology-effect.rd-consolidation" } } },
        prerequisites = t.prerequisites,
        unit = {
          count_formula = Config.consolidation_formula(tier),
          ingredients = ingredients,
          time = Config.consolidation_time(),
        },
        max_level = t.max_level,
        upgrade = false,
        ignore_tech_cost_multiplier = true,
        order = "zz-rd-" .. tier,
      },
    })
  end
end

-- Phase 3: the Archive (optional via startup setting)
if settings.startup["rd-enable-archive"].value then
  local tint = { r = 0.55, g = 0.45, b = 0.95, a = 1 }
  local chest = table.deepcopy(data.raw["container"]["steel-chest"])
  chest.name = "rd-archive"
  chest.icons = { { icon = "__base__/graphics/icons/steel-chest.png", icon_size = 64, tint = tint } }
  chest.icon = nil
  chest.minable = { mining_time = 0.3, result = "rd-archive" }
  chest.inventory_size = 24
  chest.max_health = 400
  chest.localised_name = { "entity-name.rd-archive" }
  chest.localised_description = { "entity-description.rd-archive" }
  if chest.picture and chest.picture.layers then
    chest.picture.layers[1].tint = tint
  elseif chest.picture then
    chest.picture.tint = tint
  end
  chest.fast_replaceable_group = nil
  chest.next_upgrade = nil

  data:extend({
    chest,
    {
      type = "item",
      name = "rd-archive",
      icons = chest.icons,
      subgroup = "storage",
      order = "a[items]-d[rd-archive]",
      place_result = "rd-archive",
      stack_size = 20,
    },
    {
      type = "recipe",
      name = "rd-archive",
      enabled = false,
      energy_required = 5,
      ingredients = {
        { type = "item", name = "steel-chest", amount = 1 },
        { type = "item", name = "electronic-circuit", amount = 10 },
      },
      results = { { type = "item", name = "rd-archive", amount = 1 } },
    },
    {
      type = "technology",
      name = "rd-archive",
      icons = { { icon = "__base__/graphics/icons/steel-chest.png", icon_size = 64, tint = tint, scale = 3 } },
      effects = { { type = "unlock-recipe", recipe = "rd-archive" } },
      prerequisites = { "steel-processing", "electronics" },
      unit = {
        count = 50,
        ingredients = { { "automation-science-pack", 1 } },
        time = 15,
      },
      ignore_tech_cost_multiplier = true,
    },
  })
end

-- GUI access: shortcut bar button + hotkey
data:extend({
  {
    type = "custom-input",
    name = "rd-toggle-gui",
    key_sequence = "CONTROL + K",
    consuming = "none",
    action = "lua",
  },
  {
    type = "shortcut",
    name = "rd-toggle-gui",
    action = "lua",
    toggleable = true,
    associated_control_input = "rd-toggle-gui",
    icon = "__base__/graphics/icons/lab.png",
    icon_size = 64,
    small_icon = "__base__/graphics/icons/lab.png",
    small_icon_size = 64,
    order = "r[research-debt]",
  },
})
