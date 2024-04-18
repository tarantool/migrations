#!/usr/bin/env tarantool

require('strict').on()

local cartridge = require('cartridge')
local ok, err = cartridge.cfg({
    workdir = 'tmp/db',
    roles = {
        'cartridge.roles.vshard-storage',
        'cartridge.roles.vshard-router',
        'migrator-ee',
    },
    cluster_cookie = 'migrations-test-cluster-cookie',
    roles_reload_allowed = true
}, {
    log_level = 6
})
require('migrator-ee').set_loader(require('migrator-ee.directory-loader').new('test/integration/migrations'))

require('json').cfg{encode_use_tostring = true,}

assert(ok, tostring(err))
