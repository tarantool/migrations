local t = require('luatest')
local g = t.group('integration_api')
local fiber = require('fiber') -- luacheck: ignore

local helper = require('test.helper.integration')
local cluster = helper.cluster

g.test_basic = function()
    local main = cluster.main_server
    for _, server in pairs(cluster.servers) do
        t.assert(server.net_box:eval('return box.space.first == nil'))
    end
    main:http_request('post', '/migrations/up', { json = {} })
    for _, server in pairs(cluster.servers) do
        t.assert_not(server.net_box:eval('return box.space.first == nil'))
    end

    local config = main:download_config()
    t.assert_covers(config, {
        migrations = { applied = { "01_first.lua", "02_second.lua" } },
    })
    t.assert_covers(config, {
        schema = {
            spaces = {
                first = {
                    engine = "memtx",
                    format = {
                        { is_nullable = false, name = "key", type = "string" },
                        { is_nullable = true, name = "value", type = "string" },
                    },
                    indexes = {
                        {
                            name = "primary",
                            parts = { { is_nullable = false, path = "key", type = "string" } },
                            type = "TREE",
                            unique = true,
                        },
                        {
                            name = "value",
                            parts = { { is_nullable = true, path = "value", type = "string" } },
                            type = "TREE",
                            unique = false,
                        },
                    },
                    is_local = false,
                    temporary = false,
                },
            },
        },
    })
end
