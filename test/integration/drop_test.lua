local t = require('luatest')
local g = t.group('dangerous_ddl')
local fiber = require('fiber') -- luacheck: ignore

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')

local shared = require('test.helper.integration').shared
local utils = require("test.helper.utils")

local datadir = fio.pathjoin(shared.datadir, 'basic')

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

g.before_all(function() g.cluster:start() end)
g.after_all(function() g.cluster:stop() end)

g.test_drop = function()
    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval([[
                require('migrator').set_loader(
                    require('migrator.config-loader').new()
                )
            ]])
    end

    -- create spaces and indexes, set schema
    local files = { "01_first.lua", "02_second.lua", "03_sharded.lua" }
    for _, v in ipairs(files) do
        local file = fio.open('test/integration/migrations/' .. v)
        local content = file:read()
        utils.set_sections(g, { { filename = "migrations/source/" .. v, content = content } })
        file:close()
    end
    g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })

    -- drop an existing index separately, check that new schema is applied successfully
    utils.set_sections(g, { { filename = "migrations/source/04_drop_index.lua", content = [[
        return {
            up = function()
                box.space.first.index.value:drop()
            end
        }
    ]] } })

    g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })
    for _, server in pairs(g.cluster.servers) do
        t.assert(server.net_box:eval('return box.space.first.index.value == nil'))
    end

    utils.set_sections(g, { { filename = "migrations/source/05_drop_space.lua", content = [[
        return {
            up = function()
                box.space.first:drop()
            end
        }
    ]] } })

    -- drop a space, check that new schema is applied successfully
    g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })
    for _, server in pairs(g.cluster.servers) do
        t.assert(server.net_box:eval('return box.space.first == nil'))
    end

    utils.set_sections(g, { { filename = "migrations/source/06_change_format.lua", content = [[
        return {
            up = function()
                box.space.sharded:format({
                    { name = 'key', type = 'string' },
                    { name = 'bucket_id', type = 'unsigned' },
                    { name = 'value', type = 'any', is_nullable = true },
                    { name = 'external_id', type = 'string', is_nullable = true }
                })
            end
        }
    ]] } })

    -- change space format, check that new schema is applied successfully
    g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })
    for _, server in pairs(g.cluster.servers) do
        t.assert_equals(server.net_box:eval('return box.space.sharded:format()')[4], { name = 'external_id', type = 'string', is_nullable = true })
    end
end
