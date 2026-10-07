data:extend({
  {
    type = "bool-setting",
    name = "urq-show-disabled-techs",
    setting_type = "runtime-per-user",
    default_value = false,
  },
  {
    type = "bool-setting",
    name = "urq-show-control-hints",
    setting_type = "runtime-per-user",
    default_value = true,
  },
  {
    type = "string-setting",
    name = "srq-default-goals",
    setting_type = "runtime-per-user",
    default_value = "",
    allow_blank = true,
  },
  {
    type = "string-setting",
    name = "srq-default-blacklist",
    setting_type = "runtime-per-user",
    default_value = "",
    allow_blank = true,
  },
})
