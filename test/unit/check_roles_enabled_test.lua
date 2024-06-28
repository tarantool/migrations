local t = require("luatest")
local g = t.group("check_roles_enabled_unit")

g.before_all(function(cg)
    cg._orig_confapplier = package.loaded["cartridge.confapplier"]
end)

g.after_all(function(cg)
    package.loaded["cartridge.confapplier"] = cg._orig_confapplier
end)

g.test_check = function()
    package.loaded["cartridge.confapplier"] = {
        get_readonly = function()
            return {
                replicasets = {
                    [box.info.cluster.uuid] = {
                        roles = {
                            ['space-explorer'] = true,
                            ['vshard-router'] = true,
                            ['crud-router'] = true,
                            ['my_super_role'] = true,
                        }
                    }
                }
            }
        end
    }

    local utils = require('migrator.utils')

    t.assert(utils.check_roles_enabled({'crud-router', 'my_super_role'}))
    t.assert(utils.check_roles_enabled({'space-explorer', 'vshard-router', 'crud-router', 'my_super_role'}))
    t.assert(utils.check_roles_enabled({}))
    t.assert(utils.check_roles_enabled({'my_super_role'}))
    t.assert_not(utils.check_roles_enabled({'crud-storage', 'my_super_role'}))
    t.assert_not(utils.check_roles_enabled({'crud-storage'}))
    t.assert_not(utils.check_roles_enabled({'crud-storage', 'expirationd'}))
end
