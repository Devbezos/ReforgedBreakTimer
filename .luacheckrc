std = "lua51"
codes = true
max_line_length = false

-- WoW API names (CreateFrame, C_Timer, SOUNDKIT, Settings, ...) are
-- runtime-provided globals, and the addon intentionally exposes its shared
-- state on the `ns` table passed in via `local addonName, ns = ...`. Keep
-- undefined/global-mutation checks out of the baseline while retaining
-- Luacheck's local, control-flow, and hygiene diagnostics.
ignore = {
    "111", -- setting a non-standard global
    "112", -- mutating a non-standard global
    "113", -- accessing an undefined global
}
