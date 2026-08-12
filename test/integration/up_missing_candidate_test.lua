local t = require('luatest')
local g = t.group('up_missing_leader_candidate')

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper.integration').shared
local utils = require("test.helper.utils")
local datadir = fio.pathjoin(shared.datadir, 'up_missing_leader_candidate')

-- Reproduces the silent-skip bug: when a replicaset has no healthy leader
-- candidate (e.g. its leader is disabled / down / not yet elected during
-- stateful failover), `migrator.up()` used to skip it, report success, and
-- leave that replicaset without migrated spaces — so CRUD later failed with
-- "Space ... doesn't exist". The fix makes `up()` fail loudly instead.

g.before_all(function()
    g.cluster = cartridge_helpers.Cluster:new({
        server_command = shared.server_command,
        datadir = datadir,
        use_vshard = true,
        base_advertise_port = 10600,
        replicasets = {
            {
                alias = 'router',
                uuid = cartridge_helpers.uuid('a'),
                roles = { 'vshard-router', 'migrator' },
                servers = { {
                    alias = 'router',
                    instance_uuid = cartridge_helpers.uuid('a', 1)
                } },
            },
            {
                alias = 'storage-1',
                uuid = cartridge_helpers.uuid('b'),
                roles = { 'vshard-storage', 'migrator' },
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
                roles = { 'vshard-storage', 'migrator' },
                servers = {
                    {
                        alias = 'storage-2-master',
                        instance_uuid = cartridge_helpers.uuid('c', 1),
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

-- Helper: re-enable any servers disabled during a test, so after_each cleanup
-- can talk to a fully healthy cluster.
local function enable_all_servers(cg)
    local main = cg.cluster.main_server
    main:eval([[
        local admin = require('cartridge.admin')
        local topology = require('cartridge.lua-api.get-topology').get_servers()
        local disabled = {}
        for _, s in pairs(topology) do
            if s.disabled then
                table.insert(disabled, s.uuid)
            end
        end
        if #disabled > 0 then
            local _, err = admin.enable_servers(disabled)
            if err ~= nil then error(err.err) end
        end
    ]])
    cg.cluster:wait_until_healthy()
end

g.test_up_fails_when_replicaset_has_no_leader_candidate = function(cg)
    local main = cg.cluster.main_server
    local storage2_master = cg.cluster:server('storage-2-master')

    -- Sanity check: with every replicaset having a healthy leader, migrations
    -- apply on all three replicasets.
    local status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ['router'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-1-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-2-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
    })

    -- Drop storage-2 out of the candidate list by disabling its leader. With
    -- manual failover the configured master is the only leader; disabling it
    -- leaves the replicaset with no healthy leader candidate, exactly as a
    -- freshly added replicaset during a stateful-failover election window.
    local _, err = main:eval([[
        local admin = require('cartridge.admin')
        local ok, err = admin.disable_servers({...})
        if not ok then error(err.err) end
        return true
    ]], { storage2_master.instance_uuid })
    t.assert(_, tostring(err))
    -- Do not wait_until_healthy here: storage-2 is intentionally leaderless,
    -- so the cluster is unhealthy by design until we re-enable the server.

    -- Now up() must fail loudly instead of silently skipping storage-2.
    status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert_not(status, 'up() expected to fail when a replicaset has no leader candidate')
    t.assert_str_contains(tostring(resp), 'healthy leader candidate')
    t.assert_str_contains(tostring(resp), 'replicasets')

    -- Nothing was applied during the failed call: storage-2-master still
    -- reports locally the migrations it got on the first (successful) run.
    -- (We query it directly because, being leaderless, storage-2 is no longer
    -- among the candidates `get_applied` queries.)
    local applied_local = storage2_master:eval(
        "return require('migrator').get_applied_local()")
    t.assert_equals(applied_local,
        { '01_first.lua', '02_second.lua', '03_sharded.lua' })

    -- After the leader is back, up() succeeds again.
    enable_all_servers(cg)
    status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
end
