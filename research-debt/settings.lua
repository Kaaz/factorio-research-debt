data:extend({
  -- Startup
  {
    type = "string-setting", name = "rd-preset", setting_type = "startup",
    default_value = "standard", allowed_values = { "relaxed", "standard", "hardcore", "custom" }, order = "a-0",
  },
  {
    type = "string-setting", name = "rd-growth-mode", setting_type = "startup",
    default_value = "linear", allowed_values = {"linear", "exponential"}, order = "a-a",
  },
  {
    type = "double-setting", name = "rd-step", setting_type = "startup",
    default_value = 0.1, minimum_value = 0.0, maximum_value = 10.0, order = "a-b",
  },
  {
    type = "bool-setting", name = "rd-tier-scaling", setting_type = "startup",
    default_value = true, order = "a-b2",
  },
  {
    type = "bool-setting", name = "rd-count-trigger-techs", setting_type = "startup",
    default_value = false, order = "a-c",
  },
  {
    type = "bool-setting", name = "rd-enable-archive", setting_type = "startup",
    default_value = true, order = "a-d",
  },
  {
    type = "bool-setting", name = "rd-enable-trades", setting_type = "startup",
    default_value = true, order = "a-f",
  },
  {
    type = "double-setting", name = "rd-consolidation-value", setting_type = "startup",
    default_value = 0.25, minimum_value = 0.0, maximum_value = 100.0, order = "a-e",
  },
  -- Runtime global
  {
    type = "double-setting", name = "rd-max-multiplier", setting_type = "runtime-global",
    default_value = 50, minimum_value = 0.001, maximum_value = 100000, order = "b-a",
  },
  {
    type = "double-setting", name = "rd-min-multiplier", setting_type = "runtime-global",
    default_value = 1.0, minimum_value = 0.001, maximum_value = 1000, order = "b-b",
  },
  {
    type = "int-setting", name = "rd-request-interval", setting_type = "runtime-global",
    default_value = 15, minimum_value = 0, maximum_value = 600, order = "b-b3",
  },
  {
    type = "double-setting", name = "rd-debt-free-bonus", setting_type = "runtime-global",
    default_value = 0.2, minimum_value = 0.0, maximum_value = 5.0, order = "b-b2",
  },
  {
    type = "double-setting", name = "rd-penalty-threshold", setting_type = "runtime-global",
    default_value = 3.0, minimum_value = 0.0, maximum_value = 100.0, order = "b-b4",
  },
  {
    type = "double-setting", name = "rd-penalty", setting_type = "runtime-global",
    default_value = 0.1, minimum_value = 0.0, maximum_value = 0.9, order = "b-b5",
  },
  {
    type = "bool-setting", name = "rd-chat-notifications", setting_type = "runtime-global",
    default_value = true, order = "b-c",
  },
  -- Runtime per user
  {
    type = "bool-setting", name = "rd-show-hud", setting_type = "runtime-per-user",
    default_value = false, order = "c-a",
  },
})
