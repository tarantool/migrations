local t = require('luatest')
local g = t.group()
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

g.before_each(function()
    for _, server in pairs(g.cluster.servers) do
        server.net_box:eval([[
            require('migrator').set_loader(
                require('migrator.config-loader').new()
            )
        ]])
    end

    utils.set_sections(g, { { filename = "migrations/source/01_test.lua", content = [[
return {
    up = function()
        return true
    end
}
    ]]}})

    require('fiber').sleep(0.5)

    local result = g.cluster.main_server:http_request('post', '/migrations/up', { json = {} })
    t.assert_equals(result.json, {
        applied = {
            ["api-1"] = {"01_test.lua"},
            ["storage-1-1"] = {"01_test.lua"},
            ["storage-2-1"] = {"01_test.lua"},
        }
    })
    local cfg = g.cluster:download_config()
    cfg.migrations = nil
    g.cluster:upload_config(cfg)
end)

local function make_applied_migrations_writable()
    local cfg = g.cluster:download_config()
    cfg.migrations = cfg.migrations or {}
    cfg.migrations.options = {
        is_applied_migrations_writable = true,
    }
    g.cluster:upload_config(cfg)
end

local function make_applied_migrations_unwritable()
    local cfg = g.cluster:download_config()
    cfg.migrations = cfg.migrations or {}
    cfg.migrations.options = {
        is_applied_migrations_writable = false,
    }
    g.cluster:upload_config(cfg)
end

g.after_each(function()
    -- make_applied_migrations_writable()
    utils.cleanup(g)
    make_applied_migrations_unwritable()
end)

g.test_error_apply_config_with_modified_migrations = function(cg)
    t.assert_error_msg_contains("Modifying already applied migrations is not allowed.",
        cg.cluster.main_server.graphql, g.cluster.main_server, { query = [[
        mutation($sections: [ConfigSectionInput!]) {
            cluster {
                config(sections: $sections) {
                    filename
                    content
                }
            }
        }]],
        variables = { sections = {{
            filename = "migrations/source/01_test.lua", content = [[
                return {
                    // some changes
                    up = function()
                        return true
                    end
                }
            ]]
        }} }
    })
end

g.test_ok_apply_config_with_modified_migrations = function(cg)
    make_applied_migrations_writable()
    utils.set_sections(cg, { { filename = "migrations/source/01_test.lua", content = [[
        return {
            // some changes
            up = function()
                return true
            end
        }
    ]]
    }})
end

g.test_error_migrations_up = function(cg)
    -- update hash manually in order to simulate changes
    for _, s_name in pairs({'api-1', 'storage-1-1', 'storage-2-1'}) do
        cg.cluster:server(s_name):exec(function()
            box.space._migrations:update(1, {{'=', 'hash', 'changed'}})
        end)
    end

    -- check migrations up call
    local status, resp = cg.cluster.main_server:exec(function() return pcall(function() require('migrator').up() end) end)
    t.assert_equals(status, false)
    t.assert_str_contains(resp, "Modifying already applied migrations is not allowed.")
end
