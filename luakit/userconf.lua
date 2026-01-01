-- ~/.config/luakit/userconf.lua
local window = require "window"

window.add_signal("init", function (w)
    -- borderless (no titlebar) + fullscreen
    w.win.decorated = false
    w.win.fullscreen = true
end)
