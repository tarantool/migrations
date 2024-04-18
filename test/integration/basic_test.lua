local t = require('luatest')
local g = t.group('integration_api')
local fiber = require('fiber') -- luacheck: ignore

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')

local shared = require('test.helper.integration').shared
local utils = require("test.helper.utils")

local datadir = fio.pathjoin(shared.datadir, 'basic')

g.before_all(function()
    g.cluster = cartridge_helpers.Cluster:new({
        server_command = shared.server_command,
        datadir = datadir,
        use_vshard = true,
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
                    { instance_uuid = cartridge_helpers.uuid('b', 1), env = {TARANTOOL_HTTP_ENABLED = 'false'} },
                    { instance_uuid = cartridge_helpers.uuid('b', 2), env = {TARANTOOL_HTTP_ENABLED = 'false'} },
                },
            },
            {
                alias = 'storage-2',
                uuid = cartridge_helpers.uuid('c'),
                roles = { 'vshard-storage' },
                servers = {
                    { instance_uuid = cartridge_helpers.uuid('c', 1), env = {TARANTOOL_HTTP_ENABLED = 'false'} },
                    { instance_uuid = cartridge_helpers.uuid('c', 2), env = {TARANTOOL_HTTP_ENABLED = 'false'} },
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

local cases = {
    with_config_loader = function()
        for _, server in pairs(g.cluster.servers) do
            server.net_box:eval([[
                require('migrator-ee').set_loader(
                    require('migrator-ee.config-loader').new()
                )
            ]])
        end

        local files = { "01_first.lua", "02_second.lua", "03_sharded.lua" }
        for _, v in ipairs(files) do
            local file = fio.open('test/integration/migrations/' .. v)
            local content = file:read()
            utils.set_sections(g, { { filename = "migrations/source/" .. v, content = content } })
            file:close()
        end
    end,
    with_directory_loader = function()
        for _, server in pairs(g.cluster.servers) do
            server.net_box:eval([[
                require('migrator-ee').set_loader(
                    require('migrator-ee.directory-loader').new('test/integration/migrations')
                )
            ]])
        end
    end
}

for k, configure_func in pairs(cases) do
    g['test_basic_' .. k] = function()
        configure_func()

        for _, server in pairs(g.cluster.servers) do
            t.assert(server.net_box:eval('return box.space.first == nil'), server.alias)
        end

        -- gh-26 - check that httpd is disabled on some nodes
        t.assert_covers(
            g.cluster:server('storage-2-2'):http_request('get', '/', {raise = false}),
            {status = 595, reason = "Couldn't connect to server"}
        )

        local main = g.cluster.main_server
        local result = main:http_request('post', '/migrations/up', { json = {} })
        for _, server in pairs(g.cluster.servers) do
            -- spaces may be created with a slight delay on replicas
            g.cluster:retrying({ timeout = 5 }, function()
                t.assert_not(server.net_box:eval('return box.space.first == nil'), server.alias)
            end)
        end

        local expected_applied = {
            ["api-1"] = {"01_first.lua", "02_second.lua", "03_sharded.lua"},
            ["storage-1-1"] = {"01_first.lua", "02_second.lua", "03_sharded.lua"},
            ["storage-2-1"] = {"01_first.lua", "02_second.lua", "03_sharded.lua"},
        }
        t.assert_equals(result.json, { applied = expected_applied })

        local config = main:download_config()

        local expected_schema = {
            schema = {
                spaces = {
                    _migrations = {
                        engine = "memtx",
                        format = {
                            {is_nullable = false, name = "id", type = "unsigned"},
                            {is_nullable = false, name = "name", type = "string"}
                        },
                        indexes = {
                            {
                                name = "primary",
                                parts = {{is_nullable = false, path = "id", type = "unsigned"}},
                                sequence = "_migrations_id_seq",
                                type = "TREE",
                                unique = true,
                            },
                        },
                        is_local = false,
                        temporary = false,
                    },
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
                    sharded = {
                        engine = "memtx",
                        format = {
                            { is_nullable = false, name = "key", type = "string" },
                            { is_nullable = false, name = "bucket_id", type = "unsigned" },
                            { is_nullable = true, name = "value", type = "any" },
                        },
                        indexes = {
                            {
                                name = "primary",
                                parts = { { is_nullable = false, path = "key", type = "string" } },
                                type = "TREE",
                                unique = true,
                            },
                            {
                                name = "bucket_id",
                                parts = { { is_nullable = false, path = "bucket_id", type = "unsigned" } },
                                type = "TREE",
                                unique = false,
                            },
                        },
                        is_local = false,
                        sharding_key = { "key" },
                        temporary = false,
                    },
                },
                sequences = {
                    _migrations_id_seq = {
                        cache = 0,
                        cycle = false,
                        max = 9223372036854775807ULL,
                        min = 1,
                        start = 1,
                        step = 1,
                    },
                },
            },
        }

        expected_schema = utils.downgrade_ddl_schema_if_required(expected_schema)
        t.assert_covers(config, expected_schema)

        result = main:http_request('post', '/migrations/up', { json = {} })
        t.assert_equals(result.json, { applied = {} })
    end
end

g.test_gh_66_configurable_timeout = function(cg)
    local main = g.cluster.main_server

    main:eval([[
        require('cartridge').config_patch_clusterwide({['migrations-ee'] = {applied = {}, options = {storage_timeout = 0.1}}})
    ]])

    for _, server in pairs(cg.cluster.servers) do
        server.net_box:eval([[
            require('migrator-ee').set_loader(
                require('migrator-ee.directory-loader').new('test/integration/migrations-gh-66')
            )
        ]])
    end

    local status, resp = g.cluster.main_server:eval("return pcall(function() require('migrator-ee').up() end)")
    t.assert_equals(status, false)
    t.assert_str_contains(tostring(resp), 'Errors happened during migrations')

    -- Depending on Tarantool version, error message may differ.
    local status_v1, err_v1 = pcall(function()
        t.assert_str_contains(tostring(resp), 'timed out')
    end)
    local status_v2, err_v2 = pcall(function()
        t.assert_str_contains(tostring(resp), 'Timeout exceeded')
    end)
    t.assert(status_v1 or status_v2, ("Got errors: %s, %s"):format(err_v1 and err_v1.message, err_v2 and err_v2.message))
end
