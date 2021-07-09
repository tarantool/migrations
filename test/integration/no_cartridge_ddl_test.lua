local t = require('luatest')

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper')
local utils = require("test.helper.utils")

local g = t.group('no_cartridge_ddl')

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
    g.cluster:start()
    for _, server in ipairs(g.cluster.servers) do
        server.net_box:eval("require('migrator').set_use_cartridge_ddl(false)")
    end
end)
g.after_all(function() g.cluster:stop() end)

local cases = {
    with_config_loader = function()
        for _, server in pairs(g.cluster.servers) do
            server.net_box:eval([[
                require('migrator').set_loader(
                    require('migrator.config-loader').new()
                )
            ]])
        end

        local files = {"01_first.lua", "02_second.lua", "03_sharded.lua"}
        for _, v in ipairs(files) do
            local file = fio.open('test/integration/migrations/' .. v)
            local content = file:read()
            utils.set_sections(g, {{filename="migrations/source/"..v, content=content}})
            file:close()
        end
    end,
    with_directory_loader = function()
        for _, server in pairs(g.cluster.servers) do
            server.net_box:eval([[
                require('migrator').set_loader(
                    require('migrator.directory-loader').new('test/integration/migrations')
                )
            ]])
        end
    end
}

for k, configure_func in pairs(cases) do
    g['test_no_cartridge_ddl_' .. k] = function()
        utils.cleanup(g)
        configure_func()

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
end
