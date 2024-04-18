local t = require('luatest')
local g = t.group('directory-loader')

local fun = require('fun')
local fio = require('fio')

local loader = require('migrator-ee.directory-loader')

g.test_positive = function()
    local list = loader.new('test/unit/migrations/positive'):list()
    local names = fun.iter(list):map(function(x) return x.name end):totable()
    t.assert_equals(names, { '01_first.lua', '02_second.lua' })
end

g.test_missing_folder = function()
    local loader = loader.new('test/unit/mmmmirgations') -- luacheck: ignore
    t.assert_error_msg_contains('is not valid', loader.list, loader)
end

g.test_dynamic_folder = function()
    fio.rmtree('test/unit/migrations/empty')
    fio.mkdir('test/unit/migrations/empty')
    local ldr = loader.new('test/unit/migrations/empty')
    t.assert_equals(ldr:list(), { })

    fio.copyfile('test/unit/migrations/positive/01_first.lua', './test/unit/migrations/empty/test.lua')
    t.assert_equals(ldr:list()[1].name, 'test.lua')
    fio.rmtree('test/unit/migrations/empty')
end


