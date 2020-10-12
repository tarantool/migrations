local t = require("luatest")
local g = t.group("config-loader")
local fun = require("fun")

local loader = require("migrator.config-loader")

g.test___must_sort_sorts = function()
    local a = {{name = '002_second.lua'}, {name = '003_third.lua'}, {name = '001_first.lua'}}
    loader.__must_sort(a)
    t.assert_equals(a, {{name = '001_first.lua'}, {name = '002_second.lua'}, {name = '003_third.lua'}})
end

local function mock_clusterwide_config(cfg)
    package.loaded["cartridge.confapplier"] = {
        get_active_config = function()
            return {
                get_plaintext = function()
                    return cfg
                end
            }
        end
    }
end

for name, case in pairs({
    no_migrations = {cfg = {}, expected = {}},
    single_migration = {
        cfg = {
            ['migrations/source/001_first.lua'] = 'return {up = function() return "first" end}',
        },
        expected = {"001_first.lua"},
    },
    multiple_migrations = {
        cfg = {
            ['migrations/source/001_first.lua'] = 'return {up = function() return "first" end}',
            ['migrations/source/002_second.lua'] = 'return {up = function() return "second" end}',
        },
        expected = {"001_first.lua", "002_second.lua"},
    },
    ignores_other_config_sections = {
        cfg = {
            ['migrations/source/001_first.lua'] = 'return {up = function() return "first" end}',
            ['migrations/MY_MIGRATIONS/002_second.lua'] = 'return {up = function() return "second" end}',
        },
        expected = {"001_first.lua"},
    },
    ignores_lua_errors = {
        cfg = {
            ['migrations/source/001_first.lua'] = 'return {up = function() return "first" end}',
            ['migrations/source/002_with_lua_err.lua'] = 'return up = function() return "second" end}',
        },
        expected = {"001_first.lua"},
    },
}) do
    g['test_' .. name] = function()
        local l = loader.new()
        mock_clusterwide_config(case.cfg)

        local names = fun.iter(l:list()):map(function(x) return x.name end):totable()
        t.assert_equals(names, case.expected)
    end
end
