#!/usr/bin/env tarantool

require('strict').on()

package.preload['cartridge.roles.role1-dep'] = function()
    return {
        role_name = 'cartridge.roles.role1-dep',
    }
end

package.preload['cartridge.roles.role1'] = function()
    return {
        role_name = 'cartridge.roles.role1',
        dependencies = {'cartridge.roles.role1-dep'},
    }
end

package.preload['cartridge.roles.role2'] = function()
    return {
        role_name = 'cartridge.roles.role2',
    }
end

local cartridge = require('cartridge')
local ok, err = cartridge.cfg({
    workdir = 'tmp/db',
    roles = {
        'cartridge.roles.role1-dep',
        'cartridge.roles.role1',
        'cartridge.roles.role2',
        'cartridge.roles.vshard-storage',
        'cartridge.roles.vshard-router',
        'migrator-ee',
    },
    cluster_cookie = 'secret-cluster-cookie',
}, {
    log_level = 5
})

require('migrator-ee').set_loader(require('migrator-ee.directory-loader').new('test/integration/migrations_check_roles_enabled'))

assert(ok, tostring(err))
