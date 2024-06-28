local t = require('luatest')
local g = t.group('get_migrations_state')

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper.integration').shared
local utils = require("test.helper.utils")
local datadir = fio.pathjoin(shared.datadir, 'get_migrations_state')

g.before_all(function()
    g.cluster = cartridge_helpers.Cluster:new({
        server_command = shared.server_command,
        datadir = datadir,
        use_vshard = true,
        replicasets = {
            {
                alias = 'router',
                uuid = cartridge_helpers.uuid('a'),
                roles = { 'vshard-router' },
                servers = { {
                    alias = 'router',
                    instance_uuid = cartridge_helpers.uuid('a', 1)
                } },
            },
            {
                alias = 'storage-1',
                uuid = cartridge_helpers.uuid('b'),
                roles = { 'vshard-storage' },
                servers = {
                    {
                        alias = 'storage-1-master',
                        instance_uuid = cartridge_helpers.uuid('b', 1),
                        env = {TARANTOOL_HTTP_ENABLED = 'false'},
                    },
                    {
                        alias = 'storage-1-replica',
                        instance_uuid = cartridge_helpers.uuid('b', 2),
                        env = {TARANTOOL_HTTP_ENABLED = 'false'},
                    },
                },
            },
            {
                alias = 'storage-2',
                uuid = cartridge_helpers.uuid('c'),
                roles = { 'vshard-storage' },
                servers = {
                    {
                        alias = 'storage-2-master',
                        instance_uuid = cartridge_helpers.uuid('c', 1),
                        env = {TARANTOOL_HTTP_ENABLED = 'false'},
                    },
                    {
                        alias = 'storage-2-replica',
                        instance_uuid = cartridge_helpers.uuid('c', 2),
                        env = {TARANTOOL_HTTP_ENABLED = 'false'},
                    },
                },
            },
        },
    })

    g.cluster:start()
end)

g.after_all(function()
    g.cluster:stop()
    fio.rmtree(g.cluster.datadir)
end)

g.after_each(function() utils.cleanup(g) end)

g.test_get_migrations_state = function(cg)
    local main = cg.cluster.main_server

    local status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ['router'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-1-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-2-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
    })

    status, resp = main:eval("return pcall(require('migrator').get_applied)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ['router'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-1-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-2-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
    })

    -- Check the same result is returned by http.
    local result = main:http_request('get', '/migrations/applied')
    local expected_applied = {
        ['router'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-1-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-2-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
    }
    t.assert_equals(result.json, { applied = expected_applied })
end
