local utils = require('migrator-ee.utils')

return {
    up = function()
        if utils.check_roles_enabled({'vshard-router'}) then
            rawset(_G, 'vshard-router-set', true)
        end

        if utils.check_roles_enabled({'vshard-storage'}) then
            rawset(_G, 'vshard-storage-set', true)
        end
        return true
    end
}
