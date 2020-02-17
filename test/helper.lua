-- This file is required automatically by luatest.
-- Add common configuration here.

local fio = require('fio')
local t = require('luatest')

local helper = {}

helper.root = fio.cwd()
print('ROOT : ' ..  helper.root)
helper.datadir = fio.pathjoin(helper.root, 'tmp', 'db_test')

package.setsearchroot(helper.root)

helper.server_command = fio.pathjoin(helper.root, 'test', 'init.lua')

t.before_suite(function()
    fio.rmtree(helper.datadir)
    fio.mktree(helper.datadir)
end)

return helper
