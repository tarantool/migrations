local t = require('luatest')
local g = t.group('directory-loader')

local fun = require('fun')

local loader = require('migrator.directory-loader')

g.test_positive = function()
    local list = loader.new('test/unit/migrations/positive'):list()
    local names = fun.iter(list):map(function(x) return x.name end):totable()
    t.assert_equals(names, { '01_first.lua', '02_second.lua' })
end

g.test_missing_folder = function()
    local loader = loader.new('test/unit/mmmmirgations') -- luacheck: ignore
    t.assert_error_msg_contains('is not valid', loader.list, loader)
end

g.test_empty_folder = function()
    local list = loader.new('test/unit/migrations/empty'):list()
    t.assert_equals(list, { })
end


