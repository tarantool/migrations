local t = require('luatest')
local g = t.group('dangerous_operations')
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
                { instance_uuid = cartridge_helpers.uuid('b', 2), },
            },
        },
    },
})

g.before_all(function() g.cluster:start() end)
g.after_all(function() g.cluster:stop() end)
g.after_each(function() utils.cleanup(g) end)

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

g.test_error_in_migrations = function()
    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval([[
                require('migrator').set_loader(
                    require('migrator.config-loader').new()
                )
            ]])
    end

    utils.set_sections(g, { { filename = "migrations/source/101_error.lua", content = [[
        return {
            up = function()
                error('Oops')
            end
        }
    ]] } })

    local status, resp = g.cluster.main_server:eval("return pcall(function() require('migrator').up() end)")
    t.assert_equals(status, false)
    t.assert_str_contains(tostring(resp), 'Oops')
    t.assert_str_contains(tostring(resp), 'Errors happened during migrations')

    utils.assert_cluster_has_migrator_issue{
        main_server = g.cluster.main_server,
        server_with_issue = g.cluster.main_server,
        level = 'warning',
        content_fragments = {
            'Errors happened during migrations',
            'Oops',
        },
    }
end

g.test_inconsistent_migrations = function()
    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval([[
                require('migrator').set_loader({
                    list = function() return {} end
                })
            ]])
    end
    g.cluster.main_server.net_box:eval([[
                require('migrator').set_loader({
                    list = function(_)
                        return {
                            {
                                name = '102_local',
                                up = function() return true end
                            },
                        }
                    end
                })
            ]])

    local status, resp = g.cluster.main_server:eval("return pcall(function() require('migrator').up() end)")
    t.assert_equals(status, false)
    t.assert_str_contains(tostring(resp), 'Inconsistent migrations in cluster: '
    .. 'expected: [\"102_local\"],')

    utils.assert_cluster_has_migrator_issue{
        main_server = g.cluster.main_server,
        server_with_issue = g.cluster.main_server,
        level = 'warning',
        content_fragments = {
            'Inconsistent migrations in cluster: expected: [\"102_local\"],',
        },
    }
end

g.test_reload = function()
    for _, server in pairs(g.cluster.servers) do
        local e_get_routes_cnt = [[
            local httpd = require('cartridge').service_get('httpd')
            return table.maxn(httpd.routes)
        ]]
        local routes_count = server.net_box:eval(e_get_routes_cnt)
        local ok, err = server.net_box:eval([[
            return require("cartridge.roles").reload()
        ]])
       t.assert_equals({ ok, err }, { true, nil })
       t.assert_equals(server.net_box:eval(e_get_routes_cnt), routes_count)
    end
end

-- https://github.com/tarantool/migrations/issues/56
g.test_up_on_replica = function()
    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval([[
                require('migrator').set_loader(
                    require('migrator.config-loader').new()
                )
            ]])
    end

    -- create some space
    g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })
    utils.set_sections(g, { { filename = "migrations/source/100_create_space.lua", content = [[
        return {
            up = function()
                local f = box.schema.create_space('somespace', {
                    format = {
                        { name = 'key', type = 'string' },
                        { name = 'value', type = 'string', is_nullable = true }
                    },
                    if_not_exists = true,
                })
                f:create_index('primary', {
                    parts = { 'key' },
                    if_not_exists = true,
                })
            end
        }
    ]] } })
    g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })

    fiber.sleep(0.5)

    -- inject schema replication delay
    g.cluster:server('storage-1-2').net_box:eval([[
        box.space._space:before_replace(function(old, new) os.execute('sleep 0.5'); return new end)
    ]])

    -- change space format to make ddl schema incompatible
    utils.set_sections(g, { { filename = "migrations/source/101_alter_space.lua", content = [[
        return {
            up = function()
                box.space.somespace:format({
                        { name = 'key', type = 'string' },
                        { name = 'value', type = 'string', is_nullable = true },
                        { name = 'secondvalue', type = 'string', is_nullable = true }
                    })
            end
        }
    ]] } })
    g.cluster:server('storage-1-2'):http_request('post', '/migrations/up', { json = {} })
end

g.test_up_clusterwide_applied_migrations_exist = function(cg)
    local main = cg.cluster.main_server
    -- Simulate previous version configuration.
    local _, err = main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {
                applied = { '001.lua', '002.lua' }
            }
        })
    ]])
    t.assert_not(err)

    local status, resp = main:eval([[ return pcall(require('migrator').up) ]])
    t.assert_not(status)
    t.assert_str_contains(tostring(resp), 'A list of applied migrations is found in cluster config')

    utils.assert_cluster_has_migrator_issue{
        main_server = g.cluster.main_server,
        server_with_issue = g.cluster.main_server,
        level = 'warning',
        content_fragments = {
            'A list of applied migrations is found in cluster config',
        },
    }
end

g.test_inconsistent_migration_cartridge_issue_cleaned_after_fix = function()
    local no_migrations_eval = [[
        require('migrator').set_loader({
            list = function() return {} end
        })
    ]]
    local one_migration_eval = [[
        require('migrator').set_loader({
            list = function(_)
                return {
                    {
                        name = '102_local',
                        up = function() return true end
                    },
                }
            end
        })
    ]]

    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval(no_migrations_eval)
    end
    g.cluster.main_server.net_box:eval(one_migration_eval)

    local status, resp = g.cluster.main_server:eval("return pcall(require('migrator').up)")
    t.assert_equals(status, false)
    t.assert_str_contains(
        tostring(resp),
        'Inconsistent migrations in cluster: expected: [\"102_local\"],'
    )

    utils.assert_cluster_has_migrator_issue{
        main_server = g.cluster.main_server,
        server_with_issue = g.cluster.main_server,
        level = 'warning',
        content_fragments = {
            'Inconsistent migrations in cluster: expected: [\"102_local\"],',
        },
    }

    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval(one_migration_eval)
    end
    status, resp = g.cluster.main_server:eval("return pcall(require('migrator').up)")
    t.assert_equals(status, true, resp)

    utils.assert_cluster_has_no_migrator_issues{main_server = g.cluster.main_server}
end

g.after_each(function()
    g.cluster:server('storage-1-2').net_box:eval([[
        local f = box.space._space:before_replace()
         box.space._space:before_replace(nil, f[1])
    ]])
end)
