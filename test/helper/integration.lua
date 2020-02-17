local t = require('luatest')

local cartridge_helpers = require('cartridge.test-helpers')
local shared = require('test.helper')

local helper = { shared = shared }

helper.cluster = cartridge_helpers.Cluster:new({
    server_command = shared.server_command,
    datadir = shared.datadir,
    use_vshard = false,
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
            roles = { 'vshard-router' },
            servers = {
                { instance_uuid = cartridge_helpers.uuid('b', 1), },
                { instance_uuid = cartridge_helpers.uuid('b', 2), },
            },
        },
        {
            alias = 'storage-2',
            uuid = cartridge_helpers.uuid('c'),
            roles = { 'vshard-router' },
            servers = {
                { instance_uuid = cartridge_helpers.uuid('c', 1), },
                { instance_uuid = cartridge_helpers.uuid('c', 2), },
            },
        },
    },
})

t.before_suite(function()
    for _, server in ipairs(helper.cluster.servers) do
        server.env.TARANTOOL_LOG_LEVEL = 6
    end
    helper.cluster:start()
end)
t.after_suite(function() helper.cluster:stop() end)

return helper
