local t = require('luatest')
local g = t.group('join_new_instance')
local fiber = require('fiber') -- luacheck: ignore

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper.integration').shared
local datadir = fio.pathjoin(shared.datadir, 'join_new_server')
local utils = require("test.helper.utils")



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
        },
    })

    g.new_server = cartridge_helpers.Server:new({
        alias = 'storage-2-master',
        command = g.cluster.server_command,
        replicaset_uuid = cartridge_helpers.uuid('c'),
        instance_uuid = cartridge_helpers.uuid('c', 1),
        cluster_cookie = g.cluster.cookie,
        workdir = datadir,
        advertise_port = 10204,
        http_port = 8084,
    })

    g.cluster:start()
    g.new_server:start()
end)

g.after_all(function()
    g.cluster:stop()
    g.new_server:stop()
    fio.rmtree(g.cluster.datadir)
    fio.rmtree(g.new_server.workdir)
end)

g.after_each(function() utils.cleanup(g) end)

g.test_gh_65_migrations_in_new_replicaset = function(cg)
    local main = cg.cluster.main_server

    main:eval([[
        require('cartridge').config_patch_clusterwide({['migrations'] = {options = {storage_timeout = 3.0}}})
    ]])

    local set_loader = [[
        require('migrator').set_loader(
            require('migrator.directory-loader').new('test/integration/migrations-gh-65')
        )
    ]]

    for _, server in pairs(cg.cluster.servers) do
        server.net_box:eval(set_loader)
    end

    local status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ["router"] = {"001_create_func.lua"},
        ["storage-1-master"] = {"001_create_func.lua"},
    })

    t.assert(cg.cluster:server('router'):eval([[ return box.func.sum ~= nil ]]))
    t.assert(cg.cluster:server('storage-1-master'):eval([[ return box.func.sum ~= nil ]]))
    t.assert(cg.cluster:server('storage-1-replica'):eval([[ return box.func.sum ~= nil ]]))

    cg.new_server:eval(set_loader)
    cg.new_server:join_cluster(main)
    cg.cluster:wait_until_healthy()

    -- Wait until new member really become healthy.
    cg.cluster:retrying({ timeout = 5 }, function()
        t.assert(main:eval([[
            local member = require('membership').get_member('localhost:10204')
            return member and member.payload.state_prev == 'ConfiguringRoles' or
                member.payload.state_prev == 'RolesConfigured'
        ]]))
    end)

    status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ["storage-2-master"] = {"001_create_func.lua"},
    })
    t.assert(cg.new_server:eval([[ return box.func.sum ~= nil ]]))
end
