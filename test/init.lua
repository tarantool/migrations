#!/usr/bin/env tarantool

require('strict').on()

local root = os.getenv('LUATEST_LUACOV_ROOT')
package.setsearchroot(root)

local cartridge = require('cartridge')
local ok, err = cartridge.cfg({
    workdir = 'tmp/db',
    roles = {
        'cartridge.roles.vshard-storage',
        'cartridge.roles.vshard-router',
        'migrator',
    },
    cluster_cookie = 'migrations-test-cluster-cookie',
})
require('migrator').set_loader(require('migrator.directory-loader').new('test/integration/migrations'))

require('json').cfg{encode_use_tostring = true,}

assert(ok, tostring(err))
