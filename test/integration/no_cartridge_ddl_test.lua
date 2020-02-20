local t = require('luatest')

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper')

local g = t.group('no_cartridge_ddl')

local helper = { shared = shared }

local datadir = fio.pathjoin(shared.datadir, 'no_ddl')

g.cluster = cartridge_helpers.Cluster:new({
    server_command = shared.server_command,
    datadir = datadir,
    use_vshard = true,
    base_advertise_port = 13400,
    base_http_port = 8090,
    replicasets = {
        {
            alias = 'api',
            uuid = cartridge_helpers.uuid('a'),
            roles = { 'vshard-router' },
            servers = { { instance_uuid = cartridge_helpers.uuid('a', 1) } },
        },
        {
            alias = 'storage-1',
            uuid = cartridge_helpers.uuid('b'),
            roles = { 'vshard-storage' },
            servers = {
                { instance_uuid = cartridge_helpers.uuid('b', 1), },
            },
        },
    },
})

g.before_all(function()
    for _, server in ipairs(g.cluster.servers) do
        server.env.TARANTOOL_LOG_LEVEL = 6
    end
    g.cluster:start()
    for _, server in ipairs(g.cluster.servers) do
        server.net_box:eval("require('migrator').set_use_cartridge_ddl(false)")
    end
end)
g.after_all(function() g.cluster:stop() end)

g.test_no_cartridge_ddl = function()
    local main = g.cluster.main_server
    for _, server in pairs(g.cluster.servers) do
        t.assert(server.net_box:eval('return box.space.first == nil'))
    end
    main:http_request('post', '/migrations/up', { json = {} })
    for _, server in pairs(g.cluster.servers) do
        t.assert_not(server.net_box:eval('return box.space.first == nil'))
    end
    local config = main:download_config()
    t.assert_not(config.schema)
end


return helper
