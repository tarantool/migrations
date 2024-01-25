local t = require('luatest')
local g = t.group('check_roles_enabled_integration')
local fiber = require('fiber') -- luacheck: ignore

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')

local shared = require('test.helper.integration').shared

local datadir = fio.pathjoin(shared.datadir, 'basic')

g.cluster = cartridge_helpers.Cluster:new({
    server_command = fio.pathjoin(shared.root, 'test', 'entrypoint', 'check_roles_enabled_init.lua'),
    datadir = datadir,
    use_vshard = true,
    base_advertise_port = 10400,
    base_http_port = 10090,
    replicasets = {
        {
            alias = 'api',
            uuid = cartridge_helpers.uuid('a'),
            roles = { 'vshard-router', 'migrator' },
            servers = { { alias='api-master', instance_uuid = cartridge_helpers.uuid('a', 1) } },
        },
        {
            alias = 'storage-role1-role2',
            uuid = cartridge_helpers.uuid('b'),
            roles = { 'vshard-storage', 'cartridge.roles.role1', 'cartridge.roles.role2', 'migrator' },
            servers = {
                {
                    alias = 'storage-role1-role2-master',
                    instance_uuid = cartridge_helpers.uuid('b', 1),
                    env = {TARANTOOL_HTTP_ENABLED = 'false'},
                },
                {
                    alias = 'storage-role1-role2-replica',
                    instance_uuid = cartridge_helpers.uuid('b', 2),
                    env = {TARANTOOL_HTTP_ENABLED = 'false'},
                },
            },
        },
    },
})

g.before_all(function(cg) cg.cluster:start() end)
g.after_all(function(cg) cg.cluster:stop() end)

g.test_check = function(cg)
    t.assert(cg.cluster:server('api-master'):exec(function() return require('migrator.utils').check_roles_enabled({'vshard-router'}) end))
    t.assert(cg.cluster:server('api-master'):exec(function()
        return require('migrator.utils').check_roles_enabled({'vshard-router', 'migrator'})
    end))
    t.assert(cg.cluster:server('api-master'):exec(function()
        return require('migrator.utils').check_roles_enabled({'vshard-router', 'migrator', 'ddl-manager'})
    end))
    t.assert_not(cg.cluster:server('api-master'):exec(function()
        return require('migrator.utils').check_roles_enabled({'vshard-storage', 'migrator', 'ddl-manager'})
    end))

    t.assert(cg.cluster:server('storage-role1-role2-master'):exec(function()
        return require('migrator.utils').check_roles_enabled({'vshard-storage'})
    end))

    t.assert(cg.cluster:server('storage-role1-role2-master'):exec(function()
        return require('migrator.utils').check_roles_enabled(
            {'vshard-storage', 'migrator', 'ddl-manager', 'cartridge.roles.role1', 'cartridge.roles.role2', 'cartridge.roles.role1-dep'}
        )
    end))

    t.assert_not(cg.cluster:server('storage-role1-role2-master'):exec(function()
        return require('migrator.utils').check_roles_enabled({'vshard-router', 'migrator', 'cartridge.roles.role1-dep'})
    end))

    t.assert(cg.cluster:server('storage-role1-role2-replica'):exec(function()
        return require('migrator.utils').check_roles_enabled({'vshard-storage'})
    end))

    t.assert(cg.cluster:server('storage-role1-role2-replica'):exec(function()
        return require('migrator.utils').check_roles_enabled(
            {'vshard-storage', 'migrator', 'ddl-manager', 'cartridge.roles.role1', 'cartridge.roles.role2', 'cartridge.roles.role1-dep'}
        )
    end))

    t.assert_not(cg.cluster:server('storage-role1-role2-replica'):exec(function()
        return require('migrator.utils').check_roles_enabled(
            {'vshard-router', 'migrator', 'cartridge.roles.role1-dep'}
        )
    end))
end

g.test_with_migrations = function (cg)
    local status, resp = cg.cluster.main_server:exec(function() return pcall(function() require('migrator').up() end) end)
    t.assert_equals(status, true, resp)

    t.assert(cg.cluster:server('api-master'):exec(function()
        return rawget(_G, 'vshard-router-set') or false
    end))
    t.assert_not(cg.cluster:server('api-master'):exec(function()
        return rawget(_G, 'vshard-storage-set') or false
    end))

    t.assert_not(cg.cluster:server('storage-role1-role2-master'):exec(function()
        return rawget(_G, 'vshard-router-set') or false
    end))
    t.assert(cg.cluster:server('storage-role1-role2-master'):exec(function()
        return rawget(_G, 'vshard-storage-set') or false
    end))

    t.assert_not(cg.cluster:server('storage-role1-role2-replica'):exec(function()
        return rawget(_G, 'vshard-router-set') or false
    end))
    t.assert_not(cg.cluster:server('storage-role1-role2-replica'):exec(function()
        return rawget(_G, 'vshard-storage-set') or false
    end))
end
