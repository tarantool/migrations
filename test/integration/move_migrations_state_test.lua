local t = require('luatest')
local g = t.group('move_migrations_state')

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper.integration').shared
local utils = require("test.helper.utils")
local datadir = fio.pathjoin(shared.datadir, 'move_migrations_state')

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
            {
                alias = 'storage-2',
                uuid = cartridge_helpers.uuid('c'),
                roles = { 'vshard-storage' },
                servers = {
                    {
                        alias = 'storage-2-master',
                        instance_uuid = cartridge_helpers.uuid('c', 1),
                        env = {TARANTOOL_HTTP_ENABLED = 'false'},
                    },
                    {
                        alias = 'storage-2-replica',
                        instance_uuid = cartridge_helpers.uuid('c', 2),
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

g.test_move_migrations_state = function(cg)
    local main = cg.cluster.main_server

    -- Pretend first two migrations are already applied on cluster by prev migrator version.
    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {
                applied = { '01_first.lua', '02_second.lua' }
            }
        })
    ]])

    -- `up` call does not work due to non-empty cluster-wide migrations list.
    local status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert_not(status)
    t.assert_str_contains(tostring(resp), 'Cannot perform an upgrade.')

    -- Move migrations.
    status, resp = main:eval("return pcall(require('migrator').move_migrations_state)")
    t.assert(status, tostring(resp))
    t.assert_items_equals(resp, {
        ["router"] = {"01_first.lua", "02_second.lua"},
        ["storage-1-master"] = {"01_first.lua", "02_second.lua"},
        ["storage-2-master"] = {"01_first.lua", "02_second.lua"},
    })

    -- Check migrations are copied.
    for _, server_alias in pairs({'router', 'storage-1-master', 'storage-2-master'}) do
        t.assert(cg.cluster:server(server_alias):eval([[
            return box.space._migrations:get(1)['name'] == '01_first.lua' and
                box.space._migrations:get(2)['name'] == '02_second.lua'
        ]]))
    end
    t.assert(main:eval([[
        return require('cartridge.confapplier').get_readonly('migrations').applied == nil
    ]]))

    -- `up` should perform 03 migration only.
    status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ['router'] = { '03_sharded.lua' },
        ['storage-1-master'] = { '03_sharded.lua' },
        ['storage-2-master'] = { '03_sharded.lua' },
    })
end

g.test_move_migrations_state_http = function(cg)
    local main = cg.cluster.main_server

    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {
                applied = { '01_first.lua', '02_second.lua' }
            }
        })
    ]])

    -- Move migrations.
    local result = main:http_request('post', '/migrations/move_migrations_state', { json = {} })
    local expected_moved = {
        ['router'] = { '01_first.lua', '02_second.lua' },
        ['storage-1-master'] = { '01_first.lua', '02_second.lua' },
        ['storage-2-master'] = { '01_first.lua', '02_second.lua' },
    }
    t.assert_equals(result.json, { migrations_moved = expected_moved })

    -- Check migrations are copied.
    for _, server_alias in pairs({'router', 'storage-1-master', 'storage-2-master'}) do
        t.assert(cg.cluster:server(server_alias):eval([[
            return box.space._migrations:get(1)['name'] == '01_first.lua' and
                box.space._migrations:get(2)['name'] == '02_second.lua'
        ]]))
    end
end

g.test_move_migrations_call_on_replica = function(cg)
    local main = cg.cluster.main_server

    -- Pretend first two migrations are already applied on cluster by prev migrator version.
    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {
                applied = { '01_first.lua', '02_second.lua' }
            }
        })
    ]])

    -- Move migrations.
    local status, resp = cg.cluster:server('storage-1-replica'):eval(
        "return pcall(require('migrator').move_migrations_state)")
    t.assert(status, tostring(resp))
    t.assert_items_equals(resp, {
        ["router"] = {"01_first.lua", "02_second.lua"},
        ["storage-1-master"] = {"01_first.lua", "02_second.lua"},
        ["storage-2-master"] = {"01_first.lua", "02_second.lua"},
    })

    -- Check migrations are copied.
    for _, server_alias in pairs({'router', 'storage-1-master', 'storage-2-master'}) do
        t.assert(cg.cluster:server(server_alias):eval([[
            return box.space._migrations:get(1)['name'] == '01_first.lua' and
                box.space._migrations:get(2)['name'] == '02_second.lua'
        ]]))
    end
    t.assert(main:eval([[
        return require('cartridge.confapplier').get_readonly('migrations').applied == nil
    ]]))
end

g.test_move_empty_migrations_state = function(cg)
    local main = cg.cluster.main_server

    -- Pretend first two migrations are already applied on custer by prev migrator version.
    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {applied = {}},
            options = {storage_timeout = 3.0}
        })
    ]])

    -- Move migrations. No config - no errors.
    local status, resp = main:eval("return pcall(require('migrator').move_migrations_state)")
    t.assert(status, tostring(resp))
    t.assert_items_equals(resp, {})
end

g.test_move_migrations_consistency_check = function(cg)
    local main = cg.cluster.main_server

    local status, resp = main:eval([[
        return pcall(require('cartridge').config_patch_clusterwide,
            {['migrations'] = {applied = {}}})
    ]])
    t.assert(status, tostring(resp))

    -- Apply all migrations.
    status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ['router'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-1-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
        ['storage-2-master'] = { '01_first.lua', '02_second.lua', '03_sharded.lua' },
    })

    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {applied = { '01_first.lua', '02_second.lua', '03_sharded.lua' }},
        })
    ]])

    -- Migrations in config are consistent with local. No error.
    status, resp = main:eval("return pcall(require('migrator').move_migrations_state)")
    t.assert(status, tostring(resp))
    t.assert_items_equals(resp, {
        ['router'] = {},
        ['storage-1-master'] = {},
        ['storage-2-master'] = {},
    })

    -- Make state inconsistent.
    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {applied = { '01_first.lua', '03_sharded.lua' }}
        })
    ]])
    status, resp = main:eval("return pcall(require('migrator').move_migrations_state)")
    t.assert_not(status)
    t.assert_str_contains(tostring(resp), 'Inconsistency between cluster-wide and local applied migrations')

    -- Make sure cluster-wide migrations state is still there.
    t.assert(main:eval([[
        return require('cartridge.confapplier').get_readonly('migrations').applied ~= nil
    ]]))
end

g.test_move_migrations_append_to_existing_local = function(cg)
    local main = cg.cluster.main_server

    for _, server in pairs(cg.cluster.servers) do
        server:eval([[
            require('migrator').set_loader({
                list = function()
                    return {
                        {
                            name = '01.lua',
                            up = function() return true end
                        },
                    }
                end,
                hashes_by_name = function()
                    return {
                        ['01.lua'] = 'hashXXX',
                    }
                end,
            })
        ]])
    end

    local status, resp = main:eval("return pcall(require('migrator').up)")
    t.assert(status, tostring(resp))
    t.assert_equals(resp, {
        ['router'] = { '01.lua' },
        ['storage-1-master'] = { '01.lua' },
        ['storage-2-master'] = { '01.lua' },
    })

    -- Append "applied" migrations to cluster config.
    main:eval([[
        require('cartridge').config_patch_clusterwide({
            migrations = {applied = { '01.lua', '02.lua' }},
        })
    ]])

    for _, server in pairs(cg.cluster.servers) do
        server:eval([[
            require('migrator').set_loader({
                list = function()
                    return {
                        {
                            name = '01.lua',
                            up = function() return true end
                        },
                        {
                            name = '02.lua',
                            up = function() return true end
                        },
                    }
                end,
                hashes_by_name = function()
                    return {
                        ['01.lua'] = 'hashXXX',
                        ['02.lua'] = 'hashYYY',
                    }
                end,
            })
        ]])
    end

    -- Only new missing applied migrations is copied to local storage.
    status, resp = main:eval("return pcall(require('migrator').move_migrations_state)")
    t.assert(status, tostring(require('json').encode(resp)))
    t.assert_items_equals(resp, {
        ['router'] = { '02.lua' },
        ['storage-1-master'] = { '02.lua' },
        ['storage-2-master'] = { '02.lua' },
    })

    t.assert(main:eval([[
        return require('cartridge.confapplier').get_readonly('migrations').applied == nil
    ]]))
end
