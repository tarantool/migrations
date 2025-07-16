local t = require("luatest")
local g = t.group()

g.after_each(function()
    if box.space._migrations ~= nil then
        box.space._migrations:drop()
    end
end)

g.test_apply_config_order = function()
    box.ctl.on_schema_init(function()
        box.space._space:on_replace(function(_, sp)
            if sp.name == '_migrations' then

                require('fiber').sleep(3)
            end
        end)
    end)
    local migrator = require('migrator')
    package.setsearchroot("test/unit")
    t.assert(pcall(migrator.validate_config,{}, {}))
    t.assert(pcall(migrator.init))
    t.assert(pcall(migrator.validate_config,{}, {}))
    t.assert(pcall(migrator.apply_config,{is_master = true}, {}))
    package.setsearchroot(box.NULL)
end
