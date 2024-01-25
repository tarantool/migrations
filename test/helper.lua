-- This file is required automatically by luatest.
-- Add common configuration here.

local digest = require('digest')
local fio = require('fio')
local t = require('luatest')

local helper = {}

helper.root = fio.cwd()
local tmpdir = os.getenv('TMPDIR')
    and fio.pathjoin(os.getenv('TMPDIR'),
        'migrations.' .. digest.base64_encode(digest.urandom(9), {urlsafe = true}))
    or fio.pathjoin(helper.root, 'tmp')
helper.datadir = fio.pathjoin(tmpdir, 'db_test')

package.setsearchroot(helper.root)

helper.server_command = fio.pathjoin(helper.root, 'test', 'init.lua')

t.before_suite(function()
    fio.rmtree(helper.datadir)
    fio.mktree(helper.datadir)
    box.cfg{}
end)

return helper
