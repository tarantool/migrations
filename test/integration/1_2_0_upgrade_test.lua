local t = require('luatest')
local g = t.group()
local fiber = require('fiber') -- luacheck: ignore

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')

local shared = require('test.helper.integration').shared

local datadir = fio.pathjoin(shared.datadir, '1_2_0_upgrade')

local function get_cluster_config(cluster_datadir, server_command)
    return {
        server_command = server_command,
        datadir = cluster_datadir,
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
    }
end

g.test_upgrade = function()
    -- In this test we start cluster on 1.2.0 version of migrations and then on the same data start
    -- cluster with current version.
    -- We check that after upgrade we can modify config and start migrations.
    -- See related task
    g.cluster_1_2_0 = cartridge_helpers.Cluster:new(get_cluster_config(datadir, shared.server_command_1_2_0))
    g.cluster_1_2_0:start()

    local res_1_2_0 = g.cluster_1_2_0.main_server:http_request('post', '/migrations/up', { json = {} })
    local expected_applied_1_2_0 = {
        ["api-1"] = {"01_first.lua", "02_second.lua"},
        ["storage-1-1"] = {"01_first.lua", "02_second.lua"},
        ["storage-2-1"] = {"01_first.lua", "02_second.lua"},
    }
    t.assert_equals(res_1_2_0.json, { applied = expected_applied_1_2_0 })

    g.cluster_1_2_0:stop()

    g.cluster_current = cartridge_helpers.Cluster:new(get_cluster_config(datadir, shared.server_command))
    g.cluster_current.bootstrapped = true -- we preaviously bootstrapped this cluster
    g.cluster_current:start()

    local cfg = g.cluster_1_2_0.main_server:download_config()
    cfg.some_change_in_confi = {}
    g.cluster_1_2_0.main_server:upload_config(cfg)

    local res_current = g.cluster_1_2_0.main_server:http_request('post', '/migrations/up', { json = {} })
    local expected_applied_current = {
        ["api-1"] = {"03_sharded.lua"},
        ["storage-1-1"] = {"03_sharded.lua"},
        ["storage-2-1"] = {"03_sharded.lua"},
    }
    t.assert_equals(res_current.json, { applied = expected_applied_current })

    g.cluster_current:stop()
    fio.rmtree(datadir)
end