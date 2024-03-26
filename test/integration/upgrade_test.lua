local t = require('luatest')

local fio = require('fio')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper.integration').shared
local utils = require("test.helper.utils")

local g = t.group('upgrade')

local datadir = fio.pathjoin(shared.datadir, 'upgrade')

g.before_all(function()
    g.cluster = cartridge_helpers.Cluster:new({
        server_command = shared.server_command,
        datadir = datadir,
        use_vshard = false,
        base_advertise_port = 13400,
        base_http_port = 8090,
        replicasets = {
            {
                alias = 'storage-1',
                uuid = cartridge_helpers.uuid('a'),
                roles = { 'migrator' },
                servers = { { instance_uuid = cartridge_helpers.uuid('a', 1) } },
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

g.test_upgrade_basic = function(cg)
    local main = cg.cluster.main_server
    main:eval([[
        require('migrator').set_loader(
            require('migrator.config-loader').new())
    ]])
    utils.set_sections(g, {
        {
            filename = "migrations/source/01_script.lua",
            content = [[
                return {
                    up = function()
                        box.schema.create_space('test', {
                            format = {{'id', type='unsigned'}},
                        })
                        box.space.test:create_index('p')
                    end
                }
            ]]
        },
        {
            filename = "migrations/source/02_script.lua",
            content = [[
                return {
                    up = function()
                        box.space.test:insert{1}
                    end
                }
            ]]
        },
    })


    local result = main:eval([[ return require('migrator').upgrade() ]])
    t.assert_equals(result.applied_now, {'01_script.lua', '02_script.lua'})
    t.assert_equals(result.applied, {'01_script.lua', '02_script.lua'})

    t.assert(main:eval([[ return box.space.test:get(1) ]]))
    t.assert_not(main:eval([[ return box.space.test:get(2) ]]))

    -- Append migration script.
    utils.set_sections(g, {
        {
            filename = "migrations/source/03_script.lua",
            content = [[ return { up = function() box.space.test:insert{2} end } ]]
        },
    })
    result = main:eval([[ return require('migrator').upgrade() ]])
    t.assert_equals(result.applied_now, { '03_script.lua' })
    t.assert_equals(result.applied, { '01_script.lua', '02_script.lua', '03_script.lua' })
    t.assert(main:eval([[ return box.space.test:get(1) ]]))
    t.assert(main:eval([[ return box.space.test:get(2) ]]))
end

g.test_upgrade_clusterwide_applied_migrations_exist = function(cg)
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

    local status, resp = main:eval([[ return pcall(require('migrator').upgrade) ]])
    t.assert_not(status)
    t.assert_str_contains(tostring(resp), 'A list of applied migrations is found in cluster config')
end

